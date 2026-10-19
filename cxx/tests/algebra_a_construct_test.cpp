// Lot 2 (algebra A): the constructors checked by evaluation - every normal
// form has the value of the EVM operations it stands for, on random and
// edge words - and the shapes the later stages rely on.
#include <doctest/doctest.h>

#include <random>
#include <string>
#include <vector>

#include "algebra/construct.hpp"
#include "algebra/eval.hpp"
#include "algebra/linear.hpp"
#include "algebra/masks.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/dump.hpp"
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

Value big(const char* hex) {
    mpz_class z(hex, 16);
    return mk_int_mpz(z.get_mpz_t());
}

Value pow2(u32 k) { return EvmInt::pow2(k).value(); }
Value pow2m1(u32 k) { return (EvmInt::pow2(k) - EvmInt(1)).value(); }

// The env of the tests: STORAGE(size, off, slot) with size, off >= 0 ints is
// (S[slot] >> off) & (2^size - 1), S[slot] a word of the slot's value; a
// node or leaf whose sort is Bool is 0 or 1; anything else a word of
// (seed, its structural hash) (RandomEnv's, edge values included).
struct TestEnv final : A::Env {
    u64 seed;
    explicit TestEnv(u64 s) : seed(s) {}
    std::optional<Word256> value(Value v, A::Evaluator& ev) override {
        if (v.is(Op::STORAGE, 3) && v[0].is_small() && v[1].is_small() && v[0].small_val() >= 0 && v[1].small_val() >= 0) {
            auto slot = ev.try_eval(v[2]);
            if (!slot) return std::nullopt;
            u64 h = 0x51ed2701;
            for (u64 l : slot->limb) h = h * 0x9e3779b97f4a7c15ull ^ l;
            Word256 s = A::RandomEnv::word_for(seed ^ 0x5707a6e, h);
            i64 size = v[0].small_val(), off = v[1].small_val();
            if (off >= 256) return Word256{};
            Word256 r = pan::shr(Word256::of(u64(off)), s);
            return pan::band(r, A::mask_word(size, 0));
        }
        Word256 w = A::RandomEnv::word_for(seed, v.hash());
        if (info(v.op()).sort == Sort::Bool) return Word256::of(w.limb[0] & 1);
        return w;
    }
};

