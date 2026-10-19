// Lot 3 (algebra B): value ranges, comparisons, truth values, path facts.
// Soundness by sampling: for random expressions over random leaves (edge
// words included), the concrete value lies in range(); a decided comparison
// holds on every sample; a decision under facts holds on every sample where
// the facts do. Wrap cases (x + 1 > x with x = 2^256 - 1) stay undecided.
#include <doctest/doctest.h>
#include <gmpxx.h>

#include <random>
#include <string>
#include <vector>

#include "algebra/compare.hpp"
#include "algebra/construct.hpp"
#include "algebra/eval.hpp"
#include "algebra/facts.hpp"
#include "algebra/linear.hpp"
#include "algebra/ranges.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/dump.hpp"
#include "core/errors.hpp"
#include "core/evmint.hpp"

using namespace pan;
namespace A = pan::alg;

namespace {

struct Fixture {
    Budget budget{Budget::Limits{}};
    std::unique_ptr<Context> ctx;
    std::optional<ContextScope> scope;
    Fixture() {
        init();
        budget.attach_thread();
        ctx = Context::create(budget);
        scope.emplace(*ctx);
    }
    ~Fixture() {
        scope.reset();
        ctx.reset();
        budget.detach_thread();
    }
};

Value pow2(u32 k) { return EvmInt::pow2(k).value(); }
EvmInt I(const Word256& w) { return w.to_int(); }
std::string hexw(const Word256& w) {
    static const char* d = "0123456789abcdef";
    std::string s = "0x";
    for (int i = 3; i >= 0; --i)
        for (int j = 60; j >= 0; j -= 4) s += d[(w.limb[i] >> j) & 15];
    return s;
}
std::string str(const EvmInt& x) {
    if (const mpz_class* z = x.big()) return z->get_str(16);
    return std::to_string(x.to_i64());
}
std::string str(const A::Range& r) { return "[" + str(r.lo) + ", " + str(r.hi) + "]"; }
const char* tstr(Tri t) { return t == Tri::True ? "True" : t == Tri::False ? "False" : "None"; }

// The leaves' values within what the ranges assume of an execution: the
// BOUNDED leaves below 2^64, addresses below 2^160, mem[64] at least 0x60
// (the free memory pointer), truth values 0 / 1, STORAGE(size, off, slot) a
// field of a word of the slot; anything else a word of (seed, its hash) -
// edge words included (RandomEnv's). Given leaves: a value in their range.
struct TestEnv final : A::Env {
    u64 seed;
    std::vector<std::pair<Value, std::pair<EvmInt, EvmInt>>> ranges;  // leaf -> [lo, hi]
    explicit TestEnv(u64 s) : seed(s) {}

    static Word256 in_range(const EvmInt& lo, const EvmInt& hi, const Word256& w) {
        // lo, hi, lo + 1, hi - 1, or lo + (w mod (hi - lo + 1))
        EvmInt span = hi - lo + EvmInt(1);
        switch (w.limb[1] % 6) {
            case 0: return Word256::from_int(lo);
            case 1: return Word256::from_int(hi);
            case 2: return Word256::from_int(hi - lo >= EvmInt(1) ? lo + EvmInt(1) : lo);
            case 3: return Word256::from_int(hi - lo >= EvmInt(1) ? hi - EvmInt(1) : hi);
            default: return Word256::from_int(lo + pymod(w.to_int(), span));
        }
    }

    std::optional<Word256> value(Value v, A::Evaluator& ev) override {
        for (auto& [x, r] : ranges)
            if (x == v) return in_range(r.first, r.second, A::RandomEnv::word_for(seed ^ 0x77, v.hash()));
        if (v.is(Op::STORAGE, 3) && v[0].is_small() && v[1].is_small() && v[0].small_val() >= 0 &&
            v[1].small_val() >= 0) {
            auto slot = ev.try_eval(v[2]);
            if (!slot) return std::nullopt;
            u64 h = 0x51ed2701;
            for (u64 l : slot->limb) h = h * 0x9e3779b97f4a7c15ull ^ l;
            Word256 s = A::RandomEnv::word_for(seed ^ 0x5707a6e, h);
            i64 size = v[0].small_val(), off = v[1].small_val();
            if (off >= 256) return Word256{};
            return pan::band(pan::shr(Word256::of(u64(off)), s), A::mask_word(size, 0));
        }
        Word256 w = A::RandomEnv::word_for(seed, v.hash());
        if (info(v.op()).sort == Sort::Bool) return Word256::of(w.limb[0] & 1);
        if (v.is_leaf()) {
            switch (v.op()) {
                case Op::CALLDATASIZE: case Op::RETURNDATASIZE: case Op::CODESIZE: case Op::MSIZE: case Op::GAS:
                    return Word256::of(w.limb[0]);
                case Op::ADDRESS: case Op::CALLER: case Op::ORIGIN: case Op::COINBASE: case Op::CREATE_ADDRESS:
                    return pan::band(w, A::mask_word(160, 0));
                default:
                    break;
            }
        }
        if (v.is_name(NameKind::MSIZE_VAR)) return Word256::of(w.limb[0]);
        if (v.is(Op::MEM, 1) && v[0] == V("(range 64 32)") && w < Word256::of(0x60)) return Word256::of(0x60 + w.limb[0] % 64);
        return w;
    }
};

Word256 ev(Value v, TestEnv& env) {
    A::Evaluator e(env);
    return e(v);
}

// random expressions (raw: normalized by the caller), lot 2's distributions
struct Gen {
    std::mt19937_64 rng;
    int max_depth = 3;
    explicit Gen(u64 seed, int depth = 3) : rng(seed), max_depth(depth) {}
    u64 next() { return rng(); }
    u64 below(u64 n) { return next() % n; }
    bool chance(u64 num, u64 den) { return below(den) < num; }

