// Lot 4 over a corpus, checked by execution (opt-in:
// PANORAMIX_MEM_CORPUS=a list of .hex paths, PANORAMIX_MEM_LIMIT=N the first
// N, PANORAMIX_MEM_SKIP=N skipped first, PANORAMIX_MEM_SIGDB=a signature
// database for typed calls, PANORAMIX_MEM_QUIET=1 a line per contract).
//
// Each contract: lot 5's raw traces (stage "raw"), and the same traces with
// the memory model applied (in stage "whiles"'s place): every SETMEM split
// (split_setmem) and every STORE (split_store), every memory read the
// memory model can assemble from the writes before it on its path filled
// (MemState::read in bytes, read_word in words), the state carried along
// the path (forgotten at loops' heads, internal calls; the storage and
// state reads after stores and calls). Both run by lot 11's machine against
// evmone on the same calls (validate::check_contract); a difference the raw
// stage hasn't is the memory model's.
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

#include "algebra/construct.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/contract.hpp"
#include "core/dump.hpp"
#include "core/errors.hpp"
#include "core/smallvec.hpp"
#include "hex.hpp"
#include "mem/memory.hpp"
#include "sigdb.hpp"
#include "validate/stage_check.hpp"
#include "vm/vm.hpp"

using namespace pan;

namespace {

struct PassCounts {
    u64 reads = 0, filled = 0, setmems = 0, setmems_split = 0, stores = 0, stores_split = 0;
    u32 show = 0;  // examples of splits and fills printed (PANORAMIX_MEM_SHOW)
};

// the memory model over a trace, along its paths
struct MemPass {
    PassCounts& n;
    bool fill_reads = true;

    // the operands of e that are bytes
    static bool bytes_operand(Value e, u32 i) {
        switch (e.op()) {
            case Op::SIZED: return i == 1 && mem::is_bytes(e[1]);
            case Op::SETMEM: return i == 1 && mem::is_bytes(e[1]);
            default: break;
        }
        for (u8 k : mem::byte_operands(e))
            if (k == i) return true;
        return false;
    }

    Value expr(Value e, bool bytes_ctx, const mem::MemState& st) {
        check_stack();
        if (!e.has_flags(F_MEM) || !e.is_expr()) return e;
        if (e.is(Op::MEM, 1) && mem::is_range(e[0])) {
            Value r = e[0];
            Value r2 = mem::make_range(expr(r[0], false, st), expr(r[1], false, st));
            ++n.reads;
            if (fill_reads) {
                std::optional<Value> got = bytes_ctx ? st.read(r2) : st.read_word(r2);
                if (got) {
                    ++n.filled;
                    if (n.show) {
                        --n.show;
                        std::printf("  fill %s %s\n     -> %s\n", bytes_ctx ? "bytes" : "word", dump(r2).c_str(),
                                    dump(*got).c_str());
                    }
                    return *got;
                }
            }
            return r2 == r ? e : mk(Op::MEM, r2);
        }
        SmallVec<Value, 8> args;
        bool changed = false;
        for (u32 i = 0; i < e.size(); ++i) {
            Value a = e[i];
            Value b = a.is_list() ? a : expr(a, bytes_operand(e, i), st);
            changed |= a != b;
            args.push_back(b);
        }
        if (!changed) return e;
        return alg::apply(e.op(), args.span());
    }

    // the lines of a trace; *falls: its end is reached (no halt, no goto)
    Value trace(Value t, mem::MemState& st, bool* falls) {
        check_stack();
        SmallVec<Value, 32> out;
        bool f = true;
        for (Value l : t.args()) {
            poll();
            line(l, st, out, &f);
            if (!f) break;
        }
        if (falls) *falls = f;
        return mk_trace(out.span());
    }

