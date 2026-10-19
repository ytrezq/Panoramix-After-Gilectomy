// Masks: views, mask constants, structural bit facts (masks.hpp).
#include "algebra/masks.hpp"

#include "algebra/construct.hpp"
#include "algebra/eval.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/intops.hpp"

namespace pan::alg {

std::optional<MaskShl> as_mask(Value v) noexcept {
    if (!v.is(Op::MASK_SHL, 4)) return std::nullopt;
    return MaskShl{v[0], v[1], v[2], v[3]};
}

MaskShl mask_view(Value v) {
    if (v.is(Op::MASK_SHL, 4)) return MaskShl{v[0], v[1], v[2], v[3]};
    if (v.is(Op::MUL, 2) && v[0].is_int()) {
        if (auto p = to_exp2(v[0]); p && *p > 0)
            return MaskShl{Value::small(256 - i64(*p)), Value::small(0), Value::small(*p), v[1]};
    }
    return MaskShl{Value::small(256), Value::small(0), Value::small(0), v};
}

std::optional<u32> log2_exact(const Word256& w) noexcept {
    int idx = -1;
    for (int i = 0; i < 4; ++i) {
        if (!w.limb[i]) continue;
        if (idx >= 0 || (w.limb[i] & (w.limb[i] - 1))) return std::nullopt;
        idx = i;
    }
    if (idx < 0) return std::nullopt;
    return u32(idx * 64 + __builtin_ctzll(w.limb[idx]));
}

std::optional<u32> to_exp2(Value v) noexcept {
    if (v.is_small()) {
        i64 x = v.small_val();
        if (x <= 0 || (x & (x - 1))) return std::nullopt;
        return u32(__builtin_ctzll(u64(x)));
    }
    if (!v.is_big() || int_sign(v) <= 0) return std::nullopt;
    EvmInt e(v);
    u64 bl = e.bit_length();
    if (bl > 256) return std::nullopt;
    Word256 w = Word256::from_int(e);
    return log2_exact(w);
}

namespace {

// (size, off) of a word whose set bits are one run
std::optional<BitSpan> run_of_ones(const Word256& w) noexcept {
    if (w.is_zero()) return std::nullopt;
    u32 lo = 256, hi = 0;
    for (u32 i = 0; i < 4; ++i) {
        if (!w.limb[i]) continue;
        u32 l = i * 64 + u32(__builtin_ctzll(w.limb[i]));
        u32 h = i * 64 + 64 - u32(__builtin_clzll(w.limb[i]));
        if (l < lo) lo = l;
        if (h > hi) hi = h;
    }
    // every bit in [lo, hi) set
    Word256 m = mask_word(hi - lo, lo);
    if (!(m == w)) return std::nullopt;
    return BitSpan{hi - lo, lo};
}

// e for 2^(k*e) - 1 as SUB(EXP(2^k, e), 1) or ADD(-1, EXP(2^k, e)), when
// k * e < 2^256 structurally: the size k * e as a value
std::optional<Value> symbolic_low_mask(Value v) {
    Value ex;
    if (v.is(Op::SUB, 2) && int_is(v[1], 1))
        ex = v[0];
    else if (v.is(Op::ADD, 2) && v[0].is_int() && Word256::from_value(v[0]) == pan::bnot(Word256{}))
        ex = v[1];
    else
        return std::nullopt;
    if (!ex.is(Op::EXP, 2) || !ex[0].is_int()) return std::nullopt;
    auto k = to_exp2(ex[0]);
    if (!k || *k == 0) return std::nullopt;
    Value e = ex[1];
    // k * e must not wrap: e < 2^(256 - bits(k))
    u32 eb = max_bits(e);
    u32 kb = 32 - u32(__builtin_clz(*k));
    if (eb + kb > 255) return std::nullopt;
    if (*k == 1) return e;
    return mul(mk_int(*k), e);
}

}  // namespace

std::optional<MaskFields> to_mask(Value v) {
    if (v.is_int()) {
        auto w = eval_const(v);
        auto r = run_of_ones(*w);
        if (!r) return std::nullopt;
        return MaskFields{Value::small(r->size), Value::small(r->off)};
    }
    if (v.is(Op::NOT, 1)) return to_neg_mask(v[0]);
    if (auto s = symbolic_low_mask(v)) return MaskFields{*s, Value::small(0)};
    return std::nullopt;
}

std::optional<MaskFields> to_neg_mask(Value v) {
    if (v.is(Op::NOT, 1)) return to_mask(v[0]);
    if (!v.is_int()) return std::nullopt;
    Word256 w = pan::bnot(Word256::from_value(v));
    auto r = run_of_ones(w);
    if (!r) return std::nullopt;
    return MaskFields{Value::small(r->size), Value::small(r->off)};
}

BitSpan find_mask(const Word256& w) noexcept {
    if (w.is_zero()) return BitSpan{0, 256};
    u32 lo = 256, hi = 0;
    for (u32 i = 0; i < 4; ++i) {
        if (!w.limb[i]) continue;
        u32 l = i * 64 + u32(__builtin_ctzll(w.limb[i]));
        u32 h = i * 64 + 64 - u32(__builtin_clzll(w.limb[i]));
        if (l < lo) lo = l;
        if (h > hi) hi = h;
    }
    u32 pos = lo - lo % 8;
    u32 end = (hi + 7) / 8 * 8;
    return BitSpan{end - pos, pos};
}

// ---------------------------------------------------------------- bit facts

namespace {

u32 bitlen_word(const Word256& w) noexcept {
    for (int i = 3; i >= 0; --i)
        if (w.limb[i]) return u32(i * 64 + 64 - __builtin_clzll(w.limb[i]));
    return 0;
}

// a non-negative small int field
std::optional<u32> small_field(Value v) noexcept {
    if (!v.is_small()) return std::nullopt;
    i64 x = v.small_val();
    if (x < 0 || x > 4096) return std::nullopt;
    return u32(x);
}

}  // namespace

u32 max_bits(Value v) {
    if (v.is_int()) return bitlen_word(Word256::from_value(v));
    if (v.is_bool()) return v.is_true() ? 1 : 0;
    if (!v.is_expr()) return 256;
    check_stack();
    switch (v.op()) {
        case Op::LT: case Op::GT: case Op::SLT: case Op::SGT: case Op::EQ: case Op::ISZERO:
        case Op::BOOL: case Op::LE: case Op::GE: case Op::SLE: case Op::SGE:
            return 1;
        case Op::BYTE:
            return 8;
        case Op::CLZ:
            return 9;
        case Op::MASK_SHL: {
            if (v.size() != 4 || !v[0].is_small() || !v[1].is_small() || !v[2].is_small()) return 256;
            i64 size = v[0].small_val(), off = v[1].small_val(), shl = v[2].small_val();
            if (off < 0) {
                size += off;
                off = 0;
            }
            if (size <= 0 || off >= 256 || shl >= 256 || shl <= -256) return 0;
            i64 top = off + size;
            i64 xb = max_bits(v[3]);
            if (xb < top) top = xb;
            if (top <= off) return 0;
            top += shl;
            if (top <= 0) return 0;
            return top > 256 ? 256 : u32(top);
        }
        case Op::AND: {
            u32 m = 256;
            for (Value a : v.args()) {
                u32 b = max_bits(a);
                if (b < m) m = b;
            }
            return m;
        }
        case Op::OR:
        case Op::XOR:
        case Op::MAX: {
            u32 m = 0;
            for (Value a : v.args()) {
                u32 b = max_bits(a);
                if (b > m) m = b;
                if (m == 256) break;
            }
            return m;
        }
        case Op::MIN: {
            u32 m = 256;
            for (Value a : v.args()) {
                u32 b = max_bits(a);
                if (b < m) m = b;
            }
            return m;
        }
        case Op::SHR: {
            if (v.size() != 2) return 256;
            u32 xb = max_bits(v[1]);
            if (auto k = small_field(v[0])) return *k >= xb ? 0 : xb - *k;
            return xb;
        }
        case Op::DIV:
            return v.size() == 2 ? max_bits(v[0]) : 256;
        case Op::MOD: {
            if (v.size() != 2) return 256;
            u32 a = max_bits(v[0]), b = max_bits(v[1]);
            return a < b ? a : b;
        }
        case Op::ADD: {
            // non-negative terms (MUL with a negative coefficient wraps)
            u32 m = 0;
            for (Value a : v.args()) {
                if (a.is_int() && int_sign(a) < 0) return 256;
                if (a.is(Op::MUL) && a[0].is_int() && int_sign(a[0]) < 0) return 256;
                u32 b = max_bits(a);
                if (b > m) m = b;
            }
            u32 n = v.size();
            u32 extra = 32 - u32(__builtin_clz((n - 1) | 1));  // bits of the term count
            u32 r = m + extra;
            return r >= 256 ? 256 : r;
        }
        case Op::MUL: {
            u32 s = 0;
            for (Value a : v.args()) {
                if (a.is_int() && int_sign(a) < 0) return 256;
                s += max_bits(a);
                if (s >= 256) return 256;
            }
            return s;
        }
        case Op::STORAGE: {
            if (v.size() != 3) return 256;
            auto size = small_field(v[0]);
            if (!size || !v[1].is_small() || v[1].small_val() < 0) return 256;
            return *size > 256 ? 256 : *size;
        }
        default:
            return 256;
    }
}

u32 low_zero_bits(Value v) {
    if (v.is_int()) {
        Word256 w = Word256::from_value(v);
        if (w.is_zero()) return 256;
        for (u32 i = 0; i < 4; ++i)
            if (w.limb[i]) return i * 64 + u32(__builtin_ctzll(w.limb[i]));
        return 256;
    }
    if (!v.is_expr()) return 0;
    check_stack();
    switch (v.op()) {
        case Op::MASK_SHL: {
            if (v.size() != 4 || !v[1].is_small() || !v[2].is_small()) return 0;
            i64 z = v[1].small_val() + v[2].small_val();
            if (z <= 0) return 0;
            return z > 256 ? 256 : u32(z);
        }
        case Op::MUL: {
            u32 s = 0;
            for (Value a : v.args()) {
                s += low_zero_bits(a);
                if (s >= 256) return 256;
            }
            return s;
        }
        case Op::ADD: {
            u32 m = 256;
            for (Value a : v.args()) {
                u32 b = low_zero_bits(a);
                if (b < m) m = b;
                if (!m) break;
            }
            return m;
        }
        case Op::AND: {
            u32 m = 0;
            for (Value a : v.args()) {
                u32 b = low_zero_bits(a);
                if (b > m) m = b;
            }
            return m;
        }
        case Op::OR: {
            u32 m = 256;
            for (Value a : v.args()) {
                u32 b = low_zero_bits(a);
                if (b < m) m = b;
            }
            return m;
        }
        case Op::SHL: {
            if (v.size() != 2) return 0;
            if (auto k = small_field(v[0])) {
                u32 r = *k + low_zero_bits(v[1]);
                return r > 256 ? 256 : r;
            }
            return 0;
        }
        default:
            return 0;
    }
}

}  // namespace pan::alg
