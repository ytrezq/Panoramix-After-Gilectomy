// lot 10's entries (output.hpp): the texts, the JSON, --explain - on the
// printer (print.hpp); the ast's are ast.cpp's.
#include "output/output.hpp"

#include <format>
#include <string>
#include <vector>

#include "core/dump.hpp"
#include "driver/pipeline.hpp"
#include "output/print.hpp"

namespace pan::output {

using namespace detail;

std::string no_code_text(bool color)
{
    Out o(color);
    o.col(Col::gray, "# No code found for this contract.");
    return std::move(o.s);
}

std::string print_contract(const driver::ContractResult& r, const PrintOptions& opts)
{
    return contract_text(r, opts);
}

std::string print_function(const driver::ContractResult& r, const FunctionInfo& fn, const PrintOptions& opts)
{
    return std::move(function_text(&r, fn, opts).s);
}

std::string print_trace(Value trace, const TraceContext& ctx, u32 indent)
{
    Out o(ctx.color);
    const ContractNames names = contract_names(ctx.storage, ctx.safemath, ctx.db);
    const FnEnv env(ctx.fn, ctx.db, trace, &names);
    Printer p(o, env);
    p.lines(trace, indent);
    if (o.s.empty()) {
        o.spaces(indent);
        o.put("stop\n");
    }
    return std::move(o.s);
}

std::string print_exp(Value e, const TraceContext& ctx)
{
    Out o(ctx.color);
    const ContractNames names = contract_names(ctx.storage, ctx.safemath, ctx.db);
    const FnEnv env(ctx.fn, ctx.db, Value(), &names);
    Printer p(o, env);
    p.exp(e);
    return std::move(o.s);
}

std::string to_json(const driver::ContractResult& r, const PrintOptions& opts) { return contract_json(r, opts); }

void explain_trace(std::string& out, std::string_view title, Value trace, const TraceContext& ctx)
{
    Out o(ctx.color);
    o.put('\n');
    o.code(Col::green_back);
    o.put(' ');
    o.put(title);
    o.put(": ");
    o.end();
    o.put("\n\n");
    out += o.s;
    out += print_trace(trace, ctx, 2);
    out += "\n\n";
}

void explain_text(std::string& out, std::string_view title, std::span<const std::pair<std::string, std::string>> items,
                  bool color)
{
    Out o(color);
    o.put('\n');
    o.code(Col::blue_back);
    o.put(' ');
    o.put(title);
    o.put(": ");
    o.end();
    o.put("\n\n");
    for (const auto& [name, value] : items) {
        o.put(' ');
        o.code(Col::gray);
        o.put(name);
        o.end();
        o.put(": ");
        o.put(value);
        o.put('\n');
    }
    o.put('\n');
    out += o.s;
}

void explain_traits(std::string& out, const FunctionInfo& fn, const TraceContext& ctx)
{
    // python Function.analyse's: the possible return values, payable,
    // read_only, const, getter
    std::vector<std::pair<std::string, std::string>> items;
    std::string rets = "[";
    {
        std::vector<Value> todo{fn.trace};
        bool first = true;
        while (!todo.empty()) {
            const Value t = todo.back();
            todo.pop_back();
            if (!t.is_list())
                continue;
            for (const Value l : t.args()) {
                if (l.is(Op::RETURN)) {
                    if (!first)
                        rets += ", ";
                    first = false;
                    rets += print_exp(l[0], TraceContext{ctx.fn, ctx.db, false, ctx.storage, ctx.safemath});
                }
                if (l.is_expr())
                    for (const Value a : l.args())
                        if (a.is_list())
                            todo.push_back(a);
            }
        }
    }
    rets += "]";
    items.emplace_back("possible return values", rets);
    items.emplace_back("payable", fn.entry.nonpayable ? "False" : "True");
    items.emplace_back("read_only", fn.read_only ? "True" : "False");
    if (fn.is_const)
        items.emplace_back("const", "True");
    if (fn.getter)
        items.emplace_back("getter for", "True");
    explain_text(out, "function traits", items, ctx.color);
}

}  // namespace pan::output