// random raw expressions (made with mk: no normal form), with the asm's
// differential tests' distributions (tests/test_algebra.py, test_arith.py)
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
        switch (below(10)) {
            case 0: case 1: case 2: case 3:
                return mk_int(small_list[below(std::size(small_list))]);
            case 4: case 5:
                return mk_int(i64(below(601)) - 300);
            case 6: {  // 2^k (- 1), and their negations
                u32 k = u32(below(257));
                EvmInt v = EvmInt::pow2(k) - EvmInt(i64(below(2)));
                if (chance(1, 4)) v = -v;
                return v.value();
            }
            case 7: {  // mask constants and their complements
                u32 s = u32(below(257)), o = u32(below(257));
                EvmInt m = EvmInt::mask(s, o).mod_2exp(256);
                if (chance(1, 3)) m = (~m).mod_2exp(256);
                return m.value();
            }
            case 8: {  // big values past 2^62 (the magnitude guards)
                static const char* bigs[] = {"4000000000000000", "3fffffffffffffff", "8000000000000005",
                                             "10000000000000000", "10000000000000000000000007",
                                             "80000000000000000000000000000000000000000000000000000000000000ff",
                                             "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
                                             "10000000000000000000000000000000000000000000000000000000000000000",
                                             "8000000000000000000000000000000000000000000000000000000000000000"};
                Value b = big(bigs[below(std::size(bigs))]);
                return chance(1, 3) ? EvmInt(-EvmInt(b)).value() : b;
            }
            default: {
                Word256 w{{next(), next(), next(), next()}};
                return w.to_value();
            }
        }
    }

    Value ratom() {
        switch (below(17)) {
            case 0: return mk(Op::CALLDATALOAD, mk_int(4));
            case 1: return mk(Op::CALLDATALOAD, mk_int(36));
            case 2: return mk(Op::CALLDATALOAD, mk(Op::ADD, mk_int(4), mk(Op::CALLDATALOAD, mk_int(4))));
            case 3: return Value::leaf(Op::CALLVALUE);
            case 4: return Value::leaf(Op::CALLDATASIZE);
            case 5: return Value::leaf(Op::CALLER);
            case 6: return Value::name(NameKind::TMP, 1);
            case 7: return Value::name(NameKind::TMP, 2);
            case 8: return Value::name(NameKind::PARAM, 0);
            case 9: return mk(Op::STORAGE, mk_int(256), mk_int(0), mk_int(5));
            case 10: return mk(Op::STORAGE, mk_int(160), mk_int(0), mk_int(3));
            case 11: return mk(Op::STORAGE, mk_int(8), mk_int(160), mk_int(3));
            case 12: return mk(Op::MEM, mk(Op::RANGE, mk_int(64), mk_int(32)));
            case 13: return mk(Op::SHA3, mk_int(1));
            case 14: return Value::leaf(Op::CALL_SUCCESS, 1);
            case 15: return mk(Op::RETURNDATA_BYTES, mk_int(1), mk_int(0), mk_int(32));
            default: return Value::name(NameKind::LOOP, 7);
        }
    }

    Value leafish() { return chance(1, 2) ? rint() : ratom(); }

    // a small shift / index / byte count, mostly
    Value rshift(int depth) {
        if (chance(1, 8)) return rexp(depth + 1);
        if (chance(1, 10)) return rint();
        return mk_int(i64(below(300)));
    }

    Value rfield(int depth, int which) {
        static const i64 sizes[] = {1, 8, 16, 32, 64, 96, 160, 224, 248, 251, 253, 255, 256, 0, 300, -5};
        static const i64 offs[] = {0, 0, 0, 3, 5, 8, 32, 96, 160, 255, 256, -3};
        static const i64 shls[] = {0, 0, 0, 1, 3, 5, 32, 96, -3, -5, -32, -96, -160, -224, 255, -255, 256};
        if (chance(1, 12)) return rexp(depth + 1);
        if (chance(1, 20)) return rint();
        if (chance(1, 30)) return Value(true);
        switch (which) {
            case 0: return mk_int(sizes[below(std::size(sizes))]);
            case 1: return mk_int(offs[below(std::size(offs))]);
            default: return mk_int(shls[below(std::size(shls))]);
        }
    }

    Value rexp(int depth = 0) {
        if (depth > max_depth || chance(3, 10)) return leafish();
        auto sub = [&] { return rexp(depth + 1); };
        switch (below(34)) {
            case 0: case 1: case 2: {
                u32 n = 2 + u32(below(3));
                std::vector<Value> a;
                for (u32 i = 0; i < n; ++i) a.push_back(sub());
                return mk(Op::ADD, a);
            }
            case 3: case 4: {
                if (chance(1, 2)) return mk(Op::MUL, rint(), sub());
                return mk(Op::MUL, sub(), sub());
            }
            case 5: return mk(Op::SUB, sub(), sub());
            case 6: return mk(Op::DIV, sub(), chance(1, 2) ? rint() : sub());
            case 7: return mk(Op::SDIV, sub(), chance(1, 2) ? rint() : sub());
            case 8: return mk(Op::MOD, sub(), chance(1, 2) ? rint() : sub());
            case 9: return mk(Op::SMOD, sub(), chance(1, 2) ? rint() : sub());
            case 10: return mk(chance(1, 2) ? Op::ADDMOD : Op::MULMOD, sub(), sub(), sub());
            case 11: return mk(Op::EXP, chance(1, 2) ? rint() : sub(), chance(1, 2) ? rshift(depth) : sub());
            case 12: {
                static const i64 bs[] = {0, 1, 3, 15, 19, 30, 31, 32, -1};
                Value b = chance(4, 5) ? mk_int(bs[below(std::size(bs))]) : (chance(1, 2) ? rint() : sub());
                return mk(Op::SIGNEXTEND, b, sub());
            }
            case 13: case 14: {
                static const Op cmps[] = {Op::LT, Op::GT, Op::SLT, Op::SGT, Op::EQ, Op::LE, Op::GE, Op::SLE, Op::SGE};
                Value a = sub(), b = chance(1, 5) ? a : sub();
                return mk(cmps[below(9)], a, b);
            }
            case 15: return mk(Op::ISZERO, sub());
            case 16: return mk(Op::BOOL, sub());
            case 17: case 18: {
                Value m = chance(1, 2) ? rint() : sub();
                if (chance(1, 3)) return mk(Op::AND, sub(), m, sub());
                return chance(1, 2) ? mk(Op::AND, sub(), m) : mk(Op::AND, m, sub());
            }
            case 19: {
                if (chance(1, 3)) return mk(Op::OR, sub(), sub(), sub());
                return mk(Op::OR, sub(), sub());
            }
            case 20: return mk(Op::XOR, sub(), sub());
            case 21: return mk(Op::NOT, sub());
            case 22: return mk(Op::BYTE, chance(4, 5) ? mk_int(i64(below(34))) : sub(), sub());
            case 23: case 24: return mk(Op::SHL, rshift(depth), sub());
            case 25: case 26: return mk(Op::SHR, rshift(depth), sub());
            case 27: return mk(Op::SAR, rshift(depth), sub());
            case 28: return mk(Op::CLZ, sub());
            case 29: case 30: return mk(Op::MASK_SHL, rfield(depth, 0), rfield(depth, 1), rfield(depth, 2), sub());
            case 31: return mk(chance(1, 2) ? Op::MAX : Op::MIN, sub(), sub());
            case 32: return mk(chance(1, 2) ? Op::LAND : Op::LOR, sub(), sub());
            default: {
                // a sum of fields of one value (the try_add cases)
                Value x = chance(1, 2) ? ratom() : sub();
                static const i64 fs[][3] = {{8, 0, 0}, {248, 8, 0}, {5, 0, 0}, {251, 5, 0}, {8, 8, 0}, {16, 0, 0},
                                            {8, 0, 5}, {251, 0, 5}, {8, 8, -8}, {8, 16, -8}, {160, 0, 0}, {96, 160, 0}};
                std::vector<Value> a;
                u32 n = 2 + u32(below(3));
                for (u32 i = 0; i < n; ++i) {
                    const i64* f = fs[below(std::size(fs))];
                    Value t = chance(1, 4) ? x : mk(Op::MASK_SHL, mk_int(f[0]), mk_int(f[1]), mk_int(f[2]), x);
                    if (chance(1, 3)) t = mk(Op::MUL, mk_int(chance(1, 2) ? -1 : 2), t);
                    a.push_back(t);
                }
                return mk(Op::ADD, a);
            }
        }
    }
};