    Value rint() {
        static const i64 small_list[] = {0, 1, 2, 3, 4, 5, 7, 8, 16, 31, 32, 64, 96, 128, 160, 224, 248, 251,
                                         253, 255, 256, 257, 288, 300, -1, -4, -8, -32, -256, -255};
        switch (below(9)) {
            case 0: case 1: case 2: case 3:
                return mk_int(small_list[below(std::size(small_list))]);
            case 4: case 5:
                return mk_int(i64(below(601)) - 300);
            case 6: {
                u32 k = u32(below(257));
                EvmInt v = EvmInt::pow2(k) - EvmInt(i64(below(2)));
                if (chance(1, 4)) v = -v;
                return Word256::from_int(v).to_value();
            }
            case 7: {
                u32 s = u32(below(257)), o = u32(below(257));
                EvmInt m = EvmInt::mask(s, o).mod_2exp(256);
                if (chance(1, 3)) m = (~m).mod_2exp(256);
                return m.value();
            }
            default: {
                Word256 w{{next(), next(), next(), next()}};
                return w.to_value();
            }
        }
    }

    Value ratom() {
        switch (below(18)) {
            case 0: return mk(Op::CALLDATALOAD, mk_int(4));
            case 1: return mk(Op::CALLDATALOAD, mk_int(36));
            case 2: return mk(Op::CALLDATALOAD, mk(Op::ADD, mk_int(4), mk(Op::CALLDATALOAD, mk_int(4))));
            case 3: return Value::leaf(Op::CALLVALUE);
            case 4: return Value::leaf(Op::CALLDATASIZE);
            case 5: return Value::leaf(Op::CALLER);
            case 6: return Value::name(NameKind::TMP, 1);
            case 7: return Value::name(NameKind::TMP, 2);
            case 8: return Value::leaf(Op::RETURNDATASIZE, 1);
            case 9: return mk(Op::STORAGE, mk_int(256), mk_int(0), mk_int(5));
            case 10: return mk(Op::STORAGE, mk_int(160), mk_int(0), mk_int(3));
            case 11: return mk(Op::STORAGE, mk_int(8), mk_int(160), mk_int(3));
            case 12: return mk(Op::MEM, mk(Op::RANGE, mk_int(64), mk_int(32)));
            case 13: return mk(Op::SHA3, mk_int(1));
            case 14: return Value::leaf(Op::CALL_SUCCESS, 1);
            case 15: return Value::leaf(Op::GAS);
            case 16: return Value::name(NameKind::MSIZE_VAR, 0);
            default: return Value::name(NameKind::LOOP, 7);
        }
    }

    Value leafish() { return chance(1, 3) ? rint() : ratom(); }

    Value rshift(int depth) {
        if (chance(1, 8)) return rexp(depth + 1);
        if (chance(1, 10)) return rint();
        return mk_int(i64(below(300)));
    }

    Value rfield(int which) {
        static const i64 sizes[] = {1, 8, 16, 32, 64, 96, 160, 224, 248, 251, 253, 255, 256};
        static const i64 offs[] = {0, 0, 0, 3, 5, 8, 16, 32, 96, 160};
        static const i64 shls[] = {0, 0, 0, 1, 3, 5, 32, 96, -3, -5, -32, -96, 8, 16};
        switch (which) {
            case 0: return mk_int(sizes[below(std::size(sizes))]);
            case 1: return mk_int(offs[below(std::size(offs))]);
            default: return mk_int(shls[below(std::size(shls))]);
        }
    }

    Value rexp(int depth = 0) {
        if (depth > max_depth || chance(3, 10)) return leafish();
        auto sub = [&] { return rexp(depth + 1); };
        switch (below(32)) {
            case 0: case 1: case 2: case 3: {
                u32 n = 2 + u32(below(3));
                std::vector<Value> a;
                for (u32 i = 0; i < n; ++i) a.push_back(chance(1, 3) ? rint() : sub());
                return mk(Op::ADD, a);
            }
            case 4: case 5: {
                if (chance(2, 3)) return mk(Op::MUL, rint(), sub());
                return mk(Op::MUL, sub(), sub());
            }
            case 6: return mk(Op::SUB, sub(), sub());
            case 7: return mk(Op::DIV, sub(), chance(1, 2) ? rint() : sub());
            case 8: return mk(Op::SDIV, sub(), chance(1, 2) ? rint() : sub());
            case 9: return mk(Op::MOD, sub(), chance(1, 2) ? rint() : sub());
            case 10: return mk(Op::SMOD, sub(), chance(1, 2) ? rint() : sub());
            case 11: return mk(chance(1, 2) ? Op::ADDMOD : Op::MULMOD, sub(), sub(), sub());
            case 12: return mk(Op::EXP, chance(1, 2) ? rint() : sub(), chance(1, 2) ? rshift(depth) : sub());
            case 13: {
                static const i64 bs[] = {0, 1, 3, 15, 19, 30, 31, 32, -1};
                Value b = chance(4, 5) ? mk_int(bs[below(std::size(bs))]) : sub();
                return mk(Op::SIGNEXTEND, b, sub());
            }
            case 14: case 15: {
                static const Op cmps[] = {Op::LT, Op::GT, Op::SLT, Op::SGT, Op::EQ, Op::LE, Op::GE, Op::SLE, Op::SGE};
                Value a = sub(), b = chance(1, 5) ? a : sub();
                return mk(cmps[below(9)], a, b);
            }
            case 16: return mk(Op::ISZERO, sub());
            case 17: {
                Value m = chance(1, 2) ? rint() : sub();
                return chance(1, 2) ? mk(Op::AND, sub(), m) : mk(Op::AND, m, sub());
            }
            case 18: return mk(Op::OR, sub(), sub());
            case 19: return mk(Op::XOR, sub(), sub());
            case 20: return mk(Op::NOT, sub());
            case 21: return mk(Op::BYTE, chance(4, 5) ? mk_int(i64(below(34))) : sub(), sub());
            case 22: return mk(Op::SHL, rshift(depth), sub());
            case 23: return mk(Op::SHR, rshift(depth), sub());
            case 24: return mk(Op::SAR, rshift(depth), sub());
            case 25: return mk(Op::CLZ, sub());
            case 26: case 27: return mk(Op::MASK_SHL, rfield(0), rfield(1), rfield(2), sub());
            case 28: return mk(chance(1, 2) ? Op::MAX : Op::MIN, sub(), sub());
            case 29: return mk(chance(1, 2) ? Op::LAND : Op::LOR, sub(), sub());
            default: {
                // ceil32 / floor32 shapes around a value (the mask readings)
                Value x = chance(1, 2) ? ratom() : sub();
                switch (below(4)) {
                    case 0: return mk(Op::MASK_SHL, mk_int(251), mk_int(5), mk_int(0), mk(Op::ADD, mk_int(31), x));
                    case 1: return mk(Op::MASK_SHL, mk_int(251), mk_int(5), mk_int(0), x);
                    case 2: return mk(Op::ADD, x, mk(Op::MUL, mk_int(-1), mk(Op::MASK_SHL, mk_int(5), mk_int(0), mk_int(0), x)));
                    default: return mk(Op::MASK_SHL, mk_int(248), mk_int(0), mk_int(8), x);
                }
            }
        }
    }

