// The check of a printed access (python storage.py's checks: the form must
// read as the access): the slot and the bits the form denotes - by
// storage::locate, the semantics the trace machine runs - must be those the
// access reads for every value of what they are computed from. Proven, never
// sampled: both places as expressions (sym_place: what locate computes, as
// the IR writes it), made canonical (canon: a hash of constant bytes is its
// number, a hash's DATA operands are their elements, every node rebuilt by
// the constructors), then the same expression (alg::same_value). What isn't
// proven is refused: the access is printed raw, which always reads as it.
#include "storage/check.hpp"

#include <bit>

#include "algebra/construct.hpp"
#include "algebra/eval.hpp"
#include "algebra/identity.hpp"
#include "core/context.hpp"
#include "core/errors.hpp"
#include "exec/machine.hpp"
#include "storage/internal.hpp"

namespace pan::storage::detail {

namespace {

// a DATA's bytes are its elements' one after the other - but where it has
// an ARR, which the machine encodes as the ABI does (heads, then tails)
bool has_arr(Value d) {
    for (Value x : d.args())
        if (x.is(Op::ARR)) return true;
    return false;
}

// the place of a location as expressions (what locate computes, as the IR
// writes it: the hashes as SHA3 of SIZED words, the sums normal)
struct SymPlace {
    Value slot, bit;
    bool length = false;
    std::optional<u32> type;
};

std::optional<SymPlace> sym_place(const StorageLayout& L, Value loc) {
    check_stack();
    switch (loc.op()) {
        case Op::SV: {
            if (!loc.is(Op::SV, 1) || !loc[0].is_name(NameKind::STORVAR) || loc[0].name_id() >= L.vars.size())
                return std::nullopt;
            const StorageVar& v = L.vars[loc[0].name_id()];
            return SymPlace{v.slot.to_value(), small(v.off), false, v.type};
        }
        case Op::SR:
            if (!loc.is(Op::SR, 1)) return std::nullopt;
            return SymPlace{loc[0], small(0), false, std::nullopt};
        case Op::SL:
        case Op::SBL: {
            if (loc.size() != 1) return std::nullopt;
            std::optional<SymPlace> p = sym_place(L, loc[0]);
            if (!p || p->length) return std::nullopt;
            p->type.reset();
            p->length = loc.op() == Op::SBL;
            return p;
        }
        case Op::SF: {
            if (!loc.is(Op::SF, 2) || !loc[1].is_small()) return std::nullopt;
            std::optional<SymPlace> p = sym_place(L, loc[0]);
            if (!p || p->length || !p->bit.is_small()) return std::nullopt;
            if (loc[1].small_val() < -(i64(1) << 60) || loc[1].small_val() > (i64(1) << 60) ||
                p->bit.small_val() < 0 || p->bit.small_val() >= 256)
                return std::nullopt;
            const i64 t = p->bit.small_val() + loc[1].small_val();
            const i64 q = t >= 0 ? t / 256 : -((-t + 255) / 256);
            return SymPlace{q ? alg::add(p->slot, small(q)) : p->slot, small(t - 256 * q), false, std::nullopt};
        }
        case Op::SI: {
            if (!loc.is(Op::SI, 2)) return std::nullopt;
            const std::optional<SymPlace> p = sym_place(L, loc[0]);
            if (!p || p->length || !p->type || *p->type >= L.types.size()) return std::nullopt;
            const StorageType& T = L.types[*p->type];
            const Value key = loc[1];
            const Value slot_word = mk(Op::SIZED, small(32), p->slot);
            switch (T.kind) {
                case StorageType::Kind::Mapping: {
                    SmallVec<Value, 8> args;
                    if (L.lang == Lang::Vyper) args.push_back(slot_word);
                    if (key.is(Op::DATA)) {
                        // (its elements' bytes: an ARR's would be encoded)
                        if (has_arr(key)) return std::nullopt;
                        for (Value x : key.args()) args.push_back(x);
                    } else if (is_bytes_expr(key)) {
                        args.push_back(key);
                    } else {
                        args.push_back(mk(Op::SIZED, small(32), key));
                    }
                    if (L.lang != Lang::Vyper) args.push_back(slot_word);
                    return SymPlace{mk(Op::SHA3, args.span()), small(0), false, T.elem};
                }
                case StorageType::Kind::Bytes:
                    return SymPlace{alg::add(mk(Op::SHA3, slot_word), key), small(0), false, std::nullopt};
                case StorageType::Kind::Array:
                case StorageType::Kind::Fixed: {
                    const Value start = T.kind == StorageType::Kind::Array ? mk(Op::SHA3, slot_word) : p->slot;
                    const u16 w = L.packed_width(T.elem);
                    if (w < 256) {
                        const i64 per = 256 / w;
                        const i64 lp = std::countr_zero(u64(per)), lw = std::countr_zero(u64(w));
                        return SymPlace{alg::add(start, alg::mask(256 - lp, lp, -lp, key)), alg::mask(lp, 0, lw, key), false,
                                        T.elem};
                    }
                    return SymPlace{alg::add(start, alg::mul(mk_uint(T.stride), key)), small(0), false, T.elem};
                }
                case StorageType::Kind::Value:
                case StorageType::Kind::Struct:
                    return std::nullopt;
            }
            return std::nullopt;
        }
        default:
            return std::nullopt;
    }
}

// the bytes of a constant element of a hash's data, as the machine's evb
// makes them: BYTES; SIZED(n, k) of a word k (n <= 32: its last n bytes),
// SIZED(n, BYTES) (its last n bytes, zeroes first when shorter); false: not
// constant
bool const_bytes(Value e, std::vector<u8>& out) {
    if (e.is_bytes()) {
        const auto b = e.bytes();
        out.insert(out.end(), b.begin(), b.end());
        return true;
    }
    if (!e.is(Op::SIZED, 2) || !e[0].is_small() || e[0].small_val() < 0 || e[0].small_val() > 32) return false;
    const usize n = usize(e[0].small_val());
    const Value x = e[1];
    if (x.is_int()) {
        // (a word: a negative or wider int's bytes are its magnitude's there)
        if (alg::word_int(x) != x) return false;
        u8 w[32];
        alg::word_of(x).to_be(w);
        out.insert(out.end(), w + (32 - n), w + 32);
        return true;
    }
    if (x.is_bytes()) {
        const auto b = x.bytes();
        if (b.size() >= n) {
            out.insert(out.end(), b.end() - isize(n), b.end());
        } else {
            out.insert(out.end(), n - b.size(), u8(0));
            out.insert(out.end(), b.begin(), b.end());
        }
        return true;
    }
    return false;
}

}  // namespace

// v as the canonical expression of the same word (v a word: SIZED(32, x)
// of a word x, LOC(x) are x - the machine reads them so; every node rebuilt
// with its operands canonical, through the constructors when pure); and
// everywhere, a SHA3's DATA operands without an ARR replaced by their
// elements, a SHA3 of constant bytes by its keccak
Value Checker::canon(Value v) {
    check_stack();
    if (!v.is_expr()) return v;
    if (const Value* m = canon_.find(v)) return *m;
    Value r = v;
    if ((v.is(Op::SIZED, 2) && is_small(v[0], 32) && !is_bytes_expr(v[1])) || v.is(Op::LOC, 1)) {
        r = canon(v.is(Op::LOC) ? v[0] : v[1]);
    } else if (v.is(Op::SHA3)) {
        SmallVec<Value, 8> parts;
        bool changed = false;
        auto flat = [&](auto&& self, std::span<const Value> xs) -> void {
            for (Value x : xs) {
                if (x.is(Op::DATA) && !has_arr(x)) {
                    changed = true;
                    self(self, x.args());
                    continue;
                }
                const Value nx = bytes_canon(x);
                changed |= nx != x;
                parts.push_back(nx);
            }
        };
        flat(flat, v.args());
        std::vector<u8> buf;
        bool constant = true;
        for (Value p : parts)
            if (!const_bytes(p, buf)) {
                constant = false;
                break;
            }
        if (constant)
            r = exec::keccak256(buf).to_value();
        else if (changed)
            r = mk(Op::SHA3, parts.span());
    } else {
        SmallVec<Value, 8> args;
        bool changed = false;
        const bool pure = alg::is_pure(v.op());
        for (usize i = 0; i < v.size(); ++i) {
            const Value a = v[i];
            // (a pure op's operands are words - but a mask of bytes's)
            const bool word = pure && !(v.is(Op::MASK_SHL) && i == 3 && alg::may_be_wide(a));
            const Value na = word ? canon(a) : bytes_canon(a);
            changed |= na != a;
            args.push_back(na);
        }
        if (changed) r = pure ? alg::apply(v.op(), args.span()) : mk_like(v, args.span());
    }
    canon_.put(v, r);
    return r;
}

// an operand that may be bytes (a hash's data, a non-pure op's operand): the
// same bytes, its words canonical but itself kept as written (an unsized
// word's bytes are as wide as its form, ir.md 4.2)
Value Checker::bytes_canon(Value v) {
    check_stack();
    if (!v.is_expr()) return v;
    if (v.is(Op::SHA3)) return canon(v);
    if (const Value* m = bytes_.find(v)) return *m;
    SmallVec<Value, 8> args;
    bool changed = false;
    for (usize i = 0; i < v.size(); ++i) {
        const Value a = v[i];
        // (SIZED(n, x): x a word unless it is bytes)
        const bool word = v.is(Op::SIZED, 2) && i == 1 && !is_bytes_expr(a);
        const Value na = word ? canon(a) : bytes_canon(a);
        changed |= na != a;
        args.push_back(na);
    }
    const Value r = changed ? mk_like(v, args.span()) : v;
    bytes_.put(v, r);
    return r;
}

bool Checker::same(Value a, Value b) { return a == b || alg::same_value(canon(a), canon(b)); }

bool Checker::check(const StorageLayout& layout, Value f, const Access& a) {
    try {
        i64 d = 0, size = 0;
        Value st = f;
        if (f.is(Op::MASK_SHL, 4)) {
            if (!f[0].is_small() || !f[1].is_small() || !f[2].is_small() || !f[3].is(Op::ST, 3)) return refuse();
            size = f[0].small_val();
            d = f[1].small_val();
            if (f[2].small_val() != -d || d < 0 || size < 0) return refuse();
            st = f[3];
            // (no bit past what the ST reads)
            if (!st[0].is_small() || size + d > st[0].small_val()) return refuse();
        } else if (f.is(Op::ST, 3) && f[0].is_small()) {
            size = f[0].small_val();
        } else {
            return refuse();
        }
        if (size < 0 || size > 256 || !is_small(a.size, size)) return refuse();
        const std::optional<SymPlace> p = sym_place(layout, st[1]);
        if (!p) return refuse();
        Value want = a.idx;
        bool length = false;
        if (a.idx.is(Op::LENGTH, 1)) {
            want = a.idx[0];
            length = true;
        }
        if (p->length != length) return refuse();
        if (!same(p->slot, want) || !same(d ? alg::add(p->bit, small(d)) : p->bit, a.off)) return refuse();
        ++proven_;
        return true;
    } catch (const Error&) {  // (the constructors' SizeLimit...)
        return refuse();
    }
}

}  // namespace pan::storage::detail
