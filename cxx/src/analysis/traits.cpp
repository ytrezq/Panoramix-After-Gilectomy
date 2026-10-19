// The function traits (traits.hpp) - stub: the trace as it is, every
// function payable, no params (lot 8 at work).
#include "analysis/traits.hpp"

#include "core/errors.hpp"
#include "sigdb.hpp"

namespace pan::traits {

void analyse_function(FunctionInfo& fn, const ContractShared&, const Options&) { fn.payable = !fn.entry.nonpayable; }

void analyse_stage(std::span<const FunctionInfo> in, std::vector<FunctionInfo>& out, const ContractShared& shared,
                   const Options& opts)
{
    out.assign(in.begin(), in.end());
    for (FunctionInfo& f : out)
        if (!f.problem && f.trace.is_trace())
            analyse_function(f, shared, opts);
}

void returns_of(Value, std::vector<Value>&) {}

std::optional<Getter> getter_of(const FunctionInfo&) { return std::nullopt; }

Value const_of(const FunctionInfo&) { return NIL; }

std::vector<ParamInfo> abi_params(const sigdb::Entry&) { return {}; }

}  // namespace pan::traits
