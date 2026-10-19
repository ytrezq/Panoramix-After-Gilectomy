// Lot 2 (algebra A): concrete evaluation - eval_op against a reference made
// of python's integer operations (py-evm's arithmetic, panoramix's
// apply_mask), on random and edge words; eval_const, the Evaluator, the
// environments.
#include <doctest/doctest.h>

#include <vector>

#include "algebra/eval.hpp"
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

// ---- the reference: python ints ----

const EvmInt& M() { return two_256(); }
EvmInt I(const Word256& w) { return w.to_int(); }
Word256 W(const EvmInt& x) { return Word256::from_int(x); }  // mod 2^256
EvmInt sgn(const Word256& w) { return I(w).to_signed(); }
EvmInt absi(const EvmInt& x) { return x.sign() < 0 ? -x : x; }

EvmInt clamp4096(const EvmInt& x) {
    if (x > EvmInt(4096)) return EvmInt(4096);
    if (x < EvmInt(-4096)) return EvmInt(-4096);
    return x;
}

// panoramix algebra.mask_to_int + apply_mask, fields read as signed words
Word256 ref_mask_shl(const Word256& size_w, const Word256& off_w, const Word256& shl_w, const Word256& x) {
    i64 size = clamp4096(sgn(size_w)).to_i64(), off = clamp4096(sgn(off_w)).to_i64(),
        shl = clamp4096(sgn(shl_w)).to_i64();
    EvmInt mask;
    if (off < 0) {
        size += off;
        mask = size < 1 ? EvmInt(0) : EvmInt::pow2(u64(size)) - EvmInt(1);
    } else {
        mask = size < 0 ? EvmInt(0) : (EvmInt::pow2(u64(size)) - EvmInt(1)) * EvmInt::pow2(u64(off));
    }
    EvmInt v = I(x) & mask;
    if (shl >= 256 || shl <= -256) return Word256{};
    if (shl > 0) v = v << u64(shl);
    if (shl < 0) v = v >> u64(-shl);
    return W(v);
}