Word256 ev(Value v, u64 seed) {
    TestEnv env(seed);
    A::Evaluator e(env);
    return e(v);
}

std::string hexw(const Word256& w) {
    static const char* d = "0123456789abcdef";
    std::string s = "0x";
    for (int i = 3; i >= 0; --i)
        for (int j = 60; j >= 0; j -= 4) s += d[(w.limb[i] >> j) & 15];
    return s;
}

constexpr u64 kSeeds[] = {1, 2, 3, 0x9e37, 77, 1234567, 42, 0xdead};

}  // namespace

// ------------------------------------------------------------------ properties

TEST_CASE("algebra: normalize keeps the value of random expressions (edge words included)") {
    Fixture f;
    Gen g(20261019);
    int bad = 0, cases = 0;
    for (int i = 0; i < 6000 && bad < 8; ++i) {
        Value e = g.rexp();
        Value n = A::normalize(e);
        for (u64 s : kSeeds) {
            ++cases;
            Word256 a = ev(e, s), b = ev(n, s);
            if (!(a == b)) {
                ++bad;
                MESSAGE("seed ", s, "\n  raw:  ", dump(e), "\n  norm: ", dump(n), "\n  raw = ", hexw(a),
                        "\n  norm = ", hexw(b));
                break;
            }
        }
    }
    CHECK(bad == 0);
    CHECK(cases > 40000);
}

TEST_CASE("algebra: every constructor equals the EVM operation on random operands") {
    Fixture f;
    Gen g(77);
    struct Spec {
        Op op;
        u32 n;
    };
    const Spec specs[] = {{Op::ADD, 2}, {Op::ADD, 3}, {Op::MUL, 2}, {Op::MUL, 3}, {Op::SUB, 2}, {Op::DIV, 2},
                          {Op::SDIV, 2}, {Op::MOD, 2}, {Op::SMOD, 2}, {Op::ADDMOD, 3}, {Op::MULMOD, 3},
                          {Op::EXP, 2}, {Op::SIGNEXTEND, 2}, {Op::LT, 2}, {Op::GT, 2}, {Op::SLT, 2},
                          {Op::SGT, 2}, {Op::EQ, 2}, {Op::ISZERO, 1}, {Op::AND, 2}, {Op::AND, 3}, {Op::OR, 2},
                          {Op::OR, 3}, {Op::XOR, 2}, {Op::NOT, 1}, {Op::BYTE, 2}, {Op::SHL, 2}, {Op::SHR, 2},
                          {Op::SAR, 2}, {Op::CLZ, 1}, {Op::MASK_SHL, 4}, {Op::BOOL, 1}, {Op::LE, 2},
                          {Op::GE, 2}, {Op::SLE, 2}, {Op::SGE, 2}, {Op::MAX, 2}, {Op::MIN, 3},
                          {Op::LAND, 2}, {Op::LOR, 2}};
    int bad = 0;
    for (int i = 0; i < 1500 && bad < 8; ++i) {
        for (const Spec& sp : specs) {
            std::vector<Value> args;
            for (u32 k = 0; k < sp.n; ++k) {
                // normal operands (the constructors' precondition), small ints for the shifts' places
                Value a = g.chance(1, 3) ? g.rint() : A::normalize(g.rexp(1));
                if (k == 0 && (sp.op == Op::SHL || sp.op == Op::SHR || sp.op == Op::SAR || sp.op == Op::BYTE ||
                               sp.op == Op::SIGNEXTEND) && g.chance(2, 3))
                    a = mk_int(i64(g.below(300)));
                if (sp.op == Op::MASK_SHL && k < 3 && g.chance(4, 5)) a = g.rfield(2, int(k));
                args.push_back(a);
            }
            Value r = A::apply(sp.op, args);
            for (u64 s : {kSeeds[i % 8], kSeeds[(i + 3) % 8]}) {
                std::vector<Word256> w;
                for (Value a : args) w.push_back(ev(a, s));
                Word256 want = *A::eval_op(sp.op, w);
                Word256 got = ev(r, s);
                if (!(want == got)) {
                    ++bad;
                    std::string as;
                    for (Value a : args) as += "\n    " + dump(a);
                    MESSAGE(op_name(sp.op), " seed ", s, as, "\n  -> ", dump(r), "\n  want ", hexw(want), "\n  got  ",
                            hexw(got));
                    break;
                }
            }
        }
    }
    CHECK(bad == 0);
}

