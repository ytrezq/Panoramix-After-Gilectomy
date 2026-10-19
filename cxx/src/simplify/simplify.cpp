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
#include "simplify/internal.hpp"

namespace pan::simplify {

namespace {

// python variable_values: every (name, value) a SETVAR sets anywhere
// (WHILE / CONTINUE / LABEL / GOTO setvars too), each pair once, in a
// deterministic order
std::vector<std::pair<Value, Value>> variable_values(Value trace) {
    std::vector<std::pair<Value, Value>> out;
    SmallVec<Value, 64> todo{trace};
    MemoSet<Value> seen;
    MemoSet<Key2> pairs;
    while (!todo.empty()) {
        poll();
        Value v = todo.back();
        todo.pop_back();
        if (!(v.is_list() || v.is_expr())) continue;
        if (v.is_expr() && !has(v.op(), LINE)) continue;
        if (!seen.add(v)) continue;
        if (v.is(Op::SETVAR, 2)) {
            if (pairs.add(Key2{v[0].raw(), v[1].raw()})) out.emplace_back(v[0], v[1]);
            continue;
        }
        for (Value x : v.children()) todo.push_back(x);
    }
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
        Value old;
        for (u32 round = 0; round < opts_.max_rounds && trace != old && !timed_out(); ++round) {
            old = trace;
            trace = step(simplify_exps(trace), ExplainStage::SimplifyExpressions);
            trace = step(cleanup_vars(trace), ExplainStage::CleanupVariables);
            trace = step(cleanup_mems(trace), ExplainStage::CleanupMems);
            trace = step(precompiled_results(trace), ExplainStage::PrecompiledResults);
            trace = step(min_ifs(trace), ExplainStage::Minimums);
            trace = step(split_lines(trace), ExplainStage::SplitSetmemsStorages);
            trace = step(cleanup_vars(trace), ExplainStage::CleanupVars);
            trace = step(simplify_exps(trace), ExplainStage::SimplifyExpressions);
            trace = step(cleanup_mul_1(trace), ExplainStage::SimplifyExpressions);
            trace = step(replace_bytes_or_string_length(trace), ExplainStage::ReplaceStorageWithLength);
            trace = step(cleanup_conds(trace), ExplainStage::CleanupUnusedIfs);
            // (lot 6's loop_to_setmem and propagate_storage_in_loops go here)
            trace = maybe_compact(trace);
        }
        if (!opts_.final_passes) return trace;
        // the final passes (python: they would break the rounds)
        if (!timed_out()) {
            for (int k = 0; k < 3; ++k) trace = cleanup_mems(trace);
            trace = simplify_exps(trace);
            trace = cleanup_vars(trace);
        }
        trace = max_to_add(trace);
        trace = postprocess_exps(trace);
        trace = step(trace, ExplainStage::Heuristics);
        trace = precompiled_results(trace);
        trace = step(cleanup_conds(trace), ExplainStage::FinalCleanup);
        trace = fix_storages(trace);
        trace = step(cleanup_conds(trace), ExplainStage::CleaningStorages);
        trace = readability(trace);
        trace = step(cleanup_mul_1(trace), ExplainStage::NicerNames);
        trace = cleanup_conds(trace);
        return trace;
    }

private:
    Value step(Value trace, ExplainStage s) {
        if (explain_) explain_->stage(s, trace);
        return trace;
    }
    bool timed_out() const { return deadline_ != 0 && platform::monotonic_ns() > deadline_; }
    Value maybe_compact(Value trace) {
        if (!opts_.compact) return trace;
        Context& c = cx();
        if (c.usage() <= compact_threshold(c.budget.limits().memory)) return trace;
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
    f.msize = trace.has_flags(F_MSIZE);
    f.dubious = opts.dubious;
    Driver d(opts, explain);
    return d.run(trace);
}

void simplify_function(FunctionInfo& fn, const SimplifyOptions& opts, ExplainHook* explain) {
    fn.trace = simplify_trace(fn.trace, opts, explain);
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
