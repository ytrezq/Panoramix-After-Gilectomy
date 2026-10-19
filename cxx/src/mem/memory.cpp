// The memory model (lot 4): see memory.hpp.
//
// Positions are compared as integers by lot 3's word comparisons under
// alg::Top::Memory: the end of a range, start + len, is the integer it is
// as a word for any range an execution that doesn't run out of gas
// accesses (its bytes are below 2^64), and a range of no bytes meets
// nothing - so every decision below is about the bytes of non-empty ranges.
#include "mem/memory.hpp"

#include <gmp.h>

#include <algorithm>
#include <vector>

#include "algebra/compare.hpp"
#include "algebra/construct.hpp"
#include "algebra/eval.hpp"
#include "algebra/linear.hpp"
#include "algebra/masks.hpp"
#include "algebra/ranges.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/errors.hpp"
#include "core/evmint.hpp"
#include "core/intops.hpp"
#include "core/memo.hpp"

namespace pan::mem {

namespace {

using alg::Facts;
using alg::Top;

// constant byte strings made here at most this long (the asm's)
constexpr usize kMaxConstBytes = usize{1} << 24;

Value small(i64 x) { return Value::small(x); }
const Value kZero = Value::small(0);

// a small int >= 0
std::optional<i64> nat(Value v) noexcept {
    if (v.is_small() && v.small_val() >= 0) return v.small_val();
    return std::nullopt;
}

// ---- comparisons of positions (addresses, sizes, offsets in bytes) -----------------

Tri pos_le(Value a, Value b, const Facts* f) {
    if (a == b) return Tri::True;
    if (auto x = nat(a))
        if (auto y = nat(b)) return tri(*x <= *y);
    Tri t = alg::le(a, b, Top::Memory, f);
    return t == Tri::Cannot ? Tri::None : t;
}
Tri pos_lt(Value a, Value b, const Facts* f) {
    if (a == b) return Tri::False;
    if (auto x = nat(a))
        if (auto y = nat(b)) return tri(*x < *y);
    Tri t = alg::lt(a, b, Top::Memory, f);
    return t == Tri::Cannot ? Tri::None : t;
}
// len is 0 (True), > 0 (False)
Tri is_empty(Value len, const Facts* f) {
    if (auto n = nat(len)) return tri(*n == 0);
    return alg::tri_not(pos_lt(kZero, len, f));
}
bool same_int(Value a, Value b) noexcept {
    if (a == b) return true;
    return a.is_int() && b.is_int() && int_cmp(a, b) == 0;
}

// a + b / a - b of positions: the algebra's sums (ints folded)
Value padd(Value a, Value b) {
    if (auto x = nat(a))
        if (auto y = nat(b))
            if (*x <= (i64(1) << 61) && *y <= (i64(1) << 61)) return small(*x + *y);
    return alg::add(a, b);
}
Value psub(Value a, Value b) {
    if (auto x = nat(a))
        if (auto y = nat(b))
            if (*x >= *y) return small(*x - *y);
    return alg::sub(a, b);
}

// the larger / smaller of a and b when decided
std::optional<Value> pos_max(Value a, Value b, const Facts* f) {
    if (pos_le(a, b, f) == Tri::True) return b;
    if (pos_le(b, a, f) == Tri::True) return a;
    return std::nullopt;
}
std::optional<Value> pos_min(Value a, Value b, const Facts* f) {
    if (pos_le(a, b, f) == Tri::True) return a;
    if (pos_le(b, a, f) == Tri::True) return b;
    return std::nullopt;
}

// q + lo doesn't wrap around 2^256, whatever q and lo are (q an offset of a
// zero-padded source: calldata, code, return data - not memory, whose ranges
// an execution reads are below 2^64)
bool offset_ok(Value q, Value lo, const Facts* f) {
    if (lo == kZero) return true;
    alg::Range rq = alg::range(q, Top::Memory, f);
    alg::Range rl = alg::range(lo, Top::Memory, f);
    return rq.hi + rl.hi <= word_max();
}

// ---- constants -------------------------------------------------------------------

// the bytes of an int as written: an int of 256 bits at most, its 32 bytes;
// more, its minimal big-endian bytes (a long constant)
void int_bytes(Value v, std::vector<u8>& out) {
    if (v.is_big()) {
        EvmInt e(v);
        if (e.sign() > 0 && e.bit_length() > 256) {
            mpz_class z = e.to_mpz();
            usize n = (mpz_sizeinbase(z.get_mpz_t(), 2) + 7) / 8;
            if (n > kMaxConstBytes) throw MemoryLimit();
            usize start = out.size();
            out.resize(start + n, 0);
            usize written = 0;
            mpz_export(out.data() + start, &written, 1, 1, 1, 0, z.get_mpz_t());
            if (written < n) {
                std::copy_backward(out.begin() + isize(start), out.begin() + isize(start + written), out.end());
                std::fill(out.begin() + isize(start), out.begin() + isize(start + n - written), 0);
            }
            return;
        }
    }
    u8 w[32];
    alg::word_of(v).to_be(w);
    out.insert(out.end(), w, w + 32);
}

// an int of more than 256 bits (positive): a BIGINT node of more than 256
// bits of limbs (normalized: no leading zero limb)
bool is_long_const(Value v) noexcept {
    return v.is_big() && v.node()->op == 0 && u64(v.size()) * 8 * sizeof(mp_limb_t) > 256;
}

// src resized to n bytes: zeroes before it, or its last n bytes
void append_resized(std::vector<u8>& out, std::span<const u8> src, u64 n) {
    if (src.size() >= n) {
        out.insert(out.end(), src.end() - isize(n), src.end());
    } else {
        out.insert(out.end(), n - src.size(), u8(0));
        out.insert(out.end(), src.begin(), src.end());
    }
}

// the bytes of a constant bytes expression (a BYTES node, SIZED(n, int), a
// DATA of them, a long constant); false when it isn't one
bool const_bytes(Value b, std::vector<u8>& out) {
    check_stack();
    if (b.is_bytes()) {
        if (out.size() + b.size() > kMaxConstBytes) throw MemoryLimit();
        out.insert(out.end(), b.bytes().begin(), b.bytes().end());
        return true;
    }
    if (is_long_const(b)) {
        int_bytes(b, out);
        return true;
    }
    if (b.is(Op::SIZED, 2)) {
        auto n = nat(b[0]);
        if (!n || u64(*n) > kMaxConstBytes || out.size() + u64(*n) > kMaxConstBytes) {
            if (n && (b[1].is_int() || b[1].is_bytes())) throw MemoryLimit();
            return false;
        }
        std::vector<u8> src;
        if (b[1].is_int()) {
            int_bytes(b[1], src);
        } else if (!const_bytes(b[1], src)) {
            return false;
        }
        append_resized(out, src, u64(*n));
        return true;
    }
    if (b.is(Op::DATA)) {
        for (Value e : b.args())
            if (!const_bytes(e, out)) return false;
        return true;
    }
    return false;
}

bool is_const_bytes(Value b) {
    check_stack();
    if (b.is_bytes() || is_long_const(b)) return true;
    if (b.is(Op::SIZED, 2)) return nat(b[0]).has_value() && (b[1].is_int() || is_const_bytes(b[1]));
    if (b.is(Op::DATA)) {
        for (Value e : b.args())
            if (!is_const_bytes(e)) return false;
        return true;
    }
    return false;
}

// bytes as an expression: 32 of them at most a SIZED int, more a BYTES node
Value bytes_value(std::span<const u8> bytes) {
    if (bytes.size() > kMaxConstBytes) throw MemoryLimit();
    if (bytes.size() <= 32) return mk(Op::SIZED, small(i64(bytes.size())), mk_int_be(bytes));
    return mk_bytes(bytes);
}

// ---- words written as bytes ----------------------------------------------------------

// the bytes [lo, hi) of the n bytes a word x is written as (n, lo, hi ints,
// 0 <= lo <= hi <= n)
Value word_slice(Value x, i64 n, i64 lo, i64 hi) {
    if (lo >= hi) return mk(Op::DATA, std::span<const Value>{});
    if (n > 32) {
        // zeroes, then the 32 bytes of the word
        const i64 z = n - 32;
        SmallVec<Value, 2> parts;
        if (lo < z) parts.push_back(mk(Op::SIZED, small(std::min(hi, z) - lo), kZero));
        if (hi > z) parts.push_back(word_slice(x, 32, std::max(lo, z) - z, hi - z));
        return concat(parts.span());
    }
    const i64 k = hi - lo, off = 8 * (n - hi);
    if (off == 0 && k == n) return sized(small(n), x);
    return sized(small(k), alg::mask(8 * k, off, -off, x));
}

// what SIZED(k, v) is as bits of a word y: bits [off, off + 8k) of y
struct FieldView {
    Value y;
    i64 off;
};
std::optional<FieldView> field_view(Value b, i64* k_out) {
    if (!b.is(Op::SIZED, 2)) return std::nullopt;
    auto k = nat(b[0]);
    if (!k || *k == 0 || *k > 32) return std::nullopt;
    Value v = b[1];
    if (is_bytes(v) || v.is_int()) return std::nullopt;
    *k_out = *k;
    if (auto m = alg::as_mask(v); m && m->concrete()) {
        const i64 s = m->isize(), o = m->ioff(), h = m->ishl();
        if (h == -o && o >= 0 && (s >= 8 * *k || o + s >= 256)) return FieldView{m->x, o};
    }
    return FieldView{v, 0};
}

// ---- concatenation -----------------------------------------------------------------

// a part of no bytes for sure
bool no_bytes(Value p) {
    if (p.is_none()) return true;
    if (p.is(Op::DATA)) return p.size() == 0;
    if (!is_bytes(p)) return false;
    auto w = width_of(p);
    return w && *w == kZero;
}

// two constants next to each other as one, when they make 32 bytes at most
// (a SIZED int) or they are long already (BYTES nodes)
std::optional<Value> merge_constants(Value a, Value b) {
    // zeroes and zeroes, of any length
    if (a.is(Op::SIZED, 2) && b.is(Op::SIZED, 2) && a[1] == kZero && b[1] == kZero)
        return mk(Op::SIZED, padd(a[0], b[0]), kZero);
    if (!is_const_bytes(a) || !is_const_bytes(b)) return std::nullopt;
    auto wa = width_u64(a), wb = width_u64(b);
    if (!wa || !wb) return std::nullopt;
    const u64 total = *wa + *wb;
    if (total > 32 && !(a.is_bytes() && b.is_bytes())) return std::nullopt;
    if (total > kMaxConstBytes) throw MemoryLimit();
    std::vector<u8> bytes;
    if (!const_bytes(a, bytes) || !const_bytes(b, bytes)) return std::nullopt;
    return bytes_value(bytes);
}

// two parts next to each other as one, when they are
std::optional<Value> merge2(Value a, Value b, const Facts* f) {
    if (a.op() != b.op()) return merge_constants(a, b);
    switch (a.op()) {
        case Op::MEM:
            if (a.size() == 1 && b.size() == 1 && is_range(a[0]) && is_range(b[0]) &&
                b[0][0] == padd(a[0][0], a[0][1]))
                return mk(Op::MEM, make_range(a[0][0], padd(a[0][1], b[0][1])));
            return std::nullopt;
        case Op::CALLDATA_BYTES:
        case Op::CODE_BYTES:
            if (a.size() == 2 && b.size() == 2 && b[0] == padd(a[0], a[1]) && offset_ok(a[0], a[1], f))
                return mk(a.op(), a[0], padd(a[1], b[1]));
            return std::nullopt;
        case Op::RETURNDATA_BYTES:
            if (a.size() == 3 && b.size() == 3 && a[0] == b[0] && b[1] == padd(a[1], a[2]) && offset_ok(a[1], a[2], f))
                return mk(a.op(), a[0], a[1], padd(a[2], b[2]));
            return std::nullopt;
        case Op::EXTCODE_BYTES:
            if (a.size() == 2 && b.size() == 2 && a[0] == b[0] && is_range(a[1]) && is_range(b[1]) &&
                b[1][0] == padd(a[1][0], a[1][1]) && offset_ok(a[1][0], a[1][1], f))
                return mk(a.op(), a[0], make_range(a[1][0], padd(a[1][1], b[1][1])));
            return std::nullopt;
        case Op::SIZED: {
            i64 ka = 0, kb = 0;
            auto fa = field_view(a, &ka);
            auto fb = field_view(b, &kb);
            if (fa && fb && fa->y == fb->y && fa->off == fb->off + 8 * kb && ka + kb <= 32) {
                const i64 k = ka + kb, o = fb->off;
                if (o == 0 && k == 32) return sized(small(32), fa->y);
                return sized(small(k), alg::mask(8 * k, o, -o, fa->y));
            }
            return merge_constants(a, b);
        }
        default:
            return merge_constants(a, b);
    }
}

void append_part(SmallVec<Value, 8>& out, Value p, const Facts* f) {
    check_stack();
    if (p.is(Op::DATA)) {
        bool arr = false;
        for (Value e : p.args()) arr = arr || e.is(Op::ARR);
        if (!arr) {
            for (Value e : p.args()) append_part(out, e, f);
            return;
        }
    }
    if (no_bytes(p)) return;
    if (!out.empty())
        if (auto m = merge2(out.back(), p, f)) {
            out.pop_back();
            append_part(out, *m, f);
            return;
        }
    out.push_back(p);
}

Value concat_f(std::span<const Value> parts, const Facts* f) {
    SmallVec<Value, 8> out;
    for (Value p : parts) {
        poll();
        append_part(out, p, f);
    }
    if (out.size() == 1) return out[0];
    return mk(Op::DATA, out.span());
}

// ---- slices ------------------------------------------------------------------------

std::optional<Value> slice_parts(std::span<const Value> parts, Value lo, Value hi, const Facts* f) {
    SmallVec<Value, 8> out;
    Value pos = kZero;
    for (Value e : parts) {
        poll();
        auto w = width_of(e);
        if (!w) return std::nullopt;
        Value end = padd(pos, *w);
        if (pos_le(end, lo, f) == Tri::True) {
            pos = end;
            continue;
        }
        if (pos_le(hi, pos, f) == Tri::True) break;
        auto a = pos_max(pos, lo, f);
        auto b = pos_min(end, hi, f);
        if (!a || !b) return std::nullopt;
        auto piece = slice(e, psub(*a, pos), psub(*b, pos), f);
        if (!piece) return std::nullopt;
        out.push_back(*piece);
        pos = end;
    }
    if (pos_le(hi, pos, f) != Tri::True) return std::nullopt;
    return concat_f(out.span(), f);
}

// a source of bytes moved: its bytes [lo, hi)
std::optional<Value> slice_source(Value b, Value lo, Value hi, const Facts* f) {
    Value len = psub(hi, lo);
    switch (b.op()) {
        case Op::MEM:
            // (memory an execution reads is below 2^64: no wrap)
            return mk(Op::MEM, make_range(padd(b[0][0], lo), len));
        case Op::CALLDATA_BYTES:
        case Op::CODE_BYTES:
            if (!offset_ok(b[0], lo, f)) return std::nullopt;
            return mk(b.op(), padd(b[0], lo), len);
        case Op::RETURNDATA_BYTES:
            if (!offset_ok(b[1], lo, f)) return std::nullopt;
            return mk(b.op(), b[0], padd(b[1], lo), len);
        case Op::EXTCODE_BYTES:
            if (!offset_ok(b[1][0], lo, f)) return std::nullopt;
            return mk(b.op(), b[0], make_range(padd(b[1][0], lo), len));
        default:
            return std::nullopt;
    }
}

// ---- memory a value reads ---------------------------------------------------------

// e reads memory that may be in range (a MEM whose range may meet it)
bool reads_mem_in(Value e, Value range, const Facts* f) {
    if (!e.has_flags(F_MEM)) return false;
    MemoSet<Value> seen;
    SmallVec<Value, 32> todo{e};
    while (!todo.empty()) {
        poll();
        Value x = todo.back();
        todo.pop_back();
        if (!x.has_flags(F_MEM) || !x.is_node()) continue;
        if (!seen.add(x)) continue;
        if (x.is(Op::MEM, 1)) {
            if (!is_range(x[0]) || overlaps(x[0], range, f) != Tri::False) return true;
            // its range may read memory too
        }
        for (Value a : x.children()) todo.push_back(a);
    }
    return false;
}

// e mentions name (a Name immediate)
bool mentions(Value e, Value name) {
    if (e == name) return true;
    const u8 nf = name.flags();
    if (nf && !e.has_flags(nf)) return false;
    if (!e.is_node()) return false;
    MemoSet<Value> seen;
    SmallVec<Value, 32> todo{e};
    while (!todo.empty()) {
        poll();
        Value x = todo.back();
        todo.pop_back();
        if (x == name) return true;
        if (!x.is_node() || (nf && !x.has_flags(nf))) continue;
        if (!seen.add(x)) continue;
        for (Value a : x.children()) todo.push_back(a);
    }
    return false;
}

// ---- in an order where none reads what one before it wrote -------------------------

// python in_order: the writes, all at once (each value read before any of
// them writes), as one after the other: i before j when i reads what j
// writes; the original order otherwise; nullopt when there's a cycle
template <class ReadsWritten>
std::optional<SmallVec<Value, 4>> in_order(std::span<const Value> writes, ReadsWritten reads_written) {
    const usize n = writes.size();
    if (n > 64) return std::nullopt;
    std::vector<u64> after(n, 0);  // after[i]: the j that must come after i
    std::vector<u32> waiting(n, 0);
    for (usize i = 0; i < n; ++i)
        for (usize j = 0; j < n; ++j) {
            if (i == j) continue;
            poll();
            if (reads_written(writes[i], writes[j])) {
                after[i] |= u64(1) << j;
                ++waiting[j];
            }
        }
    SmallVec<Value, 4> res;
    std::vector<bool> done(n, false);
    while (res.size() < n) {
        usize i = 0;
        while (i < n && (done[i] || waiting[i])) ++i;
        if (i == n) return std::nullopt;
        done[i] = true;
        res.push_back(writes[i]);
        for (usize j = 0; j < n; ++j)
            if (after[i] >> j & 1) --waiting[j];
    }
    return res;
}

}  // namespace

// ---- bytes expressions and their widths ------------------------------------------

bool is_bytes(Value v) noexcept {
    if (v.is_none() || v.is_bytes()) return true;
    if (!v.is_expr()) return false;
    return info(v.op()).sort == Sort::Bytes;
}

std::optional<Value> width_of(Value b) {
    check_stack();
    if (b.is_none()) return kZero;
    if (b.is_bytes()) return small(i64(b.size()));
    if (is_long_const(b)) return small(i64((EvmInt(b).bit_length() + 7) / 8));
    if (!b.is_expr()) return std::nullopt;
    switch (b.op()) {
        case Op::SIZED:
            if (b.size() == 2) return b[0];
            return std::nullopt;
        case Op::MEM:
            if (b.size() == 1 && is_range(b[0])) return b[0][1];
            return std::nullopt;
        case Op::CALLDATA_BYTES:
        case Op::CODE_BYTES:
            if (b.size() == 2) return b[1];
            return std::nullopt;
        case Op::RETURNDATA_BYTES:
            if (b.size() == 3) return b[2];
            return std::nullopt;
        case Op::EXTCODE_BYTES:
            if (b.size() == 2 && is_range(b[1])) return b[1][1];
            return std::nullopt;
        case Op::DATA: {
            SmallVec<Value, 8> ws;
            i64 sum = 0;
            bool ints = true;
            for (Value e : b.args()) {
                auto w = width_of(e);
                if (!w) return std::nullopt;
                if (auto n = nat(*w); n && ints && sum <= (i64(1) << 61) - *n)
                    sum += *n;
                else
                    ints = false;
                ws.push_back(*w);
            }
            if (ints) return small(sum);
            return alg::add(ws.span());
        }
        default:
            return std::nullopt;
    }
}

std::optional<u64> width_u64(Value b) {
    auto w = width_of(b);
    if (!w) return std::nullopt;
    if (auto n = nat(*w)) return u64(*n);
    return std::nullopt;
}

Value sized(Value n, Value v) {
    check_stack();
    const auto nn = nat(n);
    if (is_bytes(v)) {
        auto w = width_of(v);
        if (w && same_int(*w, n)) return v;
        if (v.is(Op::SIZED, 2)) {
            const Value m = v[0], x = v[1];
            const auto mm = nat(m);
            if (nn && mm) {
                if (!is_bytes(x)) {
                    // x's low m bytes as n of them
                    if (*nn <= *mm || *mm >= 32) return sized(n, x);
                    return sized(n, alg::mask(8 * *mm, 0, 0, x));
                }
                if (*nn <= *mm) return sized(n, x);
                if (auto wx = width_u64(x); wx && *wx <= u64(*mm)) return sized(n, x);
            }
        }
        if (nn && w) {
            if (auto ww = nat(*w)) {
                // (zeroes before them, or their last n bytes)
                if (*ww > *nn) {
                    if (auto s = slice(v, small(*ww - *nn), *w)) return *s;
                } else {
                    const Value parts[] = {mk(Op::SIZED, small(*nn - *ww), kZero), v};
                    return concat(parts);
                }
            }
        }
        return mk(Op::SIZED, n, v);
    }
    // a constant: its low n bytes only (one node for the same bytes)
    if (nn && *nn <= 32 && v.is_int()) return mk(Op::SIZED, n, alg::mask(8 * *nn, 0, 0, alg::word_int(v)));
    return mk(Op::SIZED, n, v);
}

std::optional<Value> resize_bytes(Value b, Value n) {
    if (!is_bytes(b)) return std::nullopt;
    auto w = width_of(b);
    if (!w) return std::nullopt;
    if (same_int(*w, n)) return b;
    Value r = sized(n, b);
    if (r.is(Op::SIZED, 2) && is_bytes(r[1])) return std::nullopt;
    return r;
}

Value bare_element(Value elem) noexcept {
    if (!elem.is(Op::SIZED, 2) || !elem[0].is_small()) return elem;
    Value v = elem[1];
    if (is_bytes(v)) return elem;
    auto w = implicit_width(v);
    if (w && i64(*w) == elem[0].small_val()) return v;
    return elem;
}

Value keep_width(Value old_elem, Value new_elem) {
    if (new_elem == old_elem || is_bytes(new_elem)) return new_elem;
    auto w = width_of(old_elem);
    if (!w) return old_elem;
    return sized(*w, new_elem);
}

Value keep_widths(Value old_exp, Value new_exp) {
    if (new_exp == old_exp || !old_exp.is_expr() || !new_exp.is_expr() || old_exp.op() != new_exp.op() ||
        old_exp.size() != new_exp.size())
        return new_exp;
    SmallVec<Value, 8> args;
    for (Value a : new_exp.args()) args.push_back(a);
    bool changed = false;
    for (u8 i : byte_operands(new_exp)) {
        if (args[i] == old_exp[i]) continue;
        Value k = keep_width(old_exp[i], args[i]);
        changed |= k != args[i];
        args[i] = k;
    }
    if (new_exp.is(Op::SETMEM, 2) && is_range(new_exp[0]) && is_bytes(args[1]) && !args[1].is_none()) {
        const Value len = new_exp[0][1];
        auto w = width_of(args[1]);
        if (!(w && same_int(*w, len))) {
            Value k = sized(len, args[1]);
            changed |= k != args[1];
            args[1] = k;
        }
    }
    if (!changed) return new_exp;
    Value r = mk(new_exp.op(), args.span());
    cx().pcs.inherit(r, new_exp);
    return r;
}

std::optional<u32> implicit_width(Value word) noexcept {
    auto bytes_of = [](i64 bits) -> std::optional<u32> {
        if (bits <= 0 || bits > 256 || bits % 8) return std::nullopt;
        return u32(bits / 8);
    };
    if (word.is_int()) {
        // (an int past 2^256: its bytes - too long for a word element)
        if (is_long_const(word)) return std::nullopt;
        return 32u;
    }
    if (word.is_none() || word.is_bytes()) return std::nullopt;
    if (word.is_expr()) {
        switch (word.op()) {
            case Op::MASK_SHL:
                if (word.size() == 4 && word[0].is_small() && word[1].is_small() && word[2].is_small())
                    return bytes_of(word[0].small_val() + word[1].small_val() + word[2].small_val());
                return std::nullopt;
            case Op::STORAGE:
            case Op::ST:
                if (word.size() == 3 && word[0].is_small()) return bytes_of(word[0].small_val());
                return std::nullopt;
            default:
                if (info(word.op()).sort == Sort::Bytes) return std::nullopt;
                return 32u;
        }
    }
    return 32u;
}

Value concat(std::span<const Value> parts) { return concat_f(parts, nullptr); }

std::optional<Value> as_word(Value b) {
    check_stack();
    if (b.is_none()) return kZero;
    if (b.is_bytes()) {
        if (b.size() > 32) return std::nullopt;
        return mk_int_be(b.bytes());
    }
    if (!b.is_expr()) return std::nullopt;
    switch (b.op()) {
        case Op::SIZED: {
            if (b.size() != 2) return std::nullopt;
            auto n = nat(b[0]);
            if (!n) return std::nullopt;
            Value x = b[1];
            if (!is_bytes(x) && !is_long_const(x)) {
                if (*n >= 32) return x;
                return alg::mask(8 * *n, 0, 0, x);
            }
            if (*n > 32) return std::nullopt;
            if (is_long_const(x)) return alg::mask(8 * *n, 0, 0, x);
            auto wx = width_u64(x);
            if (!wx) return std::nullopt;
            if (*wx > u64(*n)) {
                auto s = slice(x, small(i64(*wx) - *n), small(i64(*wx)));
                if (!s) return std::nullopt;
                return as_word(*s);
            }
            return as_word(x);  // (zeroes before don't change the number)
        }
        case Op::DATA: {
            auto w = width_u64(b);
            if (!w || *w > 32) return std::nullopt;
            SmallVec<Value, 8> terms;
            i64 after = i64(*w);
            for (Value e : b.args()) {
                auto we = width_u64(e);
                if (!we) return std::nullopt;
                after -= i64(*we);
                if (*we == 0) continue;
                auto x = as_word(e);
                if (!x) return std::nullopt;
                terms.push_back(alg::mask(8 * i64(*we), 0, 8 * after, *x));
            }
            if (terms.empty()) return kZero;
            return alg::bor(terms.span());
        }
        case Op::MEM:
        case Op::CODE_BYTES:
        case Op::RETURNDATA_BYTES:
        case Op::EXTCODE_BYTES: {
            auto w = width_u64(b);
            if (!w || *w > 32) return std::nullopt;
            if (*w == 0) return kZero;
            return b;
        }
        case Op::CALLDATA_BYTES: {
            auto w = width_u64(b);
            if (!w || *w > 32) return std::nullopt;
            if (*w == 0) return kZero;
            Value word = mk(Op::CALLDATALOAD, b[0]);
            if (*w == 32) return word;
            const i64 off = 8 * (32 - i64(*w));
            return alg::mask(8 * i64(*w), off, -off, word);
        }
        default:
            return std::nullopt;
    }
}

std::optional<Value> narrow_mem_mask(Value word) {
    auto m = alg::as_mask(word);
    if (!m || !m->concrete() || !m->x.is(Op::MEM, 1) || !is_range(m->x[0])) return std::nullopt;
    const auto n = nat(m->x[0][1]);
    const i64 s = m->isize(), o = m->ioff(), h = m->ishl();
    if (!n || *n > 32 || s <= 0 || o < 0 || s % 8 || o % 8 || o + s > 8 * *n) return std::nullopt;
    const i64 k = s / 8, j = o / 8;
    if (k == *n) return std::nullopt;  // (all of it)
    Value narrow = mk(Op::MEM, make_range(padd(m->x[0][0], small(*n - j - k)), small(k)));
    if (o + h == 0) return narrow;  // (its k bytes: below 2^s already)
    return alg::mask(s, 0, o + h, narrow);
}

std::optional<Value> slice(Value b, Value lo, Value hi, const Facts* f) {
    check_stack();
    auto w = width_of(b);
    if (lo == kZero && w && same_int(*w, hi)) return b;
    if (lo == hi) return mk(Op::DATA, std::span<const Value>{});
    const auto ilo = nat(lo), ihi = nat(hi);
    if (b.is_bytes() || is_long_const(b)) {
        if (!ilo || !ihi || *ilo > *ihi) return std::nullopt;
        std::vector<u8> bytes;
        if (!const_bytes(b, bytes) || u64(*ihi) > bytes.size()) return std::nullopt;
        return bytes_value(std::span<const u8>(bytes.data() + *ilo, usize(*ihi - *ilo)));
    }
    if (!b.is_expr()) return std::nullopt;
    switch (b.op()) {
        case Op::SIZED: {
            if (b.size() != 2) return std::nullopt;
            const Value n = b[0], x = b[1];
            if (!is_bytes(x) && !is_long_const(x)) {
                auto nn = nat(n);
                if (!nn || !ilo || !ihi || *ilo > *ihi || *ihi > *nn) return std::nullopt;
                return word_slice(x, *nn, *ilo, *ihi);
            }
            auto wx = width_of(x);
            if (!wx) return std::nullopt;
            if (same_int(*wx, n)) return slice(x, lo, hi, f);
            auto nn = nat(n), nx = nat(*wx);
            if (!nn || !nx) return std::nullopt;
            if (*nx >= *nn) return slice(x, padd(lo, small(*nx - *nn)), padd(hi, small(*nx - *nn)), f);
            const Value parts[] = {mk(Op::SIZED, small(*nn - *nx), kZero), x};
            return slice_parts(parts, lo, hi, f);
        }
        case Op::DATA: {
            for (Value e : b.args())
                if (e.is(Op::ARR)) return std::nullopt;
            return slice_parts(b.args(), lo, hi, f);
        }
        case Op::MEM:
            if (b.size() != 1 || !is_range(b[0])) return std::nullopt;
            return slice_source(b, lo, hi, f);
        case Op::CALLDATA_BYTES:
        case Op::CODE_BYTES:
            if (b.size() != 2) return std::nullopt;
            return slice_source(b, lo, hi, f);
        case Op::RETURNDATA_BYTES:
            if (b.size() != 3) return std::nullopt;
            return slice_source(b, lo, hi, f);
        case Op::EXTCODE_BYTES:
            if (b.size() != 2 || !is_range(b[1])) return std::nullopt;
            return slice_source(b, lo, hi, f);
        default:
            return std::nullopt;
    }
}

std::span<const u8> byte_operands(Value v) noexcept {
    static constexpr u8 k0[] = {0}, k1[] = {1}, k2[] = {2}, k3[] = {3}, k34[] = {3, 4}, k45[] = {4, 5};
    static constexpr u8 kAll[] = {0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15,
                                  16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31};
    if (!v.is_expr()) return {};
    const u32 n = v.size();
    auto upto = [&](std::span<const u8> s) {
        usize k = 0;
        while (k < s.size() && s[k] < n) ++k;
        return s.first(k);
    };
    switch (v.op()) {
        case Op::SHA3:
        case Op::DATA:
            if (n <= 32) return std::span<const u8>(kAll, n);
            return {};
        case Op::ARR:
            if (n >= 1 && n <= 32) return std::span<const u8>(kAll + 1, n - 1);
            return {};
        case Op::RETURN:
        case Op::REVERT:
        case Op::LOG0:
        case Op::LOG1:
        case Op::LOG2:
        case Op::LOG3:
        case Op::LOG4:
            return upto(k0);
        case Op::CALL:
        case Op::CALLCODE:
            return upto(k45);
        case Op::DELEGATECALL:
        case Op::STATICCALL:
            return upto(k34);
        case Op::CREATE:
        case Op::CREATE2:
            return upto(k2);
        case Op::PRECOMPILED:
            return upto(k3);
        case Op::REQUIRE:
            return upto(k1);
        default:
            return {};
    }
}

// ---- ranges ------------------------------------------------------------------------

Value make_range(Value start, Value len) { return mk(Op::RANGE, start, len); }

Value range_end(Value r) { return padd(r[0], r[1]); }

Tri overlaps(Value r1, Value r2, const Facts* f) {
    if (!is_range(r1) || !is_range(r2)) return Tri::None;
    const Value s1 = r1[0], n1 = r1[1], s2 = r2[0], n2 = r2[1];
    if (auto a = nat(s1), la = nat(n1), b = nat(s2), lb = nat(n2); a && la && b && lb) {
        if (*la == 0 || *lb == 0) return Tri::False;
        return tri(*a < *b + *lb && *b < *a + *la);
    }
    const Tri e1 = is_empty(n1, f), e2 = is_empty(n2, f);
    if (e1 == Tri::True || e2 == Tri::True) return Tri::False;
    const Value end1 = padd(s1, n1), end2 = padd(s2, n2);
    if (pos_le(end2, s1, f) == Tri::True || pos_le(end1, s2, f) == Tri::True) return Tri::False;
    if (e1 == Tri::False && e2 == Tri::False && pos_lt(s1, end2, f) == Tri::True && pos_lt(s2, end1, f) == Tri::True)
        return Tri::True;
    return Tri::None;
}

Tri contains(Value outer, Value inner, const Facts* f) {
    if (!is_range(outer) || !is_range(inner)) return Tri::None;
    if (outer == inner) return Tri::True;
    const Value so = outer[0], no = outer[1], si = inner[0], ni = inner[1];
    if (auto a = nat(so), la = nat(no), b = nat(si), lb = nat(ni); a && la && b && lb) {
        if (*lb == 0) return Tri::True;
        return tri(*a <= *b && *b + *lb <= *a + *la);
    }
    const Tri ei = is_empty(ni, f);
    if (ei == Tri::True) return Tri::True;
    const Value eo = padd(so, no), ein = padd(si, ni);
    if (pos_le(so, si, f) == Tri::True && pos_le(ein, eo, f) == Tri::True) return Tri::True;
    if (ei == Tri::False) {
        if (is_empty(no, f) == Tri::True) return Tri::False;
        if (pos_lt(si, so, f) == Tri::True || pos_lt(eo, ein, f) == Tri::True) return Tri::False;
    }
    return Tri::None;
}

Tri overwrites(Value write, Value read, const Facts* f) {
    if (!is_range(write) || !is_range(read)) return Tri::None;
    if (is_empty(read[1], f) == Tri::True) return Tri::False;
    if (contains(write, read, f) == Tri::True) return Tri::True;
    if (overlaps(write, read, f) == Tri::False) return Tri::False;
    return Tri::None;
}

SmallVec<Value, 2> survivors(Value read, Value write, const Facts* f) {
    SmallVec<Value, 2> all{read};
    if (!is_range(read) || !is_range(write)) return all;
    if (is_empty(read[1], f) == Tri::True) return {};
    if (overlaps(write, read, f) == Tri::False) return all;
    if (contains(write, read, f) == Tri::True) return {};
    // the write writes bytes for sure, where it's decided
    if (is_empty(write[1], f) != Tri::False) return all;
    const Value sr = read[0], er = range_end(read), sw = write[0], ew = range_end(write);
    SmallVec<Value, 2> res;
    // before the write
    if (pos_le(sw, sr, f) != Tri::True) {
        if (pos_lt(sr, sw, f) != Tri::True || pos_le(sw, er, f) != Tri::True) return all;
        res.push_back(make_range(sr, psub(sw, sr)));
    }
    // after it
    if (pos_le(er, ew, f) != Tri::True) {
        if (pos_lt(ew, er, f) != Tri::True || pos_le(sr, ew, f) != Tri::True) return all;
        res.push_back(make_range(ew, psub(er, ew)));
    }
    return res;
}

// ---- reads from the writes before them -------------------------------------------

namespace {

// The parts of `piece` a write over `write` leaves as they were for sure
// (python splits_mem's: knowledge kept, a subset - survivors is the
// superset): the bytes before the write's start, and after its end when
// that end is known; each where its bounds are decided.
SmallVec<Value, 2> untouched(Value piece, Value write, const Facts* f) {
    SmallVec<Value, 2> res;
    const Value sp = piece[0], ep = range_end(piece), sw = write[0], ew = range_end(write);
    if (pos_lt(sp, sw, f) == Tri::True)
        if (auto hi = pos_min(sw, ep, f)) res.push_back(make_range(sp, psub(*hi, sp)));
    if (pos_lt(ew, ep, f) == Tri::True)
        if (auto lo = pos_max(ew, sp, f)) res.push_back(make_range(*lo, psub(ep, *lo)));
    return res;
}

}  // namespace

MemWrite as_write(Value line) {
    if (line.is(Op::SETMEM, 2) && is_range(line[0])) return MemWrite{line[0], line[1]};
    return MemWrite{};
}

MemState::MemState(bool fresh, const Facts* facts)
    : facts_(facts),
      fresh_(fresh),
      pieces_(cx().budget.resource()),
      spans_(cx().budget.resource()),
      written_(cx().budget.resource()) {}

MemState::MemState(const MemState& o)
    : facts_(o.facts_),
      fresh_(o.fresh_),
      pieces_(o.pieces_, o.pieces_.get_allocator()),
      spans_(o.spans_, o.spans_.get_allocator()),
      written_(o.written_, o.written_.get_allocator()) {}

void MemState::unfresh() noexcept {
    fresh_ = false;
    spans_.clear();
    written_.clear();
}

void MemState::note_written(Value range) {
    const auto s = nat(range[0]), n = nat(range[1]);
    if (s && n) {
        if (*n == 0) return;
        // [lo, hi) into the sorted disjoint spans, merged with those it meets
        u64 lo = u64(*s), hi = u64(*s) + u64(*n);
        auto it = std::lower_bound(spans_.begin(), spans_.end(), lo,
                                   [](const Span& x, u64 v) { return x.hi < v; });
        auto first = it;
        while (it != spans_.end() && it->lo <= hi) {
            lo = std::min(lo, it->lo);
            hi = std::max(hi, it->hi);
            ++it;
        }
        it = spans_.erase(first, it);
        spans_.insert(it, Span{lo, hi});
        return;
    }
    if (written_.size() >= kMaxSymbolicWritten) {
        unfresh();
        return;
    }
    written_.push_back(range);
}

bool MemState::untouched_since_start(Value gap) const {
    const Facts* f = facts_;
    if (auto s = nat(gap[0]), n = nat(gap[1]); s && n) {
        const u64 lo = u64(*s), hi = u64(*s) + u64(*n);
        auto it = std::lower_bound(spans_.begin(), spans_.end(), lo,
                                   [](const Span& x, u64 v) { return x.hi <= v; });
        if (it != spans_.end() && it->lo < hi) return false;
    } else {
        for (const Span& sp : spans_)
            if (overlaps(make_range(small(i64(sp.lo)), small(i64(sp.hi - sp.lo))), gap, f) != Tri::False) return false;
    }
    for (Value w : written_)
        if (overlaps(w, gap, f) != Tri::False) return false;
    return true;
}

void MemState::write(Value range, Value value) {
    if (range.nil() || !is_range(range)) {
        clear();
        return;
    }
    const Facts* f = facts_;
    const Value len = range[1];
    if (is_empty(len, f) == Tri::True) return;  // no bytes: nothing changes
    // a copy of memory: what's known of its source, read before the write
    if (!value.nil() && value.has_flags(F_MEM)) {
        if (value.is(Op::MEM, 1)) {
            if (auto r = read(value[0])) value = *r;
        } else if (value.is(Op::DATA)) {
            SmallVec<Value, 8> parts;
            bool changed = false;
            for (Value e : value.args()) {
                if (e.is(Op::MEM, 1))
                    if (auto r = read(e[0])) {
                        parts.push_back(*r);
                        changed = true;
                        continue;
                    }
                parts.push_back(e);
            }
            bool arr = false;
            for (Value e : parts) arr = arr || e.is(Op::ARR);
            if (changed && !arr) value = concat_f(parts.span(), f);
        }
    }
    std::pmr::vector<Piece> kept(pieces_.get_allocator());
    kept.reserve(pieces_.size() + 2);
    for (const Piece& p : pieces_) {
        poll();
        // a piece that reads memory the write may change isn't what it was
        if (reads_mem_in(p.range, range, f) || reads_mem_in(p.value, range, f)) continue;
        const Tri ov = overlaps(p.range, range, f);
        if (ov == Tri::False) {
            kept.push_back(p);
            continue;
        }
        if (contains(range, p.range, f) == Tri::True) continue;
        // what's left of it for sure
        for (Value r : untouched(p.range, range, f)) {
            auto v = slice(p.value, psub(r[0], p.range[0]), psub(range_end(r), p.range[0]), f);
            if (v) kept.push_back(Piece{r, *v});
        }
    }
    if (fresh_) {
        // (where a write was must be where it is now: a range that reads
        // memory this write may change, or msize, ends what's known fresh)
        bool stable = !range.has_flags(F_MSIZE) && !reads_mem_in(range, range, f);
        for (Value w : written_)
            if (!stable || reads_mem_in(w, range, f)) {
                stable = false;
                break;
            }
        if (stable)
            note_written(range);
        else
            unfresh();
    }
    // the write itself, when its value and range stand for its bytes later
    if (!value.nil() && !value.has_flags(F_MSIZE) && !range.has_flags(F_MSIZE) && !reads_mem_in(value, range, f) &&
        !reads_mem_in(range, range, f)) {
        bool ok = true;
        if (is_bytes(value)) {
            auto w = width_of(value);
            ok = w && same_int(*w, len);
        }
        if (ok) kept.push_back(Piece{range, sized(len, value)});
    }
    pieces_.swap(kept);
}

void MemState::clear() noexcept {
    pieces_.clear();
    unfresh();
}

void MemState::forget_flags(u8 content_flags) {
    std::erase_if(pieces_, [&](const Piece& p) {
        return p.range.has_flags(content_flags) || p.value.has_flags(content_flags);
    });
    for (Value w : written_)
        if (w.has_flags(content_flags)) {
            unfresh();
            break;
        }
}

void MemState::forget_name(Value name) {
    std::erase_if(pieces_, [&](const Piece& p) { return mentions(p.range, name) || mentions(p.value, name); });
    for (Value w : written_)
        if (mentions(w, name)) {
            unfresh();
            break;
        }
}

std::optional<Value> MemState::read(Value range) const {
    if (!is_range(range)) return std::nullopt;
    const Facts* f = facts_;
    const Value sr = range[0], len = range[1];
    if (is_empty(len, f) == Tri::True) return mk(Op::DATA, std::span<const Value>{});
    // a piece of that very range: it (the pieces are disjoint)
    for (const Piece& p : pieces_)
        if (p.range == range) return p.value;
    const Value er = range_end(range);
    // the pieces it meets for sure, where: [a, b) from the read's start
    struct Part {
        Value a, b, value;
    };
    SmallVec<Part, 8> parts;
    for (const Piece& p : pieces_) {
        poll();
        if (overlaps(p.range, range, f) == Tri::False) continue;
        const Value sp = p.range[0], ep = range_end(p.range);
        auto lo = pos_max(sp, sr, f);
        auto hi = pos_min(ep, er, f);
        if (!lo || !hi || pos_le(*lo, *hi, f) != Tri::True) continue;
        auto v = slice(p.value, psub(*lo, sp), psub(*hi, sp), f);
        if (!v) continue;
        Part part{psub(*lo, sr), psub(*hi, sr), *v};
        // in order (the pieces are disjoint: where it goes, when decided)
        usize at = 0;
        bool placed = true;
        while (at < parts.size()) {
            if (pos_le(parts[at].b, part.a, f) == Tri::True) {
                ++at;
                continue;
            }
            if (pos_le(part.b, parts[at].a, f) != Tri::True) placed = false;
            break;
        }
        if (!placed) continue;
        parts.push_back(part);
        for (usize k = parts.size() - 1; k > at; --k) parts[k] = parts[k - 1];
        parts[at] = part;
    }
    // the bytes between them: zeroes of fresh memory, or memory as it is here
    bool known = !parts.empty();
    auto gap = [&](Value a, Value b, SmallVec<Value, 8>& out) {
        if (a == b) return;
        if (pos_le(b, a, f) == Tri::True) return;
        const Value start = padd(sr, a), glen = psub(b, a);
        if (fresh_) {
            auto n = nat(glen);
            if (n && *n <= i64(limits::MAX_ZEROES_SIZE)) {
                if (untouched_since_start(make_range(start, glen))) {
                    known = true;
                    out.push_back(mk(Op::SIZED, glen, kZero));
                    return;
                }
            }
        }
        out.push_back(mk(Op::MEM, make_range(start, glen)));
    };
    SmallVec<Value, 8> out;
    Value pos = kZero;
    for (const Part& p : parts) {
        gap(pos, p.a, out);
        out.push_back(p.value);
        pos = p.b;
    }
    gap(pos, len, out);
    if (!known) return std::nullopt;
    return concat_f(out.span(), f);
}

std::optional<Value> MemState::read_word(Value range) const {
    auto b = read(range);
    if (!b) return std::nullopt;
    return as_word(*b);
}

void MemState::meet(const MemState& other) {
    if (&other == this) return;
    MemoSet<Key2> theirs;
    for (const Piece& p : other.pieces_) theirs.add(Key2{p.range.raw(), p.value.raw()});
    std::erase_if(pieces_, [&](const Piece& p) { return !theirs.contains(Key2{p.range.raw(), p.value.raw()}); });
    if (!(fresh_ && other.fresh_)) {
        unfresh();
        return;
    }
    // written on either path
    for (const Span& sp : other.spans_) note_written(make_range(small(i64(sp.lo)), small(i64(sp.hi - sp.lo))));
    MemoSet<Value> mine;
    for (Value r : written_) mine.add(r);
    for (Value r : other.written_)
        if (fresh_ && mine.add(r)) note_written(r);
}

std::optional<Value> fill(Value read_range, std::span<const MemWrite> writes, const Facts* facts) {
    MemState st(false, facts);
    for (const MemWrite& w : writes) st.write(w);
    return st.read(read_range);
}

// ---- splits of a write of fields ---------------------------------------------------

std::optional<SmallVec<Field, 8>> split_word(Value word) {
    struct Row {
        i64 lo, hi;
        Value v;
    };
    SmallVec<Row, 8> rows;
    auto terms = word.is(Op::OR) ? word.args() : std::span<const Value>(&word, 1);
    for (Value t : terms) {
        poll();
        if (t.is_int()) {
            const Word256 w = alg::word_of(t);
            if (w.is_zero()) continue;
            const alg::BitSpan sp = alg::find_mask(w);
            const i64 off = sp.off, size = sp.size;
            rows.push_back(Row{off, off + size, alg::mask(size, off, -off, t)});
            continue;
        }
        if (auto m = alg::as_mask(t); m && m->concrete()) {
            const i64 lo = m->lo(), hi = m->hi();
            if (lo < 0 || hi > 256 || lo >= hi || alg::may_be_wide(m->x)) return std::nullopt;
            rows.push_back(Row{lo, hi, alg::mask(m->isize(), m->ioff(), -m->ioff(), m->x)});
            continue;
        }
        if (t.is(Op::MUL, 2) && t[0].is_int()) {
            if (auto p = alg::to_exp2(t[0]); p && *p > 0 && *p < 256) {
                // x moved up by p: its bits, as many as it may have
                const i64 hi = std::min<i64>(256, i64(*p) + i64(alg::max_bits(t[1])));
                if (hi <= i64(*p)) continue;
                rows.push_back(Row{i64(*p), hi, alg::mask(hi - i64(*p), 0, 0, t[1])});
                continue;
            }
        }
        // anything else at bit 0: as many bits as it may have (a truth value
        // 1, an address 160, a read of k bytes of memory 8k...)
        u32 b = std::min(alg::max_bits(t), alg::range_bits(t));
        if (is_bytes(t))
            if (auto w = width_u64(t); w && *w < 32) b = std::min<u32>(b, u32(8 * *w));
        if (b >= 256) return std::nullopt;
        if (b == 0) continue;
        rows.push_back(Row{0, i64(b), t});
    }
    if (rows.empty()) return std::nullopt;
    std::stable_sort(rows.begin(), rows.end(), [](const Row& a, const Row& b) { return a.lo < b.lo; });
    SmallVec<Field, 8> res;
    i64 pos = 0;
    for (const Row& r : rows) {
        if (r.lo < pos) return std::nullopt;  // their bits are or-ed
        if (r.lo > pos) res.push_back(Field{u32(r.lo - pos), u32(pos), kZero});
        res.push_back(Field{u32(r.hi - r.lo), u32(r.lo), r.v});
        pos = r.hi;
    }
    if (pos < 256) res.push_back(Field{u32(256 - pos), u32(pos), kZero});
    return res;
}

SmallVec<Value, 4> split_setmem(Value line) {
    SmallVec<Value, 4> one{line};
    if (!line.is(Op::SETMEM, 2) || !is_range(line[0])) return one;
    const Value p = line[0][0], nv = line[0][1];
    const auto n = nat(nv);
    if (!n || *n < 1 || *n > 32) return one;
    Value v = line[1], x;
    if (v.is(Op::SIZED, 2) && same_int(v[0], nv) && !is_bytes(v[1]) && !is_long_const(v[1]))
        x = v[1];
    else if (!is_bytes(v) && !is_long_const(v))
        x = v;
    else
        return one;
    // (python splits ORs only)
    if (!x.is(Op::OR) || x.has_flags(F_MSIZE)) return one;
    auto fields = split_word(x);
    if (!fields) return one;
    const i64 top = 8 * *n;
    // runs of whole bytes: byte j (from the lowest) holds the bits [8j, 8j + 8)
    struct Seg {
        i64 b0, b1;     // bytes [b0, b1) from the lowest
        u32 first, nf;  // its fields: cut[first, first + nf)
    };
    SmallVec<Field, 8> cut;
    SmallVec<Seg, 8> segs;
    for (const Field& fl : *fields) {
        if (fl.value == kZero || i64(fl.off) >= top) continue;
        Field c = fl;
        if (i64(c.off + c.size) > top) {
            c.size = u32(top - c.off);
            c.value = alg::mask(c.size, 0, 0, c.value);
        }
        const i64 b0 = i64(c.off) / 8, b1 = (i64(c.off + c.size) + 7) / 8;
        cut.push_back(c);
        if (!segs.empty() && segs.back().b1 > b0) {
            segs.back().b1 = std::max(segs.back().b1, b1);
            ++segs.back().nf;
        } else {
            segs.push_back(Seg{b0, b1, u32(cut.size() - 1), 1});
        }
    }
    // with the zeroes between them
    SmallVec<Seg, 8> all;
    i64 pos = 0;
    for (const Seg& s : segs) {
        if (s.b0 > pos) all.push_back(Seg{pos, s.b0, 0, 0});
        all.push_back(s);
        pos = s.b1;
    }
    if (pos < *n) all.push_back(Seg{pos, *n, 0, 0});
    if (all.size() < 2) return one;
    SmallVec<Value, 8> lines;
    for (const Seg& s : all) {
        const i64 k = s.b1 - s.b0;
        SmallVec<Value, 4> vals;
        for (u32 i = s.first; i < s.first + s.nf; ++i) {
            const Field& fl = cut[i];
            vals.push_back(alg::mask(fl.size, 0, i64(fl.off) - 8 * s.b0, fl.value));
        }
        Value val = vals.empty() ? kZero : vals.size() == 1 ? vals[0] : alg::bor(vals.span());
        Value r = make_range(padd(p, small(*n - s.b1)), small(k));
        Value l = mk(Op::SETMEM, r, sized(small(k), val));
        cx().pcs.inherit(l, line);
        lines.push_back(l);
    }
    auto ordered = in_order(lines.span(), [](Value a, Value b) {
        return reads_mem_in(a[1], b[0], nullptr) || a[1].has_flags(F_MSIZE);
    });
    if (!ordered) return one;
    return *ordered;
}

namespace {

// x * 256^k (python times_byte): (x, k)
struct TimesByte {
    Value x, k;
};
std::optional<TimesByte> times_byte(Value e) {
    auto is_pow = [](Value f) { return f.is(Op::EXP, 2) && f[0] == small(256); };
    if (is_pow(e)) return TimesByte{small(1), e[1]};
    if (e.is(Op::SHL, 2)) {
        // x << 8k
        Value s = e[0];
        if (s.is(Op::MUL, 2) && s[0] == small(8)) return TimesByte{e[1], s[1]};
        return std::nullopt;
    }
    if (!e.is(Op::MUL)) return std::nullopt;
    SmallVec<Value, 4> others;
    std::optional<Value> k;
    for (Value f : e.args()) {
        if (is_pow(f)) {
            if (k) return std::nullopt;
            k = f[1];
        } else if (f != small(1)) {
            others.push_back(f);
        }
    }
    if (!k || others.size() != 1) return std::nullopt;
    return TimesByte{others[0], *k};
}

// whether the value of the store a may read bits the store b writes (of
// its slot, or of one that may be it) - python store_reads_written
bool store_reads_written(Value a, Value b) {
    const Value bsize = b[0], boff = b[1], bslot = b[2];
    const Value v = a[3];
    if (!v.has_flags(F_STORAGE)) return false;
    MemoSet<Value> seen;
    SmallVec<Value, 32> todo{v};
    while (!todo.empty()) {
        poll();
        Value x = todo.back();
        todo.pop_back();
        if (!x.is_node() || !x.has_flags(F_STORAGE) || !seen.add(x)) continue;
        if (x.is(Op::STORAGE, 3)) {
            auto d = alg::const_diff(x[2], bslot);
            if (!(d && *d != kZero)) {
                if (!x[0].is_small() || !x[1].is_small() || !bsize.is_small() || !boff.is_small()) return true;
                i64 roff = std::max<i64>(0, x[1].small_val());
                const i64 rsize = x[0].small_val(), off = boff.small_val(), size = bsize.small_val();
                if (roff < off + size && off < roff + rsize) return true;
            }
        } else if (x.op() != Op::NONE && has(x.op(), R_STORAGE)) {
            return true;  // another read of the storage (length, ...)
        }
        for (Value c : x.children()) todo.push_back(c);
    }
    return false;
}

}  // namespace

std::optional<Value> byte_field_store(Value line) {
    if (!line.is(Op::STORE, 4) || line[0] != small(256) || line[1] != kZero) return std::nullopt;
    const Value slot = line[2], val = line[3];
    if (!val.is(Op::OR, 2)) return std::nullopt;
    const Value stor = mk(Op::STORAGE, small(256), kZero, slot);
    for (int i = 0; i < 2; ++i) {
        const Value put = val[i], keep = val[1 - i];
        if (!keep.is(Op::AND, 2)) continue;
        for (int j = 0; j < 2; ++j) {
            const Value cleared = keep[j], s = keep[1 - j];
            if (s != stor || !cleared.is(Op::NOT, 1)) continue;
            auto mask = times_byte(cleared[0]);
            auto v = times_byte(put);
            if (!mask || !v || mask->k != v->k || !mask->x.is_int()) continue;
            const Word256 mw = alg::word_of(mask->x);
            auto run = alg::as_bit_run(mw);
            if (!run || run->off != 0) continue;
            const u32 size = run->size;
            if (alg::max_bits(v->x) > size) continue;
            const alg::Range rk = alg::range(v->k);
            if (rk.lo.sign() < 0 || rk.hi * EvmInt(8) + EvmInt(i64(size)) > EvmInt(256)) continue;
            Value l = mk(Op::STORE, small(size), alg::mul(small(8), v->k), slot, v->x);
            cx().pcs.inherit(l, line);
            return l;
        }
    }
    return std::nullopt;
}

namespace {

// python merge_zeros: a value that fits in its part with the 0 bits after
// it, up to a whole byte: one store of both
SmallVec<Value, 8> merge_zeros(std::span<const Value> stores) {
    SmallVec<Value, 8> res;
    for (Value s : stores) {
        if (!res.empty()) {
            Value last = res.back();
            if (last[0].is_small() && last[1].is_small() && s[0].is_small() && s[1].is_small() && s[3] == kZero) {
                const i64 size = last[0].small_val(), off = last[1].small_val();
                if (s[1].small_val() == off + size && size % 8 && alg::max_bits(last[3]) <= u32(size)) {
                    const i64 grow = std::min<i64>(s[0].small_val(), 8 - size % 8);
                    Value grown = mk(Op::STORE, small(size + grow), last[1], last[2], last[3]);
                    cx().pcs.inherit(grown, last);
                    res.back() = grown;
                    if (grow < s[0].small_val()) {
                        Value rest = mk(Op::STORE, small(s[0].small_val() - grow), small(s[1].small_val() + grow), s[2], kZero);
                        cx().pcs.inherit(rest, s);
                        res.push_back(rest);
                    }
                    continue;
                }
            }
        }
        res.push_back(s);
    }
    return res;
}

}  // namespace

SmallVec<Value, 4> split_store(Value line) {
    SmallVec<Value, 4> one{line};
    if (!line.is(Op::STORE, 4)) return one;
    if (auto r = byte_field_store(line)) return SmallVec<Value, 4>{*r};
    if (line[0] != small(256) || line[1] != kZero) return one;
    const Value slot = line[2], val = line[3];
    auto fields = split_word(val);
    if (!fields) return one;
    auto same = [&](const Field& fl) { return fl.value == mk(Op::STORAGE, small(fl.size), small(fl.off), slot); };
    bool any_same = false;
    u32 values = 0;
    for (const Field& fl : *fields) {
        if (same(fl))
            any_same = true;
        else if (fl.value != kZero)
            ++values;
    }
    // one value: the word it makes, rather than it at its bits and zeroes
    // around them (but a store that keeps some bits of the slot is split)
    if (!any_same && values < 2) return one;
    SmallVec<Value, 8> res;
    for (const Field& fl : *fields) {
        if (same(fl)) continue;
        Value l = mk(Op::STORE, small(fl.size), small(fl.off), slot, fl.value);
        cx().pcs.inherit(l, line);
        res.push_back(l);
    }
    if (res.empty()) return one;  // (it writes the slot as it is)
    SmallVec<Value, 8> merged = merge_zeros(res.span());
    auto ordered = in_order(merged.span(), [](Value a, Value b) { return store_reads_written(a, b); });
    if (!ordered) return one;
    return *ordered;
}

}  // namespace pan::mem