TEST_CASE("algebra: normal forms are fixpoints, sums and products canonical") {
    Fixture f;
    Gen g(5);
    int not_fix = 0, not_comm = 0, not_assoc = 0;
    for (int i = 0; i < 3000; ++i) {
        Value n = A::normalize(g.rexp());
        Value n2 = A::normalize(n);
        if (!(n2 == n) && not_fix++ < 5) MESSAGE("not a fixpoint:\n  ", dump(n), "\n  ", dump(n2));
        Value a = A::normalize(g.rexp(1)), b = A::normalize(g.rexp(1)), c = A::normalize(g.rexp(2));
        if (!(A::add(a, b) == A::add(b, a)) || !(A::mul(a, b) == A::mul(b, a))) {
            if (not_comm++ < 5) MESSAGE("not commutative:\n  ", dump(a), "\n  ", dump(b));
        }
        if (!(A::add(A::add(a, b), c) == A::add(a, A::add(b, c)))) {
            if (not_assoc++ < 5)
                MESSAGE("add not associative:\n  ", dump(A::add(A::add(a, b), c)), "\n  ", dump(A::add(a, A::add(b, c))));
        }
    }
    CHECK(not_fix == 0);
    CHECK(not_comm == 0);
    CHECK(not_assoc == 0);
}

TEST_CASE("algebra: linear forms are congruent to their expressions") {
    Fixture f;
    Gen g(99);
    int bad = 0;
    for (int i = 0; i < 3000 && bad < 5; ++i) {
        Value e = g.chance(1, 2) ? g.rexp() : A::normalize(g.rexp());
        A::Linear l = A::linear(e);
        for (const A::LinTerm& t : l.terms) {
            CHECK(!t.term.is_int());
            CHECK(!t.term.is(Op::ADD));
            CHECK(!(t.coeff.is_small() && t.coeff.small_val() == 0));
        }
        for (u64 s : {kSeeds[i % 8], kSeeds[(i + 5) % 8]}) {
            Word256 sum = Word256::from_value(l.constant);
            for (const A::LinTerm& t : l.terms) sum = pan::add(sum, pan::mul(Word256::from_value(t.coeff), ev(t.term, s)));
            Word256 want = ev(e, s);
            if (!(sum == want) || !(ev(A::from_linear(l), s) == want)) {
                ++bad;
                MESSAGE("linear of ", dump(e), " seed ", s);
                break;
            }
        }
    }
    CHECK(bad == 0);
}

TEST_CASE("algebra: max_bits, low_zero_bits, is_bool are sound") {
    Fixture f;
    Gen g(31337);
    int bad = 0;
    for (int i = 0; i < 4000 && bad < 6; ++i) {
        Value e = g.chance(1, 2) ? g.rexp() : A::normalize(g.rexp());
        u32 mb = A::max_bits(e), lz = A::low_zero_bits(e);
        bool b = A::is_bool(e);
        for (u64 s : {kSeeds[i % 8], kSeeds[(i + 1) % 8], kSeeds[(i + 2) % 8]}) {
            Word256 w = ev(e, s);
            bool ok = true;
            if (mb < 256 && !pan::shr(Word256::of(mb), w).is_zero()) ok = false;
            if (lz > 0 && !pan::band(w, A::mask_word(i64(lz), 0)).is_zero()) ok = false;
            if (b && !(w == Word256::of(0) || w == Word256::of(1))) ok = false;
            if (!ok) {
                ++bad;
                MESSAGE(dump(e), " = ", hexw(w), " max_bits ", mb, " low_zero_bits ", lz, " is_bool ", b);
                break;
            }
        }
    }
    CHECK(bad == 0);
}

TEST_CASE("algebra: iszero, to_bool and the comparisons keep their truth values") {
    Fixture f;
    Gen g(4242);
    int bad = 0;
    for (int i = 0; i < 3000 && bad < 6; ++i) {
        Value a = A::normalize(g.rexp(1)), b = g.chance(1, 4) ? a : A::normalize(g.rexp(1));
        Value z = A::iszero(a), t = A::to_bool(a);
        static const Op cmps[] = {Op::LT, Op::GT, Op::SLT, Op::SGT, Op::EQ, Op::LE, Op::GE, Op::SLE, Op::SGE};
        Op op = cmps[i % 9];
        Value c = A::cmp(op, a, b);
        Value nc = A::iszero(c);
        for (u64 s : {kSeeds[i % 8], kSeeds[(i + 1) % 8]}) {
            Word256 wa = ev(a, s), wb = ev(b, s);
            const Word256 args[] = {wa, wb};
            Word256 wc = *A::eval_op(op, args);
            bool ok = ev(z, s) == pan::iszero(wa) && ev(t, s) == Word256::of(wa.is_zero() ? 0 : 1) && ev(c, s) == wc &&
                      ev(nc, s) == pan::iszero(wc);
            if (!ok) {
                ++bad;
                MESSAGE(op_name(op), "\n  a ", dump(a), "\n  b ", dump(b), "\n  iszero ", dump(z), "\n  cmp ", dump(c),
                        "\n  not cmp ", dump(nc));
                break;
            }
        }
    }
    CHECK(bad == 0);
}

// ------------------------------------------------------------------ shapes

