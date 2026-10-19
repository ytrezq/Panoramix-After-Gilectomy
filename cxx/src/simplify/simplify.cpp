// The simplifier's driver and passes (simplify.hpp) - first a stub: every
// pass returns its input (trivially correct).
#include "simplify/simplify.hpp"

#include "core/errors.hpp"

namespace pan::simplify {

Value simplify_exp(Value e) { return e; }
Value simplify_trace(Value trace, const SimplifyOptions&, ExplainHook*) { return trace; }
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
Value simplify_exps(Value trace) { return trace; }
Value cleanup_vars(Value trace) { return trace; }
Value cleanup_mems(Value trace) { return trace; }
Value precompiled_results(Value trace) { return trace; }
Value min_ifs(Value trace) { return trace; }
Value split_lines(Value trace) { return trace; }
Value replace_bytes_or_string_length(Value trace) { return trace; }
Value cleanup_conds(Value trace) { return trace; }
Value cleanup_mul_1(Value trace) { return trace; }
Value max_to_add(Value trace) { return trace; }
Value postprocess_exps(Value trace) { return trace; }
Value fix_storages(Value trace) { return trace; }
Value readability(Value trace) { return trace; }
Value short_circuits(Value trace) { return trace; }

}  // namespace pan::simplify