    // b made from a: a itself moved by a constant, a mask of it, a sum with
    // it, or another expression
    Value related(Value a) {
        switch (below(7)) {
            case 0: return A::add(a, rint());
            case 1: return A::add(a, mk_int(i64(below(64)) - 32));
            case 2: return A::mask(251, 5, 0, A::add(a, mk_int(31)));
            case 3: return A::mask(251, 5, 0, a);
            case 4: return A::add(a, A::normalize(rexp(2)));
            case 5: return A::normalize(rexp());
            default: return A::sub(A::normalize(rexp(2)), a);
        }
    }
};

constexpr u64 kSeeds[] = {1, 2, 3, 0x9e37, 77, 1234567, 42, 0xdead, 5, 6, 7, 8, 9, 10, 11, 12};

bool holds(Op op, const Word256& a, const Word256& b) {
    const Word256 xs[2] = {a, b};
    auto r = A::eval_op(op, std::span<const Word256>(xs, 2));
    return r && !r->is_zero();
}

}  // namespace

// ------------------------------------------------------------------ soundness

TEST_CASE("ranges: random expressions evaluate within their range") {
    Fixture f;
    Gen g(20261019);
    int bad = 0, cases = 0, narrow = 0;
    for (int i = 0; i < 5000 && bad < 6; ++i) {
        Value e = A::normalize(g.rexp());
        A::Range r = A::range(e);
        CHECK_MESSAGE(r.is_word(), dump(e), " ", str(r));
        if (!(r == A::Range::word())) ++narrow;
        for (u64 s : kSeeds) {
            TestEnv env(s);
            Word256 w = ev(e, env);
            ++cases;
            if (!r.contains(I(w))) {
                ++bad;
                FAIL_CHECK("outside its range: ", dump(e), " = ", hexw(w), " not in ", str(r), " (seed ", s, ")");
                break;
            }
        }
    }
    CHECK(bad == 0);
    MESSAGE("ranges: ", cases, " evaluations, ", narrow, " of 5000 ranges narrower than a word");
}

TEST_CASE("ranges: decided comparisons hold on every sample") {
    Fixture f;
    Gen g(77001);
    int bad = 0, decided = 0, total = 0;
    static const Op ops[] = {Op::LT, Op::LE, Op::EQ, Op::SLT, Op::SLE, Op::GT, Op::GE, Op::SGT, Op::SGE};
    for (int i = 0; i < 4000 && bad < 6; ++i) {
        Value a = A::normalize(g.rexp(1));
        Value b = g.related(a);
        if (g.chance(1, 2)) std::swap(a, b);
        for (Op op : ops) {
            ++total;
            Tri t = A::decide_cmp(op, a, b);
            if (t == Tri::None) continue;
            ++decided;
            for (u64 s : kSeeds) {
                TestEnv env(s);
                const bool h = holds(op, ev(a, env), ev(b, env));
                if (h != (t == Tri::True)) {
                    ++bad;
                    FAIL_CHECK("wrong decision ", tstr(t), " of ", op_name(op), " ", dump(a), " ", dump(b), " (seed ", s,
                               ": ", hexw(ev(a, env)), " ", hexw(ev(b, env)), ")");
                    break;
                }
            }
        }
        // the differences' ranges
        A::Range d = A::word_diff(a, b);
        for (u64 s : kSeeds) {
            TestEnv env(s);
            EvmInt x = I(ev(b, env)) - I(ev(a, env));
            if (!d.contains(x)) {
                ++bad;
                FAIL_CHECK("word_diff ", dump(a), " ", dump(b), " = ", str(x), " not in ", str(d));
                break;
            }
        }
    }
    CHECK(bad == 0);
    MESSAGE("comparisons: ", decided, " of ", total, " decided");
}