TEST_CASE("algebra: sums") {
    Fixture f;
    Value x = V("caller"), y = V("(calldataload 4)");
    CHECK(A::add(x, mk_int(1)) == V("(add 1 caller)"));
    CHECK(A::add(mk_int(1), x) == V("(add 1 caller)"));
    CHECK(A::sub(x, mk_int(1)) == V("(add -1 caller)"));
    CHECK(A::add(x, V("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")) == V("(add -1 caller)"));
    CHECK(A::sub(x, x) == mk_int(0));
    CHECK(A::add(x, A::neg(x)) == mk_int(0));
    CHECK(A::sub(mk_int(3), mk_int(5)) == V("0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe"));
    CHECK(A::add(x, x) == V("(mul 2 caller)"));
    CHECK(A::add(A::add(x, mk_int(5)), A::add(y, mk_int(-5))) == A::add(x, y));
    CHECK(A::add(x, y) == A::add(y, x));
    CHECK(A::mul(mk_int(32), x) == V("(mul 32 caller)"));
    CHECK(A::shl(mk_int(5), x) == V("(mul 32 caller)"));
    CHECK(A::mul(mk_int(-1), A::mul(mk_int(-1), x)) == x);
    CHECK(A::mul(A::add(x, mk_int(1)), mk_int(3)) == V("(add 3 (mul 3 caller))"));
    CHECK(A::mul(x, y) == A::mul(y, x));
    CHECK(A::mul(x, mk_int(0)) == mk_int(0));
    CHECK(A::bits(A::add(x, mk_int(4))) == V("(add 32 (mul 8 caller))"));
    CHECK(A::add(std::span<const Value>{}) == mk_int(0));
}

TEST_CASE("algebra: masks") {
    Fixture f;
    Value x = V("caller"), cd0 = V("(calldataload 0)");
    // address(x), the selector, uint8, bytes4
    CHECK(A::band(x, pow2m1(160)) == V("(mask_shl 160 0 0 caller)"));
    CHECK(A::band(pow2m1(160), x) == V("(mask_shl 160 0 0 caller)"));
    CHECK(A::shr(mk_int(224), cd0) == V("(mask_shl 32 224 -224 (calldataload 0))"));
    CHECK(A::div(cd0, pow2(224)) == V("(mask_shl 32 224 -224 (calldataload 0))"));
    CHECK(A::band(cd0, V("0xffffffff00000000000000000000000000000000000000000000000000000000")) ==
          V("(mask_shl 32 224 0 (calldataload 0))"));
    CHECK(A::byte(mk_int(0), x) == V("(mask_shl 8 248 -248 caller)"));
    CHECK(A::byte(mk_int(31), x) == V("(mask_shl 8 0 0 caller)"));
    CHECK(A::byte(mk_int(32), x) == mk_int(0));
    CHECK(A::shr(mk_int(256), x) == mk_int(0));
    CHECK(A::shl(mk_int(256), x) == mk_int(0));
    // a mask of a mask is one mask
    CHECK(A::mask(8, 0, 0, A::mask(16, 0, 0, x)) == V("(mask_shl 8 0 0 caller)"));
    CHECK(A::mask(160, 0, 0, A::mask(160, 0, 0, x)) == A::mask(160, 0, 0, x));
    CHECK(A::shr(mk_int(8), A::band(x, mk_int(0xff00))) == V("(mask_shl 8 8 -8 caller)"));
    CHECK(A::shl(mk_int(8), A::band(x, mk_int(0xff))) == V("(mask_shl 8 0 8 caller)"));
    CHECK(A::mask(256, 0, 0, x) == x);
    CHECK(A::mask(0, 0, 0, x) == mk_int(0));
    CHECK(A::mask(8, 256, 0, x) == mk_int(0));
    // floor32, ceil32
    CHECK(A::band(x, V("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe0")) ==
          V("(mask_shl 251 5 0 caller)"));
    CHECK(A::sub(x, A::mask(5, 0, 0, x)) == V("(mask_shl 251 5 0 caller)"));
    CHECK(A::mask(251, 5, 0, A::add(x, mk_int(31))) == V("(mask_shl 251 5 0 (add 31 caller))"));
    // adjacent fields of one value are one field
    CHECK(A::add(A::mask(8, 0, 0, x), A::mask(248, 8, 0, x)) == x);
    CHECK(A::bor(A::mask(8, 0, 0, x), A::mask(8, 8, 0, x)) == V("(mask_shl 16 0 0 caller)"));
    // the complement of a mask: the bits around it
    CHECK(A::band(x, EvmInt(~EvmInt::mask(8, 8)).mod_2exp(256).value()) ==
          A::bor(A::mask(240, 16, 0, x), A::mask(8, 0, 0, x)));
    CHECK(A::neg_mask(mk_int(8), mk_int(8), x) == A::bor(A::mask(240, 16, 0, x), A::mask(8, 0, 0, x)));
    CHECK(A::neg_mask(mk_int(160), mk_int(0), V("(storage 256 0 0)")) == V("(mask_shl 96 160 0 (storage 256 0 0))"));
    // a 0/1 value under a mask that keeps bit 0
    Value lt = V("(lt caller 5)");
    CHECK(A::mask(8, 0, 0, lt) == lt);
    CHECK(A::band(lt, mk_int(1)) == lt);
    // the low bits of a sum don't see the terms above them
    CHECK(A::mask(8, 0, 0, A::add(x, mk_int(256))) == V("(mask_shl 8 0 0 caller)"));
    CHECK(A::mask(160, 0, 0, A::add(x, A::mul(pow2(160), V("tmp1")))) == V("(mask_shl 160 0 0 caller)"));
    // a field of a storage read is a narrower read
    CHECK(A::band(V("(storage 256 0 5)"), mk_int(0xff)) == V("(storage 8 0 5)"));
    CHECK(A::shr(mk_int(160), A::band(V("(storage 256 0 5)"), V("0xff0000000000000000000000000000000000000000"))) ==
          V("(storage 8 160 5)"));
    // a shift by a byte: a mask moved by it
    Value sh = A::shl(V("(mask_shl 8 0 0 tmp1)"), x);
    CHECK(sh == V("(mask_shl 256 0 (mask_shl 8 0 0 tmp1) caller)"));
    // a shift by anything else stays a shift
    CHECK(A::shl(V("tmp1"), x) == V("(shl tmp1 caller)"));
    CHECK(A::shr(V("tmp1"), x) == V("(shr tmp1 caller)"));
}

