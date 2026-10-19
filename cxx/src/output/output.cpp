// lot 10's outputs: the stubs of the published header (output.hpp) until
// the real ones land - trivially correct results.
#include "output/output.hpp"

#include "core/dump.hpp"
#include "driver/pipeline.hpp"

namespace pan::output {

Value fold(Value trace) { return trace; }

Value make_ast(const FunctionInfo& fn, const AstOptions&) { return fn.trace; }

void ast_stage(std::span<const FunctionInfo> in, std::vector<FunctionInfo>& out, const AstStageOptions&)
{
    out.assign(in.begin(), in.end());
}

std::string no_code_text(bool color)
{
    return color ? "\033[38;5;8m# No code found for this contract.\033[0m" : "# No code found for this contract.";
}

std::string print_trace(Value trace, const TraceContext&, u32 indent)
{
    std::string out;
    const std::string text = trace.is_trace() && trace.size() ? dump_trace(trace) : std::string("stop");
    usize start = 0;
    while (start < text.size()) {
        usize end = text.find('\n', start);
        if (end == std::string::npos)
            end = text.size();
        out.append(indent, ' ');
        out.append(text, start, end - start);
        out += '\n';
        start = end + 1;
    }
    return out;
}

std::string print_exp(Value e, const TraceContext&) { return dump(e); }

std::string print_function(const driver::ContractResult&, const FunctionInfo& fn, const PrintOptions&)
{
    return "def ?:\n" + print_trace(fn.trace);
}

std::string print_contract(const driver::ContractResult& r, const PrintOptions& opts)
{
    std::string t = "# Palkeoramix decompiler. \n\n";
    for (const FunctionInfo& f : r.final_functions())
        if (!f.problem)
            t += print_function(r, f, opts) + "\n";
    return t;
}

std::string to_json(const driver::ContractResult&, const PrintOptions&) { return "{}"; }

void explain_trace(std::string& out, std::string_view title, Value trace, const TraceContext& ctx)
{
    out += "\n ";
    out += title;
    out += ": \n\n";
    out += print_trace(trace, ctx);
    out += "\n\n";
}

void explain_text(std::string& out, std::string_view title, std::span<const std::pair<std::string, std::string>> items,
                  bool)
{
    out += "\n ";
    out += title;
    out += ": \n\n";
    for (const auto& [name, value] : items)
        out += " " + name + ": " + value + "\n";
    out += "\n";
}

void explain_traits(std::string&, const FunctionInfo&, const TraceContext&) {}

}  // namespace pan::output
