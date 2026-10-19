// Lot 7: simplify_exp's rules, each checked by concrete evaluation of the
// expression before and after on random and edge values of its leaves
// (lot 2's RandomEnv), plus random expressions through all of them.
#include <doctest/doctest.h>

#include <optional>
#include <string>
#include <vector>

#include "algebra/construct.hpp"
#include "algebra/eval.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/dump.hpp"
#include "core/errors.hpp"
#include "core/evmint.hpp"
#include "simplify/effects.hpp"
#include "simplify/simplify.hpp"

using namespace pan;
namespace A = pan::alg;
namespace S = pan::simplify;

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

Value small(i64 x) { return Value::small(x); }

// e and f have the same value on `seeds` random environments
bool same_value(Value e, Value f, int seeds = 64) {
    for (int s = 0; s < seeds; ++s) {
        A::RandomEnv env(u64(s) * 0x9e3779b97f4a7c15ull + 7);
        A::Evaluator ev1(env), ev2(env);
        auto a = ev1.try_eval(e);
        auto b = ev2.try_eval(f);
        if (!a || !b) return false;
        if (!(*a == *b)) {
            MESSAGE("differ on seed " << s << ": " << dump(e) << " vs " << dump(f));
            return false;
        }
    }
    return true;
}

// simplified, and the same value
Value check(Value e) {
    Value s = S::simplify_exp(e);
    CHECK_MESSAGE(same_value(e, s), dump(e) << " -> " << dump(s));
    return s;
}

Value cd(i64 off) { return mk(Op::CALLDATALOAD, small(off)); }
Value tmp(u32 n) { return Value::name(NameKind::TMP, n); }

// a small random expression generator (deterministic)
struct Gen {
    u64 s;
    u64 next() {
        s ^= s << 13;
        s ^= s >> 7;
        s ^= s << 17;
        return s;
    }
    Value leaf() {
        switch (next() % 9) {
            case 0: return cd(4);
            case 1: return cd(36);
            case 2: return tmp(1);
            case 3: return tmp(2);
            case 4: return small(i64(next() % 300));
            case 5: return small(i64(next() % 64) * 32);
            case 6: return mk_int(-1);
            case 7: return A::value_of(A::mask_word(160, 0));
            default: return small(i64(next() % 8));
        }
    }
    Value exp(int depth) {
        if (depth == 0 || next() % 4 == 0) return leaf();
        static const Op ops[] = {Op::ADD, Op::MUL, Op::SUB, Op::AND, Op::OR, Op::XOR, Op::NOT, Op::ISZERO,
                                 Op::EQ, Op::LT, Op::GT, Op::SLT, Op::SGT, Op::SHL, Op::SHR, Op::SAR,
                                 Op::BYTE, Op::MOD, Op::DIV, Op::BOOL, Op::MAX, Op::MIN, Op::LE, Op::GE,
                                 Op::MASK_SHL, Op::SIGNEXTEND};
        const Op op = ops[next() % (sizeof ops / sizeof ops[0])];
        switch (op) {
            case Op::NOT:
            case Op::ISZERO:
            case Op::BOOL: return mk(op, exp(depth - 1));
            case Op::MASK_SHL: {
                const i64 size = i64(next() % 257), off = i64(next() % 64) * (next() % 2 ? 8 : 1);
                const i64 shl = i64(next() % 64) - 32;
                return mk(op, small(size), small(off), small(shl), exp(depth - 1));
            }
            case Op::SHL:
            case Op::SHR:
            case Op::SAR: return mk(op, small(i64(next() % 300)), exp(depth - 1));
            case Op::BYTE: return mk(op, small(i64(next() % 40)), exp(depth - 1));
            case Op::SIGNEXTEND: return mk(op, small(i64(next() % 34)), exp(depth - 1));
            default: return mk(op, exp(depth - 1), exp(depth - 1));
        }
    }
};

}  // namespace

TEST_CASE("simplify: iszero rules") {
    Fixture f;
    Value x = cd(4), y = cd(36);
    // iszero(c + x): x == -c
    Value s = check(mk(Op::ISZERO, mk(Op::ADD, small(5), x)));
    CHECK(s.is(Op::EQ));
    // iszero(a - b): a == b
    s = check(mk(Op::ISZERO, A::sub(x, y)));
    CHECK(s.is(Op::EQ));
    // iszero(a ^ b): a == b
    s = check(mk(Op::ISZERO, mk(Op::XOR, x, y)));
    CHECK(s.is(Op::EQ));
    // iszero(-x), bool(-x)
    check(mk(Op::ISZERO, A::neg(x)));
    check(mk(Op::BOOL, A::neg(x)));
    // a shift that loses none of the bits
    check(mk(Op::ISZERO, mk(Op::MASK_SHL, small(8), small(8), small(-8), x)));
    check(mk(Op::ISZERO, mk(Op::MASK_SHL, small(8), small(0), small(16), x)));
}

TEST_CASE("simplify: eq rules") {
    Fixture f;
    Value x = cd(4);
    Value s = check(mk(Op::EQ, x, small(0)));
    CHECK(s.is(Op::ISZERO));
    s = check(mk(Op::EQ, small(1), mk(Op::LT, x, small(5))));
    CHECK(s.is(Op::LT));
    check(mk(Op::EQ, small(1), x));
}

