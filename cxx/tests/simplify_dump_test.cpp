// Lot 7: a debugging aid (opt-in): PANORAMIX_SIMPLIFY_DUMP=X.hex prints each
// function's raw trace (lot 5's VM) and its simplification;
// PANORAMIX_SIMPLIFY_SEL=a9059cbb only that selector's (fallback: "fb"),
// PANORAMIX_SIMPLIFY_RAW=0 not the raw traces.
#include <doctest/doctest.h>

#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/contract.hpp"
#include "core/dump.hpp"
#include "core/errors.hpp"
#include "evm/decoder.hpp"
#include "hex.hpp"
#include "simplify/simplify.hpp"
#include "vm/vm.hpp"

using namespace pan;

TEST_CASE("simplify: dump (PANORAMIX_SIMPLIFY_DUMP)") {
    const char* path = std::getenv("PANORAMIX_SIMPLIFY_DUMP");
    if (!path) return;
    const char* sel = std::getenv("PANORAMIX_SIMPLIFY_SEL");
    const char* raw = std::getenv("PANORAMIX_SIMPLIFY_RAW");
    const bool show_raw = !raw || std::string(raw) != "0";
    std::ifstream f(path, std::ios::binary);
    std::stringstream ss;
    ss << f.rdbuf();
    auto bytes = hex::decode(ss.str());
    REQUIRE(bytes);
    init();
    Budget budget{Budget::Limits{.memory = usize{4} << 30}};
    budget.attach_thread();
    {
        auto ctx = Context::create(budget);
        ContextScope scope(*ctx);
        CodeMap map = analyse(*bytes);
        ContractShared shared;
        shared.code = *bytes;
        shared.map = &map;
        shared.free_memory_pointer = map.fmp;
        std::vector<FunctionInfo> fns = vm::discover(shared, budget);
        std::vector<vm::InternalEntry> known;
        for (auto& fn : fns) {
            char name[32];
            if (fn.kind == FunctionInfo::Kind::Selector)
                std::snprintf(name, sizeof name, "%08x", fn.selector);
            else
                std::snprintf(name, sizeof name, "fb");
            if (sel && std::string(sel) != name) continue;
            vm::VmOptions o;
            o.known_internals = &known;
            try {
                auto r = vm::run_function(shared, fn, o);
                fn.trace = r.trace;
                if (show_raw) std::printf("==== %s raw\n%s\n", name, dump_trace(fn.trace).c_str());
                Value s = simplify::simplify_trace(fn.trace);
                std::printf("==== %s simplified\n%s\n", name, dump_trace(s).c_str());
            } catch (const Error& e) {
                std::printf("==== %s failed: %s\n", name, e.what());
            }
        }
    }
    budget.detach_thread();
}
