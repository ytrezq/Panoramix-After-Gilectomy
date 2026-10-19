// Lot 7: a debugging aid (opt-in): PANORAMIX_SIMPLIFY_DUMP=X.hex prints each
// function's raw trace (lot 5's VM) and its simplification;
// PANORAMIX_SIMPLIFY_SEL=a9059cbb only that selector's (fallback: "fb"),
// PANORAMIX_SIMPLIFY_RAW=0 not the raw traces.
#include <doctest/doctest.h>

#include <algorithm>
#include <cstdio>
#include <memory>
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
#include "evm/decoder.hpp"
#include "hex.hpp"
#include "loops/loops.hpp"
#include "sigdb.hpp"
#include "simplify/simplify.hpp"
#include "validate/stage_check.hpp"
#include "vm/vm.hpp"

using namespace pan;

namespace {

// the WHILE lines of a trace (any depth), with lot 6's facts on them
void show_loops(Value t) {
    if (!t.is_list()) return;
    for (Value l : t.args()) {
        if (l.is(Op::WHILE, 4)) {
            const loops::LoopSummary& s = loops::summary(l);
            std::printf("  loop %s: writes %s%s reads %s%s\n", dump(l[2]).c_str(), dump(s.mem_writes).c_str(),
                        s.mem_writes_any ? " (any)" : "", dump(s.mem_reads).c_str(), s.mem_reads_any ? " (any)" : "");
            if (auto ind = loops::induction(l))
                std::printf("    induction %s start %s step %s bound %s trips %s endvars %s\n", dump(ind->var).c_str(),
                            dump(ind->start).c_str(), dump(ind->step).c_str(), dump(ind->bound).c_str(),
                            dump(ind->trips).c_str(), dump(ind->endvars).c_str());
            show_loops(l[1]);
        }
        if (l.is(Op::IF, 3)) {
            show_loops(l[1]);
            show_loops(l[2]);
        }
    }
}

// --explain's stages, printed when the trace changed
struct Explain final : simplify::ExplainHook {
    Value last;
    void stage(simplify::ExplainStage st, Value trace) override {
        if (trace == last) return;
        last = trace;
        std::printf("---- stage %d\n%s\n", int(st), dump_trace(trace).c_str());
    }
};

}  // namespace

TEST_CASE("simplify: dump (PANORAMIX_SIMPLIFY_DUMP)") {
    const char* path = std::getenv("PANORAMIX_SIMPLIFY_DUMP");
    if (!path) return;
    const char* sel = std::getenv("PANORAMIX_SIMPLIFY_SEL");
    const char* raw = std::getenv("PANORAMIX_SIMPLIFY_RAW");
    const bool show_raw = !raw || std::string(raw) != "0";
    const bool quiet = std::getenv("PANORAMIX_SIMPLIFY_QUIET") != nullptr;
    i64 t_vm = 0, t_whiles = 0, t_simplify = 0;
    simplify::simplify_stats() = simplify::SimplifyStats{};
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
                const i64 t0 = platform::monotonic_ns();
                auto r = vm::run_function(shared, fn, o);
                const i64 t1 = platform::monotonic_ns();
                fn.trace = r.trace;
                if (show_raw && !quiet) std::printf("==== %s raw\n%s\n", name, dump_trace(fn.trace).c_str());
                fn.calls = std::move(r.calls);
                fn.loops = std::move(r.loops);
                FunctionInfo g = fn;
                loops::whiles_function(g);
                const i64 t2 = platform::monotonic_ns();
                if (show_raw && !quiet) std::printf("==== %s whiles\n%s\n", name, dump_trace(g.trace).c_str());
                if (std::getenv("PANORAMIX_SIMPLIFY_LOOPS")) show_loops(g.trace);
                Explain ex;
                ex.last = g.trace;
                simplify::simplify_function(g, {}, std::getenv("PANORAMIX_SIMPLIFY_EXPLAIN") ? &ex : nullptr);
                const i64 t3 = platform::monotonic_ns();
                t_vm += t1 - t0;
                t_whiles += t2 - t1;
                t_simplify += t3 - t2;
                if (quiet)
                    std::printf("%s: vm %lld ms, whiles %lld ms, simplify %lld ms\n", name, (long long)((t1 - t0) / 1000000),
                                (long long)((t2 - t1) / 1000000), (long long)((t3 - t2) / 1000000));
                else
                    std::printf("==== %s simplified\n%s\n", name, dump_trace(g.trace).c_str());
            } catch (const Error& e) {
                std::printf("==== %s failed: %s\n", name, e.what());
            }
        }
    }
    const auto& st = simplify::simplify_stats();
    std::printf("total: vm %lld ms, whiles %lld ms, simplify %lld ms; passes (ms/runs):", (long long)(t_vm / 1000000),
                (long long)(t_whiles / 1000000), (long long)(t_simplify / 1000000));
    static const char* const names[12] = {"exps", "vars", "mems", "precompiled", "min_ifs", "split", "length", "conds", "final", "loops", "-", "-"};
    for (int k = 0; k < 10; ++k) std::printf(" %s %llu/%llu", names[k], (unsigned long long)(st.ns[k] / 1000000), (unsigned long long)st.runs[k]);
    std::printf("\n");
    budget.detach_thread();
}