TEST_CASE("ranges: python's integers (int_range, int_diff_sign) hold on every sample") {
    Fixture f;
    Gen g(4242);
    int bad = 0;
    // the integer of a linear form: constant + sum(coeff * word(term))
    auto integer = [](Value v, TestEnv& env) {
        A::Linear l = A::linear(v);
        EvmInt x(l.constant);
        for (usize i = 0; i < l.terms.size(); ++i) x = x + l.coeff_int(i) * I(ev(l.terms[i].term, env));
        return x;
    };
    for (int i = 0; i < 3000 && bad < 6; ++i) {
        Value a = A::normalize(g.rexp(2));
        Value b = g.related(a);
        A::Range ra = A::int_range(A::linear(a));
        A::SignRange s = A::int_diff_sign(a, b);
        for (u64 seed : kSeeds) {
            TestEnv env(seed);
            EvmInt ia = integer(a, env), ib = integer(b, env);
            if (!ra.contains(ia)) {
                ++bad;
                FAIL_CHECK("int_range ", dump(a), " = ", str(ia), " not in ", str(ra));
                break;
            }
            int sd = (ib - ia).sign();
            if ((s.pos() && sd <= 0) || (s.nonneg() && sd < 0) || (s.neg() && sd >= 0) || (s.nonpos() && sd > 0)) {
                ++bad;
                FAIL_CHECK("int_diff_sign ", dump(a), " ", dump(b), " sign ", sd);
                break;
            }
        }
    }
    CHECK(bad == 0);
}

TEST_CASE("ranges: decisions under facts hold wherever the facts do") {
    Fixture f;
    Gen g(99);
    std::mt19937_64 rng(5);
    // leaves with known ranges, and the conditions that say so
    const Value x = V("(calldataload 4)"), y = V("(calldataload 36)"), z = V("tmp1"), w = V("(storage 256 0 5)");
    int bad = 0, decided = 0, total = 0, samples_used = 0;
    for (int round = 0; round < 400 && bad < 6; ++round) {
        std::vector<std::pair<Value, std::pair<EvmInt, EvmInt>>> rs;
        A::Facts facts;
        auto bound_leaf = [&](Value leaf) {
            // one of: x < c, x <= c, x > c, x >= c, x == c (c small or near 2^256)
            static const i64 cs[] = {1, 2, 10, 32, 100, 255, 1000, 1 << 20};
            EvmInt c = rng() % 5 == 0 ? word_max() - EvmInt(i64(rng() % 40)) : EvmInt(cs[rng() % std::size(cs)]);
            Value cv = c.value();
            switch (rng() % 5) {
                case 0: rs.push_back({leaf, {EvmInt(0), c - EvmInt(1)}}); facts = facts.with_cond(A::cmp(Op::LT, leaf, cv)); break;
                case 1: rs.push_back({leaf, {EvmInt(0), c}}); facts = facts.with_cond(A::cmp(Op::LE, leaf, cv)); break;
                case 2:
                    rs.push_back({leaf, {c, word_max()}});
                    facts = facts.with_cond(A::iszero(A::cmp(Op::LT, leaf, cv)));
                    break;
                case 3:
                    if (c == word_max()) c = c - EvmInt(1);
                    rs.push_back({leaf, {c + EvmInt(1), word_max()}});
                    facts = facts.with_cond(A::cmp(Op::GT, leaf, c.value()));
                    break;
                default: rs.push_back({leaf, {c, c}}); facts = facts.with_cond(A::cmp(Op::EQ, leaf, cv)); break;
            }
        };
        for (Value leaf : {x, y, z, w})
            if (rng() % 3) bound_leaf(leaf);
        // a relational fact sometimes (checked by rejection)
        Value rel;
        if (rng() % 3 == 0) {
            rel = A::cmp(rng() % 2 ? Op::LT : Op::LE, rng() % 2 ? x : A::add(x, mk_int(i64(rng() % 5))), y);
            facts = facts.with_cond(rel);
        }
        for (int q = 0; q < 12; ++q) {
            // queries over the leaves
            Value a = std::vector<Value>{x, y, z, w}[rng() % 4];
            Value b;
            switch (rng() % 6) {
                case 0: b = A::add(a, mk_int(i64(rng() % 7) - 3)); break;
                case 1: b = mk_int(i64(rng() % 300)); break;
                case 2: b = std::vector<Value>{x, y, z, w}[rng() % 4]; break;
                case 3: b = A::add(std::vector<Value>{x, y, z, w}[rng() % 4], mk_int(i64(rng() % 40))); break;
                case 4: b = A::mask(251, 5, 0, A::add(a, mk_int(31))); break;
                default: b = A::normalize(g.rexp(1)); break;
            }
            if (rng() % 3 == 0) a = A::add(a, mk_int(i64(rng() % 33)));
            static const Op ops[] = {Op::LT, Op::LE, Op::EQ, Op::GT, Op::GE, Op::SLT, Op::SGE};
            Op op = ops[rng() % std::size(ops)];
            Value cond = A::cmp(op, a, b);
            if (rng() % 4 == 0) cond = A::iszero(cond);
            if (rng() % 5 == 0) cond = A::bor(cond, A::cmp(Op::LT, a, mk_int(i64(rng() % 50))));
            ++total;
            Tri t = A::eval_bool(cond, &facts);
            if (t == Tri::None) continue;
            ++decided;
            for (u64 s = 0; s < 48; ++s) {
                TestEnv env(s * 7919 + u64(round));
                env.ranges = rs;
                if (!rel.nil() && ev(rel, env).is_zero()) continue;  // the facts don't hold there
                ++samples_used;
                const bool h = !ev(cond, env).is_zero();
                if (h != (t == Tri::True)) {
                    ++bad;
                    FAIL_CHECK("wrong decision ", tstr(t), " of ", dump(cond), " under facts (seed ", s, ")");
                    break;
                }
            }
        }
    }
    CHECK(bad == 0);
    MESSAGE("facts: ", decided, " of ", total, " decided, ", samples_used, " samples");
}

// ------------------------------------------------------------------ the wrap

