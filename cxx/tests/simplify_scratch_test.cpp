// Lot 7: scratch experiments (opt-in: PANORAMIX_SIMPLIFY_SCRATCH=1)
#include <doctest/doctest.h>

#include <cstdio>
#include <cstdlib>
#include <optional>

#include "algebra/compare.hpp"
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
        Value mn = V("(min 32 (returndatasize 1))");
        Value c = V("(iszero (lt (returndatasize 1) 32))");
        std::printf("constraint: %s\n", dump(alg::apply_constraint(mn, alg::normalize(c))).c_str());
        Value t2 = V("{(staticcall 1 (gas 1) caller None None) (setmem (range 128 (min 32 (returndatasize 1))) (returndata_bytes 1 0 (min 32 (returndatasize 1)))) (if (iszero (call_success 1)) {(revert None)} {(if (lt (returndatasize 1) 32) {(revert None)} {(setvar tmp4 (mem (range 128 32))) (return (sized 32 tmp4))})})}");
        std::printf("mems: %s\n", dump_trace(simplify::cleanup_mems(t2)).c_str());
    }
    budget.detach_thread();
}