TEST_CASE("algebra: truth values") {
    Fixture f;
    Value x = V("caller");
    CHECK(A::iszero(mk_int(0)) == mk_int(1));
    CHECK(A::iszero(mk_int(7)) == mk_int(0));
    CHECK(A::iszero(V("(lt caller 5)")) == V("(ge caller 5)"));
    CHECK(A::iszero(V("(sgt caller 5)")) == V("(sle caller 5)"));
    CHECK(A::iszero(A::iszero(x)) == V("(bool caller)"));
    CHECK(A::iszero(A::iszero(V("(eq caller 5)"))) == V("(eq caller 5)"));
    CHECK(A::iszero(A::iszero(A::iszero(x))) == V("(iszero caller)"));
    CHECK(A::to_bool(V("(lt caller 5)")) == V("(lt caller 5)"));
    CHECK(A::iszero(V("(bool caller)")) == V("(iszero caller)"));
    CHECK(A::iszero(V("(or caller tmp1)")) == V("(and (iszero caller) (iszero tmp1))"));
    CHECK(A::iszero(V("(and (lt caller 5) (gt tmp1 3))")) == V("(or (ge caller 5) (le tmp1 3))"));
    CHECK(A::cmp(Op::LT, x, x) == mk_int(0));
    CHECK(A::cmp(Op::LE, x, x) == mk_int(1));
    CHECK(A::cmp(Op::GT, mk_int(0), x) == mk_int(0));
    CHECK(A::cmp(Op::GE, x, mk_int(0)) == mk_int(1));
    CHECK(A::cmp(Op::EQ, A::add(x, mk_int(1)), x) == mk_int(0));
    CHECK(A::cmp(Op::EQ, A::add(x, mk_int(1)), A::add(mk_int(1), x)) == mk_int(1));
    // volatile: two reads of storage need not be equal (python eval_symbolic)
    Value s = V("(storage 256 0 5)");
    CHECK(A::cmp(Op::LT, s, s) == V("(lt (storage 256 0 5) (storage 256 0 5))"));
    CHECK(A::is_bool(V("(call_success 1)")));
    CHECK(A::is_bool(V("(mask_shl 1 0 0 caller)")));
    CHECK(!A::is_bool(V("(mask_shl 1 1 0 caller)")));
    CHECK(A::exp(mk_int(0), x) == V("(iszero caller)"));
    // truth: the same zero-ness, not the same value
    CHECK(A::truth(V("(bool caller)")) == x);
    CHECK(A::truth(V("(iszero (iszero caller))")) == x);
    CHECK(A::truth(V("(iszero (bool caller))")) == V("(iszero caller)"));
    CHECK(A::truth(V("(iszero caller)")) == V("(iszero caller)"));
}

TEST_CASE("algebra: truth keeps zero-ness") {
    Fixture f;
    Gen g(808);
    int bad = 0;
    for (int i = 0; i < 2000 && bad < 5; ++i) {
        Value e = A::normalize(g.rexp(1));
        Value w = g.chance(1, 2) ? A::to_bool(e) : A::iszero(A::iszero(e));
        if (g.chance(1, 3)) w = mk(Op::ISZERO, mk(Op::BOOL, w));
        Value t = A::truth(w);
        for (u64 s : {kSeeds[i % 8], kSeeds[(i + 1) % 8]}) {
            if (ev(w, s).is_zero() != ev(t, s).is_zero()) {
                ++bad;
                MESSAGE(dump(w), " -> ", dump(t));
                break;
            }
        }
    }
    CHECK(bad == 0);
    CHECK(A::may_be_wide(V("(mem (range 0 64))")));
    CHECK(A::may_be_wide(V("(mem (range 0 tmp1))")));
    CHECK(!A::may_be_wide(V("(mem (range 0 32))")));
    CHECK(A::may_be_wide(V("(data 1 2)")));
    CHECK(!A::may_be_wide(V("caller")));
    // a mask of a wide value keeps its fields: bits past 256 exist
    Value m = A::mask(256, 256, -256, V("(mem (range 0 64))"));
    CHECK(m == V("(mask_shl 256 256 -256 (mem (range 0 64)))"));
}