TEST_CASE("ranges: sums that may wrap decide nothing") {
    Fixture f;
    const Value x = V("(calldataload 4)"), s0 = V("(storage 256 0 0)");
    // x + 1 > x: false for x = 2^256 - 1
    CHECK(A::lt(x, A::add(x, mk_int(1))) == Tri::None);
    CHECK(A::eval_bool(A::cmp(Op::GT, A::add(x, mk_int(1)), x)) == Tri::None);
    CHECK(A::eval_bool(A::cmp(Op::LT, x, A::add(x, mk_int(1)))) == Tri::None);
    // python's own unsoundness: stor0 <= stor0 + 1
    CHECK(A::le(s0, A::add(s0, mk_int(1))) == Tri::None);
    CHECK(A::eval_bool(A::cmp(Op::LE, s0, A::add(s0, mk_int(1)))) == Tri::None);
    // x - 1 < x: false for x = 0
    CHECK(A::lt(A::sub(x, mk_int(1)), x) == Tri::None);
    // never equal, whatever wraps: a difference that is a constant
    CHECK(A::eq(x, A::add(x, mk_int(1))) == Tri::False);
    CHECK(A::eq(A::add(x, mk_int(5)), A::add(x, mk_int(5))) == Tri::True);
    // ceil32(x) >= x: false for x past 2^256 - 32 (it wraps to 0)
    Value c32 = A::mask(251, 5, 0, A::add(x, mk_int(31)));
    CHECK(A::le(x, c32) == Tri::None);
    // but ceil32(x) - x is in [0, 31] as a word
    CHECK(A::range(A::sub(c32, x)) == A::Range::of(EvmInt(0), EvmInt(31)));
    // the integer of x + 1 isn't a word; its word is any word
    CHECK(A::range(A::add(x, mk_int(1))) == A::Range::word());
    CHECK(A::int_range(A::add(x, mk_int(1))) == A::Range::of(EvmInt(1), two_256()));
    CHECK(!A::is_word(A::add(x, mk_int(1))));
}

TEST_CASE("ranges: sums that can't wrap decide") {
    Fixture f;
    const Value cds = V("calldatasize"), x = V("(calldataload 4)");
    CHECK(A::range(cds) == A::Range::bits(64));
    CHECK(A::range(A::add(cds, mk_int(1))) == A::Range::of(EvmInt(1), EvmInt::pow2(64)));
    CHECK(A::lt(cds, A::add(cds, mk_int(1))) == Tri::True);
    CHECK(A::lt(A::add(cds, mk_int(1)), cds) == Tri::False);
    CHECK(A::le(cds, A::mask(251, 5, 0, A::add(cds, mk_int(31)))) == Tri::True);
    CHECK(A::eval_bool(A::cmp(Op::GT, A::add(cds, mk_int(32)), cds)) == Tri::True);
    // x - 1 where x >= 1 is known: below x
    A::Facts k = A::Facts().with_cond(A::iszero(A::iszero(x)));
    CHECK(A::lt(A::sub(x, mk_int(1)), x, A::Top::Word, &k) == Tri::True);
    // x + 1 > x where x < 10 is known
    A::Facts k10 = A::Facts().with_cond(A::cmp(Op::LT, x, mk_int(10)));
    CHECK(A::eval_bool(A::cmp(Op::GT, A::add(x, mk_int(1)), x), &k10) == Tri::True);
    CHECK(A::range(A::add(x, mk_int(1)), A::Top::Word, &k10) == A::Range::of(EvmInt(1), EvmInt(10)));
    // a negative constant: the word of x - 5 where x >= 5
    A::Facts k5 = A::Facts().with_cond(A::iszero(A::cmp(Op::LT, x, mk_int(5))));
    CHECK(A::range(A::sub(x, mk_int(5)), A::Top::Word, &k5) == A::Range::of(EvmInt(0), word_max() - EvmInt(5)));
    // -x where x >= 1: 2^256 - x
    CHECK(A::range(A::neg(x), A::Top::Word, &k) == A::Range::of(EvmInt(1), word_max()));
}

// ------------------------------------------------------------------ the shapes

TEST_CASE("ranges: leaves, masks and the other operations") {
    Fixture f;
    CHECK(A::range(V("caller")) == A::Range::bits(160));
    CHECK(A::range(V("(mask_shl 160 0 0 (calldataload 4))")) == A::Range::bits(160));
    CHECK(A::range(V("(lt (calldataload 4) 5)")) == A::Range::bits(1));
    CHECK(A::range(V("(storage 8 160 3)")) == A::Range::bits(8));
    CHECK(A::range(V("(mod (calldataload 4) 32)")) == A::Range::of(EvmInt(0), EvmInt(31)));
    CHECK(A::range(V("(div calldatasize 32)")) == A::Range::of(EvmInt(0), (EvmInt::pow2(64) - EvmInt(1)) >> 5));
    CHECK(A::range(V("(byte 3 (calldataload 4))")) == A::Range::bits(8));
    CHECK(A::range(V("(clz (calldataload 4))")) == A::Range::of(EvmInt(0), EvmInt(256)));
    // floor32 of a 64-bit word: monotone
    CHECK(A::range(A::mask(251, 5, 0, V("calldatasize"))) ==
          A::Range::of(EvmInt(0), EvmInt::pow2(64) - EvmInt(32)));
    // 8 * uint8(x)
    CHECK(A::range(A::mask(8, 0, 3, V("(calldataload 4)"))) == A::Range::of(EvmInt(0), EvmInt(255 * 8)));
    // a product of two small words
    CHECK(A::range(A::mul(V("(mask_shl 8 0 0 (calldataload 4))"), V("(mask_shl 8 0 0 (calldataload 36))"))) ==
          A::Range::of(EvmInt(0), EvmInt(255 * 255)));
    // exp
    CHECK(A::range(A::exp(mk_int(2), V("(mask_shl 3 0 0 (calldataload 4))"))) == A::Range::of(EvmInt(1), EvmInt(128)));
    // max / min of ranges
    CHECK(A::range(A::max({V("(mask_shl 8 0 0 caller)"), mk_int(1000)})) == A::Range::of(EvmInt(1000), EvmInt(1000)));
    // the free memory pointer
    CHECK(A::range(V("(mem (range 64 32))")) == A::Range::of(EvmInt(0x60), word_max()));
    A::set_free_memory_pointer(false);
    CHECK(A::range(V("(mem (range 64 32))")) == A::Range::word());
    A::set_free_memory_pointer(true);
    CHECK(A::range(V("(mem (range 64 32))")) == A::Range::of(EvmInt(0x60), word_max()));
    // range_bits
    CHECK(A::range_bits(V("calldatasize")) == 64);
    CHECK(A::range_bits(V("(add 1 calldatasize)")) == 65);
    CHECK(A::range_bits(mk_int(0)) == 0);
    CHECK(A::max_value_bits(V("caller")) == 160);
}