TEST_CASE("simplify: masks") {
    Fixture f;
    Value x = cd(4);
    // floor32(95 + x) = 64 + floor32(31 + x)
    Value s = check(mk(Op::MASK_SHL, small(251), small(5), small(0), mk(Op::ADD, small(95), x)));
    CHECK(s.is(Op::ADD));
    // a constant below 2^off added to multiples of 2^off
    check(mk(Op::MASK_SHL, small(251), small(5), small(0), mk(Op::ADD, small(31), A::mul(small(32), x))));
    // mod 2^k
    s = check(mk(Op::MOD, x, small(32)));
    CHECK(s.is(Op::MASK_SHL));
    check(mk(Op::MOD, x, small(2)));
    // mask of x / 256^k
    check(mk(Op::MASK_SHL, small(8), small(0), small(0), mk(Op::DIV, x, mk(Op::EXP, small(256), small(3)))));
    check(mk(Op::MASK_SHL, small(8), small(0), small(0), mk(Op::DIV, x, mk(Op::EXP, small(256), cd(36)))));
    // a field of storage moved past 0
    Value st = mk(Op::STORAGE, small(8), small(0), small(3));
    CHECK(S::simplify_exp(mk(Op::MASK_SHL, small(256), small(0), small(-8), st)) == small(0));
}

TEST_CASE("simplify: comparisons of sums") {
    Fixture f;
    Value x = A::mask(64, 0, 0, cd(4)), y = A::mask(64, 0, 0, cd(36)), z = A::mask(64, 0, 0, tmp(1));
    Value s = check(mk(Op::LT, A::add({x, y, small(5)}), A::add(x, z)));
    MESSAGE(dump(s));
    check(mk(Op::GE, A::add({x, y}), A::add({x, small(32)})));
    // with a wrap possible: as it is
    check(mk(Op::LT, A::add(cd(4), small(1)), A::add(cd(4), cd(36))));
}

TEST_CASE("simplify: random expressions") {
    Fixture f;
    Gen g{0x1234567};
    for (int i = 0; i < 3000; ++i) {
        Value e = g.exp(4);
        Value s = S::simplify_exp(e);
        if (!same_value(e, s, 16)) {
            FAIL_CHECK("random #" << i << ": " << dump(e) << " -> " << dump(s));
            break;
        }
    }
}

TEST_CASE("simplify: effects") {
    Fixture f;
    Value r1 = mk(Op::RANGE, small(64), small(32)), r2 = mk(Op::RANGE, small(96), small(32));
    Value w = mk(Op::SETMEM, r1, small(5));
    CHECK(S::affects(w, mk(Op::MEM, r1)));
    CHECK(!S::affects(w, mk(Op::MEM, r2)));
    CHECK(S::affects(w, mk(Op::ADD, small(1), mk(Op::MEM, mk(Op::RANGE, small(80), small(32))))));
    CHECK(!S::affects(w, cd(4)));
    // storage: slots, fields
    Value st = mk(Op::STORE, small(256), small(0), small(3), small(1));
    CHECK(S::affects(st, mk(Op::STORAGE, small(256), small(0), small(3))));
    CHECK(!S::affects(st, mk(Op::STORAGE, small(256), small(0), small(4))));
    Value fld = mk(Op::STORE, small(8), small(0), small(3), small(1));
    CHECK(!S::affects(fld, mk(Op::STORAGE, small(8), small(8), small(3))));
    CHECK(S::affects(fld, mk(Op::STORAGE, small(16), small(0), small(3))));
    Value hashed = mk(Op::SHA3, mk(Op::SIZED, small(32), cd(4)));
    CHECK(!S::affects(st, mk(Op::STORAGE, small(256), small(0), hashed)));
    // variables
    Value sv = mk(Op::SETVAR, tmp(1), small(2));
    CHECK(S::affects(sv, A::add(tmp(1), small(3))));
    CHECK(!S::affects(sv, A::add(tmp(2), small(3))));
    // calls change storage, not memory
    Value call = mk(Op::CALL, small(1), mk(Op::GAS), cd(4), small(0), None, None);
    CHECK(S::affects(call, mk(Op::STORAGE, small(256), small(0), small(3))));
    CHECK(!S::affects(call, mk(Op::MEM, r1)));
    CHECK(S::affects(call, Value::leaf(Op::CALL_SUCCESS, 1)));
    CHECK(!S::affects(call, Value::leaf(Op::CALL_SUCCESS, 2)));
    // msize grows with any access of memory
    CHECK(S::affects(w, Value::leaf(Op::MSIZE)));
    CHECK(!S::affects(sv, Value::leaf(Op::MSIZE)));
    // control
    Value t = mk_trace({w, mk(Op::REVERT, None)});
    CHECK(S::ends(t));
    CHECK(!S::ends(mk_trace({w})));
    Value iff = mk(Op::IF, cd(4), mk_trace({mk(Op::STOP, std::span<const Value>{})}), mk_trace({w}));
    CHECK(!S::ends(iff));
    CHECK((S::summary(iff).control & S::C_HALTS) != 0);
    CHECK(S::independent(w, sv));
    CHECK(!S::independent(w, mk(Op::SETMEM, mk(Op::RANGE, small(70), small(1)), small(1))));
}
