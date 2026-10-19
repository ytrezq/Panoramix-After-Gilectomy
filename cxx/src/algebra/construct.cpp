// The algebra's constructors and their normal forms (construct.hpp).
#include "algebra/construct.hpp"

#include <algorithm>

#include "algebra/eval.hpp"
#include "algebra/linear.hpp"
#include "algebra/masks.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/errors.hpp"
#include "core/intops.hpp"
#include "core/order.hpp"
#include "core/smallvec.hpp"

namespace pan::alg {

namespace {

// ---------------------------------------------------------------- words

inline bool is_const(Value v) noexcept { return v.is_int() || v.is_bool(); }
inline Word256 cw(Value v) noexcept { return word_of(v); }
inline Value wv(const Word256& w) { return value_of(w); }
inline Word256 w_ones() noexcept { return Word256{{~u64(0), ~u64(0), ~u64(0), ~u64(0)}}; }
inline bool w_neg(const Word256& w) noexcept { return w.limb[3] >> 63; }
inline Value small(i64 x) noexcept { return Value::small(x); }

u32 tz(const Word256& w) noexcept {
    for (u32 i = 0; i < 4; ++i)
        if (w.limb[i]) return i * 64 + u32(__builtin_ctzll(w.limb[i]));
    return 256;
}

Word256 pow2w(u32 k) noexcept {
    Word256 r{};
    if (k < 256) r.limb[k / 64] = u64(1) << (k % 64);
    return r;
}

// the signed representative of a word, [-2^255, 2^255)
inline Value signed_value(const Word256& w) { return signed_value_of(w); }

// the value of an int-like operand as a signed field, clamped (masks)
inline i64 field_of(Value v) { return clamp_field(cw(v)); }
// an operand of a node made as it is: a constant as its word (one node per value)
inline Value cn(Value v) { return is_const(v) ? wv(cw(v)) : v; }

Value fold(Op op, std::span<const Value> args) {
    SmallVec<Word256, 4> w;
    for (Value a : args) w.push_back(cw(a));
    auto r = eval_op(op, w.span());
    if (!r) throw InternalError("algebra: fold of an impure op");
    return wv(*r);
}

bool all_const(std::span<const Value> args) noexcept {
    for (Value a : args)
        if (!is_const(a)) return false;
    return true;
}

// ---------------------------------------------------------------- memo

struct CtorState final : ModuleState {
    Memo<Key2, Value> add2, mul2, mask, and2, or2;
    Memo<Value, Value> norm;
    // pure functions of their operands: nothing to forget at clear_caches
};

inline CtorState& st() { return cx().state<CtorState>(); }

// ---------------------------------------------------------------- terms

// A term of a sum, k * base: a field of x (bits [off, off + size) of x
// moved down to bit 0, MASK_SHL(size, off, -off, x); x itself when off = 0
// and size = 256), or a plain base (a value wider than a word). The terms
// are ordered by x (compare()), then off, then size.
struct Acc {
    Value base;  // field: x; plain: the base
    Word256 k;   // the coefficient, mod 2^256
    i32 off;     // field: off >= 0; plain: -1
    i32 size;    // field: 0 < size <= 256 - off (256: the whole of x)
};

inline bool is_field(const Acc& a) noexcept { return a.off >= 0; }

// a field's size once k's trailing zeros push its top bits out: 256 for a
// field that is the whole of x times k
i32 eff_size(const Acc& a) noexcept {
    u32 p = tz(a.k);
    if (p >= 256) return 0;
    i32 s = a.size;
    i32 room = i32(256 - p);
    if (a.off == 0 && s >= room) return 256;
    return s < room ? s : room;
}


// is v a concrete canonical mask of a word: its field (off, size, shl)
struct FieldOf {
    Value x;
    i32 off, size, shl;
};
std::optional<FieldOf> field_of_mask(Value v) {
    if (!v.is(Op::MASK_SHL, 4) || !v[0].is_small() || !v[1].is_small() || !v[2].is_small()) return std::nullopt;
    i64 s = v[0].small_val(), o = v[1].small_val(), h = v[2].small_val();
    // canonical masks only (what mask() makes): the bits it takes all kept
    if (s <= 0 || o < 0 || o + s > 256 || o + h < 0 || o + s + h > 256) return std::nullopt;
    if (may_be_wide(v[3])) return std::nullopt;
    return FieldOf{v[3], i32(o), i32(s), i32(h)};
}

Value mask_concrete(i64 s, i64 o, i64 h, Value x, int depth);

void push_term(SmallVec<Acc, 8>& out, Word256& c, Value t, const Word256& k, int depth = 0);

// the most terms a product of sums is distributed into
constexpr usize kMaxExpansion = 64;

// a product k * f1 * ... * fm (constants folded into k) as terms
void push_product(SmallVec<Acc, 8>& out, Word256& c, std::span<const Value> factors, Word256 k, int depth) {
    SmallVec<Value, 8> f;
    for (Value x : factors) {
        if (is_const(x)) {
            k = pan::mul(k, cw(x));
        } else if (x.is(Op::MUL)) {
            for (Value y : x.args()) {
                if (is_const(y))
                    k = pan::mul(k, cw(y));
                else
                    f.push_back(y);
            }
        } else {
            f.push_back(x);
        }
    }
    if (k.is_zero()) return;
    if (f.empty()) {
        c = pan::add(c, k);
        return;
    }
    if (f.size() == 1) {
        push_term(out, c, f[0], k, depth + 1);
        return;
    }
    // a product of sums: distributed when the whole expansion is small (a
    // decision of the factors alone: the result is a fixpoint either way)
    usize expansion = 1;
    for (Value x : f)
        if (x.is(Op::ADD) && (expansion *= x.size()) > kMaxExpansion) break;
    if (expansion > 1 && expansion <= kMaxExpansion) {
        for (usize i = 0; i < f.size(); ++i) {
            if (!f[i].is(Op::ADD)) continue;
            Value s = f[i];
            for (Value t : s.args()) {
                SmallVec<Value, 8> g;
                for (usize j = 0; j < f.size(); ++j) g.push_back(j == i ? t : f[j]);
                push_product(out, c, g.span(), k, depth + 1);
            }
            return;
        }
    }
    // the powers of two of the mask factors moved out into k (their
    // fields at bit 0, through mask(): a storage read narrows...)
    bool redo = false;
    for (Value& x : f) {
        if (auto m = field_of_mask(x); m && m->off + m->shl > 0) {
            k = pan::mul(k, pow2w(u32(m->off + m->shl)));
            x = mask_concrete(m->size, m->off, -m->off, m->x, depth + 1);
            if (is_const(x) || x.is(Op::ADD) || x.is(Op::MUL)) redo = true;
        }
    }
    if (k.is_zero()) return;
    if (redo) {
        push_product(out, c, f.span(), k, depth + 1);
        return;
    }
    std::sort(f.begin(), f.end(), StructuralLess{});
    out.push_back(Acc{mk(Op::MUL, f.span()), k, 0, 256});
}

void push_term(SmallVec<Acc, 8>& out, Word256& c, Value t, const Word256& k, int depth) {
    if (k.is_zero()) return;
    if (depth > 64) throw SizeLimit("algebra: a sum nested too deep");
    if (is_const(t)) {
        c = pan::add(c, pan::mul(k, cw(t)));
        return;
    }
    if (t.is(Op::ADD)) {
        for (Value a : t.args()) push_term(out, c, a, k, depth + 1);
        return;
    }
    if (t.is(Op::SUB, 2)) {
        push_term(out, c, t[0], k, depth + 1);
        push_term(out, c, t[1], pan::sub(Word256{}, k), depth + 1);
        return;
    }
    if (t.is(Op::MUL)) {
        push_product(out, c, t.args(), k, depth);
        return;
    }
    if (t.is(Op::MASK_SHL, 4) && is_const(t[0]) && is_const(t[1]) && is_const(t[2]) && is_const(t[3])) {
        c = pan::add(c, pan::mul(k, mask_shl_word(cw(t[0]), cw(t[1]), cw(t[2]), cw(t[3]))));
        return;
    }
    if (auto m = field_of_mask(t)) {
        Word256 kk = pan::mul(k, pow2w(u32(m->off + m->shl)));
        if (kk.is_zero()) return;
        out.push_back(Acc{m->x, kk, m->off, m->size});
        return;
    }
    // anything else: the whole of t (a field [0, 256) of it)
    if (may_be_wide(t))
        out.push_back(Acc{t, k, -1, 0});
    else
        out.push_back(Acc{t, k, 0, 256});
}

// a field's size as k leaves it (0: the term is 0)
void set_key(Acc& a) {
    if (!is_field(a)) return;
    i32 s = eff_size(a);
    if (s <= 0) {
        a.k = Word256{};
        return;
    }
    a.size = s;  // 256: the whole of x (off 0)
}

int acc_cmp(const Acc& a, const Acc& b) {
    if (int c = compare(a.base, b.base)) return c;
    if (a.off != b.off) return a.off < b.off ? -1 : 1;
    if (a.size != b.size) return a.size < b.size ? -1 : 1;
    return 0;
}

Value mask_concrete(i64 s, i64 o, i64 h, Value x, int depth);

// the term k * base, built in its normal form; *exact = false when the
// mask rules changed the field (the sum is then made again from the terms)
Value build_term(const Acc& a, bool* exact) {
    const Word256& k = a.k;
    if (k.is_zero()) return small(0);
    // k times the whole of x
    auto whole = [&](Value x) -> Value {
        if (k == Word256::of(1)) return x;
        Value ks = signed_value(k);
        if (x.is(Op::MUL) && !is_const(x[0])) {  // a product's base: one MUL
            SmallVec<Value, 8> f;
            f.push_back(ks);
            for (Value y : x.args()) f.push_back(y);
            return mk(Op::MUL, f.span());
        }
        if (x.is(Op::MUL) || x.is(Op::ADD)) {  // (a field of it became all of it)
            *exact = false;
            return mul(ks, x);
        }
        return mk(Op::MUL, ks, x);
    };
    if (!is_field(a) || (a.off == 0 && a.size >= 256)) return whole(a.base);
    u32 p = tz(k);
    if (p >= 256) return small(0);
    i32 s = a.size;
    if (i32(256 - p) < s) s = i32(256 - p);
    if (s <= 0) return small(0);
    if (a.off == 0 && s == i32(256 - p)) return whole(a.base);
    // k = +-2^p: the field moved by p (floor32(x), -floor32(x), uint8(x) << 5);
    // else k times the field at bit 0 (96 * uint8(x), 3 * (x >> 8 & 0xff))
    const Word256 odd = pan::sar(Word256::of(p), k);  // the signed odd part
    const bool unit = odd == Word256::of(1) || odd == w_ones();
    const i64 h = unit ? i64(p) - a.off : -i64(a.off);
    // (through mask(): a narrower field may simplify what it is made of)
    Value m = mask_concrete(s, a.off, h, a.base, 0);
    if (!(m.is(Op::MASK_SHL, 4) && m[3] == a.base && int_is(m[0], s) && int_is(m[1], a.off) && int_is(m[2], h)))
        *exact = false;
    if (unit && odd == Word256::of(1)) return m;
    Value ks = unit ? small(-1) : signed_value(k);
    if (!*exact) return mul(ks, m);
    return mk(Op::MUL, ks, m);
}

// merges the terms of one x, one displacement, that make fewer fields
// together (python try_add: x - (x & 31), adjacent fields of x). The terms
// are sorted: the fields of one x are a run.
bool merge_group(SmallVec<Acc, 8>& terms, const usize* grp, usize ng, Value x, i32 d) {
    // the weights per bit interval: the signed odd parts summed
    SmallVec<i32, 16> cuts;
    for (usize g = 0; g < ng; ++g) {
        cuts.push_back(terms[grp[g]].off);
        cuts.push_back(terms[grp[g]].off + terms[grp[g]].size);
    }
    std::sort(cuts.begin(), cuts.end());
    struct Piece {
        i32 lo, hi;
        Word256 w;
    };
    SmallVec<Piece, 16> pieces;
    for (usize c = 0; c + 1 < cuts.size(); ++c) {
        i32 lo = cuts[c], hi = cuts[c + 1];
        if (lo == hi) continue;
        Word256 w{};
        for (usize g = 0; g < ng; ++g) {
            const Acc& t = terms[grp[g]];
            if (t.off <= lo && hi <= t.off + t.size) w = pan::add(w, pan::sar(Word256::of(tz(t.k)), t.k));
        }
        if (!pieces.empty() && pieces.back().hi == lo && pieces.back().w == w)
            pieces.back().hi = hi;
        else
            pieces.push_back(Piece{lo, hi, w});
    }
    usize nonzero = 0;
    for (const Piece& p : pieces)
        if (!p.w.is_zero()) ++nonzero;
    if (nonzero >= ng) return false;
    // replace: the group's terms zeroed, the pieces appended
    for (usize g = 0; g < ng; ++g) terms[grp[g]].k = Word256{};
    for (const Piece& p : pieces) {
        if (p.w.is_zero()) continue;
        i32 sh = p.lo + d;  // >= 0: lo >= some off of the group
        if (sh >= 256) continue;
        Word256 k = pan::mul(p.w, pow2w(u32(sh)));
        if (!k.is_zero()) terms.push_back(Acc{x, k, p.lo, p.hi - p.lo});
    }
    return true;
}

bool merge_fields(SmallVec<Acc, 8>& terms) {
    bool changed = false;
    const usize n = terms.size();
    for (usize i = 0; i < n;) {
        usize j = i + 1;
        while (j < n && terms[j].base == terms[i].base) ++j;
        if (j - i >= 2 && is_field(terms[i])) {
            // the run's fields grouped by displacement (where bit off lands: tz(k) - off)
            SmallVec<u8, 16> done;
            done.resize(j - i);
            for (usize a = i; a < j; ++a) {
                if (done[a - i] || terms[a].k.is_zero()) continue;
                const i32 d = i32(tz(terms[a].k)) - terms[a].off;
                SmallVec<usize, 8> grp;
                for (usize b = a; b < j; ++b) {
                    if (done[b - i] || terms[b].k.is_zero() || i32(tz(terms[b].k)) - terms[b].off != d) continue;
                    done[b - i] = 1;
                    grp.push_back(b);
                }
                if (grp.size() >= 2 && merge_group(terms, grp.data(), grp.size(), terms[a].base, d)) changed = true;
            }
        }
        i = j;
    }
    return changed;
}

Value add_impl(std::span<const Value> args);

Value add_terms(SmallVec<Acc, 8>& terms, Word256 c, int round) {
    // merge equal keys, until stable (a merged coefficient may shorten a field)
    for (int pass = 0;; ++pass) {
        poll();
        for (Acc& a : terms)
            if (!a.k.is_zero()) set_key(a);
        std::sort(terms.begin(), terms.end(), [](const Acc& a, const Acc& b) {
            if (a.k.is_zero() != b.k.is_zero()) return b.k.is_zero();
            if (a.k.is_zero()) return false;
            return acc_cmp(a, b) < 0;
        });
        while (!terms.empty() && terms.back().k.is_zero()) terms.pop_back();
        bool merged = false;
        SmallVec<Acc, 8> out;
        for (const Acc& a : terms) {
            if (!out.empty() && acc_cmp(out.back(), a) == 0) {
                Acc& b = out.back();
                b.k = pan::add(b.k, a.k);
                merged = true;
                if (b.k.is_zero()) out.pop_back();
                continue;
            }
            out.push_back(a);
        }
        terms = out;
        bool fields = merge_fields(terms);
        if (!merged && !fields) break;
        if (pass > 8) break;
    }
    // build
    SmallVec<Value, 8> built;
    bool again = false;
    for (const Acc& a : terms) {
        if (a.k.is_zero()) continue;
        bool exact = true;
        Value t = build_term(a, &exact);
        if (!exact) again = true;
        if (is_const(t)) {
            c = pan::add(c, cw(t));
            continue;
        }
        if (t.is(Op::ADD) || (t.is(Op::MUL) && t.size() >= 2 && is_const(t[0]) && t[1].is(Op::ADD))) again = true;
        built.push_back(t);
    }
    if (again && round < 4) {
        SmallVec<Value, 8> all;
        if (!c.is_zero()) all.push_back(signed_value(c));
        for (Value t : built) all.push_back(t);
        SmallVec<Acc, 8> t2;
        Word256 c2{};
        for (Value t : all) push_term(t2, c2, t, Word256::of(1));
        return add_terms(t2, c2, round + 1);
    }
    if (built.empty()) return wv(c);
    if (built.size() == 1 && c.is_zero()) return built[0];
    SmallVec<Value, 8> ops;
    if (!c.is_zero()) ops.push_back(signed_value(c));
    for (Value t : built) ops.push_back(t);
    if (ops.size() > limits::MAX_NODE_COUNT) throw SizeLimit("algebra: a sum of too many terms");
    return mk(Op::ADD, ops.span());
}

Value add_impl(std::span<const Value> args) {
    SmallVec<Acc, 8> terms;
    Word256 c{};
    const Word256 one = Word256::of(1);
    for (Value a : args) push_term(terms, c, a, one);
    return add_terms(terms, c, 0);
}

// ---------------------------------------------------------------- masks

// mask() with concrete fields, canonicalized
Value mask_concrete(i64 s, i64 o, i64 h, Value x, int depth);

// the field [lo, hi) of x as it lands after shl
Value mask_rules(i64 s, i64 o, i64 h, Value x, int depth) {
    const i64 hi = o + s;
    if (is_const(x)) return wv(mask_shl_word(s, o, h, cw(x)));
    if (low_zero_bits(x) >= hi) return small(0);
    u32 mb = max_bits(x);
    if (mb <= o) return small(0);
    // a mask of a mask (or of x * 2^p): one mask
    if (auto f = field_of_mask(x)) {
        i64 a = std::max<i64>(o, f->off + f->shl), b = std::min<i64>(hi, f->off + f->size + f->shl);
        if (a >= b) return small(0);
        return mask_concrete(b - a, a - f->shl, f->shl + h, f->x, depth + 1);
    }
    if (x.is(Op::MUL, 2) && x[0].is_int()) {
        if (auto p = to_exp2(x[0]); p && *p > 0 && *p < 256) {
            i64 a = std::max<i64>(o, *p), b = std::min<i64>(hi, 256);
            if (a >= b) return small(0);
            return mask_concrete(b - a, a - *p, i64(*p) + h, x[1], depth + 1);
        }
    }
    if (i64(mb) <= hi && i64(low_zero_bits(x)) >= o) {
        // every bit x may have is in the field: x moved
        if (h == 0) return x;
        if (h > 0) return mul(wv(pow2w(u32(h))), x);
    }

    switch (x.op()) {
        case Op::ADD: {
            // the terms with no bit below the field's top don't change it
            SmallVec<Value, 8> keep;
            bool dropped = false;
            for (Value t : x.args()) {
                if (is_const(t)) {
                    // the constant mod 2^hi, when that makes it smaller
                    Word256 r = pan::band(cw(t), mask_word(hi, 0));
                    if (hi < 256 && w_neg(pan::shl(Word256::of(u64(256 - hi)), r)))
                        r = pan::sub(r, pow2w(u32(hi)));  // the signed residue
                    Value rv = signed_value(r);
                    EvmInt a = EvmInt(signed_int(t)), b = EvmInt(rv);
                    if (a.sign() < 0) a = -a;
                    if (b.sign() < 0) b = -b;
                    if (b < a) {
                        dropped = true;
                        if (!r.is_zero()) keep.push_back(rv);
                    } else {
                        keep.push_back(t);
                    }
                    continue;
                }
                if (low_zero_bits(t) >= hi) {
                    dropped = true;
                    continue;
                }
                keep.push_back(t);
            }
            if (dropped) return mask_concrete(s, o, h, add(keep.span()), depth + 1);
            break;
        }
        case Op::OR: {
            SmallVec<Value, 8> parts;
            for (Value t : x.args()) parts.push_back(mask_concrete(s, o, h, t, depth + 1));
            return bor(parts.span());
        }
        case Op::SIGNEXTEND: {
            if (x.size() == 2 && x[0].is_int()) {
                Word256 b = cw(x[0]);
                if (auto bb = b.as_u64(); bb && *bb < 31 && hi <= i64(8 * (*bb + 1)))
                    return mask_concrete(s, o, h, x[1], depth + 1);
            }
            break;
        }
        case Op::STORAGE: {
            // a field of a storage read moved down to bit 0: a narrower read
            // (python apply_mask_to_storage); elsewhere the mask stays (the
            // fields of one read add up as fields of it)
            if (o + h == 0 && x.size() == 3 && x[0].is_small() && x[1].is_small() && x[0].small_val() > 0 &&
                x[1].small_val() >= 0 && x[0].small_val() <= 256 && x[1].small_val() < 256) {
                i64 ss = x[0].small_val(), so = x[1].small_val();
                i64 ns = std::min<i64>(s, ss - o);
                if (ns <= 0) return small(0);
                return mk(Op::STORAGE, small(ns), small(so + o), x[2]);
            }
            break;
        }
        default:
            break;
    }
    return Value();
}

Value mask_concrete(i64 s, i64 o, i64 h, Value x, int depth) {
    if (depth > 64) throw SizeLimit("algebra: masks nested too deep");
    bool wide = may_be_wide(x);
    if (o < 0) {
        s += o;
        o = 0;
    }
    if (s <= 0) return small(0);
    if (!wide) {
        if (h >= 256 || h <= -256) return small(0);
        if (o >= 256) return small(0);
        if (o + s > 256) s = 256 - o;
        if (o + h < 0) {  // bits shifted out at the bottom
            s -= -h - o;
            o = -h;
        }
        if (s <= 0) return small(0);
        if (o + s + h > 256) s = 256 - o - h;  // shifted out at the top
        if (s <= 0) return small(0);
        if (o == 0 && s + h == 256) {
            // x times 2^h
            if (h == 0) return x;
            return mul(wv(pow2w(u32(h))), x);
        }
    }
    if (is_const(x) && !wide) return wv(mask_shl_word(s, o, h, cw(x)));
    // a leaf, a name: no rule applies (no memo needed)
    if (!x.is_node()) return mk(Op::MASK_SHL, small(s), small(o), small(h), x);
    // memo
    Key2 key{(u64(s + 8192) | u64(o + 8192) << 16 | u64(h + 8192) << 32) << 1 | 1, x.raw()};
    CtorState& S = st();
    if (Value* r = S.mask.find(key)) return *r;
    check_stack();
    Value res;
    if (!wide) res = mask_rules(s, o, h, x, depth);
    if (res.nil()) res = mk(Op::MASK_SHL, small(s), small(o), small(h), x);
    S.mask.put(key, res);
    return res;
}

// ---------------------------------------------------------------- products

Value mul_impl(std::span<const Value> args) {
    SmallVec<Acc, 8> terms;
    Word256 c{};
    push_product(terms, c, args, Word256::of(1), 0);
    if (terms.empty()) return wv(c);
    return add_terms(terms, c, 0);
}

// ---------------------------------------------------------------- bitwise helpers

// the flattened operands of an n-ary op
void flatten(Op op, std::span<const Value> args, SmallVec<Value, 8>& out) {
    check_stack();
    for (Value a : args) {
        if (a.is(op))
            flatten(op, a.args(), out);
        else
            out.push_back(a);
    }
}

void dedupe(SmallVec<Value, 8>& v) {
    SmallVec<Value, 8> out;
    for (Value a : v) {
        bool seen = false;
        for (Value b : out)
            if (b == a) {
                seen = true;
                break;
            }
        if (!seen) out.push_back(a);
    }
    v = out;
}

// OR of fields of one x at one displacement: their union when it is one field
bool merge_or_fields(SmallVec<Value, 8>& v) {
    for (usize i = 0; i < v.size(); ++i) {
        auto a = field_of_mask(v[i]);
        if (!a) continue;
        for (usize j = i + 1; j < v.size(); ++j) {
            auto b = field_of_mask(v[j]);
            if (!b || !(b->x == a->x) || b->shl != a->shl) continue;
            i32 lo = std::min(a->off, b->off), hi = std::max(a->off + a->size, b->off + b->size);
            // overlapping or adjacent: one field
            if (std::max(a->off, b->off) > std::min(a->off + a->size, b->off + b->size)) continue;
            v[i] = mask_concrete(hi - lo, lo, a->shl, a->x, 0);
            for (usize k = j; k + 1 < v.size(); ++k) v[k] = v[k + 1];
            v.pop_back();
            return true;
        }
    }
    return false;
}

}  // namespace

Value neg_mask(Value size, Value off, Value x) {
    // the bits outside [off, off + size)
    Value top = mask(sub(small(256), add(size, off)), add(off, size), small(0), x);
    Value low = mask(off, small(0), small(0), x);
    return bor(top, low);
}

// ================================================================ public

Value add(std::span<const Value> args) {
    if (args.empty()) return small(0);
    if (args.size() == 1) {
        Value a = args[0];
        if (is_const(a)) return wv(cw(a));
        if (!a.is(Op::ADD) && !a.is(Op::MUL) && !a.is(Op::SUB) && !a.is(Op::MASK_SHL)) return a;
        return add_impl(args);
    }
    if (all_const(args)) return fold(Op::ADD, args);
    return add_impl(args);
}

// a term that is the whole of itself in a sum: no constant, sum, product,
// difference or mask (the fast paths of add and mul)
inline bool simple_term(Value v) noexcept {
    if (is_const(v)) return false;
    switch (v.op()) {
        case Op::ADD: case Op::MUL: case Op::SUB: case Op::MASK_SHL:
            return false;
        default:
            return true;
    }
}

Value add(Value a, Value b) {
    if (is_const(a) && is_const(b)) return wv(pan::add(cw(a), cw(b)));
    // x + c, x + y: their normal form at once
    if (is_const(b) && simple_term(a)) std::swap(a, b);
    if (is_const(a) && simple_term(b)) {
        Word256 c = cw(a);
        return c.is_zero() ? b : mk(Op::ADD, signed_value(c), b);
    }
    if (simple_term(a) && simple_term(b)) {
        if (a == b) return mk(Op::MUL, small(2), a);
        return compare(a, b) < 0 ? mk(Op::ADD, a, b) : mk(Op::ADD, b, a);
    }
    if (is_const(a) && cw(a).is_zero()) {
        const Value one[] = {b};
        return add(std::span<const Value>(one));
    }
    if (is_const(b) && cw(b).is_zero()) {
        const Value one[] = {a};
        return add(std::span<const Value>(one));
    }
    Key2 key = a.raw() < b.raw() ? Key2{a.raw(), b.raw()} : Key2{b.raw(), a.raw()};
    CtorState& S = st();
    if (Value* r = S.add2.find(key)) return *r;
    const Value args[] = {a, b};
    Value r = add_impl(args);
    S.add2.put(key, r);
    return r;
}

Value add(Value a, Value b, Value c) {
    const Value args[] = {a, b, c};
    return add(std::span<const Value>(args));
}

Value neg(Value a) { return mul(small(-1), a); }

Value sub(Value a, Value b) {
    if (is_const(a) && is_const(b)) return wv(pan::sub(cw(a), cw(b)));
    if (a == b) return small(0);
    if (is_const(b) && cw(b).is_zero()) return add(std::span<const Value>(&a, 1));
    return add(a, neg(b));
}

Value mul(std::span<const Value> args) {
    if (args.empty()) return small(1);
    if (all_const(args)) return fold(Op::MUL, args);
    return mul_impl(args);
}

Value mul(Value a, Value b) {
    if (is_const(a) && is_const(b)) return wv(pan::mul(cw(a), cw(b)));
    // k * x: its normal form at once
    if (is_const(b) && simple_term(a)) std::swap(a, b);
    if (is_const(a) && simple_term(b)) {
        Word256 k = cw(a);
        if (k.is_zero()) return small(0);
        if (k == Word256::of(1)) return b;
        return mk(Op::MUL, signed_value(k), b);
    }
    Key2 key = a.raw() < b.raw() ? Key2{a.raw(), b.raw()} : Key2{b.raw(), a.raw()};
    CtorState& S = st();
    if (Value* r = S.mul2.find(key)) return *r;
    const Value args[] = {a, b};
    Value r = mul_impl(args);
    S.mul2.put(key, r);
    return r;
}

Value div(Value a, Value b) {
    if (is_const(a) && is_const(b)) return wv(pan::div(cw(a), cw(b)));
    if (is_const(b)) {
        Word256 w = cw(b);
        if (w.is_zero()) return small(0);
        if (w == Word256::of(1)) return a;
        if (auto p = log2_exact(w)) return mask(256 - i64(*p), i64(*p), -i64(*p), a);
    }
    if (is_const(a) && cw(a).is_zero()) return small(0);
    return mk(Op::DIV, cn(a), cn(b));
}

Value sdiv(Value a, Value b) {
    if (is_const(a) && is_const(b)) return wv(pan::sdiv(cw(a), cw(b)));
    if (is_const(b)) {
        Word256 w = cw(b);
        if (w.is_zero()) return small(0);
        if (w == Word256::of(1)) return a;
        if (w == w_ones()) return neg(a);
    }
    if (is_const(a) && cw(a).is_zero()) return small(0);
    return mk(Op::SDIV, cn(a), cn(b));
}

Value mod(Value a, Value b) {
    if (is_const(a) && is_const(b)) return wv(pan::mod(cw(a), cw(b)));
    if (is_const(b)) {
        Word256 w = cw(b);
        if (w.is_zero() || w == Word256::of(1)) return small(0);
    }
    if (is_const(a) && cw(a).is_zero()) return small(0);
    if (a == b && !a.has_flags(F_VOLATILE)) return small(0);
    return mk(Op::MOD, cn(a), cn(b));
}

Value smod(Value a, Value b) {
    if (is_const(a) && is_const(b)) return wv(pan::smod(cw(a), cw(b)));
    if (is_const(b)) {
        Word256 w = cw(b);
        if (w.is_zero() || w == Word256::of(1) || w == w_ones()) return small(0);
    }
    if (is_const(a) && cw(a).is_zero()) return small(0);
    return mk(Op::SMOD, cn(a), cn(b));
}

Value addmod(Value a, Value b, Value n) {
    if (is_const(a) && is_const(b) && is_const(n)) return wv(pan::addmod(cw(a), cw(b), cw(n)));
    if (is_const(n)) {
        Word256 w = cw(n);
        if (w.is_zero() || w == Word256::of(1)) return small(0);
    }
    return mk(Op::ADDMOD, cn(a), cn(b), cn(n));
}

Value mulmod(Value a, Value b, Value n) {
    if (is_const(a) && is_const(b) && is_const(n)) return wv(pan::mulmod(cw(a), cw(b), cw(n)));
    if (is_const(n)) {
        Word256 w = cw(n);
        if (w.is_zero() || w == Word256::of(1)) return small(0);
    }
    if ((is_const(a) && cw(a).is_zero()) || (is_const(b) && cw(b).is_zero())) return small(0);
    return mk(Op::MULMOD, cn(a), cn(b), cn(n));
}

Value exp(Value base, Value e) {
    if (is_const(base) && is_const(e)) return wv(pan::exp(cw(base), cw(e)));
    if (is_const(e)) {
        Word256 w = cw(e);
        if (w.is_zero()) return small(1);
        if (w == Word256::of(1)) return base;
    }
    if (is_const(base)) {
        Word256 w = cw(base);
        if (w.is_zero()) return iszero(e);  // 0 ** 0 = 1
        if (w == Word256::of(1)) return small(1);
    }
    return mk(Op::EXP, cn(base), cn(e));
}

// ---------------------------------------------------------------- masks

Value mask(i64 size, i64 off, i64 shl, Value x) {
    // (fields past +-4096 behave as +-4096: eval.hpp clamp_field)
    auto clamp = [](i64 v) { return v > 4096 ? 4096 : v < -4096 ? -4096 : v; };
    return mask_concrete(clamp(size), clamp(off), clamp(shl), x, 0);
}

Value mask(Value size, Value off, Value shl, Value x) {
    if (is_const(size) && is_const(off) && is_const(shl)) return mask_concrete(field_of(size), field_of(off), field_of(shl), x, 0);
    if (is_const(size) && field_of(size) <= 0) return small(0);
    if (is_const(x) && cw(x).is_zero()) return small(0);
    auto fld = [](Value v) { return is_const(v) ? small(field_of(v)) : v; };
    return mk(Op::MASK_SHL, fld(size), fld(off), fld(shl), cn(x));
}

Value shl(Value shift, Value x) {
    if (is_const(shift)) {
        Word256 w = cw(shift);
        auto k = w.as_u64();
        if (!k || *k >= 256) return small(0);
        if (is_const(x)) return wv(pan::shl(w, cw(x)));
        return mask_concrete(256, 0, i64(*k), x, 0);
    }
    if (is_const(x) && cw(x).is_zero()) return small(0);
    // a shift below 256 for every value: the mask (python shl_op)
    if (max_bits(shift) <= 8) return mk(Op::MASK_SHL, small(256), small(0), shift, cn(x));
    return mk(Op::SHL, shift, cn(x));
}

Value shr(Value shift, Value x) {
    if (is_const(shift)) {
        Word256 w = cw(shift);
        auto k = w.as_u64();
        if (!k || *k >= 256) return small(0);
        if (is_const(x)) return wv(pan::shr(w, cw(x)));
        return mask_concrete(256 - i64(*k), i64(*k), -i64(*k), x, 0);
    }
    if (is_const(x) && cw(x).is_zero()) return small(0);
    return mk(Op::SHR, shift, cn(x));
}

Value sar(Value shift, Value x) {
    if (is_const(shift) && is_const(x)) return wv(pan::sar(cw(shift), cw(x)));
    if (is_const(x)) {
        Word256 w = cw(x);
        if (w.is_zero() || w == w_ones()) return x;  // 0 and -1 stay
    }
    if (is_const(shift) && cw(shift).is_zero()) return x;
    // a non-negative x: a logical shift
    if (max_bits(x) <= 255) return shr(shift, x);
    return mk(Op::SAR, cn(shift), cn(x));
}

Value byte(Value idx, Value x) {
    if (is_const(idx)) {
        auto k = cw(idx).as_u64();
        if (!k || *k >= 32) return small(0);
        if (is_const(x)) return wv(pan::byte(cw(idx), cw(x)));
        i64 off = 248 - 8 * i64(*k);
        return mask_concrete(8, off, -off, x, 0);
    }
    if (is_const(x) && cw(x).is_zero()) return small(0);
    return mk(Op::BYTE, idx, cn(x));
}

Value signextend(Value b, Value x) {
    if (is_const(b) && is_const(x)) return wv(pan::signextend(cw(b), cw(x)));
    if (!is_const(b)) return mk(Op::SIGNEXTEND, b, cn(x));
    auto bb = cw(b).as_u64();
    if (!bb || *bb >= 31) return x;
    const i64 bits = 8 * (i64(*bb) + 1);
    // its sign bit 0: x as it is
    if (max_bits(x) < bits) return x;
    if (x.is(Op::SIGNEXTEND, 2) && x[0].is_int()) {
        auto c = cw(x[0]).as_u64();
        if (c && *c < 31) return signextend(small(i64(std::min<u64>(*bb, *c))), x[1]);
    }
    // only the low bits count (python signextend_op): a field at bit 0 of
    // more bits is narrowed, or its value itself when it starts at 0
    if (auto f = field_of_mask(x); f && f->off + f->shl == 0) {
        if (f->off == 0) return signextend(b, f->x);
        if (f->size > bits) return mk(Op::SIGNEXTEND, cn(b), mask_concrete(bits, f->off, -f->off, f->x, 0));
    }
    if (x.is(Op::STORAGE, 3) && x[0].is_small() && x[0].small_val() > bits && x[1].is_small() && x[1].small_val() >= 0)
        return mk(Op::SIGNEXTEND, cn(b), mk(Op::STORAGE, small(bits), x[1], x[2]));
    return mk(Op::SIGNEXTEND, cn(b), x);
}

// ---------------------------------------------------------------- bitwise

Value band(std::span<const Value> args) {
    SmallVec<Value, 8> v;
    flatten(Op::AND, args, v);
    Word256 c = w_ones();
    bool any_const = false;
    SmallVec<Value, 8> rest;
    for (Value a : v) {
        if (is_const(a)) {
            c = pan::band(c, cw(a));
            any_const = true;
        } else {
            rest.push_back(a);
        }
    }
    if (any_const && c.is_zero()) return small(0);
    dedupe(rest);
    if (rest.empty()) return wv(c);
    Value r = rest.size() == 1 ? rest[0] : Value();
    if (any_const && !(c == w_ones())) {
        Value inner = rest.size() == 1 ? rest[0] : mk(Op::AND, rest.span());
        if (auto m = as_bit_run(c)) return mask_concrete(m->size, m->off, 0, inner, 0);
        if (auto m = as_bit_run(pan::bnot(c))) return neg_mask(small(m->size), small(m->off), inner);
        SmallVec<Value, 8> ops;
        for (Value a : rest) ops.push_back(a);
        ops.push_back(wv(c));
        return mk(Op::AND, ops.span());
    }
    if (!r.nil()) return r;
    // a symbolic mask (2^e - 1) among them
    for (usize i = 0; i < rest.size(); ++i) {
        if (auto m = to_mask(rest[i])) {
            SmallVec<Value, 8> others;
            for (usize j = 0; j < rest.size(); ++j)
                if (j != i) others.push_back(rest[j]);
            Value inner = others.size() == 1 ? others[0] : mk(Op::AND, others.span());
            return mask(m->size, m->off, small(0), inner);
        }
    }
    // fields of one x at one displacement: their intersection
    for (usize i = 0; i < rest.size(); ++i) {
        auto a = field_of_mask(rest[i]);
        if (!a) continue;
        for (usize j = i + 1; j < rest.size(); ++j) {
            auto b = field_of_mask(rest[j]);
            if (!b || !(b->x == a->x) || b->shl != a->shl) continue;
            i32 lo = std::max(a->off, b->off), hi = std::min(a->off + a->size, b->off + b->size);
            SmallVec<Value, 8> ops;
            for (usize k = 0; k < rest.size(); ++k)
                if (k != i && k != j) ops.push_back(rest[k]);
            ops.push_back(lo >= hi ? small(0) : mask_concrete(hi - lo, lo, a->shl, a->x, 0));
            return band(ops.span());
        }
    }
    return mk(Op::AND, rest.span());
}

Value band(Value a, Value b) {
    if (is_const(a) && is_const(b)) return wv(pan::band(cw(a), cw(b)));
    Key2 key{a.raw(), b.raw()};  // (the operands' order is kept)
    CtorState& S = st();
    if (Value* r = S.and2.find(key)) return *r;
    const Value args[] = {a, b};
    Value r = band(std::span<const Value>(args));
    S.and2.put(key, r);
    return r;
}

Value bor(std::span<const Value> args) {
    SmallVec<Value, 8> v;
    flatten(Op::OR, args, v);
    Word256 c{};
    bool any_const = false;
    SmallVec<Value, 8> rest;
    for (Value a : v) {
        if (is_const(a)) {
            c = pan::bor(c, cw(a));
            any_const = true;
        } else {
            rest.push_back(a);
        }
    }
    if (c == w_ones()) return wv(c);
    dedupe(rest);
    while (merge_or_fields(rest)) {
    }
    // merge_or_fields may make constants or ORs: flatten again once
    {
        SmallVec<Value, 8> again;
        bool redo = false;
        for (Value a : rest)
            if (is_const(a) || a.is(Op::OR)) redo = true;
        if (redo) {
            for (Value a : rest) again.push_back(a);
            if (!c.is_zero()) again.push_back(wv(c));
            return bor(again.span());
        }
    }
    if (rest.empty()) return wv(c);
    if (any_const && !c.is_zero()) rest.push_back(wv(c));
    if (rest.size() == 1) return rest[0];
    return mk(Op::OR, rest.span());
}

Value bor(Value a, Value b) {
    if (is_const(a) && is_const(b)) return wv(pan::bor(cw(a), cw(b)));
    Key2 key{a.raw(), b.raw()};
    CtorState& S = st();
    if (Value* r = S.or2.find(key)) return *r;
    const Value args[] = {a, b};
    Value r = bor(std::span<const Value>(args));
    S.or2.put(key, r);
    return r;
}

Value bxor(Value a, Value b) {
    if (is_const(a) && is_const(b)) return wv(pan::bxor(cw(a), cw(b)));
    if (a == b && !a.has_flags(F_VOLATILE)) return small(0);
    if (is_const(a) && cw(a).is_zero()) return b;
    if (is_const(b) && cw(b).is_zero()) return a;
    if (is_const(a) && cw(a) == w_ones()) return bnot(b);
    if (is_const(b) && cw(b) == w_ones()) return bnot(a);
    return mk(Op::XOR, cn(a), cn(b));
}

Value bnot(Value a) {
    if (is_const(a)) return wv(pan::bnot(cw(a)));
    if (a.is(Op::NOT, 1)) return a[0];
    return mk(Op::NOT, a);
}

Value clz(Value a) {
    if (is_const(a)) return wv(pan::clz(cw(a)));
    return mk(Op::CLZ, a);
}

// ---------------------------------------------------------------- truth values

bool is_bool(Value a) {
    if (a.is_bool()) return true;
    if (a.is_int()) return a.is_small() && (a.small_val() == 0 || a.small_val() == 1);
    if (a.is_leaf()) return info(a.op()).sort == Sort::Bool;
    if (!a.is_expr()) return false;
    check_stack();
    switch (a.op()) {
        case Op::LOR:
            return a.size() == 2 && is_bool(a[0]) && is_bool(a[1]);
        case Op::LAND:
            return a.size() == 2 && is_bool(a[1]);
        case Op::AND:
            for (Value x : a.args())
                if (is_bool(x)) return true;
            break;
        case Op::OR:
        case Op::XOR: {
            for (Value x : a.args())
                if (!is_bool(x)) return false;
            return true;
        }
        default:
            break;
    }
    return max_bits(a) <= 1;
}

Value iszero(Value a) {
    if (is_const(a)) return small(cw(a).is_zero() ? 1 : 0);
    check_stack();
    switch (a.op()) {
        case Op::ISZERO:
            if (a.size() == 1) return to_bool(a[0]);
            break;
        case Op::BOOL:
            if (a.size() == 1) return iszero(a[0]);
            break;
        case Op::LT: return cmp(Op::GE, a[0], a[1]);
        case Op::GT: return cmp(Op::LE, a[0], a[1]);
        case Op::LE: return cmp(Op::GT, a[0], a[1]);
        case Op::GE: return cmp(Op::LT, a[0], a[1]);
        case Op::SLT: return cmp(Op::SGE, a[0], a[1]);
        case Op::SGT: return cmp(Op::SLE, a[0], a[1]);
        case Op::SLE: return cmp(Op::SGT, a[0], a[1]);
        case Op::SGE: return cmp(Op::SLT, a[0], a[1]);
        case Op::OR: {
            // all of them 0
            SmallVec<Value, 8> zs;
            for (Value x : a.args()) {
                Value z = iszero(x);
                if (is_const(z)) {
                    if (cw(z).is_zero()) return small(0);
                    continue;
                }
                zs.push_back(z);
            }
            if (zs.empty()) return small(1);
            return band(zs.span());
        }
        case Op::AND: {
            // of truth values: one of them 0
            bool bools = true;
            for (Value x : a.args())
                if (!is_bool(x)) {
                    bools = false;
                    break;
                }
            if (!bools) break;
            SmallVec<Value, 8> zs;
            for (Value x : a.args()) {
                Value z = iszero(x);
                if (is_const(z)) {
                    if (!cw(z).is_zero()) return small(1);
                    continue;
                }
                zs.push_back(z);
            }
            if (zs.empty()) return small(0);
            return bor(zs.span());
        }
        default:
            break;
    }
    return mk(Op::ISZERO, a);
}

Value truth(Value a) {
    check_stack();
    for (int i = 0; i < 64; ++i) {
        if (a.is(Op::BOOL, 1)) {
            a = a[0];
        } else if (a.is(Op::ISZERO, 1) && a[0].is(Op::ISZERO, 1)) {
            a = a[0][0];
        } else if (a.is(Op::ISZERO, 1)) {
            Value in = truth(a[0]);
            return in == a[0] ? a : iszero(in);
        } else {
            return a;
        }
    }
    return a;
}

Value to_bool(Value a) {
    if (is_const(a)) return small(cw(a).is_zero() ? 0 : 1);
    if (is_bool(a)) return a;
    if (a.is(Op::BOOL, 1)) return a;
    return mk(Op::BOOL, a);
}

Value cmp(Op op, Value a, Value b) {
    switch (op) {
        case Op::LT: case Op::GT: case Op::SLT: case Op::SGT: case Op::EQ:
        case Op::LE: case Op::GE: case Op::SLE: case Op::SGE:
            break;
        default:
            throw InternalError("algebra: cmp of a non-comparison");
    }
    if (is_const(a) && is_const(b)) {
        const Value args[] = {a, b};
        return fold(op, args);
    }
    if (a == b && !a.has_flags(F_VOLATILE)) {
        switch (op) {
            case Op::LT: case Op::GT: case Op::SLT: case Op::SGT:
                return small(0);
            default:
                return small(1);
        }
    }
    const bool a0 = is_const(a) && cw(a).is_zero(), b0 = is_const(b) && cw(b).is_zero();
    const bool amax = is_const(a) && cw(a) == w_ones(), bmax = is_const(b) && cw(b) == w_ones();
    switch (op) {
        case Op::GT:
            if (a0 || bmax) return small(0);
            break;
        case Op::LT:
            if (b0 || amax) return small(0);
            break;
        case Op::LE:
            if (a0 || bmax) return small(1);
            break;
        case Op::GE:
            if (b0 || amax) return small(1);
            break;
        case Op::EQ: {
            // a - b a constant (mod 2^256): decided
            if (auto d = const_diff(a, b)) return small(cw(*d).is_zero() ? 1 : 0);
            break;
        }
        default:
            break;
    }
    return mk(op, cn(a), cn(b));
}

Value max(std::span<const Value> args) {
    SmallVec<Value, 8> v;
    flatten(Op::MAX, args, v);
    Word256 c{};
    bool any_const = false;
    SmallVec<Value, 8> rest;
    for (Value a : v) {
        if (is_const(a)) {
            Word256 w = cw(a);
            if (!any_const || w > c) c = w;
            any_const = true;
        } else {
            rest.push_back(a);
        }
    }
    if (any_const && c == w_ones()) return wv(c);
    dedupe(rest);
    std::sort(rest.begin(), rest.end(), StructuralLess{});
    if (any_const && !c.is_zero()) rest.insert_front(wv(c));
    if (rest.empty()) return small(0);
    if (rest.size() == 1) return rest[0];
    return mk(Op::MAX, rest.span());
}

Value min(std::span<const Value> args) {
    SmallVec<Value, 8> v;
    flatten(Op::MIN, args, v);
    Word256 c = w_ones();
    bool any_const = false;
    SmallVec<Value, 8> rest;
    for (Value a : v) {
        if (is_const(a)) {
            Word256 w = cw(a);
            if (w < c) c = w;
            any_const = true;
        } else {
            rest.push_back(a);
        }
    }
    if (any_const && c.is_zero()) return small(0);
    dedupe(rest);
    std::sort(rest.begin(), rest.end(), StructuralLess{});
    if (any_const && !(c == w_ones())) rest.insert_front(wv(c));
    if (rest.empty()) return wv(c);
    if (rest.size() == 1) return rest[0];
    return mk(Op::MIN, rest.span());
}

// ---------------------------------------------------------------- bits and bytes

Value bits(Value nbytes) { return mul(small(8), nbytes); }

ToBytes to_bytes(Value nbits) {
    if (nbits.is_int()) {
        EvmInt n(nbits);
        return ToBytes{floordiv(n + EvmInt(7), EvmInt(8)).value(), u32(pymod(n, EvmInt(8)).to_i64())};
    }
    if (auto f = field_of_mask(nbits); f && f->off + f->shl >= 3)
        return ToBytes{mask_concrete(f->size, f->off, f->shl - 3, f->x, 0), 0u};
    if (nbits.is(Op::MUL) && nbits.size() >= 2 && nbits[0].is_int()) {
        Word256 k = cw(nbits[0]);
        if (tz(k) >= 3) {
            SmallVec<Value, 8> f;
            f.push_back(signed_value(pan::sar(Word256::of(3), k)));
            for (usize i = 1; i < nbits.size(); ++i) f.push_back(nbits[i]);
            return ToBytes{mul(f.span()), 0u};
        }
    }
    if (nbits.is(Op::ADD)) {
        SmallVec<Value, 8> parts;
        bool exact = true;
        for (Value t : nbits.args()) {
            ToBytes b = t.is_int() ? ToBytes{small(0), std::nullopt} : to_bytes(t);
            if (t.is_int()) {
                EvmInt n(signed_int(t));
                if (!pymod(n, EvmInt(8)).is_zero()) {
                    exact = false;
                    break;
                }
                parts.push_back(floordiv(n, EvmInt(8)).value());
                continue;
            }
            if (!b.rem || *b.rem != 0) {
                exact = false;
                break;
            }
            parts.push_back(b.bytes);
        }
        if (exact) return ToBytes{add(parts.span()), 0u};
        return ToBytes{shr(small(3), nbits), std::nullopt};
    }
    if (low_zero_bits(nbits) >= 3) return ToBytes{shr(small(3), nbits), 0u};
    return ToBytes{shr(small(3), nbits), std::nullopt};
}

// ---------------------------------------------------------------- apply

Value apply(Op op, std::span<const Value> a) {
    const OpInfo& in = info(op);
    if (!in.defined || in.leaf || a.size() < in.arity_min || (in.arity_max != 255 && a.size() > in.arity_max))
        return mk(op, a);  // mk checks (InternalError) and makes leaves
    switch (op) {
        case Op::ADD: return add(a);
        case Op::MUL: return mul(a);
        case Op::SUB: return sub(a[0], a[1]);
        case Op::DIV: return div(a[0], a[1]);
        case Op::SDIV: return sdiv(a[0], a[1]);
        case Op::MOD: return mod(a[0], a[1]);
        case Op::SMOD: return smod(a[0], a[1]);
        case Op::ADDMOD: return addmod(a[0], a[1], a[2]);
        case Op::MULMOD: return mulmod(a[0], a[1], a[2]);
        case Op::EXP: return exp(a[0], a[1]);
        case Op::SIGNEXTEND: return signextend(a[0], a[1]);
        case Op::LT: case Op::GT: case Op::SLT: case Op::SGT: case Op::EQ:
        case Op::LE: case Op::GE: case Op::SLE: case Op::SGE:
            return cmp(op, a[0], a[1]);
        case Op::ISZERO: return iszero(a[0]);
        case Op::BOOL: return to_bool(a[0]);
        case Op::AND: return band(a);
        case Op::OR: return bor(a);
        case Op::XOR:
            if (a.size() == 2) return bxor(a[0], a[1]);
            break;
        case Op::NOT: return bnot(a[0]);
        case Op::BYTE: return byte(a[0], a[1]);
        case Op::SHL: return shl(a[0], a[1]);
        case Op::SHR: return shr(a[0], a[1]);
        case Op::SAR: return sar(a[0], a[1]);
        case Op::CLZ: return clz(a[0]);
        case Op::MASK_SHL: return mask(a[0], a[1], a[2], a[3]);
        case Op::MAX: return max(a);
        case Op::MIN: return min(a);
        case Op::LAND:
            if (is_const(a[0])) return cw(a[0]).is_zero() ? small(0) : a[1];
            break;
        case Op::LOR:
            if (is_const(a[0])) return cw(a[0]).is_zero() ? a[1] : wv(cw(a[0]));
            break;
        default:
            break;
    }
    return mk(op, a);
}

Value normalize(Value v) {
    if (!v.is_expr()) {
        if (v.is_int()) return v;
        return v;
    }
    CtorState& S = st();
    if (Value* r = S.norm.find(v)) return *r;
    check_stack();
    SmallVec<Value, 8> args;
    bool changed = false;
    for (Value a : v.args()) {
        Value n = normalize(a);
        if (!(n == a)) changed = true;
        args.push_back(n);
    }
    Value r = is_pure(v.op()) ? apply(v.op(), args.span()) : (changed ? mk_like(v, args.span()) : v);
    S.norm.put(v, r);
    return r;
}

}  // namespace pan::alg