Word256 ref(Op op, const std::vector<Word256>& a) {
    auto b2 = [](bool b) { return Word256::of(b ? 1 : 0); };
    switch (op) {
        case Op::ADD: {
            EvmInt s;
            for (const Word256& x : a) s = s + I(x);
            return W(s);
        }
        case Op::MUL: {
            EvmInt s(1);
            for (const Word256& x : a) s = (s * I(x)).mod_2exp(256);
            return W(s);
        }
        case Op::SUB: return W(I(a[0]) - I(a[1]));
        case Op::DIV: return a[1].is_zero() ? Word256{} : W(floordiv(I(a[0]), I(a[1])));
        case Op::SDIV: {
            if (a[1].is_zero()) return Word256{};
            EvmInt x = sgn(a[0]), y = sgn(a[1]);
            EvmInt q = floordiv(absi(x), absi(y));
            return W((x.sign() < 0) != (y.sign() < 0) ? -q : q);
        }
        case Op::MOD: return a[1].is_zero() ? Word256{} : W(pymod(I(a[0]), I(a[1])));
        case Op::SMOD: {
            if (a[1].is_zero()) return Word256{};
            EvmInt x = sgn(a[0]), y = sgn(a[1]);
            EvmInt r = pymod(absi(x), absi(y));
            return W(x.sign() < 0 ? -r : r);
        }
        case Op::ADDMOD: return a[2].is_zero() ? Word256{} : W(pymod(I(a[0]) + I(a[1]), I(a[2])));
        case Op::MULMOD: return a[2].is_zero() ? Word256{} : W(pymod(I(a[0]) * I(a[1]), I(a[2])));
        case Op::EXP: {
            EvmInt r(1), base = I(a[0]);
            EvmInt e = I(a[1]);
            for (int bit = 255; bit >= 0; --bit) {
                r = (r * r).mod_2exp(256);
                if (e.test_bit(u64(bit))) r = (r * base).mod_2exp(256);
            }
            return W(r);
        }
        case Op::SIGNEXTEND: {
            EvmInt b = I(a[0]), v = I(a[1]);
            if (b > EvmInt(31)) return a[1];
            u64 testbit = u64(b.to_i64()) * 8 + 7;
            EvmInt sign_bit = EvmInt::pow2(testbit);
            if (!(v & sign_bit).is_zero()) return W(v | (M() - sign_bit));
            return W(v & (sign_bit - EvmInt(1)));
        }
        case Op::LT: return b2(I(a[0]) < I(a[1]));
        case Op::GT: return b2(I(a[0]) > I(a[1]));
        case Op::SLT: return b2(sgn(a[0]) < sgn(a[1]));
        case Op::SGT: return b2(sgn(a[0]) > sgn(a[1]));
        case Op::LE: return b2(I(a[0]) <= I(a[1]));
        case Op::GE: return b2(I(a[0]) >= I(a[1]));
        case Op::SLE: return b2(sgn(a[0]) <= sgn(a[1]));
        case Op::SGE: return b2(sgn(a[0]) >= sgn(a[1]));
        case Op::EQ: return b2(I(a[0]) == I(a[1]));
        case Op::ISZERO: return b2(a[0].is_zero());
        case Op::BOOL: return b2(!a[0].is_zero());
        case Op::AND: {
            EvmInt s = word_max();
            for (const Word256& x : a) s = s & I(x);
            return W(s);
        }
        case Op::OR: {
            EvmInt s;
            for (const Word256& x : a) s = s | I(x);
            return W(s);
        }
        case Op::XOR: return W(I(a[0]) ^ I(a[1]));
        case Op::NOT: return W(word_max() - I(a[0]));
        case Op::BYTE: {
            EvmInt i = I(a[0]);
            if (i >= EvmInt(32)) return Word256{};
            return W(pymod(floordiv(I(a[1]), EvmInt::pow2(u64(8 * (31 - i.to_i64())))), EvmInt(256)));
        }
        case Op::SHL: {
            EvmInt s = I(a[0]);
            if (s >= EvmInt(256)) return Word256{};
            return W(I(a[1]) << u64(s.to_i64()));
        }
        case Op::SHR: {
            EvmInt s = I(a[0]);
            if (s >= EvmInt(256)) return Word256{};
            return W(I(a[1]) >> u64(s.to_i64()));
        }
        case Op::SAR: {
            EvmInt s = I(a[0]), v = sgn(a[1]);
            if (s >= EvmInt(256)) return W(v.sign() < 0 ? EvmInt(-1) : EvmInt(0));
            return W(v >> u64(s.to_i64()));
        }
        case Op::CLZ: return Word256::of(256 - I(a[0]).bit_length());
        case Op::MASK_SHL: return ref_mask_shl(a[0], a[1], a[2], a[3]);
        case Op::MAX: {
            Word256 r = a[0];
            for (const Word256& x : a)
                if (I(x) > I(r)) r = x;
            return r;
        }
        case Op::MIN: {
            Word256 r = a[0];
            for (const Word256& x : a)
                if (I(x) < I(r)) r = x;
            return r;
        }
        case Op::LAND: return a[0].is_zero() ? a[0] : a[1];
        case Op::LOR: return a[0].is_zero() ? a[1] : a[0];
        default: return Word256{};
    }
}

Word256 rw(u64 seed, u64 i) { return A::RandomEnv::word_for(seed, i); }

// a small signed field word (masks) or a random one
Word256 rfield(u64 seed, u64 i) {
    u64 r = rw(seed, i ^ 0xf1e1d).limb[0];
    if (r % 4 == 0) return rw(seed, i);
    i64 v = i64(r % 700) - 350;
    return Word256::from_int(EvmInt(v));
}

}  // namespace

