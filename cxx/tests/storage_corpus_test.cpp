// Lot 9 over a corpus (opt-in: PANORAMIX_STORAGE_CORPUS=a list of .hex
// paths, PANORAMIX_STORAGE_LIMIT=N the first N, PANORAMIX_STORAGE_SKIP=N
// skipped first, PANORAMIX_STORAGE_SHOW=N differences shown): each contract
// through the pipeline to its simplified traces, then the storage analysis
// on a copy - and every function, raw and rewritten, run by the trace
// machine on storage worlds (empty, random, of small words): the same ends,
// the same writes, logs and calls. The stage's own equivalence (stagecheck
// --stage analysed compares with evmone).
#include <doctest/doctest.h>

#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include "analysis/traits.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/contract.hpp"
#include "core/dump.hpp"
#include "core/errors.hpp"
#include "core/platform.hpp"
#include "driver/pipeline.hpp"
#include "evm/decoder.hpp"
#include "exec/machine.hpp"
#include "hex.hpp"
#include "sigdb.hpp"
#include "storage/storage.hpp"

using namespace pan;

namespace {

// a world: storage words of the slot's hash (seed 0: empty storage; odd
// seeds: small words), calldata of the selector and words
class CorpusWorld final : public exec::SimpleHost {
public:
    CorpusWorld(u64 seed, const FunctionInfo& fn, std::span<const u8> code_) : seed_(seed) {
        if (fn.kind == FunctionInfo::Kind::Selector)
            calldata = {u8(fn.selector >> 24), u8(fn.selector >> 16), u8(fn.selector >> 8), u8(fn.selector)};
        for (u64 i = 0; i < 8; ++i) {
            u8 w[32];
            Word256 v;
            switch ((seed + i) % 4) {
                case 0: v = Word256::of(i + 1); break;
                case 1: v = Word256{{hash_mix(seed * 77 + i), hash_mix(seed * 79 + i) & 0xffffffff, 0, 0}}; break;
                case 2: v = Word256::of(32 * (i + 1)); break;
                default: v = Word256{{hash_mix(seed * 7 + i), hash_mix(seed * 11 + i), hash_mix(seed * 13 + i), 0}}; break;
            }
            v.to_be(w);
            calldata.insert(calldata.end(), w, w + 32);
        }
        code.assign(code_.begin(), code_.end());
        call_env.caller = Word256{{0xaaaabbbbccccddddull + seed, 0x1111, 0x22, 0}};
        call_env.address = Word256{{0x1234, 0x5678, 0x9a, 0}};
        call_env.timestamp = Word256::of(1700000000 + seed);
        call_env.number = Word256::of(18000000 + seed);
        call_env.gas = Word256::of(10000000);
    }
    // (as the stage checks' random worlds mix them: zero, one, small, an
    // address, a large word, the largest)
    Word256 initial(const Word256& slot) override {
        if (seed_ == 0) return Word256{};
        u8 buf[40];
        slot.to_be(buf);
        for (int i = 0; i < 8; ++i) buf[32 + i] = u8(seed_ >> (8 * i));
        const Word256 h = exec::keccak256(std::span<const u8>(buf, 40));
        switch (h.limb[0] % 6) {
            case 0: return Word256{};
            case 1: return Word256::of(1);
            case 2: return Word256::of(2 + h.limb[1] % 62);
            case 3: return Word256{{h.limb[1], h.limb[2], h.limb[3] & 0xffffffff, 0}};
            case 4: return h;
            default: return Word256{{~u64(0), ~u64(0), ~u64(0), ~u64(0)}};
        }
    }

private:
    u64 seed_;
};

// the effects as the stage checks compare them (validate/effects.hpp): the
// events but the storage writes in their order, and the storage at the end
bool same_effects(exec::SimpleHost& a, exec::SimpleHost& b) {
    auto events = [](const exec::SimpleHost& h) {
        std::vector<exec::SimpleHost::Effect> e;
        for (const auto& x : h.effects)
            if (!std::holds_alternative<exec::SimpleHost::Sstore>(x)) e.push_back(x);
        return e;
    };
    if (events(a) != events(b)) return false;
    for (const auto* h : {&a, &b})
        for (const auto& [slot, value] : h->storage) {
            (void)value;
            if (a.sload(slot) != b.sload(slot)) return false;
        }
    return true;
}

struct Forms {
    u64 typed = 0, raw = 0;
};
void count_forms(Value v, Forms& f) {
    if (v.is(Op::ST, 3)) {
        Value loc = v[1];
        while (loc.is(Op::SF, 2) || loc.is(Op::SL, 1) || loc.is(Op::SBL, 1)) loc = loc[0];
        if (loc.is(Op::SR)) ++f.raw;
        else ++f.typed;
    }
    for (Value c : v.children()) count_forms(c, f);
}

std::string where(const exec::Outcome& o) {
    std::string s = o.line.nil() ? "" : dump(o.line);
    if (s.size() > 300) s = s.substr(0, 300) + "...";
    return s;
}

}  // namespace

