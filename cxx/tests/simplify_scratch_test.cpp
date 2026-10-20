// Lot 7: scratch experiments (opt-in: PANORAMIX_SIMPLIFY_SCRATCH=1)
#include <doctest/doctest.h>

#include <cstdio>
#include <cstdlib>
#include <optional>
#include <utility>
#include <vector>

#include "algebra/compare.hpp"
#include "algebra/construct.hpp"
#include "algebra/ranges.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/dump.hpp"
#include "simplify/simplify.hpp"

using namespace pan;

namespace {
const char* tri_name(Tri t) { return t == Tri::True ? "True" : t == Tri::False ? "False" : "None"; }
}  // namespace

TEST_CASE("simplify: scratch (PANORAMIX_SIMPLIFY_SCRATCH)") {
    if (!std::getenv("PANORAMIX_SIMPLIFY_SCRATCH")) return;
    init();
    Budget budget{Budget::Limits{}};
    budget.attach_thread();
    {
        auto ctx = Context::create(budget);
        ContextScope scope(*ctx);
        Value L = V("(calldataload (add 4 (calldataload 36)))");
        Value X = V("(mask_shl 251 5 0 (add 31 (calldataload (add 4 (calldataload 36)))))");
        Value p = alg::add(X, Value::small(160));
        std::printf("p: %s\n", dump(p).c_str());
        std::printf("unchecked L %d X %d p %d\n", int(alg::unchecked(L)), int(alg::unchecked(X)), int(alg::unchecked(p)));
        std::printf("no small: le(96, p) %s\n", tri_name(alg::le(Value::small(96), p, alg::Top::Memory)));
        const Value small[] = {L};
        alg::set_variables({}, small);
        std::printf("unchecked L %d X %d p %d\n", int(alg::unchecked(L)), int(alg::unchecked(X)), int(alg::unchecked(p)));
        auto r = alg::range(p, alg::Top::Memory);
        std::printf("range p: lo %s hi %s\n", r.lo.to_mpz().get_str().c_str(), r.hi.to_mpz().get_str().c_str());
        auto rx = alg::range(X, alg::Top::Memory);
        std::printf("range X: lo %s hi %s\n", rx.lo.to_mpz().get_str().c_str(), rx.hi.to_mpz().get_str().c_str());
        auto rl = alg::range(L, alg::Top::Memory);
        std::printf("range L: lo %s hi %s\n", rl.lo.to_mpz().get_str().c_str(), rl.hi.to_mpz().get_str().c_str());
        std::printf("small: le(96, p) %s\n", tri_name(alg::le(Value::small(96), p, alg::Top::Memory)));
        alg::clear_variables();
        // the conditions' bounds
        for (const char* c : {"(iszero (gt (calldataload (add 4 (calldataload 36))) 4294967296))",
                              "(iszero (or (gt (calldataload (add 4 (calldataload 36))) 4294967296) (gt (add 36 (calldataload 36) "
                              "(calldataload (add 4 (calldataload 36)))) calldatasize)))"}) {
            Value cv = alg::normalize(V(c));
            std::printf("cond %s\n", dump(cv).c_str());
            for (const alg::CondBound& b : alg::cond_bounds(cv))
                std::printf("  bound %s in [%s, %s]\n", dump(b.x).c_str(), dump(b.lo).c_str(), dump(b.hi).c_str());
        }
        // the trace
        const char* text = std::getenv("PANORAMIX_SIMPLIFY_SCRATCH_TRACE");
        if (text) {
            Value t = V(text);
            std::printf("in:\n%s\n", dump_trace(t).c_str());
            std::printf("out:\n%s\n", dump_trace(simplify::simplify_trace(t)).c_str());
        }
    }
    budget.detach_thread();
}