TEST_CASE("algebra: eval_op agrees with python's integer semantics") {
    Fixture f;
    struct Spec {
        Op op;
        u32 n;
    };
    const Spec specs[] = {{Op::ADD, 2}, {Op::ADD, 4}, {Op::MUL, 2}, {Op::MUL, 3}, {Op::SUB, 2}, {Op::DIV, 2},
                          {Op::SDIV, 2}, {Op::MOD, 2}, {Op::SMOD, 2}, {Op::ADDMOD, 3}, {Op::MULMOD, 3},
                          {Op::EXP, 2}, {Op::SIGNEXTEND, 2}, {Op::LT, 2}, {Op::GT, 2}, {Op::SLT, 2},
                          {Op::SGT, 2}, {Op::EQ, 2}, {Op::ISZERO, 1}, {Op::AND, 2}, {Op::AND, 3}, {Op::OR, 3},
                          {Op::XOR, 2}, {Op::NOT, 1}, {Op::BYTE, 2}, {Op::SHL, 2}, {Op::SHR, 2}, {Op::SAR, 2},
                          {Op::CLZ, 1}, {Op::MASK_SHL, 4}, {Op::BOOL, 1}, {Op::LE, 2}, {Op::GE, 2},
                          {Op::SLE, 2}, {Op::SGE, 2}, {Op::MAX, 3}, {Op::MIN, 2}, {Op::LAND, 2}, {Op::LOR, 2}};
    int bad = 0;
    for (u64 i = 0; i < 3000 && bad < 6; ++i) {
        for (const Spec& sp : specs) {
            std::vector<Word256> a;
            for (u32 k = 0; k < sp.n; ++k) {
                Word256 w = rw(i * 131 + u64(sp.op), k);
                // small shifts, byte indexes, signextend bytes, mask fields
                bool small_place = k == 0 && (sp.op == Op::SHL || sp.op == Op::SHR || sp.op == Op::SAR ||
                                              sp.op == Op::BYTE || sp.op == Op::SIGNEXTEND);
                if (small_place && i % 3 != 0) w = Word256::of(rw(i, 99).limb[0] % 300);
                if (sp.op == Op::MASK_SHL && k < 3) w = rfield(i, k + 7 * u64(sp.op));
                if (sp.n == 2 && k == 1 && i % 7 == 0) w = a[0];  // equal operands
                a.push_back(w);
            }
            auto got = A::eval_op(sp.op, a);
            REQUIRE(got);
            Word256 want = ref(sp.op, a);
            if (!(*got == want)) {
                ++bad;
                MESSAGE(op_name(sp.op), " case ", i);
            }
        }
    }
    CHECK(bad == 0);
    // not pure, or a wrong operand count
    const Word256 one[] = {Word256::of(1)};
    CHECK(!A::eval_op(Op::CALLDATALOAD, one));
    CHECK(!A::eval_op(Op::SUB, one));
    CHECK(!A::is_pure(Op::SHA3));
    CHECK(A::is_pure(Op::MASK_SHL));
}

TEST_CASE("algebra: mask_shl_word, mask_word, clamp_field") {
    Fixture f;
    Word256 x = Word256::from_value(V("0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"));
    CHECK(A::mask_shl_word(160, 0, 0, x) == Word256::from_value(V("0x89abcdef0123456789abcdef0123456789abcdef")));
    CHECK(A::mask_shl_word(32, 224, -224, x) == Word256::of(0x01234567));
    CHECK(A::mask_shl_word(8, 0, 8, x) == Word256::of(0xef00));
    CHECK(A::mask_shl_word(8, 0, 256, x) == Word256{});
    CHECK(A::mask_shl_word(8, 0, -256, x) == Word256{});
    CHECK(A::mask_shl_word(0, 0, 0, x) == Word256{});
    CHECK(A::mask_shl_word(16, -8, 0, x) == Word256::of(0xef));  // a negative offset shrinks the size
    CHECK(A::mask_shl_word(300, 0, 0, x) == x);
    CHECK(A::mask_word(8, 8) == Word256::of(0xff00));
    CHECK(A::mask_word(8, 252) == Word256::from_value(V("0xf000000000000000000000000000000000000000000000000000000000000000")));
    CHECK(A::clamp_field(Word256::of(5)) == 5);
    CHECK(A::clamp_field(Word256::from_value(mk_int(-5))) == -5);
    CHECK(A::clamp_field(Word256::from_value(mk_int(1) )) == 1);
    CHECK(A::clamp_field(Word256::from_value(V("0x8000000000000000000000000000000000000000000000000000000000000000"))) == -4096);
    CHECK(A::clamp_field(Word256::from_value(V("0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"))) == 4096);
    CHECK(A::clamp_field(Word256::of(5000)) == 4096);
    for (u64 i = 0; i < 4000; ++i) {
        Word256 s = rfield(i, 1), o = rfield(i, 2), h = rfield(i, 3), v = rw(i, 4);
        CHECK(A::mask_shl_word(s, o, h, v) == ref_mask_shl(s, o, h, v));
    }
}

