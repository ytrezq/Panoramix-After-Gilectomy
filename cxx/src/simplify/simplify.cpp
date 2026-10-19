// The simplifier's driver (python simplify_trace / _simplify_trace, asm
// simplify.s): the trace's variables installed in the algebra, the rounds of
// passes in python's order until nothing changes (or the step timeout), then
// the final passes.
#include "simplify/simplify.hpp"

#include <algorithm>
#include <utility>
#include <vector>

#include "algebra/ranges.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/errors.hpp"
#include "core/order.hpp"
#include "core/platform.hpp"
#include "loops/loops.hpp"
#include "simplify/internal.hpp"

namespace pan::simplify {

namespace {

thread_local SimplifyStats tl_stats;

// times a pass into the thread's stats
template <class F>
Value timed(u32 bit_index, F&& f) {
    const i64 t0 = platform::monotonic_ns();
    Value r = f();
    tl_stats.ns[bit_index] += u64(platform::monotonic_ns() - t0);
    ++tl_stats.runs[bit_index];
    return r;
}

// python variable_values: every (name, value) a SETVAR sets anywhere
// (WHILE / CONTINUE / LABEL / GOTO setvars too), each pair once, in a
// deterministic order
std::vector<std::pair<Value, Value>> variable_values(Value trace) {
    std::vector<std::pair<Value, Value>> out;
    SmallVec<Value, 64> todo{trace};
    MemoSet<Value> seen;
    MemoSet<Key2> pairs;
    MemoSet<Value> volatile_names;  // (set otherwise than by a SETVAR)
    while (!todo.empty()) {
        poll();
        Value v = todo.back();
        todo.pop_back();
        if (!(v.is_list() || v.is_expr())) continue;
        if (v.is_expr() && !has(v.op(), LINE)) continue;
        if (!seen.add(v)) continue;
        // (variables set otherwise: by a precompile's call, an internal call)
        if (v.is(Op::PRECOMPILED, 4) && v[1].is_name()) volatile_names.add(v[1]);
        if (v.is(Op::INTERNAL, 3))
            if (Value results = v[2]; results.is_list())
                for (Value n : results.args()) volatile_names.add(n);
        if (v.is(Op::SETVAR, 2)) {
            if (pairs.add(Key2{v[0].raw(), v[1].raw()})) out.emplace_back(v[0], v[1]);
            continue;
        }
        for (Value x : v.children()) todo.push_back(x);
    }
    // (a variable also set by a precompile's or an internal call: values
    // not known, left out: any word)
    std::erase_if(out, [&](const auto& p) { return volatile_names.contains(p.first); });
    std::sort(out.begin(), out.end(), [](const auto& a, const auto& b) {
        int c = compare(a.first, b.first);
        return c != 0 ? c < 0 : compare(a.second, b.second) < 0;
    });
    return out;
}

class Driver {
public:
    Driver(const SimplifyOptions& o, ExplainHook* e) : opts_(o), explain_(e) {
        i64 t = o.timeout_ns;
        if (t == 0) t = scaled_timeout(limits::WHILES_TIMEOUT_NS);
        deadline_ = t < 0 || t >= limits::NO_TIMEOUT_NS ? 0 : platform::monotonic_ns() + t;
    }

