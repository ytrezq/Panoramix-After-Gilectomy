// Lot 6 over a corpus (opt-in: PANORAMIX_LOOPS_CORPUS=a list of .hex paths,
// PANORAMIX_LOOPS_LIMIT=N the first N, PANORAMIX_LOOPS_SKIP=N skipped first,
// PANORAMIX_LOOPS_DUMP=1 each loop's head printed): every function's raw
// trace (lot 5's VM) through make_whiles - what its loops became (an exit
// test, rotated, renamed, while True), the failures, the time - and the
// analyses of each WHILE (induction: counters found, trips and endvars
// proven). Not a check of the meaning (stagecheck --stage whiles is): that
// the loops are made everywhere, and how.
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
#include "core/platform.hpp"
#include "core/smallvec.hpp"
#include "evm/decoder.hpp"
#include "hex.hpp"
#include "loops/loops.hpp"
#include "vm/vm.hpp"

using namespace pan;
namespace L = pan::loops;

namespace {

struct LoopCounts {
    u64 whiles = 0, counters = 0, trips = 0, endvars = 0, breaks = 0;
};

void walk_whiles(Value t, LoopCounts& c, bool show) {
    SmallVec<Value, 64> todo{t};
    while (!todo.empty()) {
        Value v = todo.back();
        todo.pop_back();
        if (v.is_list()) {
            for (Value l : v.args()) todo.push_back(l);
            continue;
        }
        if (v.is(Op::IF, 3)) {
            todo.push_back(v[1]);
            todo.push_back(v[2]);
        }
        if (v.is(Op::WHILE, 4)) {
            ++c.whiles;
            todo.push_back(v[1]);
            const L::LoopSummary& s = L::summary(v);
            c.breaks += s.breaks;
            if (auto ind = L::induction(v)) {
                ++c.counters;
                c.trips += !ind->trips.nil();
                c.endvars += !ind->endvars.nil();
            }
            if (show) {
                std::string head = dump(v[0]) + " " + dump(v[2]) + " " + dump(v[3]);
                std::printf("  WHILE %s\n", head.c_str());
                const Value body = v[1];
                for (u32 i = 0; i < body.size() && i < 4; ++i) {
                    std::string l = dump(body[i]);
                    if (l.size() > 200) l = l.substr(0, 200) + "...";
                    std::printf("    %s\n", l.c_str());
                }
            }
        }
    }
}

}  // namespace

TEST_CASE("loops: corpus (PANORAMIX_LOOPS_CORPUS)") {
    const char* list = std::getenv("PANORAMIX_LOOPS_CORPUS");
    if (!list) return;
    const char* lim = std::getenv("PANORAMIX_LOOPS_LIMIT");
    const char* skp = std::getenv("PANORAMIX_LOOPS_SKIP");
    const bool show = std::getenv("PANORAMIX_LOOPS_DUMP") != nullptr;
    const unsigned long limit = lim ? std::strtoul(lim, nullptr, 10) : 0;
    const unsigned long skip = skp ? std::strtoul(skp, nullptr, 10) : 0;
    std::ifstream in(list);
    std::string path;
    std::vector<std::string> paths;
    while (std::getline(in, path))
        if (!path.empty()) paths.push_back(path);
    init();
    L::WhilesStats total{};
    LoopCounts lc;
    u64 functions = 0, failed = 0, vm_failed = 0;
    i64 whiles_ns = 0;
    unsigned long done = 0, index = 0;
    for (const std::string& p : paths) {
        if (index++ < skip) continue;
        if (limit && done >= limit) break;
        ++done;
        std::ifstream f(p, std::ios::binary);
        std::stringstream ss;
        ss << f.rdbuf();
        auto bytes = hex::decode(ss.str());
        if (!bytes) continue;
        Budget budget{Budget::Limits{.memory = usize{4} << 30}};
        budget.attach_thread();
        L::whiles_stats() = {};
        std::string problem;
        LoopCounts c;
        u64 fns = 0;
        i64 ns = 0;
        {
            auto ctx = Context::create(budget);
            ContextScope scope(*ctx);
            CodeMap map = analyse(*bytes);
            ContractShared shared;
            shared.code = *bytes;
            shared.map = &map;
            shared.free_memory_pointer = map.fmp;
            std::string name = p.substr(p.rfind('/') + 1);
            if (show) std::printf("%s\n", name.c_str());
            try {
                std::vector<FunctionInfo> list_fns = vm::discover(shared, budget);
                for (auto& fn : list_fns) {
                    vm::VmOptions o;
                    Value raw;
                    try {
                        auto r = vm::run_function(shared, fn, o);
                        raw = r.trace;
                        fn.loops = r.loops;
                    } catch (const Error&) {
                        ++vm_failed;
                        continue;
                    }
                    ++fns;
                    try {
                        const i64 t0 = platform::monotonic_ns();
                        Value w = L::make_whiles(raw, fn.loops);
                        ns += platform::monotonic_ns() - t0;
                        walk_whiles(w, c, show);
                    } catch (const Error& e) {
                        ++failed;
                        problem = e.what();
                    }
                }
            } catch (const Error& e) {
                problem = std::string("discovery: ") + e.what();
            }
            const L::WhilesStats& s = L::whiles_stats();
            std::printf("%-40s fns %3llu loops %3llu: test %3llu (rotated %llu renamed %llu after %llu) true %3llu "
                        "plain %llu | counters %llu trips %llu endvars %llu breaks %llu | %lld us%s%s\n",
                        name.c_str(), (unsigned long long)fns, (unsigned long long)s.labels,
                        (unsigned long long)s.exit_test, (unsigned long long)s.rotated,
                        (unsigned long long)s.renamed, (unsigned long long)s.exit_after,
                        (unsigned long long)s.while_true, (unsigned long long)s.no_loop,
                        (unsigned long long)c.counters, (unsigned long long)c.trips, (unsigned long long)c.endvars,
                        (unsigned long long)c.breaks, (long long)(ns / 1000), problem.empty() ? "" : " ",
                        problem.c_str());
            std::fflush(stdout);
            total.labels += s.labels;
            total.exit_test += s.exit_test;
            total.rotated += s.rotated;
            total.renamed += s.renamed;
            total.exit_after += s.exit_after;
            total.while_true += s.while_true;
            total.no_loop += s.no_loop;
        }
        budget.detach_thread();
        functions += fns;
        lc.whiles += c.whiles;
        lc.counters += c.counters;
        lc.trips += c.trips;
        lc.endvars += c.endvars;
        lc.breaks += c.breaks;
        whiles_ns += ns;
    }
    std::printf("TOTAL %lu contracts, %llu functions (vm failed %llu), make_whiles failed %llu: loops %llu: exit test %llu "
                "(rotated %llu renamed %llu exit after %llu), while True %llu, no loop %llu; whiles %llu: counters %llu "
                "trips %llu endvars %llu breaks %llu; make_whiles %lld ms\n",
                done, (unsigned long long)functions, (unsigned long long)vm_failed, (unsigned long long)failed,
                (unsigned long long)total.labels, (unsigned long long)total.exit_test,
                (unsigned long long)total.rotated, (unsigned long long)total.renamed,
                (unsigned long long)total.exit_after, (unsigned long long)total.while_true,
                (unsigned long long)total.no_loop, (unsigned long long)lc.whiles, (unsigned long long)lc.counters,
                (unsigned long long)lc.trips, (unsigned long long)lc.endvars, (unsigned long long)lc.breaks,
                (long long)(whiles_ns / 1000000));
    CHECK(failed == 0);
}