    void line(Value l, mem::MemState& st, SmallVec<Value, 32>& out, bool* falls) {
        auto operands = [&](Value x) {
            SmallVec<Value, 8> args;
            bool changed = false;
            for (u32 i = 0; i < x.size(); ++i) {
                Value a = x[i];
                Value b = a.is_list() ? a : expr(a, bytes_operand(x, i), st);
                changed |= a != b;
                args.push_back(b);
            }
            return changed ? mk(x.op(), args.span()) : x;
        };
        switch (l.op()) {
            case Op::SETMEM: {
                Value l2 = operands(l);
                ++n.setmems;
                auto parts = mem::split_setmem(l2);
                if (parts.size() > 1) {
                    ++n.setmems_split;
                    if (n.show) {
                        --n.show;
                        std::printf("  split %s\n", dump(l2).c_str());
                        for (Value p : parts) std::printf("     -> %s\n", dump(p).c_str());
                    }
                }
                for (Value p : parts) {
                    st.write(mem::as_write(p));
                    out.push_back(p);
                }
                return;
            }
            case Op::STORE: {
                Value l2 = operands(l);
                ++n.stores;
                auto parts = mem::split_store(l2);
                if (parts.size() > 1) {
                    ++n.stores_split;
                    if (n.show) {
                        --n.show;
                        std::printf("  split %s\n", dump(l2).c_str());
                        for (Value p : parts) std::printf("     -> %s\n", dump(p).c_str());
                    }
                }
                for (Value p : parts) out.push_back(p);
                st.forget_flags(F_STORAGE);
                return;
            }
            case Op::IF: {
                Value c = expr(l[0], false, st);
                mem::MemState st_t = st, st_f = st;
                bool ft = true, ff = true;
                Value t = trace(l[1], st_t, &ft);
                Value e = trace(l[2], st_f, &ff);
                out.push_back(mk(Op::IF, c, t, e));
                if (ft && ff) {
                    st_t.meet(st_f);
                    st = st_t;
                } else if (ft) {
                    st = st_t;
                } else if (ff) {
                    st = st_f;
                } else {
                    *falls = false;
                }
                return;
            }
            case Op::LABEL:
                // a loop's head: what the iterations before wrote isn't known
                st.clear();
                out.push_back(l);
                return;
            case Op::GOTO:
                out.push_back(operands(l));
                *falls = false;
                return;
            case Op::SETVAR: {
                Value l2 = operands(l);
                st.forget_name(l2[0]);
                out.push_back(l2);
                return;
            }
            case Op::CALL:
            case Op::CALLCODE:
            case Op::DELEGATECALL:
            case Op::STATICCALL:
            case Op::CREATE:
            case Op::CREATE2:
            case Op::PRECOMPILED:
            case Op::TSTORE:
            case Op::SELFDESTRUCT:
                out.push_back(operands(l));
                st.forget_flags(F_STORAGE | F_STATE);
                return;
            case Op::INTERNAL:
                out.push_back(operands(l));
                st.clear();
                return;
            case Op::ASM:
                out.push_back(l);
                return;
            default:
                out.push_back(l.is_expr() ? operands(l) : l);
                if (l.op() != Op::NONE && has(l.op(), HALT)) *falls = false;
                return;
        }
    }
};

// lot 5's raw traces, with the waves of the recursive internal functions
// (stagecheck's raw pipeline)
void raw_stage(validate::Decompiled& c, Budget& budget) {
    constexpr unsigned max_waves = 8;
    auto& fns = c.functions[0];
    auto& internals = c.internals[0];
    fns = vm::discover(c.shared, budget);
    std::vector<vm::InternalEntry> known;
    std::vector<std::pair<bool, usize>> todo;
    for (usize i = 0; i < fns.size(); ++i) todo.emplace_back(false, i);
    for (unsigned wave = 0; wave < max_waves && !todo.empty(); ++wave) {
        std::vector<vm::InternalEntry> found;
        std::vector<std::pair<bool, usize>> again;
        for (const auto& [internal, i] : todo) {
            auto& f = internal ? internals[i] : fns[i];
            vm::VmOptions opts;
            opts.known_internals = &known;
            try {
                auto r = vm::run_function(c.shared, f, opts);
                f.trace = r.trace;
                f.calls = std::move(r.calls);
                f.loops = std::move(r.loops);
                f.problem.reset();
                bool new_ones = false;
                for (const auto& e : r.found_internals)
                    if (std::find(known.begin(), known.end(), e) == known.end()) {
                        new_ones = true;
                        if (std::find(found.begin(), found.end(), e) == found.end()) found.push_back(e);
                    }
                if (new_ones) again.emplace_back(internal, i);
            } catch (const Error&) {
                f.trace = Value{};
                f.problem = 0;
            }
        }
        todo = std::move(again);
        if (found.empty()) break;
        for (const auto& e : found) {
            known.push_back(e);
            FunctionInfo f;
            f.kind = FunctionInfo::Kind::Internal;
            f.entry_pc = e.entry;
            f.params.resize(e.nargs);
            todo.emplace_back(true, internals.size());
            internals.push_back(std::move(f));
        }
    }
    for (const auto& [internal, i] : todo)
        if (internal && internals[i].trace.nil()) internals[i].problem = 0;
    c.made[0] = true;
}

FunctionInfo with_memory_model(const FunctionInfo& f, PassCounts& n) {
    FunctionInfo g = f;
    if (f.trace.nil()) return g;
    MemPass pass{n};
    // (msize read: what the run touches must stay as it is)
    pass.fill_reads = !f.trace.has_flags(F_MSIZE) && !(f.entry.entry_lines.is_list() && f.entry.entry_lines.has_flags(F_MSIZE));
    const bool internal = f.kind == FunctionInfo::Kind::Internal;
    mem::MemState st(!internal);
    if (!internal && f.entry.entry_lines.is_list()) {
        PassCounts ignored;
        MemPass seed{ignored};
        seed.fill_reads = false;
        bool falls = true;
        seed.trace(f.entry.entry_lines, st, &falls);
    }
    bool falls = true;
    g.trace = pass.trace(f.trace, st, &falls);
    return g;
}

std::string stage_line(const validate::StageResult& r) {
    char buf[200];
    std::snprintf(buf, sizeof buf, "same %lu diff %lu inc %lu bugs %lu unsized %lu", r.same, r.different,
                  r.inconclusive, r.bugs, r.unsized);
    return buf;
}

}  // namespace