TEST_CASE("algebra: signextend, sar, apply of the other ops") {
    Fixture f;
    Value x = V("caller");
    CHECK(A::signextend(mk_int(31), x) == x);
    CHECK(A::signextend(mk_int(0), A::mask(7, 0, 0, x)) == A::mask(7, 0, 0, x));
    CHECK(A::signextend(mk_int(0), A::mask(16, 0, 0, x)) == V("(signextend 0 caller)"));
    CHECK(A::signextend(mk_int(0), A::signextend(mk_int(1), x)) == V("(signextend 0 caller)"));
    CHECK(A::signextend(mk_int(1), A::signextend(mk_int(0), x)) == V("(signextend 0 caller)"));
    CHECK(A::sar(mk_int(8), A::mask(160, 0, 0, x)) == A::shr(mk_int(8), A::mask(160, 0, 0, x)));
    CHECK(A::apply(Op::CALLDATALOAD, {mk_int(4)}) == V("(calldataload 4)"));
    CHECK(A::apply(Op::SUB, {x, mk_int(1)}) == V("(add -1 caller)"));
    CHECK_THROWS_AS(A::apply(Op::ISZERO, {x, x}), InternalError);
    CHECK(A::normalize(V("(add (add 1 caller) (sub 2 caller))")) == mk_int(3));
    CHECK(A::normalize(V("(and caller 0xffffffffffffffffffffffffffffffffffffffff)")) == V("(mask_shl 160 0 0 caller)"));
}

TEST_CASE("algebra: what solc's code makes") {
    Fixture f;
    Value len = V("(calldataload (add 4 (calldataload 36)))"), p = V("tmp3");
    // ceil32 three ways: and(add(len, 31), not(31)); mul(div(add(len, 31), 32), 32); shl(5, shr(5, ..))
    Value c1 = A::band(A::add(len, mk_int(31)), A::bnot(mk_int(31)));
    Value c2 = A::mul(A::div(A::add(len, mk_int(31)), mk_int(32)), mk_int(32));
    Value c3 = A::shl(mk_int(5), A::shr(mk_int(5), A::add(len, mk_int(31))));
    CHECK(c1 == V("(mask_shl 251 5 0 (add 31 (calldataload (add 4 (calldataload 36)))))"));
    CHECK(c2 == c1);
    CHECK(c3 == c1);
    // the free memory pointer moved by 0x20 twice
    CHECK(A::add(A::add(p, mk_int(32)), mk_int(32)) == V("(add 64 tmp3)"));
    // a packed field: (sload(0) / 2^160) & 0xff, and its write mask
    Value s0 = V("(storage 256 0 0)");
    CHECK(A::band(A::div(s0, pow2(160)), mk_int(0xff)) == V("(storage 8 160 0)"));
    CHECK(A::band(A::shr(mk_int(160), s0), mk_int(0xff)) == V("(storage 8 160 0)"));
    Value keep = A::band(s0, A::bnot(A::shl(mk_int(160), mk_int(0xff))));
    CHECK(keep == A::bor(V("(mask_shl 88 168 0 (storage 256 0 0))"), V("(storage 160 0 0)")));
    // the selector of old and new solc
    Value cd0 = V("(calldataload 0)");
    CHECK(A::band(A::div(cd0, pow2(224)), mk_int(0xffffffff)) == A::shr(mk_int(224), cd0));
    // an address argument, an overflow check that must stay a check
    CHECK(A::band(V("(calldataload 4)"), pow2m1(160)) == V("(mask_shl 160 0 0 (calldataload 4))"));
    Value a = V("(calldataload 4)"), b = V("(calldataload 36)");
    CHECK(A::cmp(Op::LT, A::add(a, b), a) == V("(lt (add (calldataload 4) (calldataload 36)) (calldataload 4))"));
    CHECK(A::cmp(Op::GT, a, A::add(a, mk_int(1))) == V("(gt (calldataload 4) (add 1 (calldataload 4)))"));
    // x - 1 as add(x, not(0))
    CHECK(A::add(a, A::bnot(mk_int(0))) == V("(add -1 (calldataload 4))"));
    // a byte of a word read from memory
    CHECK(A::byte(mk_int(0), V("(mem (range 64 32))")) == V("(mask_shl 8 248 -248 (mem (range 64 32)))"));
    // bytes4(x): the high 4 bytes in place
    CHECK(A::band(a, V("0xffffffff00000000000000000000000000000000000000000000000000000000")) ==
          V("(mask_shl 32 224 0 (calldataload 4))"));
    // uint8(x) >> 3 << 3 (python's to_bytes of a bit count)
    A::ToBytes tb = A::to_bytes(A::bits(V("tmp1")));
    CHECK(tb.bytes == V("tmp1"));
    CHECK(tb.rem == 0u);
    A::ToBytes t2 = A::to_bytes(mk_int(13));
    CHECK(t2.bytes == mk_int(2));
    CHECK(t2.rem == 5u);
    A::ToBytes t3 = A::to_bytes(V("tmp1"));
    CHECK(!t3.rem);
    CHECK(t3.bytes == V("(mask_shl 253 3 -3 tmp1)"));
}