// PANORAMIX_SIMPLIFY_CHECK=X.hex: the stage check of X (raw and simplified
// traces against evmone), PANORAMIX_SIMPLIFY_PASSES=hex the passes run
// (simplify.hpp P_*), PANORAMIX_SIMPLIFY_SIGDB=the signature database
TEST_CASE("simplify: stage check (PANORAMIX_SIMPLIFY_CHECK)") {
    const char* path = std::getenv("PANORAMIX_SIMPLIFY_CHECK");
    if (!path) return;
    const char* passes = std::getenv("PANORAMIX_SIMPLIFY_PASSES");
    const char* dbp = std::getenv("PANORAMIX_SIMPLIFY_SIGDB");
    const char* only = std::getenv("PANORAMIX_SIMPLIFY_SEL");
    simplify::SimplifyOptions opts;
    if (passes) opts.passes = u32(std::strtoul(passes, nullptr, 16));
    std::ifstream f(path, std::ios::binary);
    std::stringstream ss;
    ss << f.rdbuf();
    auto bytes = hex::decode(ss.str());
    REQUIRE(bytes);
    std::unique_ptr<sigdb::Database> db;
    if (dbp) db = sigdb::Database::open(dbp);
    validate::CheckConfig cfg;
    cfg.upto = validate::Stage::simplified;
    cfg.db = db.get();
    cfg.keep = 6;
    if (only) cfg.only = u32(std::strtoul(only, nullptr, 16));
    auto pipeline = [&](validate::Decompiled& c, validate::Stage, Budget& budget) {
        auto& fns = c.functions[0];
        auto& internals = c.internals[0];
        fns = vm::discover(c.shared, budget);
        std::vector<vm::InternalEntry> known;
        std::vector<std::pair<bool, usize>> todo;
        for (usize i = 0; i < fns.size(); ++i) todo.emplace_back(false, i);
        for (unsigned wave = 0; wave < 8 && !todo.empty(); ++wave) {
            std::vector<vm::InternalEntry> found;
            std::vector<std::pair<bool, usize>> again;
            for (const auto& [internal, i] : todo) {
                auto& fi = internal ? internals[i] : fns[i];
                vm::VmOptions o;
                o.known_internals = &known;
                try {
                    auto r = vm::run_function(c.shared, fi, o);
                    fi.trace = r.trace;
                    fi.calls = std::move(r.calls);
                    fi.loops = std::move(r.loops);
                    fi.problem.reset();
                    bool fresh = false;
                    for (const auto& e : r.found_internals)
                        if (std::find(known.begin(), known.end(), e) == known.end()) {
                            fresh = true;
                            if (std::find(found.begin(), found.end(), e) == found.end()) found.push_back(e);
                        }
                    if (fresh) again.emplace_back(internal, i);
                } catch (const Error&) {
                    fi.trace = Value{};
                    fi.problem = 0;
                }
            }
            todo = std::move(again);
            if (found.empty()) break;
            for (const auto& e : found) {
                known.push_back(e);
                FunctionInfo fi;
                fi.kind = FunctionInfo::Kind::Internal;
                fi.entry_pc = e.entry;
                fi.params.resize(e.nargs);
                todo.emplace_back(true, internals.size());
                internals.push_back(std::move(fi));
            }
        }
        for (const auto& [internal, i] : todo)
            if (internal && internals[i].trace.nil()) internals[i].problem = 0;
        c.made[0] = true;
        constexpr auto w = static_cast<unsigned>(validate::Stage::whiles);
        loops::whiles_stage(c.functions[0], c.functions[w]);
        loops::whiles_stage(c.internals[0], c.internals[w]);
        c.made[w] = true;
        constexpr auto s = static_cast<unsigned>(validate::Stage::simplified);
        simplify::simplify_stage(c.functions[w], c.functions[s], opts);
        simplify::simplify_stage(c.internals[w], c.internals[s], opts);
        c.made[s] = true;
    };
    auto rep = validate::check_contract(*bytes, cfg, pipeline);
    std::printf("%s\n", validate::summary(rep).c_str());
    for (unsigned s = 0; s < validate::stage_count; ++s)
        for (const auto& x : rep.stages[s].examples)
            std::printf("  %s %s: %s\n    %s\n    at %s\n    evm: %s\n    machine: %s\n", validate::stage_name(validate::Stage(s)),
                        validate::category_name(x.category), x.call.c_str(), x.message.c_str(), x.where.c_str(),
                        x.expected.c_str(), x.actual.c_str());
}
