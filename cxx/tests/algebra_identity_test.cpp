// Identities proven (algebra/identity.hpp): alg::same_value proves what the
// normal forms make one expression - the sums and products the passes
// rebuild without renormalizing, as the corpus has them - and nothing a
// sample of random values would take for an identity.
#include <doctest/doctest.h>

#include <optional>

#include "algebra/construct.hpp"
#include "algebra/eval.hpp"
#include "algebra/identity.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/dump.hpp"

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

// the value of v where every leaf, name and non-pure node is what RandomEnv(seed) gives it
std::optional<Word256> at(Value v, u64 seed) {
    A::RandomEnv env(seed);
    A::Evaluator ev(env);
    return ev.try_eval(v);
}

}  // namespace

TEST_CASE("algebra: same_value - the normal form of what a pass rebuilt as it was") {
    Fixture f;
    // terms and factors in another order than compare()'s: mk, as mk_like
    // leaves a sum whose term was replaced (a storage form, a SafeMath call)
    const Value x = V("(calldataload 4)"), y = V("(storage 256 0 3)"), g = Value::leaf(Op::GAS, 7);
    const Value sum = A::add(x, y), prod = A::mul(x, y);
    CHECK(A::same_value(sum, mk(Op::ADD, y, x)));
    CHECK(A::same_value(prod, mk(Op::MUL, y, x)));
    CHECK(A::same_value(A::sub(x, g), mk(Op::ADD, x, mk(Op::MUL, Value::small(-1), g))));
    // nested, below a comparison and a non-pure op (a SafeMath call's operands)
    CHECK(A::same_value(A::cmp(Op::GT, sum, x), mk(Op::GT, mk(Op::ADD, y, x), x)));
    CHECK(A::same_value(mk(Op::SAFEMATH, Value::small(0), sum, x), mk(Op::SAFEMATH, Value::small(0), mk(Op::ADD, y, x), x)));
    // -1 * (32 * z) is -32 * z; True is 1
    const Value z = V("(calldataload 36)");
    CHECK(A::same_value(A::mul(Value::small(-32), z), mk(Op::MUL, Value::small(-1), mk(Op::MUL, Value::small(32), z))));
    CHECK(A::same_value(True, Value::small(1)));
}

TEST_CASE("algebra: same_value - what random values can't tell apart isn't proven") {
    Fixture f;
    const Value a = V("(calldataload 4)"), b = V("(calldataload 36)");
    // a * b + (a == 12345): a * b but at a = 12345; max(a, 1): a but at 0
    const Value near = A::add(A::mul(a, b), A::cmp(Op::EQ, a, Value::small(12345)));
    const Value at_least = A::max({a, Value::small(1)});
    // (the four points SafeMath's abstraction was checked on: the same values)
    for (const u64 seed : {0x5afe0001ull, 0x5afe0002ull, 0x5afe0003ull, 0x5afe0004ull})
        CHECK(at(near, seed) == at(A::mul(a, b), seed));
    CHECK_FALSE(A::same_value(near, A::mul(a, b)));
    CHECK_FALSE(A::same_value(at_least, a));
    CHECK_FALSE(A::same_value(A::add(a, b), A::add(a, Value::small(1))));
}
