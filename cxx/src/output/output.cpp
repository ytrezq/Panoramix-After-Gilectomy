// lot 10's entries (output.hpp): the texts, the JSON, --explain - on the
// printer (print.hpp); the ast's are ast.cpp's.
#include "output/output.hpp"

#include <format>
#include <string>
#include <vector>

#include "analysis/traits.hpp"
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

namespace {

// a trace's lines; raw: python's view of it before the traits and the
// storage (--explain's sections)
std::string trace_lines(Value trace, const TraceContext& ctx, u32 indent, bool raw)
{
    Out o(ctx.color);
    const ContractNames names = contract_names(ctx.storage, ctx.safemath, ctx.db);
    const FnEnv env(ctx.fn, ctx.db, trace, &names);
    Printer p(o, env);
    Printer::RawView view(p, raw);
    p.lines(trace, indent);
    if (o.s.empty()) {
        o.spaces(indent);
        o.put("stop\n");
    }
    return std::move(o.s);
}

}  // namespace

std::string print_trace(Value trace, const TraceContext& ctx, u32 indent)
{
    return trace_lines(trace, ctx, indent, false);
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
    // (python's explain runs while the function is decompiled: before its
    // params have names, before the storage analysis)
    out += trace_lines(trace, ctx, 2, true);
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
    // python's prettify(self.returns): str() of the list of its return lines
    // (find_f_list's order: the lines', depth first)
    std::vector<Value> returns;
    traits::returns_of(fn.trace, returns);
    std::string rets = "[";
    for (usize i = 0; i < returns.size(); ++i) {
        if (i)
            rets += ", ";
        python_repr(rets, returns[i]);
    }
    rets += "]";
    items.emplace_back("possible return values", rets);
    items.emplace_back("payable", fn.entry.nonpayable ? "False" : "True");
    items.emplace_back("read_only", fn.read_only ? "True" : "False");
    if (fn.is_const && !returns.empty()) {
        // python's self.const: its return line
        std::string c;
        python_repr(c, returns[0]);
        items.emplace_back("const", std::move(c));
    }
    if (fn.getter)
        if (const auto g = traits::getter_of(fn)) {
            // python's prettify(self.getter): the storage read (a tuple its
            // prettifier doesn't know), bool() of it; a struct's place
            std::string t;
            switch (g->kind) {
                case traits::Getter::Kind::Read:
                    if (g->value.is(Op::BOOL, 1) && g->value[0] == g->read) {
                        t = "bool(";
                        python_repr(t, g->read);
                        t += ')';
                    } else {
                        python_repr(t, g->read);
                    }
                    break;
                case traits::Getter::Kind::Struct:
                    t = "('struct', ('loc', ";
                    python_repr(t, g->read.is(Op::STORAGE, 3) ? g->read[2] : g->read);
                    t += "))";
                    break;
                case traits::Getter::Kind::Kitties:
                    t = std::format("('struct', ('loc', {}))", g->slot);
                    break;
            }
            items.emplace_back("getter for", std::move(t));
        }
    explain_text(out, "function traits", items, ctx.color);
}

}  // namespace pan::output
