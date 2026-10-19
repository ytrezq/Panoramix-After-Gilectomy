// Lot 7: scratch experiments (opt-in: PANORAMIX_SIMPLIFY_SCRATCH=1)
#include <doctest/doctest.h>

#include <cstdio>
#include <cstdlib>
#include <optional>

#include "algebra/construct.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/dump.hpp"
#include "loops/loops.hpp"
#include "simplify/simplify.hpp"

using namespace pan;

TEST_CASE("simplify: scratch (PANORAMIX_SIMPLIFY_SCRATCH)") {
    if (!std::getenv("PANORAMIX_SIMPLIFY_SCRATCH")) return;
    init();
    Budget budget{Budget::Limits{}};
    budget.attach_thread();
    {
        auto ctx = Context::create(budget);
        ContextScope scope(*ctx);
        Value x = mk(Op::STORAGE, Value::small(256), Value::small(0), Value::small(6));
        Value low = alg::band(x, Value::small(1));
        Value m = alg::add(alg::mul(Value::small(256), alg::iszero(low)), Value::small(-1));
        Value v = alg::band(x, m);
        Value d = alg::div(v, Value::small(2));
        std::printf("idiom: %s\n", dump(d).c_str());
        std::printf("mask: %s\n", dump(alg::mask(255, 1, -1, v)).c_str());
        Value vm = V("(mask_shl 255 1 -1 (and (add -1 (mul 256 (iszero (storage 1 0 6)))) (storage 256 0 6)))");
        std::printf("vm:   %s same %d\n", dump(vm).c_str(), int(vm == d));
        Value t = V("{(return (sized 32 (mask_shl 255 1 -1 (and (add -1 (mul 256 (iszero (storage 1 0 6)))) (storage 256 0 6)))))}");
        std::printf("len: %s\n", dump_trace(simplify::replace_bytes_or_string_length(t)).c_str());
    }
    budget.detach_thread();
}