TEST_CASE("mem: corpus by execution (PANORAMIX_MEM_CORPUS)") {
    const char* list = std::getenv("PANORAMIX_MEM_CORPUS");
    if (!list) return;
    const char* lim = std::getenv("PANORAMIX_MEM_LIMIT");
    const char* skp = std::getenv("PANORAMIX_MEM_SKIP");
    const char* dbp = std::getenv("PANORAMIX_MEM_SIGDB");
    const bool quiet = std::getenv("PANORAMIX_MEM_QUIET") != nullptr;
    const unsigned long limit = lim ? std::strtoul(lim, nullptr, 10) : 0;
    const unsigned long skip = skp ? std::strtoul(skp, nullptr, 10) : 0;
    std::unique_ptr<sigdb::Database> db;
    if (dbp) db = sigdb::Database::open(dbp);
    std::ifstream in(list);
    std::string path;
    std::vector<std::string> paths;
    while (std::getline(in, path))
        if (!path.empty()) paths.push_back(path);
    init();
    PassCounts total;
    unsigned long done = 0, index = 0, worse = 0, failed = 0;
    unsigned long same[2] = {}, diff[2] = {}, bugs[2] = {}, inc[2] = {};
    for (const std::string& p : paths) {
        if (index++ < skip) continue;
        if (limit && done >= limit) break;
        ++done;
        std::ifstream f(p, std::ios::binary);
        std::stringstream ss;
        ss << f.rdbuf();
        auto bytes = hex::decode(ss.str());
        if (!bytes) continue;
        PassCounts n;
        if (const char* sh = std::getenv("PANORAMIX_MEM_SHOW")) n.show = u32(std::strtoul(sh, nullptr, 10));
        validate::CheckConfig cfg;
        cfg.upto = validate::Stage::whiles;
        cfg.db = db.get();
        cfg.timeout_ns = 600 * limits::SEC;
        cfg.keep = 2;
        auto pipeline = [&](validate::Decompiled& c, validate::Stage, Budget& budget) {
            raw_stage(c, budget);
            for (const auto& fn : c.functions[0]) c.functions[1].push_back(with_memory_model(fn, n));
            for (const auto& fn : c.internals[0]) c.internals[1].push_back(with_memory_model(fn, n));
            c.made[1] = true;
        };
        validate::StageReport r = validate::check_contract(*bytes, cfg, pipeline);
        std::string name = p.substr(p.rfind('/') + 1);
        if (!r.ran) {
            ++failed;
            std::printf("%-40s FAILED %s\n", name.c_str(), r.failure.c_str());
            continue;
        }
        const auto& s0 = r.stages[0];
        const auto& s1 = r.stages[1];
        const bool bad = s1.different + s1.bugs > s0.different + s0.bugs;
        worse += bad;
        for (int k = 0; k < 2; ++k) {
            same[k] += r.stages[k].same;
            diff[k] += r.stages[k].different;
            bugs[k] += r.stages[k].bugs;
            inc[k] += r.stages[k].inconclusive;
        }
        total.reads += n.reads;
        total.filled += n.filled;
        total.setmems += n.setmems;
        total.setmems_split += n.setmems_split;
        total.stores += n.stores;
        total.stores_split += n.stores_split;
        std::printf("%-40s raw: %s | mem: %s | reads %llu filled %llu setmems %llu/%llu stores %llu/%llu%s\n",
                    name.c_str(), stage_line(s0).c_str(), stage_line(s1).c_str(), (unsigned long long)n.reads,
                    (unsigned long long)n.filled, (unsigned long long)n.setmems_split, (unsigned long long)n.setmems,
                    (unsigned long long)n.stores_split, (unsigned long long)n.stores, bad ? " WORSE" : "");
        if (bad && !quiet)
            for (const auto& x : s1.examples)
                std::printf("    [%s] %s\n      %s\n      where: %s\n      expected: %s\n      actual: %s\n",
                            validate::category_name(x.category), x.call.c_str(), x.message.c_str(), x.where.c_str(),
                            x.expected.c_str(), x.actual.c_str());
        std::fflush(stdout);
    }
    std::printf("TOTAL %lu contracts (%lu failed): raw same %lu diff %lu bugs %lu inc %lu | mem same %lu diff %lu bugs "
                "%lu inc %lu | worse %lu | reads %llu filled %llu setmems split %llu/%llu stores split %llu/%llu\n",
                done, failed, same[0], diff[0], bugs[0], inc[0], same[1], diff[1], bugs[1], inc[1], worse,
                (unsigned long long)total.reads, (unsigned long long)total.filled,
                (unsigned long long)total.setmems_split, (unsigned long long)total.setmems,
                (unsigned long long)total.stores_split, (unsigned long long)total.stores);
    CHECK(worse == 0);
}