TEST_CASE("ranges: python's integers") {
    Fixture f;
    const Value x = V("(calldataload 4)");
    CHECK(A::int_range(A::sub(x, mk_int(1))) == A::Range::of(EvmInt(-1), word_max() - EvmInt(1)));
    CHECK(!A::is_word(A::sub(x, mk_int(1))));
    CHECK(A::is_word(V("calldatasize")));
    CHECK(A::shift_sign(mk_int(0)) == 0);
    CHECK(A::shift_sign(V("calldatasize")) == 1);
    CHECK(A::shift_sign(A::neg(V("calldatasize"))) == -1);
    CHECK(A::shift_sign(A::sub(V("calldatasize"), mk_int(5))) == std::nullopt);
    CHECK(A::ge_zero(A::linear(A::sub(V("calldatasize"), mk_int(5)))) == Tri::None);
    CHECK(A::ge_zero(A::linear(A::add(V("calldatasize"), mk_int(5)))) == Tri::True);
    CHECK(A::gt_zero(A::linear(A::neg(V("calldatasize")))) == Tri::False);
    // python lt_op on sums: x < x + 1 as integers (no wrap there)
    CHECK(A::int_lt(x, A::add(x, mk_int(1))) == Tri::True);
    CHECK(A::int_le(A::add(x, mk_int(1)), x) == Tri::False);
    // below the largest of a max
    CHECK(A::int_lt(V("(mask_shl 8 0 0 caller)"), A::max({mk_int(300), V("calldatasize")})) == Tri::True);
}

TEST_CASE("ranges: the variables and the memory top") {
    Fixture f;
    const Value t1 = V("tmp1"), t2 = V("tmp2"), l7 = V("loop7");
    std::vector<std::pair<Value, Value>> vals = {
        {t1, mk_int(5)}, {t1, mk_int(10)}, {t2, A::add(t1, mk_int(1))}, {l7, mk_int(0)}, {l7, A::add(l7, mk_int(1))}};
    std::vector<Value> small = {V("(calldataload 36)")};
    A::set_variables(vals, small);
    CHECK(A::range(t1) == A::Range::of(EvmInt(5), EvmInt(10)));
    CHECK(A::range(t2) == A::Range::of(EvmInt(6), EvmInt(11)));
    CHECK(A::range(l7) == A::Range::word());  // cyclic: a loop's counter
    CHECK(A::lt(t1, t2) == Tri::True);
    CHECK(A::eval_bool(A::cmp(Op::LT, t1, mk_int(11))) == Tri::True);
    // the memory top: unchecked words aren't below 2^64, the small ones are
    CHECK(A::unchecked(V("(calldataload 4)")));
    CHECK(!A::unchecked(V("(calldataload 36)")));
    CHECK(A::unchecked(A::add(V("(calldataload 4)"), mk_int(4))));
    CHECK(!A::unchecked(V("(storage 256 0 1)")));
    CHECK(A::memory_range(V("(storage 256 0 1)")) == A::Range::bits(64));
    CHECK(A::memory_range(V("(calldataload 4)")) == A::Range::word());
    CHECK(A::memory_range(V("(calldataload 36)")) == A::Range::bits(64));
    CHECK(A::memory_range(A::add(V("(storage 256 0 1)"), mk_int(32))) ==
          A::Range::of(EvmInt(32), EvmInt::pow2(64) + EvmInt(31)));
    CHECK(A::range(A::add(V("(storage 256 0 1)"), mk_int(32))) == A::Range::word());
    CHECK(A::lt(V("(storage 256 0 1)"), A::add(V("(storage 256 0 1)"), mk_int(32)), A::Top::Memory) == Tri::True);
    // a mask of -x: not clamped
    CHECK(A::memory_range(A::mask(5, 0, 0, A::neg(V("(storage 256 0 1)")))) == A::Range::bits(5));
    A::clear_variables();
    CHECK(A::range(t1) == A::Range::word());
}

// ------------------------------------------------------------------ truth, max, min