    Value run(Value trace) {
        const u32 p = opts_.passes;
        auto on = [&](u32 bit) { return (p & bit) != 0; };
        for (u32 round = 0; round < opts_.max_rounds && !timed_out(); ++round) {
            const Value old = trace;
            if (on(P_EXPS)) trace = step(timed(0, [&] { return simplify_exps(trace); }), ExplainStage::SimplifyExpressions);
            if (on(P_VARS)) trace = step(timed(1, [&] { return cleanup_vars(trace); }), ExplainStage::CleanupVariables);
            if (on(P_MEMS)) trace = step(timed(2, [&] { return cleanup_mems(trace); }), ExplainStage::CleanupMems);
            if (on(P_PRECOMPILED))
                trace = step(timed(3, [&] { return precompiled_results(trace); }), ExplainStage::PrecompiledResults);
            if (on(P_MIN_IFS)) trace = step(timed(4, [&] { return min_ifs(trace); }), ExplainStage::Minimums);
            if (on(P_SPLIT)) trace = step(timed(5, [&] { return split_lines(trace); }), ExplainStage::SplitSetmemsStorages);
            if (on(P_VARS)) trace = step(timed(1, [&] { return cleanup_vars(trace); }), ExplainStage::CleanupVars);
            if (on(P_EXPS)) trace = step(timed(0, [&] { return simplify_exps(trace); }), ExplainStage::SimplifyExpressions);
            trace = step(cleanup_mul_1(trace), ExplainStage::SimplifyExpressions);
            if (on(P_LENGTH))
                trace = step(timed(6, [&] { return replace_bytes_or_string_length(trace); }),
                             ExplainStage::ReplaceStorageWithLength);
            if (on(P_CONDS)) trace = step(timed(7, [&] { return cleanup_conds(trace); }), ExplainStage::CleanupUnusedIfs);
            if (on(P_LOOPS)) {
                trace = step(timed(9, [&] { return loops::loops_to_setmems(trace, loops::RewriteOptions{opts_.dubious}); }),
                             ExplainStage::ConvertLoopsToSetmems);
                trace = step(timed(9, [&] { return loops::propagate_storage_in_loops(trace); }),
                             ExplainStage::MoveLoopIndexes);
            }
            if (trace == old) break;
            trace = maybe_compact(trace);
        }
        if (!opts_.final_passes || !on(P_FINAL)) return trace;
        // the final passes (python: they would break the rounds)
        const i64 f0 = platform::monotonic_ns();
        if (!timed_out()) {
            if (on(P_MEMS))
                for (int k = 0; k < 3; ++k) trace = timed(2, [&] { return cleanup_mems(trace); });
            if (on(P_EXPS)) trace = timed(0, [&] { return simplify_exps(trace); });
            if (on(P_VARS)) trace = timed(1, [&] { return cleanup_vars(trace); });
        }
        struct Final {
            i64 f0;
            ~Final() { tl_stats.ns[8] += u64(platform::monotonic_ns() - f0); }
        } final_time{f0};
        trace = max_to_add(trace);
        trace = postprocess_exps(trace);
        trace = step(trace, ExplainStage::Heuristics);
        if (on(P_PRECOMPILED)) trace = precompiled_results(trace);
        if (on(P_CONDS)) trace = step(cleanup_conds(trace), ExplainStage::FinalCleanup);
        trace = fix_storages(trace);
        if (on(P_CONDS)) trace = step(cleanup_conds(trace), ExplainStage::CleaningStorages);
        trace = readability(trace);
        trace = step(cleanup_mul_1(trace), ExplainStage::NicerNames);
        if (on(P_CONDS)) trace = cleanup_conds(trace);
        return trace;
    }

private:
    Value step(Value trace, ExplainStage s) {
        if (explain_) explain_->stage(s, trace);
        return trace;
    }
    bool timed_out() const { return deadline_ != 0 && platform::monotonic_ns() > deadline_; }
    // (every Value the run holds is among the roots or in a state that
    // imports it: the trace, the caller's roots, the run's flags' entry lines)
    Value maybe_compact(Value trace) {
        if (!opts_.compact) return trace;
        Context& c = cx();
        const usize threshold =
            opts_.compact_threshold ? opts_.compact_threshold : compact_threshold(c.budget.limits().memory);
        if (c.usage() <= threshold) return trace;
        std::vector<Value> roots;
        roots.reserve(opts_.compact_roots.size() + 1);
        roots.push_back(trace);
        for (Value v : opts_.compact_roots) roots.push_back(v);
        c.compact(roots);
        for (usize i = 0; i < opts_.compact_roots.size(); ++i) opts_.compact_roots[i] = roots[i + 1];
        return roots[0];
    }

    SimplifyOptions opts_;
    ExplainHook* explain_;
    i64 deadline_ = 0;
};

}  // namespace

Value simplify_trace(Value trace, const SimplifyOptions& opts, ExplainHook* explain) {
    if (!trace.is_list()) return trace;
    const auto values = variable_values(trace);
    // (small_words: none assumed yet - the memory model keeps its own
    // assumptions)
    alg::set_variables(values, {});
    struct Clear {
        ~Clear() { alg::clear_variables(); }
    } clear;
    RunFlags& f = run_flags();
    f.msize = trace.has_flags(F_MSIZE) || (opts.entry_lines.is_list() && opts.entry_lines.has_flags(F_MSIZE));
    f.dubious = opts.dubious;
    f.entry_lines = opts.entry_lines;
    f.fresh = opts.fresh_memory;
    struct Reset {
        ~Reset() { run_flags() = RunFlags{}; }
    } reset;
    SimplifyOptions o = opts;
    o.entry_lines = Value();  // (run_flags() holds them, through compactions)
    Driver d(o, explain);
    return d.run(trace);
}

SimplifyStats& simplify_stats() noexcept { return tl_stats; }

void simplify_function(FunctionInfo& fn, const SimplifyOptions& opts, ExplainHook* explain) {
    SimplifyOptions o = opts;
    o.entry_lines = fn.entry.entry_lines;
    o.fresh_memory = fn.kind != FunctionInfo::Kind::Internal;
    fn.trace = simplify_trace(fn.trace, o, explain);
}

void simplify_stage(const std::vector<FunctionInfo>& in, std::vector<FunctionInfo>& out, const SimplifyOptions& opts) {
    out = in;
    for (FunctionInfo& f : out) {
        if (f.problem || f.trace.nil()) continue;
        try {
            simplify_function(f, opts);
        } catch (const Error&) {
            f.trace = Value();
            f.problem = 0;
        }
    }
}

}  // namespace pan::simplify
