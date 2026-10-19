// The accesses and the paths of their slots (python storage.py: find_accesses,
// hash_table / hash_constant, word, is_word, parse, steps, from_calldata,
// linear, packed).
#include <algorithm>
#include <array>
#include <bit>
#include <mutex>

#include "algebra/construct.hpp"
#include "core/context.hpp"
#include "core/errors.hpp"
#include "exec/machine.hpp"
#include "mem/memory.hpp"
#include "storage/internal.hpp"

namespace pan::storage::detail {

// ---- accesses ----------------------------------------------------------------------

void Accesses::add(const Access& a, Written w) {
    bool ins = false;
    u32& k = map_.slot(a.key(), &ins);
    if (ins) {
        list_.push_back(a);
        written_.push_back(w);
        k = u32(list_.size());
        return;
    }
    Written& cur = written_[k - 1];
    if (w == Written::Yes)
        cur = Written::Yes;
    else if (w == Written::Const && cur != Written::Yes)
        cur = Written::Const;
}

void Accesses::walk(Value v, Memo<Value, u8>& seen) {
    check_stack();
    // (not an ASM line's: --verbose's stacks are no accesses of the code's)
    if (!v.is_node() || !v.has_flags(F_STORAGE | F_WRITES) || v.is(Op::ASM)) return;
    if (v.is_expr() || v.is_list()) {
        if (!seen.add(v)) return;
        poll();
        if (v.is(Op::STORAGE, 3)) {
            add(Access{v[0], v[1], v[2]}, Written::No);
        } else if (v.is(Op::STORE, 4)) {
            add(Access{v[0], v[1], v[2]}, v[3].is_int() ? Written::Const : Written::Yes);
        }
        for (Value c : v.children()) walk(c, seen);
    }
}

void Accesses::find(Value trace) {
    Memo<Value, u8> seen;
    walk(trace, seen);
}

// ---- words of data ---------------------------------------------------------------------

bool is_bytes_expr(Value v) noexcept { return v.is_bytes() || (v.is_expr() && info(v.op()).sort == Sort::Bytes); }

Value word(Value e) {
    if (e.is(Op::SIZED, 2) && is_small(e[0], 32) && !is_bytes_expr(e[1])) return e[1];
    return e;
}

bool is_word(Value e) { return e.is(Op::SIZED, 2) && is_small(e[0], 32) && !is_bytes_expr(e[1]); }

bool from_calldata(Value e) {
    for (int depth = 0; depth < 64; ++depth) {
        if (e.is(Op::CALLDATALOAD) || e.is_name(NameKind::PARAM)) return true;
        if (!e.is(Op::MASK_SHL, 4)) return false;
        e = e[3];
    }
    return false;
}

// ---- the hash table --------------------------------------------------------------------

namespace {

constexpr u32 DATA_SLOTS = 4096, MAP_KEYS = 16, MAP_SLOTS = 64;
constexpr u32 MAX_DELTA = 1u << 16;

struct HashEntry {
    Word256 hash;
    u32 n;
    i32 key;  // -1: keccak(n)
};

struct HashTables {
    std::array<std::vector<HashEntry>, 2> t;  // solidity, vyper
};

const HashTables& hash_tables() {
    static HashTables tables;
    static std::once_flag once;
    std::call_once(once, [] {
        for (int lang = 0; lang < 2; ++lang) {
            std::vector<HashEntry>& v = tables.t[lang];
            v.reserve(DATA_SLOTS + MAP_SLOTS * MAP_KEYS);
            u8 buf[64] = {};
            for (u32 n = 0; n < DATA_SLOTS; ++n) {
                Word256::of(n).to_be(buf);
                v.push_back({exec::keccak256(std::span<const u8>(buf, 32)), n, -1});
            }
            for (u32 n = 0; n < MAP_SLOTS; ++n)
                for (u32 k = 0; k < MAP_KEYS; ++k) {
                    if (lang == 1) {  // vyper: slot . key
                        Word256::of(n).to_be(buf);
                        Word256::of(k).to_be(buf + 32);
                    } else {
                        Word256::of(k).to_be(buf);
                        Word256::of(n).to_be(buf + 32);
                    }
                    v.push_back({exec::keccak256(std::span<const u8>(buf, 64)), n, i32(k)});
                }
            std::sort(v.begin(), v.end(), [](const HashEntry& a, const HashEntry& b) {
                if (a.hash != b.hash) return a.hash < b.hash;
                if (a.n != b.n) return a.n < b.n;
                return a.key < b.key;
            });
        }
    });
    return tables;
}

}  // namespace

std::optional<HashHit> hash_constant(const Word256& c, Lang lang) {
    const std::vector<HashEntry>& t = hash_tables().t[lang == Lang::Vyper ? 1 : 0];
    // the last entry whose hash is <= c (python's bisect_right of (c, "~"))
    auto it = std::upper_bound(t.begin(), t.end(), c, [](const Word256& x, const HashEntry& e) { return x < e.hash; });
    if (it == t.begin()) return std::nullopt;
    --it;
    // (entries of one hash: the greatest by python's tuple order - the last)
    const Word256 d = pan::sub(c, it->hash);
    const auto du = d.as_u64();
    if (!du || *du >= MAX_DELTA) return std::nullopt;
    HashHit h;
    h.n = it->n;
    if (it->key >= 0) h.key = u32(it->key);
    h.delta = u32(*du);
    return h;
}

// ---- linear, packed ------------------------------------------------------------------------

namespace {

std::optional<EvmInt> int_of(Value v) {
    if (v.is_int()) return EvmInt(v);
    return std::nullopt;
}

std::optional<u32> log2_of(i64 n) {
    if (n <= 0 || (n & (n - 1))) return std::nullopt;
    return u32(std::countr_zero(u64(n)));
}

}  // namespace

Lin linear(Value e) {
    check_stack();
    if (e.is_int()) return Lin{Value(), EvmInt(0), EvmInt(e)};
    if (e.is(Op::ADD)) {
        EvmInt c(0);
        SmallVec<Value, 8> rest;
        for (Value t : e.args()) {
            if (t.is_int())
                c = c + EvmInt(t);
            else
                rest.push_back(t);
        }
        if (rest.size() == 1) {
            Lin l = linear(rest[0]);
            l.c = l.c + c;
            return l;
        }
        if (rest.empty()) return Lin{Value(), EvmInt(0), c};
        return Lin{alg::add(rest.span()), EvmInt(1), c};
    }
    if (e.is(Op::MUL, 2) && e[0].is_int()) {
        const EvmInt s(e[0]);
        if (s.sign() > 0) return Lin{e[1], s, EvmInt(0)};
    }
    if (auto m = alg::as_mask(e); m && m->concrete()) {
        // x's field times 2^p (p = off + shl > 0): the field is the index
        const i64 size = m->isize(), off = m->ioff(), shl = m->ishl();
        const i64 p = off + shl;
        if (size > 0 && off >= 0 && p > 0 && p < 256) {
            if (off == 0 && size + shl >= 256) return Lin{m->x, EvmInt::pow2(u64(p)), EvmInt(0)};
            return Lin{alg::mask(size, off, -off, m->x), EvmInt::pow2(u64(p)), EvmInt(0)};
        }
    }
    return Lin{e, EvmInt(1), EvmInt(0)};
}

Value packed(Value e, Value off, Value width_v) {
    const auto width = small_of(width_v);
    if (!width || *width <= 0 || *width > 256) return Value();
    const i64 per = 256 / *width;
    const auto lp = log2_of(per), lw = log2_of(*width);
    if (!lp || !lw || per < 2) return Value();
    if (off.is_int()) {
        const auto o = small_of(off);
        if (!o) return Value();
        if (e.is_int()) {
            const EvmInt ei(e);
            if (*o % *width == 0 && *o >= 0 && ei.sign() >= 0 && ei.fits_i64() && ei.to_i64() < (i64(1) << 40))
                return mk_int(ei.to_i64() * per + *o / *width);
        }
        return Value();
    }
    // off = (x % per) * width, e = x / per: off is a field of some y moved to
    // the bit lw - y's bits [o, o + a) - and x a field of y from o (python's
    // MASK_SHL(a, 0, lw, x) when x is all of y; the algebra makes one mask of
    // a mask of a field: uint16 fields of a word as indexes), checked by
    // making both again from x
    const auto m = alg::as_mask(off);
    const i64 LP = i64(*lp), LW = i64(*lw);
    if (!m || !m->concrete() || m->ioff() + m->ishl() != LW || m->isize() <= 0 || m->isize() > LP) return Value();
    const i64 a = m->isize(), o = m->ioff();
    const Value y = m->x;
    auto made = [&](Value x) { return alg::mask(LP, 0, LW, x) == off && alg::mask(256 - LP, LP, -LP, x) == e; };
    if (o == 0 && a == LP && made(y)) return y;
    if (a < LP) {
        const Value x = alg::mask(a, o, -o, y);
        if (is_small(e, 0) && made(x)) return x;
        return Value();
    }
    const alg::MaskShl ev = alg::mask_view(e);
    if (ev.concrete() && ev.x == y && ev.ioff() == o + LP && ev.ishl() == -(o + LP) && ev.isize() > 0 &&
        ev.isize() + LP + o <= 256) {
        const Value x = alg::mask(ev.isize() + LP, o, -o, y);
        if (made(x)) return x;
    }
    return Value();
}

// ---- parse --------------------------------------------------------------------------------

namespace {

// python ("off", path, e) folded by steps(): a slot after the root another
// root, offsets one after the other one
std::optional<Path> off_path(std::optional<Path> p, Value e) {
    if (!p) return std::nullopt;
    if (p->steps.empty() && e.is_int()) {
        p->root = pan::add(p->root, Word256::from_value(e));
        return p;
    }
    if (!p->steps.empty() && p->steps.back().kind == Step::Kind::Off) {
        p->steps.back().e = alg::add(p->steps.back().e, e);
        return p;
    }
    p->steps.push_back(Step{Step::Kind::Off, e, false});
    return p;
}

std::optional<Path> hash_path(const HashHit& h) {
    Path p;
    p.root = Word256::of(h.n);
    if (h.key)
        p.steps.push_back(Step{Step::Kind::Map, small(i64(*h.key)), false});
    else
        p.steps.push_back(Step{Step::Kind::Data, Value(), false});
    return p;
}

}  // namespace

std::optional<Path> Parser::parse(Value idx) {
    check_stack();
    if (const u32* k = memo_.find(idx)) return paths_[*k];
    std::optional<Path> r = compute(idx);
    memo_.put(idx, u32(paths_.size()));
    paths_.push_back(r);
    return r;
}

std::optional<Path> Parser::compute(Value idx0) {
    const Value idx = word(idx0);
    if (idx.is_int()) {
        const Word256 c = Word256::from_value(idx);
        if (const auto h = hash_constant(c, lang_)) {
            std::optional<Path> p = hash_path(*h);
            return h->delta ? off_path(std::move(p), small(h->delta)) : p;
        }
        return Path{c, {}};
    }
    if (idx.is(Op::LOC, 1) && idx[0].is_int()) return Path{Word256::from_value(idx[0]), {}};
    if (idx.is(Op::LENGTH, 1)) {
        std::optional<Path> inner = parse(idx[0]);
        if (!inner) return std::nullopt;
        inner->steps.push_back(Step{Step::Kind::Blen, Value(), false});
        return inner;
    }
    if (idx.is(Op::SHA3)) {
        std::span<const Value> parts = idx.args();
        if (parts.size() == 1 && parts[0].is(Op::DATA)) parts = parts[0].args();
        if (parts.empty()) return std::nullopt;
        if (parts.size() == 1 && is_word(parts[0])) {
            std::optional<Path> inner = parse(parts[0]);
            if (!inner) return std::nullopt;
            inner->steps.push_back(Step{Step::Kind::Data, Value(), false});
            return inner;
        }
        const bool vyper = lang_ == Lang::Vyper;
        const Value slot = vyper ? parts.front() : parts.back();
        const std::span<const Value> key = vyper ? parts.subspan(1) : parts.first(parts.size() - 1);
        if (!is_word(slot)) return std::nullopt;
        std::optional<Path> inner = parse(slot);
        if (!inner) return std::nullopt;
        if (key.size() == 1 && is_word(key[0]))
            inner->steps.push_back(Step{Step::Kind::Map, word(key[0]), false});
        else
            inner->steps.push_back(Step{Step::Kind::Map, mk(Op::DATA, key), true});
        return inner;
    }
    if (idx.is(Op::ADD)) {
        SmallVec<Value, 8> terms;
        for (Value t : idx.args()) {
            if (t.is(Op::ADD))
                for (Value u : t.args()) terms.push_back(u);
            else
                terms.push_back(t);
        }
        SmallVec<usize, 4> bases;
        for (usize k = 0; k < terms.size(); ++k)
            if (terms[k].is(Op::SHA3) || (terms[k].is_int() && hash_constant(Word256::from_value(terms[k]), lang_)))
                bases.push_back(k);
        if (bases.size() == 1) {
            const Value base = terms[bases[0]];
            SmallVec<Value, 8> rest;
            for (usize k = 0; k < terms.size(); ++k)
                if (k != bases[0]) rest.push_back(terms[k]);
            std::optional<Path> p;
            if (base.is_int()) {
                const auto h = hash_constant(Word256::from_value(base), lang_);
                p = hash_path(*h);
                if (h->delta) rest.push_back(small(h->delta));
            } else {
                p = parse(base);
            }
            if (!p) return std::nullopt;
            const Value e = rest.size() > 1 ? alg::add(rest.span()) : rest[0];
            return off_path(std::move(p), e);
        }
        if (bases.empty()) {
            SmallVec<usize, 2> consts;
            for (usize k = 0; k < terms.size(); ++k)
                if (terms[k].is_int()) consts.push_back(k);
            if (consts.size() == 1) {
                const Word256 c = Word256::from_value(terms[consts[0]]);
                SmallVec<Value, 8> rest;
                for (usize k = 0; k < terms.size(); ++k)
                    if (k != consts[0]) rest.push_back(terms[k]);
                const Value e = rest.size() > 1 ? alg::add(rest.span()) : rest[0];
                return off_path(Path{c, {}}, e);
            }
        }
        return std::nullopt;
    }
    // a slot computed from a param: the element of an array at 0 (as vyper puts them)
    if (from_calldata(idx)) return off_path(Path{Word256{}, {}}, idx);
    return std::nullopt;
}

}  // namespace pan::storage::detail
