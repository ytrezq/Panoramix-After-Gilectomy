// simplify_exp: python simplify_exp's local rules (simplify.hpp), as a
// bottom-up rewrite of hash-consed nodes. The arithmetic normal forms are
// lot 2's constructors (alg::apply), the decisions by ranges lot 3's
// (decide_cmp, eval_bool, reduce_minmax: Top::Word, sound for every
// execution), the bytes lot 4's (sized, concat, narrow_mem_mask); what is
// here are the rules none of them makes - each keeps the value for every
// value of the leaves (tests/simplify_exp_test.cpp checks them by concrete
// evaluation).
#include "simplify/simplify.hpp"
#include "simplify/internal.hpp"

#include "algebra/compare.hpp"
#include "algebra/construct.hpp"
#include "algebra/eval.hpp"
#include "algebra/linear.hpp"
#include "algebra/masks.hpp"
#include "algebra/ranges.hpp"
#include "core/context.hpp"
#include "core/evmint.hpp"
#include "core/intops.hpp"
#include "core/memo.hpp"
#include "mem/memory.hpp"

namespace pan::simplify {

namespace {

struct ExpState final : ModuleState {
    Memo<Value, Value> word, bytes, any;
    void clear_caches() override {
        word.clear();
        bytes.clear();
        any.clear();
    }
};

ExpState& est() { return cx().state<ExpState>(); }

Value small(i64 x) { return Value::small(x); }

bool is_int(Value v, i64 x) { return v.is_small() && v.small_val() == x; }

// ---- rules on words -----------------------------------------------------------------

// MUL(-1, y): y
std::optional<Value> negated(Value x) {
    if (x.is(Op::MUL, 2) && is_int(x[0], -1)) return x[1];
    return std::nullopt;
}

// python equals: c + x == 0 as a comparison
Value equals(Value x, Value c) {
    if (auto y = negated(x)) return alg::cmp(Op::EQ, *y, alg::word_int(c));
    return alg::cmp(Op::EQ, x, alg::word_int(int_neg(c)));
}

// python difference_eq: a == b when exp is a - b (a sum with one negated
// term and no constant)
std::optional<Value> difference_eq(Value e) {
    if (!e.is(Op::ADD) || e.size() < 2) return std::nullopt;
    i64 neg = -1;
    for (u32 i = 0; i < e.size(); ++i) {
        if (e[i].is_int()) return std::nullopt;
        if (negated(e[i])) {
            if (neg >= 0) return std::nullopt;
            neg = i;
        }
    }
    if (neg < 0) return std::nullopt;
    SmallVec<Value, 8> others;
    for (u32 i = 0; i < e.size(); ++i)
        if (i64(i) != neg) others.push_back(e[i]);
    return alg::cmp(Op::EQ, alg::add(others.span()), *negated(e[u32(neg)]));
}

// ISZERO(x) rewritten (python's iszero rules); nullopt: as it is
std::optional<Value> iszero_rule(Value x) {
    // iszero(c + x): x == -c
    if (x.is(Op::ADD, 2) && x[0].is_int()) return equals(x[1], x[0]);
    if (auto eq = difference_eq(x)) return *eq;
    // a xor b is 0 when they're equal
    if (x.is(Op::XOR, 2)) return alg::cmp(Op::EQ, x[0], x[1]);
    // -x is 0 when x is
    if (auto y = negated(x)) return alg::iszero(*y);
    // a shift that loses none of the mask's bits doesn't change whether they're all 0
    if (auto m = alg::as_mask(x); m && m->concrete() && m->ishl() != 0) {
        const i64 s = m->isize(), o = m->ioff(), h = m->ishl();
        if (-o <= h && h <= 256 - s - o) return alg::iszero(alg::mask(s, o, 0, m->x));
    }
    return std::nullopt;
}

// the comparison of two sums without the terms both have, when neither wraps
// (python: the terms below 2^250, here: positive coefficients, the sums
// proven words)
std::optional<Value> cancel_common(Op op, Value a, Value b) {
    if (!a.is(Op::ADD) && !b.is(Op::ADD)) return std::nullopt;
    alg::Linear la = alg::linear(a), lb = alg::linear(b);
    if (la.terms.empty() || lb.terms.empty()) return std::nullopt;
    if (int_sign(la.constant) < 0 || int_sign(lb.constant) < 0) return std::nullopt;
    for (const auto& t : la.terms)
        if (int_sign(t.coeff) <= 0) return std::nullopt;
    for (const auto& t : lb.terms)
        if (int_sign(t.coeff) <= 0) return std::nullopt;
    bool common = false;
    for (const auto& t : la.terms)
        if (int_cmp(lb.coeff_of(t.term), small(0)) != 0) common = true;
    if (!common) return std::nullopt;
    if (!alg::is_word(a) || !alg::is_word(b)) return std::nullopt;
    alg::Linear ra, rb;
    ra.constant = la.constant;
    rb.constant = lb.constant;
    for (const auto& t : la.terms) {
        Value kb = lb.coeff_of(t.term);
        Value k = int_sign(kb) == 0 ? t.coeff : int_sub(t.coeff, kb);
        if (int_sign(k) > 0) ra.terms.push_back({t.term, k});
    }
    for (const auto& t : lb.terms) {
        Value ka = la.coeff_of(t.term);
        Value k = int_sign(ka) == 0 ? t.coeff : int_sub(t.coeff, ka);
        if (int_sign(k) > 0) rb.terms.push_back({t.term, k});
    }
    return alg::cmp(op, alg::from_linear(ra), alg::from_linear(rb));
}

std::optional<Value> mask_rule(Value r) {
    auto m = alg::as_mask(r);
    if (!m) return std::nullopt;
    Value x = m->x;
    if (m->concrete()) {
        const i64 size = m->isize(), off = m->ioff(), shl = m->ishl();
        // floor32(num + x) = (num - 31) + floor32(31 + x), num - 31 a multiple of 32
        if (off == 5 && shl == 0 && size + 5 >= 256 && x.is(Op::ADD) && x[0].is_small()) {
            const i64 num = x[0].small_val();
            if (num > 32 && num % 32 == 31) {
                SmallVec<Value, 8> rest;
                rest.push_back(small(31));
                for (u32 i = 1; i < x.size(); ++i) rest.push_back(x[i]);
                return alg::add(small(num - 31), alg::mask(size, 5, 0, alg::add(rest.span())));
            }
        }
        // the other terms multiples of 2^off: a constant below 2^off changes none of the bits kept
        if (off > 0 && off < 63 && x.is(Op::ADD) && x[0].is_small()) {
            const i64 num = x[0].small_val();
            if (num > 0 && num < (i64(1) << off)) {
                bool ok = true;
                for (u32 i = 1; i < x.size() && ok; ++i) ok = alg::low_zero_bits(x[i]) >= u32(off);
                if (ok) {
                    SmallVec<Value, 8> rest;
                    for (u32 i = 1; i < x.size(); ++i) rest.push_back(x[i]);
                    return alg::mask(size, off, shl, alg::add(rest.span()));
                }
            }
        }
        // the mask keeps every bit that may be set
        if (shl == 0 && size + off >= 256 && (x.is(Op::ADD) || x.is(Op::MUL)) && alg::low_zero_bits(x) >= u32(off))
            return x;
        // a field of storage (at bit 0) moved down past 0
        if (x.is(Op::STORAGE, 3) && x[0].is_small() && x[1].is_small() && x[1].small_val() >= 0 &&
            x[0].small_val() >= 0 && x[0].small_val() <= -shl)
            return small(0);
        // a whole-bytes mask of a memory read: the narrower read
        if (x.is(Op::MEM, 1))
            if (auto n = mem::narrow_mem_mask(r)) return *n;
    }
    // mask(size, 0, 0, x / 256^shr): the bits from 8 * shr
    if (is_int(m->off, 0) && is_int(m->shl, 0) && x.is(Op::DIV, 2) && x[1].is(Op::EXP, 2) && is_int(x[1][0], 256)) {
        Value shift = alg::mul(small(8), x[1][1]);
        if (alg::is_word(shift)) return alg::mask(m->size, shift, alg::neg(shift), x[0]);
    }
    return std::nullopt;
}

// rules at a word node whose operands are simplified; nullopt: none applies
std::optional<Value> word_rule(Value r) {
    const Op op = r.op();
    switch (op) {
        case Op::EQ: {
            Value a = r[0], b = r[1];
            if (is_int(b, 0)) return alg::iszero(a);
            if (is_int(a, 0)) return alg::iszero(b);
            if (is_int(b, 1) && alg::is_bool(a)) return a;
            if (is_int(a, 1) && alg::is_bool(b)) return b;
            Tri t = alg::decide_cmp(op, a, b);
            if (decided(t)) return small(t == Tri::True ? 1 : 0);
            return std::nullopt;
        }
        case Op::LT:
        case Op::GT:
        case Op::LE:
        case Op::GE:
        case Op::SLT:
        case Op::SGT:
        case Op::SLE:
        case Op::SGE: {
            Tri t = alg::decide_cmp(op, r[0], r[1]);
            if (decided(t)) return small(t == Tri::True ? 1 : 0);
            if (op == Op::LT || op == Op::GT || op == Op::LE || op == Op::GE)
                if (auto c = cancel_common(op, r[0], r[1])) return *c;
            return std::nullopt;
        }
        case Op::ISZERO: {
            if (auto x = iszero_rule(r[0])) return *x;
            Tri t = alg::eval_bool(r[0]);
            if (decided(t)) return small(t == Tri::True ? 0 : 1);
            return std::nullopt;
        }
        case Op::BOOL: {
            if (auto y = negated(r[0])) return alg::to_bool(*y);
            Tri t = alg::eval_bool(r[0]);
            if (decided(t)) return small(t == Tri::True ? 1 : 0);
            return std::nullopt;
        }
        case Op::MAX:
        case Op::MIN: {
            Value x = alg::reduce_minmax(r);
            if (x != r) return x;
            return std::nullopt;
        }
        case Op::MOD: {
            // x % 2^k: its k low bits (python: k > 1)
            if (auto k = alg::to_exp2(r[1]); k && *k > 1) return alg::mask(i64(*k), 0, 0, r[0]);
            return std::nullopt;
        }
        case Op::MASK_SHL: return mask_rule(r);
        case Op::CALLDATA_BYTES:
            // a word of the calldata
            if (is_int(r[1], 32)) return mk(Op::CALLDATALOAD, r[0]);
            return std::nullopt;
        case Op::SHA3: {
            // the parts of a DATA operand as operands (the same bytes), no part of no bytes
            bool splice = false;
            for (Value a : r.args())
                if (a.is(Op::DATA) || a.is_none()) splice = true;
            if (!splice) return std::nullopt;
            SmallVec<Value, 8> parts;
            for (Value a : r.args()) {
                if (a.is(Op::DATA))
                    for (Value q : a.args()) parts.push_back(q);
                else if (!a.is_none())
                    parts.push_back(a);
            }
            if (parts.empty()) parts.push_back(mk(Op::DATA, std::span<const Value>{}));
            return mk(Op::SHA3, parts.span());
        }
        case Op::MEM:
            // a read of no bytes is the number 0
            if (r[0].is(Op::RANGE, 2) && is_int(r[0][1], 0)) return small(0);
            return std::nullopt;
        case Op::SIZED:
            // a byte string where a word is read: the number it is
            if (auto w = mem::as_word(r)) return *w;
            return std::nullopt;
        default: return std::nullopt;
    }
}

// ---- rules on bytes -----------------------------------------------------------------

// zeroes then the low bytes of a number below them: the number on all of
// those bytes (python data_elements)
bool merge_zeroes(SmallVec<Value, 16>& parts) {
    bool changed = false;
    SmallVec<Value, 16> out;
    for (Value p : parts) {
        if (!out.empty()) {
            Value z = out.back();
            if (z.is(Op::SIZED, 2) && is_int(z[1], 0) && z[0].is_small() && p.is(Op::SIZED, 2) && p[0].is_small() &&
                !mem::is_bytes(p[1])) {
                const i64 zn = z[0].small_val(), w = p[0].small_val();
                if (zn > 0 && w > 0 && zn + w <= 32 && i64(alg::max_bits(p[1])) <= 8 * w) {
                    out.back() = mk(Op::SIZED, small(zn + w), p[1]);
                    changed = true;
                    continue;
                }
            }
        }
        out.push_back(p);
    }
    if (changed) parts = out;
    return changed;
}

std::optional<Value> bytes_rule(Value r) {
    switch (r.op()) {
        case Op::SIZED: {
            Value n = mem::sized(r[0], r[1]);
            if (n != r) return n;
            return std::nullopt;
        }
        case Op::DATA: {
            SmallVec<Value, 16> parts;
            for (Value p : r.args()) {
                if (p.is(Op::DATA))
                    for (Value q : p.args()) parts.push_back(q);
                else
                    parts.push_back(p);
            }
            Value c = mem::concat(parts.span());
            if (c.is(Op::DATA)) {
                SmallVec<Value, 16> again(c.args());
                if (merge_zeroes(again)) c = mem::concat(again.span());
            }
            if (c != r) return c;
            return std::nullopt;
        }
        case Op::CALLDATA_BYTES:
            // a word of the calldata
            if (is_int(r[1], 32)) return mk(Op::SIZED, small(32), mk(Op::CALLDATALOAD, r[0]));
            // past the end of the calldata: zeroes (vyper clears memory so)
            if (r[0].is(Op::CALLDATASIZE) && r[1].is_small() && r[1].small_val() >= 0)
                return mk(Op::SIZED, r[1], small(0));
            return std::nullopt;
        default: return std::nullopt;
    }
}

// ---- the walk -------------------------------------------------------------------------

Value simp(Value v, Pos pos);

Value simp_node(Value v, Pos pos) {
    const Op op = v.op();
    SmallVec<Value, 8> args;
    bool changed = false;
    for (u32 i = 0; i < v.size(); ++i) {
        Value a = v[i];
        Value n = simp(a, operand_pos(op, i, v.size()));
        if (n != a) changed = true;
        args.push_back(n);
    }
    Value r;
    if (alg::is_pure(op))
        r = alg::apply(op, args.span());
    else if (changed)
        r = mem::keep_widths(v, mk_like(v, args.span()));
    else
        r = v;
    for (int round = 0; round < 8; ++round) {
        if (!r.is_expr()) break;
        std::optional<Value> n = pos == Pos::Bytes || (pos == Pos::Any && mem::is_bytes(r)) ? bytes_rule(r) : word_rule(r);
        if (!n || *n == r) break;
        r = *n;
        // what the rule made: its operands simplified too
        if (r.is_expr()) {
            SmallVec<Value, 8> a2;
            bool ch = false;
            for (u32 i = 0; i < r.size(); ++i) {
                Value x = r[i];
                Value y = simp(x, operand_pos(r.op(), i, r.size()));
                if (y != x) ch = true;
                a2.push_back(y);
            }
            if (ch) r = alg::is_pure(r.op()) ? alg::apply(r.op(), a2.span()) : mk_like(r, a2.span());
        }
    }
    return r;
}

Value simp(Value v, Pos pos) {
    if (v.is_list()) {
        // a list of values (an INTERNAL's arguments, LEAVE's values...)
        SmallVec<Value, 8> items;
        bool changed = false;
        for (Value x : v.args()) {
            Value n = x.is_expr() && has(x.op(), LINE) ? x : simp(x, Pos::Word);
            if (n != x) changed = true;
            items.push_back(n);
        }
        return changed ? mk_like(v, items.span()) : v;
    }
    if (!v.is_expr()) return v;
    if (pos == Pos::Any) pos = mem::is_bytes(v) ? Pos::Bytes : Pos::Word;
    ExpState& S = est();
    Memo<Value, Value>& memo = pos == Pos::Bytes ? S.bytes : S.word;
    if (const Value* r = memo.find(v)) return *r;
    check_stack();
    Value r = simp_node(v, pos);
    memo.put(v, r);
    if (r != v && r.is_expr()) memo.put(r, r);
    return r;
}

}  // namespace

Pos operand_pos(Op op, u32 i, u32 n) {
    (void)n;
    switch (op) {
        case Op::SHA3:
        case Op::DATA: return Pos::Bytes;
        case Op::ARR: return i == 0 ? Pos::Word : Pos::Bytes;
        case Op::SIZED: return i == 0 ? Pos::Word : Pos::Any;
        case Op::SETMEM: return i == 0 ? Pos::Word : Pos::Any;
        case Op::RETURN:
        case Op::REVERT: return Pos::Bytes;
        case Op::LOG0:
        case Op::LOG1:
        case Op::LOG2:
        case Op::LOG3:
        case Op::LOG4: return i == 0 ? Pos::Bytes : Pos::Word;
        case Op::CALL:
        case Op::CALLCODE: return i >= 4 ? Pos::Bytes : Pos::Word;
        case Op::DELEGATECALL:
        case Op::STATICCALL: return i >= 3 ? Pos::Bytes : Pos::Word;
        case Op::CREATE:
        case Op::CREATE2: return i == 2 ? Pos::Bytes : Pos::Word;
        case Op::PRECOMPILED: return i == 3 ? Pos::Bytes : Pos::Word;
        case Op::REQUIRE: return i == 1 ? Pos::Bytes : Pos::Word;
        default: return Pos::Word;
    }
}

Value simplify_word(Value e) { return simp(e, Pos::Word); }
Value simplify_bytes(Value e) { return simp(e, Pos::Bytes); }
Value simplify_at(Value e, Pos pos) { return simp(e, pos); }

Value simplify_exp(Value e) {
    if (e.is_expr() && has(e.op(), LINE)) return simplify_line(e);
    return simp(e, mem::is_bytes(e) ? Pos::Bytes : Pos::Word);
}

}  // namespace pan::simplify