TEST_CASE("storage: corpus (opt-in)") {
    const char* list = std::getenv("PANORAMIX_STORAGE_CORPUS");
    if (!list) return;
    const u64 limit = std::getenv("PANORAMIX_STORAGE_LIMIT") ? std::strtoull(std::getenv("PANORAMIX_STORAGE_LIMIT"), nullptr, 10) : ~u64(0);
    const u64 skip = std::getenv("PANORAMIX_STORAGE_SKIP") ? std::strtoull(std::getenv("PANORAMIX_STORAGE_SKIP"), nullptr, 10) : 0;
    const u64 show = std::getenv("PANORAMIX_STORAGE_SHOW") ? std::strtoull(std::getenv("PANORAMIX_STORAGE_SHOW"), nullptr, 10) : 3;
    init();
    std::ifstream in(list);
    std::string path;
    u64 n = 0, contracts = 0, failed = 0, fns = 0, same = 0, diff = 0, inconclusive = 0, bugs = 0, vars = 0;
    u64 getters = 0, shown = 0;
    Forms forms;
    i64 t_total = 0;
    while (std::getline(in, path)) {
        if (path.empty()) continue;
        if (n++ < skip) continue;
        if (contracts >= limit) break;
        ++contracts;
        std::ifstream f(path);
        std::stringstream ss;
        ss << f.rdbuf();
        auto bytes = hex::decode(ss.str());
        if (!bytes) continue;
        Budget budget{Budget::Limits{.memory = usize{4} << 30}};
        budget.attach_thread();
        std::string line = path.substr(path.rfind('/') + 1);
        try {
            auto ctx = Context::create(budget);
            ContextScope scope(*ctx);
            // the simplified stage, lot 8's traits on it (the analysed stage
            // before the storage forms, whether the driver makes them or not)
            driver::PipelineOptions o;
            o.threads = 1;
            o.keep = driver::keep_bit(driver::Stage::Simplified);
            o.db = sigdb::get();
            const driver::ContractResult r = driver::run_until(*bytes, driver::Stage::Simplified, o);
            const unsigned s = driver::stage_index(driver::Stage::Simplified);
            if (!r.kept[s]) {
                std::printf("%s: no simplified stage\n", line.c_str());
                budget.detach_thread();
                continue;
            }
            CodeMap map = analyse(*bytes);
            ContractShared shared;
            shared.code = *bytes;
            shared.map = &map;
            shared.db = o.db;
            if (const auto md = metadata(*bytes)) shared.lang = md->lang;
            std::vector<FunctionInfo> before, before_int;
            traits::analyse_stage(r.functions[s], before, shared);
            traits::analyse_stage(r.internals[s], before_int, shared);
            std::vector<FunctionInfo> after = before, after_int = before_int;
            std::shared_ptr<const StorageLayout> layout;
            const i64 t0 = platform::monotonic_ns();
            try {
                layout = storage::analyse(after, after_int, shared);
            } catch (const Error& e) {
                ++failed;
                std::printf("%s: FAILED %s\n", line.c_str(), e.what());
                layout = storage::rewrite_raw(after, after_int, shared.lang);
            }
            t_total += platform::monotonic_ns() - t0;
            vars += layout->vars.size();
            for (usize i = 0; i < after.size(); ++i) {
                if (after[i].trace != before[i].trace && before[i].read_only) {
                    // (a bytes getter: SALL)
                    std::vector<Value> todo{after[i].trace};
                    bool sall = false;
                    while (!todo.empty() && !sall) {
                        Value v = todo.back();
                        todo.pop_back();
                        if (v.is(Op::SALL)) sall = true;
                        for (Value c : v.children()) todo.push_back(c);
                    }
                    getters += sall;
                }
                count_forms(after[i].trace, forms);
            }
            exec::Program p0, p1;
            p0.functions = before;
            p0.internals = before_int;
            p0.shared = &shared;
            p1.functions = after;
            p1.internals = after_int;
            p1.shared = &shared;
            p1.layout = layout.get();
            exec::MachineLimits lim;
            lim.steps = 200000;
            exec::Machine m0(p0, lim), m1(p1, lim);
            u64 c_same = 0, c_diff = 0;
            for (usize i = 0; i < before.size(); ++i) {
                if (!before[i].trace.is_trace() || before[i].problem) continue;
                ++fns;
                for (u64 seed = 0; seed < 8; ++seed) {
                    CorpusWorld w0(seed, before[i], *bytes), w1(seed, before[i], *bytes);
                    const exec::Outcome o0 = m0.run(w0, before[i]);
                    const exec::Outcome o1 = m1.run(w1, after[i]);
                    if (o1.status == exec::Status::Bug && o0.status != exec::Status::Bug) {
                        ++bugs;
                        if (shown++ < show)
                            std::printf("  BUG %s fn %zu seed %llu: %s\n    at %s\n", line.c_str(), i, (unsigned long long)seed,
                                        o1.note.c_str(), where(o1).c_str());
                        continue;
                    }
                    if (!o0.halted() || !o1.halted()) {
                        ++inconclusive;
                        continue;
                    }
                    if (o0.status == o1.status && o0.data == o1.data && same_effects(w0, w1)) {
                        ++same;
                        ++c_same;
                    } else {
                        ++diff;
                        ++c_diff;
                        if (shown++ < show)
                            std::printf("  DIFF %s fn %zu (0x%08x) seed %llu: %s/%s data %zu/%zu effects %zu/%zu\n    raw at %s\n    "
                                        "new at %s\n",
                                        line.c_str(), i, before[i].selector, (unsigned long long)seed,
                                        exec::status_name(o0.status), exec::status_name(o1.status), o0.data.size(),
                                        o1.data.size(), w0.effects.size(), w1.effects.size(), where(o0).c_str(),
                                        where(o1).c_str());
                    }
                }
            }
            std::printf("%s: vars %zu same %llu diff %llu\n", line.c_str(), layout->vars.size(),
                        (unsigned long long)c_same, (unsigned long long)c_diff);
        } catch (const Error& e) {
            std::printf("%s: pipeline error %s\n", line.c_str(), e.what());
        } catch (const Abort& e) {
            std::printf("%s: abort %s\n", line.c_str(), e.what());
        }
        budget.detach_thread();
        std::fflush(stdout);
    }
    std::printf(
        "storage corpus: %llu contracts, %llu analyses failed, %llu functions, runs same %llu diff %llu inconclusive %llu "
        "bugs %llu; %llu vars, %llu bytes getters, forms typed %llu raw %llu; analysis %lld ms\n",
        (unsigned long long)contracts, (unsigned long long)failed, (unsigned long long)fns, (unsigned long long)same,
        (unsigned long long)diff, (unsigned long long)inconclusive, (unsigned long long)bugs, (unsigned long long)vars,
        (unsigned long long)getters, (unsigned long long)forms.typed, (unsigned long long)forms.raw,
        (long long)(t_total / 1000000));
    CHECK(diff == 0);
    CHECK(bugs == 0);
}
