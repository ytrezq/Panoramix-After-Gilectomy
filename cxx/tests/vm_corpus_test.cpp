// Lot 5: the VM over a corpus (opt-in: PANORAMIX_VM_CORPUS=a list of .hex
// paths, PANORAMIX_VM_LIMIT=N the first N, PANORAMIX_VM_SKIP=N skipped
// first) - discovery, every function's raw trace with the waves of the
// recursive internal functions; per contract the functions, the nodes, the
// functions left incomplete, the UNDEFINED lines by reason, the time; then
// the totals and the slowest contracts. Not a check of the traces' meaning
// (that is lot 11's stagecheck): a check that the VM runs everywhere, within
// its limits, and how fast.
#include <doctest/doctest.h>

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <memory>
#include <optional>
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
#include "vm/vm.hpp"

using namespace pan;

namespace {

struct Counts {
    u64 functions = 0, internals = 0, nodes = 0, incomplete = 0, failed = 0;
    u64 undefined[4] = {};
    u64 lines = 0;
    u64 hash = 0;  // PANORAMIX_VM_HASH: of the traces' dumps, in the functions' order
};

u64 fnv(const std::string& s, u64 h) {
    for (unsigned char c : s) h = (h ^ c) * 0x100000001b3ull;
    return h;
}

void count_lines(Value t, Counts& c) {
    SmallVec<Value, 64> todo{t};
    while (!todo.empty()) {
        Value v = todo.back();
        todo.pop_back();
        if (v.is_list()) {
            for (Value l : v.args()) todo.push_back(l);
            continue;
        }
        ++c.lines;
        if (v.is(Op::UNDEFINED, 2) && v[0].is_small() && v[0].small_val() > 0 && v[0].small_val() < 4)
            ++c.undefined[v[0].small_val()];
        if (v.is(Op::IF, 3)) {
            todo.push_back(v[1]);
            todo.push_back(v[2]);
        }
        if (v.is(Op::LABEL, 2) || v.is(Op::GOTO, 2)) todo.push_back(v[1]);
    }
}

}  // namespace