TEST_CASE("ranges: eval_bool, is_zero, decide") {
    Fixture f;
    const Value x = V("(calldataload 4)"), y = V("(calldataload 36)");
    CHECK(A::eval_bool(mk_int(5)) == Tri::True);
    CHECK(A::eval_bool(V("(iszero 0)")) == Tri::True);
    CHECK(A::eval_bool(V("caller")) == Tri::None);
    CHECK(A::eval_bool(A::cmp(Op::LT, V("caller"), pow2(160))) == Tri::True);
    CHECK(A::eval_bool(A::cmp(Op::GT, V("calldatasize"), pow2(64))) == Tri::False);
    // python's rule: x < 10 known decides x < 20
    A::Facts k = A::Facts().with_cond(A::cmp(Op::LT, x, mk_int(10)));
    CHECK(A::eval_bool(A::cmp(Op::LT, x, mk_int(20)), &k) == Tri::True);
    CHECK(A::eval_bool(A::cmp(Op::LT, x, mk_int(5)), &k) == Tri::None);
    CHECK(A::eval_bool(A::cmp(Op::GT, x, mk_int(15)), &k) == Tri::False);
    CHECK(A::eval_bool(A::cmp(Op::EQ, x, mk_int(15)), &k) == Tri::False);
    CHECK(A::eval_bool(A::iszero(A::cmp(Op::LT, x, mk_int(10))), &k) == Tri::False);
    CHECK(k.is_known(A::cmp(Op::LT, x, mk_int(10))) == Tri::True);
    // a relational fact: x < y known, so x < y + 1 where y + 1 can't wrap (y < 2^255)
    A::Facts r = A::Facts().with_cond(A::cmp(Op::LT, x, y)).with_cond(A::cmp(Op::LT, y, pow2(255)));
    CHECK(A::eval_bool(A::cmp(Op::LT, x, A::add(y, mk_int(1))), &r) == Tri::True);
    CHECK(A::eval_bool(A::cmp(Op::LE, x, y), &r) == Tri::True);
    CHECK(A::eval_bool(A::cmp(Op::EQ, x, y), &r) == Tri::False);
    CHECK(A::eval_bool(A::cmp(Op::GE, x, y), &r) == Tri::False);
    // facts of an AND: each of them
    A::Facts both = A::Facts().with_cond(A::band(A::cmp(Op::LT, x, mk_int(3)), A::cmp(Op::GT, y, mk_int(7))));
    CHECK(A::eval_bool(A::cmp(Op::LT, x, mk_int(3)), &both) == Tri::True);
    CHECK(A::eval_bool(A::cmp(Op::GT, y, mk_int(5)), &both) == Tri::True);
    // a nonzero word known
    A::Facts nz = A::Facts().with_cond(x);
    CHECK(A::eval_bool(A::iszero(x), &nz) == Tri::False);
    CHECK(A::eval_bool(A::cmp(Op::GT, x, mk_int(0)), &nz) == Tri::True);
    // is_zero, decide
    CHECK(A::is_zero(A::cmp(Op::LT, x, mk_int(20)), &k) == mk_int(0));
    CHECK(A::is_zero(A::cmp(Op::LT, x, mk_int(5)), &k) == A::iszero(A::cmp(Op::LT, x, mk_int(5))));
    Value c = A::bor(A::cmp(Op::LT, x, mk_int(5)), A::cmp(Op::GT, x, mk_int(50)));
    CHECK(A::decide(c, &k) == A::cmp(Op::LT, x, mk_int(5)));
    CHECK(A::decide(c, nullptr) == c);
    CHECK(k.decided(A::cmp(Op::LT, x, mk_int(20))) == mk_int(1));
}

TEST_CASE("ranges: max, min, cond_bounds, apply_constraint") {
    Fixture f;
    const Value cds = V("calldatasize"), rds = V("(returndatasize 1)"), x = V("(calldataload 4)");
    CHECK(A::max_of(cds, A::add(cds, mk_int(1))) == A::add(cds, mk_int(1)));
    CHECK(A::min_of(cds, A::add(cds, mk_int(1))) == cds);
    CHECK(A::max_of(x, A::add(x, mk_int(1))) == std::nullopt);
    CHECK(A::reduce_minmax(A::max({cds, A::add(cds, mk_int(1)), mk_int(3)})) == A::max({A::add(cds, mk_int(1)), mk_int(3)}));
    CHECK(A::reduce_minmax(A::max({V("(mask_shl 8 0 0 caller)"), mk_int(256)})) == mk_int(256));
    CHECK(A::reduce_minmax(A::min({V("(mask_shl 8 0 0 caller)"), mk_int(256)})) == V("(mask_shl 8 0 0 caller)"));
    // a comparison with a MAX / MIN by its operands
    const Value y = V("(calldataload 36)");
    CHECK(A::le(x, A::max({x, y})) == Tri::True);
    CHECK(A::lt(A::max({x, y}), x) == Tri::False);
    CHECK(A::le(A::min({x, y}), y) == Tri::True);
    CHECK(A::lt(x, A::min({x, y})) == Tri::False);
    CHECK(A::lt(A::max({V("(mask_shl 8 0 0 caller)"), V("(mask_shl 16 0 0 caller)")}), pow2(16)) == Tri::True);
    CHECK(A::le(x, A::max({y, A::add(cds, mk_int(1))})) == Tri::None);
    // cond_bounds
    A::CondBounds b = A::cond_bounds(A::cmp(Op::LT, x, mk_int(10)));
    REQUIRE(b.size() == 1);
    CHECK(b[0].x == x);
    CHECK(b[0].range() == A::Range::of(EvmInt(0), EvmInt(9)));
    b = A::cond_bounds(A::iszero(A::cmp(Op::LT, x, mk_int(10))));
    REQUIRE(b.size() == 1);
    CHECK(b[0].range() == A::Range::of(EvmInt(10), word_max()));
    b = A::cond_bounds(A::cmp(Op::GT, mk_int(10), x));
    REQUIRE(b.size() == 1);
    CHECK(b[0].range() == A::Range::of(EvmInt(0), EvmInt(9)));
    b = A::cond_bounds(A::cmp(Op::SLT, cds, mk_int(10)));
    REQUIRE(b.size() == 1);
    CHECK(b[0].range() == A::Range::of(EvmInt(0), EvmInt(9)));
    CHECK(A::cond_bounds(A::cmp(Op::SLT, x, mk_int(10))).empty());  // x may be negative
    CHECK(A::cond_bounds(A::cmp(Op::LT, x, mk_int(0))).empty());
    b = A::cond_bounds(A::iszero(x));
    REQUIRE(b.size() == 1);
    CHECK(b[0].range() == A::Range::of(EvmInt(0), EvmInt(0)));
    b = A::cond_bounds(A::cmp(Op::GE, A::min({mk_int(32), rds}), mk_int(32)));
    CHECK(b.size() == 2);
    // apply_constraint: min(32, returndatasize) is 32 once returndatasize >= 32
    Value m = A::min({mk_int(32), rds});
    CHECK(A::apply_constraint(m, A::iszero(A::cmp(Op::LT, rds, mk_int(32)))) == mk_int(32));
    CHECK(A::apply_constraint(A::add(m, mk_int(4)), A::iszero(A::cmp(Op::LT, rds, mk_int(32)))) == mk_int(36));
    CHECK(A::apply_constraint(m, A::cmp(Op::LT, rds, mk_int(10))) == rds);
    CHECK(A::apply_constraint(m, A::cmp(Op::LT, x, mk_int(10))) == m);
}