TEST_CASE("algebra: word_int and signed_int") {
    Fixture f;
    CHECK(A::word_int(mk_int(-1)) == V("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"));
    CHECK(A::word_int(mk_int(5)) == mk_int(5));
    CHECK(A::signed_int(V("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")) == mk_int(-1));
    CHECK(A::signed_int(V("0x8000000000000000000000000000000000000000000000000000000000000000")) ==
          EvmInt(-EvmInt::pow2(255)).value());
    CHECK(A::signed_int(EvmInt::pow2(256).value()) == mk_int(0));
    CHECK(A::word_int(EvmInt(-EvmInt::pow2(256) - EvmInt(3)).value()) ==
          (EvmInt::pow2(256) - EvmInt(3)).value());
}

TEST_CASE("algebra: eval_const") {
    Fixture f;
    CHECK(A::eval_const(V("(add 1 (mul 2 3))")) == Word256::of(7));
    CHECK(A::eval_const(V("(sub 1 2)")) == Word256::from_value(mk_int(-1)));
    CHECK(A::eval_const(V("(mask_shl 8 8 -8 0x1234)")) == Word256::of(0x12));
    CHECK(A::eval_const(V("(lor 0 5)")) == Word256::of(5));
    CHECK(A::eval_const(mk_int(-2)) == Word256::from_value(mk_int(-2)));
    CHECK(A::eval_const(Value(true)) == Word256::of(1));
    CHECK(!A::eval_const(V("(add 1 caller)")));
    CHECK(!A::eval_const(V("caller")));
    CHECK(!A::eval_const(V("(sha3 1)")));
    CHECK(!A::eval_const(V("(add 1 (calldataload 4))")));
    // memoized: the same answer twice
    Value e = V("(exp 3 (add 200 55))");
    CHECK(A::eval_const(e) == A::eval_const(e));
    CHECK(A::eval_const(e) == pan::exp(Word256::of(3), Word256::of(255)));
}

TEST_CASE("algebra: the Evaluator and the envs") {
    Fixture f;
    A::MapEnv env;
    env.set(V("caller"), Word256::of(10));
    env.set(V("(calldataload 4)"), Word256::of(3));
    A::Evaluator ev(env);
    CHECK(ev(V("(add caller (mul 2 (calldataload 4)))")) == Word256::of(16));
    CHECK(!ev.try_eval(V("(add 1 callvalue)")));
    CHECK_THROWS_AS(ev(V("(add 1 callvalue)")), Unsupported);
    // python's and/or: the second operand only when it decides
    CHECK(ev(V("(land 0 callvalue)")) == Word256{});
    CHECK(ev(V("(lor caller callvalue)")) == Word256::of(10));
    // a DAG of 2^60 paths: each node once
    Value v = V("caller");
    for (int i = 0; i < 60; ++i) v = mk(Op::ADD, v, v);
    CHECK(ev(v) == pan::mul(Word256::of(10), pan::shl(Word256::of(60), Word256::of(1))));
    // forget(): another env value
    env.set(V("caller"), Word256::of(1));
    CHECK(ev(V("caller")) == Word256::of(10));
    ev.forget();
    CHECK(ev(V("caller")) == Word256::of(1));
    // RandomEnv: structural, the same in every context
    A::RandomEnv r1(7);
    Word256 w1 = A::eval(V("(add caller (calldataload 4))"), r1);
    {
        auto c2 = Context::create(f.budget);
        ContextScope s(*c2);
        A::RandomEnv r2(7);
        CHECK(A::eval(V("(add caller (calldataload 4))"), r2) == w1);
        A::RandomEnv r3(8);
        CHECK(!(A::eval(V("caller"), r3) == A::eval(V("caller"), r2)));
    }
    // edge values come up
    int zeros = 0, ones = 0, maxes = 0;
    for (u64 k = 0; k < 2000; ++k) {
        Word256 w = A::RandomEnv::word_for(3, k);
        zeros += w.is_zero();
        ones += w == Word256::of(1);
        maxes += w == pan::bnot(Word256{});
    }
    CHECK(zeros > 5);
    CHECK(ones > 5);
    CHECK(maxes > 5);
    // MapEnv with a fallback
    A::MapEnv m2(&r1);
    m2.set(V("caller"), Word256::of(4));
    A::Evaluator e2(m2);
    CHECK(e2(V("caller")) == Word256::of(4));
    CHECK(e2(V("callvalue")) == A::RandomEnv::word_for(7, V("callvalue").hash()));
}