TEST_CASE("vm: corpus (PANORAMIX_VM_CORPUS)") {
    const char* list = std::getenv("PANORAMIX_VM_CORPUS");
    if (!list) return;
    const char* lim = std::getenv("PANORAMIX_VM_LIMIT");
    const char* skp = std::getenv("PANORAMIX_VM_SKIP");
    const unsigned long limit = lim ? std::strtoul(lim, nullptr, 10) : 0;
    const unsigned long skip = skp ? std::strtoul(skp, nullptr, 10) : 0;
    const bool per_function = std::getenv("PANORAMIX_VM_VERBOSE") != nullptr;
    const bool hashes = std::getenv("PANORAMIX_VM_HASH") != nullptr;
    const bool selectors = std::getenv("PANORAMIX_VM_SELECTORS") != nullptr;
    const bool discovery_only = selectors && std::getenv("PANORAMIX_VM_DISCOVERY_ONLY") != nullptr;
    // PANORAMIX_VM_ONLY=sel,sel,...: only these selectors' functions (hex)
    std::vector<u32> only;
    if (const char* o = std::getenv("PANORAMIX_VM_ONLY")) {
        std::stringstream os(o);
        std::string s;
        while (std::getline(os, s, ','))
            if (!s.empty()) only.push_back(u32(std::strtoul(s.c_str(), nullptr, 16)));
    }
    std::ifstream in(list);
    std::string path;
    std::vector<std::string> paths;
    while (std::getline(in, path))
        if (!path.empty()) paths.push_back(path);
    init();
    Counts total;
    struct Slow {
        i64 ns;
        std::string name;
    };
    std::vector<Slow> slow;
    unsigned long done = 0, index = 0;
    for (const std::string& p : paths) {
        if (index++ < skip) continue;
        if (limit && done >= limit) break;
        ++done;
        std::ifstream f(p, std::ios::binary);
        std::stringstream ss;
        ss << f.rdbuf();
        auto bytes = hex::decode(ss.str());
        if (!bytes) {
            std::printf("%s: not hex\n", p.c_str());
            continue;
        }
        Budget budget{Budget::Limits{.memory = usize{4} << 30}};
        budget.attach_thread();
        Counts c;
        const i64 t0 = platform::monotonic_ns();
        std::string problem;
        {
            auto ctx = Context::create(budget);
            ContextScope scope(*ctx);
            CodeMap map = analyse(*bytes);
            ContractShared shared;
            shared.code = *bytes;
            shared.map = &map;
            shared.free_memory_pointer = map.fmp;
            try {
                std::vector<FunctionInfo> fns = vm::discover(shared, budget);
                if (selectors) {
                    std::string line = "SEL " + p.substr(p.rfind('/') + 1);
                    char buf[32];
                    for (const auto& fn : fns) {
                        if (fn.kind == FunctionInfo::Kind::Selector)
                            std::snprintf(buf, sizeof buf, " %08x@%u", fn.selector, fn.entry_pc);
                        else
                            std::snprintf(buf, sizeof buf, " fallback@%u", fn.entry_pc);
                        line += buf;
                    }
                    std::printf("%s\n", line.c_str());
                    if (discovery_only) {
                        c.functions = fns.size();
                        throw Unsupported("discovery only");
                    }
                }
                std::vector<FunctionInfo> internals;
                std::vector<vm::InternalEntry> known;
                for (unsigned wave = 0; wave < 8; ++wave) {
                    std::vector<vm::InternalEntry> found;
                    Counts w;
                    auto run = [&](FunctionInfo& fn) {
                        if (!only.empty() && (fn.kind != FunctionInfo::Kind::Selector ||
                                              std::find(only.begin(), only.end(), fn.selector) == only.end()))
                            return;
                        vm::VmOptions o;
                        o.known_internals = &known;
                        try {
                            const i64 f0 = platform::monotonic_ns();
                            auto r = vm::run_function(shared, fn, o);
                            const i64 fns = platform::monotonic_ns() - f0;
                            if (per_function && (fns > 1000000000 || !r.complete))
                                std::printf("  fn kind %d sel %08x pc %u: nodes %u complete %d %lld ms\n", int(fn.kind),
                                            fn.selector, fn.entry_pc, r.nodes, int(r.complete),
                                            (long long)(fns / 1000000));
                            ++w.functions;
                            w.nodes += r.nodes;
                            w.incomplete += !r.complete;
                            count_lines(r.trace, w);
                            if (hashes) w.hash = fnv(dump_trace(r.trace), w.hash * 31 + 7);
                            for (const auto& e : r.found_internals)
                                if (std::find(known.begin(), known.end(), e) == known.end() &&
                                    std::find(found.begin(), found.end(), e) == found.end())
                                    found.push_back(e);
                        } catch (const Error& e) {
                            ++w.failed;
                            problem = e.what();
                        }
                    };
                    for (auto& fn : fns) run(fn);
                    for (auto& fn : internals) run(fn);
                    c = w;
                    c.internals = internals.size();
                    if (found.empty()) break;
                    for (const auto& e : found) {
                        known.push_back(e);
                        FunctionInfo fi;
                        fi.kind = FunctionInfo::Kind::Internal;
                        fi.entry_pc = e.entry;
                        fi.params.resize(e.nargs);
                        internals.push_back(std::move(fi));
                    }
                }
            } catch (const Unsupported& e) {
                if (!discovery_only) {
                    problem = std::string("discovery: ") + e.what();
                    ++c.failed;
                }
            } catch (const Error& e) {
                problem = std::string("discovery: ") + e.what();
                ++c.failed;
            }
        }
        budget.detach_thread();
        const i64 ns = platform::monotonic_ns() - t0;
        std::string name = p.substr(p.rfind('/') + 1);
        char hash[32] = "";
        if (hashes) std::snprintf(hash, sizeof hash, " hash %016llx", (unsigned long long)c.hash);
        std::printf("%-40s fns %3llu int %2llu nodes %7llu lines %7llu incomplete %llu failed %llu undef %llu/%llu/%llu%s %6lld ms%s%s\n",
                    name.c_str(), (unsigned long long)c.functions, (unsigned long long)c.internals,
                    (unsigned long long)c.nodes, (unsigned long long)c.lines, (unsigned long long)c.incomplete,
                    (unsigned long long)c.failed, (unsigned long long)c.undefined[1],
                    (unsigned long long)c.undefined[2], (unsigned long long)c.undefined[3], hash,
                    (long long)(ns / 1000000), problem.empty() ? "" : " ", problem.c_str());
        std::fflush(stdout);
        total.functions += c.functions;
        total.internals += c.internals;
        total.nodes += c.nodes;
        total.lines += c.lines;
        total.incomplete += c.incomplete;
        total.failed += c.failed;
        for (int k = 1; k < 4; ++k) total.undefined[k] += c.undefined[k];
        slow.push_back({ns, name});
    }
    std::sort(slow.begin(), slow.end(), [](const Slow& a, const Slow& b) { return a.ns > b.ns; });
    i64 sum = 0;
    for (const Slow& s : slow) sum += s.ns;
    std::printf("TOTAL %lu contracts: fns %llu internals %llu nodes %llu lines %llu incomplete %llu failed %llu "
                "undefined unfinished %llu computed-jump %llu ambiguous-call %llu; %lld ms\n",
                done, (unsigned long long)total.functions, (unsigned long long)total.internals,
                (unsigned long long)total.nodes, (unsigned long long)total.lines,
                (unsigned long long)total.incomplete, (unsigned long long)total.failed,
                (unsigned long long)total.undefined[1], (unsigned long long)total.undefined[2],
                (unsigned long long)total.undefined[3], (long long)(sum / 1000000));
    for (usize i = 0; i < slow.size() && i < 10; ++i)
        std::printf("  slow: %s %lld ms\n", slow[i].name.c_str(), (long long)(slow[i].ns / 1000000));
}