// ------------------------------------------------------------------ the facts

TEST_CASE("ranges: path facts") {
    Fixture f;
    const Value x = V("(calldataload 4)"), s = V("(storage 256 0 1)");
    A::Facts k = A::Facts().with_fresh().with_rdzero();
    CHECK(k.fresh());
    CHECK(k.rdzero());
    k = k.with(A::cmp(Op::LT, x, mk_int(100)), true).with(A::cmp(Op::LT, s, mk_int(7)), false);
    CHECK(k.size() == 4);
    CHECK(k.bounds(x) == A::Range::of(EvmInt(0), EvmInt(99)));
    CHECK(k.bounds(s) == A::Range::of(EvmInt(7), word_max()));
    CHECK(k.upper_bound(x) == EvmInt(99));
    CHECK(k.bound(x) == EvmInt(99));
    CHECK(k.bound(V("calldatasize")) == EvmInt::pow2(64) - EvmInt(1));
    CHECK(k.bound(V("(calldataload 36)")) == std::nullopt);
    // forget: storage reads go, the rest stays
    A::Facts g = k.forget(A::Forget::Storage);
    CHECK(g.size() == 3);
    CHECK(!g.bounds(s));
    CHECK(g.bounds(x) == A::Range::of(EvmInt(0), EvmInt(99)));
    CHECK(g.forget(A::Forget::Storage) == g);
    A::Facts v = k.forget(A::Forget::Volatile);
    CHECK(!v.rdzero());
    CHECK(v.fresh());
    // the memory
    A::Facts m = A::Facts().with_fresh();
    CHECK(m.read_memory(mk_int(0)) == mk_int(0));
    m = m.write_memory(mk_int(64), mk_int(32), mk_int(0x80));
    CHECK(m.read_memory(mk_int(64)) == mk_int(0x80));
    CHECK(m.known_zeroes(mk_int(0), mk_int(64)));
    CHECK(!m.known_zeroes(mk_int(0), mk_int(96)));
    m = m.write_memory(mk_int(80), mk_int(32), x);
    CHECK(m.read_memory(mk_int(80)) == x);
    // the 0x80 was in the low bytes, overwritten by x's high ones
    CHECK(m.read_memory(mk_int(64)) == A::mask(128, 128, -128, x));
    // a write somewhere unknown: memory facts dropped
    A::Facts u = m.write_memory(x, mk_int(32), mk_int(1));
    CHECK(u.read_memory(mk_int(80)).nil());
    // a write at a bounded place: only that range
    A::Facts b = A::Facts().with_fresh().with_cond(A::cmp(Op::LT, x, mk_int(4)));
    b = b.write_memory(mk_int(0), mk_int(32), mk_int(7));
    b = b.write_memory(A::add(mk_int(256), A::mul(mk_int(32), x)), mk_int(32), mk_int(1));
    CHECK(b.read_memory(mk_int(0)) == mk_int(7));
    CHECK(b.read_memory(mk_int(256)).nil());
    // equality and sharing
    A::Facts c1 = k.with_cond(x), c2 = k.with_cond(x);
    CHECK(c1 == c2);
    CHECK(!(c1 == k));
    SmallVec<A::Fact, 32> vec;
    c1.to_vector(vec);
    CHECK(A::Facts::from(vec.span()) == c1);
    CHECK(A::Facts::from(vec.span()).bounds(x) == A::Range::of(EvmInt(1), EvmInt(99)));
    // var_bits
    A::Facts vb = A::Facts().with_var_bits(V("tmp4"), 8);
    CHECK(vb.var_bits(V("tmp4")) == 8u);
    CHECK(A::range(V("tmp4"), A::Top::Word, &vb) == A::Range::bits(8));
    CHECK(A::lt(V("tmp4"), A::add(V("tmp4"), mk_int(1)), A::Top::Word, &vb) == Tri::True);
}

TEST_CASE("ranges: hostile shapes stay bounded") {
    Fixture f;
    // a long sum of products of masks: coefficients past 2^320 say nothing
    Value e = V("(calldataload 4)");
    for (int i = 0; i < 40; ++i) e = A::add(A::mul(pow2(200), e), V("(calldataload 36)"));
    A::Range r = A::range(e);
    CHECK(r.is_word());
    // deep nesting
    // (past what the stack holds: the answers that hold without looking)
    Value d = V("calldatasize");
    for (int i = 0; i < 3000; ++i) d = A::mask(251, 5, 0, A::add(d, mk_int(31)));
    CHECK(A::range(d).is_word());
    CHECK(A::lt(d, A::add(d, mk_int(1))) != Tri::False);
    CHECK(A::eval_bool(A::cmp(Op::LT, d, mk_int(5))) != Tri::True);
    Value e2 = V("calldatasize");
    for (int i = 0; i < 200; ++i) e2 = A::mask(251, 5, 0, A::add(e2, mk_int(31)));
    A::Range r2 = A::range(e2);  // (each level adds 31 at most, nothing wraps)
    CHECK(r2.hi <= EvmInt::pow2(64) + EvmInt(31 * 201));
    CHECK(A::le(V("calldatasize"), e2) == Tri::True);
    // a big constant times a word: the integer saturates, the word is fine
    Value p = A::mul(pow2(255), V("(calldataload 4)"));
    CHECK(A::range(p).is_word());
    CHECK(A::int_range(A::linear(p)).lo.sign() <= 0);
}