TEST_CASE("algebra: masks.hpp views and constants") {
    Fixture f;
    auto m = A::as_mask(V("(mask_shl 160 0 0 caller)"));
    REQUIRE(m);
    CHECK(m->concrete());
    CHECK(m->isize() == 160);
    CHECK(m->x == V("caller"));
    CHECK(!A::as_mask(V("caller")));
    A::MaskShl v = A::mask_view(V("(mul 32 caller)"));
    CHECK(v.isize() == 251);
    CHECK(v.ishl() == 5);
    auto tm = A::to_mask(pow2m1(160));
    REQUIRE(tm);
    CHECK(tm->size == mk_int(160));
    CHECK(tm->off == mk_int(0));
    CHECK(!A::to_mask(mk_int(0x101)));
    auto nm = A::to_neg_mask(V("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00ff"));
    REQUIRE(nm);
    CHECK(nm->size == mk_int(8));
    CHECK(nm->off == mk_int(8));
    CHECK(A::to_exp2(mk_int(32)) == 5u);
    CHECK(A::to_exp2(pow2(255)) == 255u);
    CHECK(!A::to_exp2(mk_int(33)));
    CHECK(!A::to_exp2(mk_int(-32)));
    A::BitSpan b = A::find_mask(Word256::from_value(mk_int(0xFABBA10000)));
    CHECK(b.size == 24);
    CHECK(b.off == 16);
    // 2^(8 * e) - 1 with e a byte count: a mask of 8 * e bits
    auto sm = A::to_mask(V("(add -1 (exp 256 (mask_shl 5 0 0 tmp1)))"));
    REQUIRE(sm);
    CHECK(sm->size == A::mul(mk_int(8), V("(mask_shl 5 0 0 tmp1)")));
    CHECK(sm->size == V("(mask_shl 5 0 3 tmp1)"));
}

TEST_CASE("algebra: linear forms") {
    Fixture f;
    Value x = V("caller"), y = V("tmp1");
    A::Linear l = A::linear(A::add({mk_int(5), A::mul(mk_int(3), x), A::neg(y)}));
    CHECK(l.constant == mk_int(5));
    REQUIRE(l.terms.size() == 2);
    CHECK(l.coeff_of(x) == mk_int(3));
    CHECK(l.coeff_of(y) == mk_int(-1));
    CHECK(A::linear(mk_int(-7)).constant == mk_int(-7));
    CHECK(A::linear(V("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")).constant == mk_int(-1));
    CHECK(A::const_diff(A::add(x, mk_int(7)), A::add(x, mk_int(2))) == mk_int(5));
    CHECK(!A::const_diff(A::add(x, mk_int(7)), y));
    CHECK(A::linear_diff(A::add(x, mk_int(1)), x).is_const());
    // the wrap is explicit: x + 1 - x is the constant 1 mod 2^256, nothing more
    CHECK(A::linear_diff(A::add(x, mk_int(1)), x).constant == mk_int(1));
}

TEST_CASE("algebra: magnitude guards") {
    Fixture f;
    Value x = V("caller");
    // fields are words read as signed numbers: 2^200 is past any width
    Value huge = pow2(200);
    CHECK(A::mask(huge, mk_int(0), mk_int(0), x) == x);         // size past 256: all of x
    CHECK(A::mask(mk_int(8), huge, mk_int(0), x) == mk_int(0));  // offset past the word
    CHECK(A::shl(huge, x) == mk_int(0));
    CHECK(A::shr(huge, x) == mk_int(0));
    CHECK(A::exp(mk_int(3), huge) == A::apply(Op::EXP, {mk_int(3), huge}));
    CHECK(A::mask(V("-1"), mk_int(0), mk_int(0), x) == mk_int(0));
    CHECK(A::mask(mk_int(8), mk_int(0), V("-4096"), x) == mk_int(0));
    CHECK_NOTHROW(A::normalize(V("(mask_shl 5000 -5000 300 caller)")));
}

// The same properties on many more expressions, deeper ones, other seeds:
// run with  -tc='algebra: fuzz*' --no-skip
TEST_CASE("algebra: fuzz normalize and the constructors against evaluation" * doctest::skip()) {
    Fixture f;
    int bad = 0, cases = 0, not_fix = 0;
    for (u64 round = 1; round <= 40 && bad < 10; ++round) {
        Gen g(round * 0x9e3779b97f4a7c15ull, round % 2 ? 3 : 5);
        for (int i = 0; i < 5000 && bad < 10; ++i) {
            Value e = g.rexp();
            if (g.chance(1, 4)) e = mk(Op::ADD, e, g.rexp(), g.rexp());
            Value n = A::normalize(e);
            if (!(A::normalize(n) == n) && not_fix++ < 5) MESSAGE("not a fixpoint: ", dump(n), "\n  -> ", dump(A::normalize(n)));
            for (u64 s : {round, round * 7 + 1, u64(i), round ^ 0xabcdef}) {
                ++cases;
                Word256 a = ev(e, s), b = ev(n, s);
                if (!(a == b)) {
                    ++bad;
                    MESSAGE("seed ", s, "\n  raw:  ", dump(e), "\n  norm: ", dump(n), "\n  raw = ", hexw(a), "\n  norm = ", hexw(b));
                    break;
                }
            }
        }
        // a fresh context now and then: the memos start empty again
        f.ctx->clear_caches();
    }
    MESSAGE(cases, " evaluations");
    CHECK(bad == 0);
    CHECK(not_fix == 0);
}
