// lot 10's outputs: the first bodies of the published header (output.hpp),
// until the printer lands - what lot 12's placeholders printed (the
// header, the problems, the functions by priority, the internal functions,
// --repr; the JSON's problems, functions, internal), the traces as
// S-expressions (core/dump.hpp).
#include "output/output.hpp"

#include <algorithm>
#include <format>
#include <string>
#include <vector>

#include "core/dump.hpp"
#include "driver/pipeline.hpp"
#include "hex.hpp"

namespace pan::output {

namespace {

// a text's size past which it isn't made (the asm's PM_BYTES_MAX)
constexpr usize TEXT_MAX = usize{16} << 20;

struct Colors {
    explicit Colors(bool on)
        : gray(on ? "\033[38;5;8m" : ""),
          end(on ? "\033[0m" : ""),
          fail(on ? "\033[91m" : ""),
          header(on ? "\033[95m" : ""),
          green_back(on ? "\033[42;1m\033[38;5;0m" : ""),
          blue_back(on ? "\033[43;1m\033[38;5;0m" : "")
    {
    }
    std::string_view gray, end, fail, header, green_back, blue_back;
};

// the lines of a trace, each indented (python's pprint_logic, for now)
void append_lines(std::string& out, Value trace, usize indent)
{
    if (!trace.is_trace() || trace.size() == 0) {
        out.append(indent, ' ');
        out += "stop\n";
        return;
    }
    const std::string text = dump_trace(trace);
    if (text.size() > TEXT_MAX) {
        out.append(indent, ' ');
        out += std::format("# (a trace of {} bytes of text)\n", text.size());
        return;
    }
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
}

// does the trace hold a line of op, at any depth (python: "selfdestruct" in str(trace))
bool has_line(Value trace, Op op)
{
    std::vector<Value> todo{trace};
    while (!todo.empty()) {
        const Value t = todo.back();
        todo.pop_back();
        if (!t.is_trace())
            continue;
        for (const Value l : t.args()) {
            if (l.is(op))
                return true;
            if (l.is_expr())
                for (const Value a : l.args())
                    if (a.is_trace())
                        todo.push_back(a);
        }
    }
    return false;
}

const vm::InternalEntry* record_of(const driver::ContractResult& r, const FunctionInfo& f)
{
    for (const vm::InternalEntry& e : r.internal_entries)
        if (e.entry == f.entry_pc)
            return &e;
    return nullptr;
}

std::string function_text(const FunctionInfo& f, const sigdb::Database* db, const Colors& c)
{
    std::string t = std::format("{}def {}{}:\n", c.header, c.end, hex::escape(driver::function_name(db, f)));
    append_lines(t, f.trace, 2);
    t.pop_back();  // (python's "\n".join of the lines)
    return t;
}

std::string internal_text(const FunctionInfo& f, const vm::InternalEntry* e, const Colors& c)
{
    std::string params;
    const u32 nargs = e ? e->nargs : u32(f.params.size());
    for (u32 k = 0; k < nargs; ++k)
        params += std::format("{}_param{}", k ? ", " : "", k + 1);
    std::string t = std::format("{}def {}internal_0x{:x}({}): {}# recursive, a call takes {} of the 1024 words of the stack{}\n",
                                c.header, c.end, f.entry_pc, params, c.gray, e ? e->frame : 0, c.end);
    append_lines(t, f.trace, 2);
    t.pop_back();
    return t;
}

// JSON: a string's text (the bytes past ASCII as \u00XX: valid whatever they are)
void json_string(std::string& out, std::string_view s)
{
    out += '"';
    for (const char ch : s) {
        const auto b = static_cast<unsigned char>(ch);
        switch (b) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\t': out += "\\t"; break;
            case '\r': out += "\\r"; break;
            default:
                if (b < 0x20 || b >= 0x7f)
                    out += std::format("\\u{:04x}", b);
                else
                    out += ch;
        }
    }
    out += '"';
}

std::string hash_of(const FunctionInfo& f)
{
    switch (f.kind) {
        case FunctionInfo::Kind::Selector: return std::format("0x{:08x}", f.selector);
        case FunctionInfo::Kind::Fallback: return "_fallback";
        case FunctionInfo::Kind::Internal: return std::format("internal_0x{:x}", f.entry_pc);
    }
    return "?";
}

const FunctionInfo& problem_function(const driver::ContractResult& r, const driver::Problem& p)
{
    return p.internal ? r.final_internals()[p.index] : r.final_functions()[p.index];
}

}  // namespace

Value fold(Value trace) { return trace; }

Value make_ast(const FunctionInfo& fn, const AstOptions&) { return fn.trace; }

void ast_stage(std::span<const FunctionInfo> in, std::vector<FunctionInfo>& out, const AstStageOptions&)
{
    out.assign(in.begin(), in.end());
}

std::string no_code_text(bool color)
{
    const Colors c(color);
    return std::format("{}# No code found for this contract.{}", c.gray, c.end);
}

std::string print_trace(Value trace, const TraceContext&, u32 indent)
{
    std::string out;
    append_lines(out, trace, indent);
    return out;
}

std::string print_exp(Value e, const TraceContext&) { return dump(e); }

std::string print_function(const driver::ContractResult& r, const FunctionInfo& fn, const PrintOptions& opts)
{
    const Colors c(opts.color);
    if (fn.kind == FunctionInfo::Kind::Internal)
        return internal_text(fn, record_of(r, fn), c);
    return function_text(fn, opts.db, c);
}

std::string print_contract(const driver::ContractResult& r, const PrintOptions& o)
{
    const Colors c(o.color);
    const sigdb::Database* db = o.db;
    std::string t = std::format("{}# Palkeoramix decompiler. {}\n", c.gray, c.end);
    if (!r.problems.empty()) {
        t += std::format("{}#\n#  I failed with these: \n", c.gray);
        for (const driver::Problem& p : r.problems)
            t += std::format("{}{}#  - {}{}{}{}{}\n", c.end, c.gray, c.end, c.fail,
                             hex::escape(driver::function_name(db, problem_function(r, p))), c.end, c.gray);
        t += std::format("#  All the rest is below.\n#{}\n", c.end);
    }
    t += '\n';
    // the functions by priority (python's: the self-destructing ones first,
    // then by the length of their text; stable)
    struct Printed {
        std::string text;
        i64 priority;
        const FunctionInfo* fn;
    };
    std::vector<Printed> printed;
    for (const FunctionInfo& f : r.final_functions()) {
        if (f.problem)
            continue;
        std::string text = function_text(f, db, c);
        const i64 priority = has_line(f.trace, Op::SELFDESTRUCT) ? -1 : i64(text.size());
        printed.push_back(Printed{std::move(text), priority, &f});
    }
    std::stable_sort(printed.begin(), printed.end(),
                     [](const Printed& a, const Printed& b) { return a.priority < b.priority; });
    const bool repr = o.repr && r.kept[driver::stage_index(driver::Stage::Simplified)];
    for (const Printed& p : printed) {
        t += p.text;
        t += '\n';
        if (repr)  // python's pprint_repr(func.orig_trace)
            for (const FunctionInfo& g : r.functions[driver::stage_index(driver::Stage::Simplified)])
                if (g.kind == p.fn->kind && g.selector == p.fn->selector && g.entry_pc == p.fn->entry_pc)
                    t += dump(g.trace) + "\n";
        t += '\n';
    }
    // the recursive internal functions, by entry
    const auto& ints = r.final_internals();
    if (std::any_of(ints.begin(), ints.end(), [](const FunctionInfo& f) { return !f.problem; })) {
        t += std::format("{}#\n#  Internal functions\n#{}\n\n", c.gray, c.end);
        for (const FunctionInfo& f : ints) {
            if (f.problem)
                continue;
            t += internal_text(f, record_of(r, f), c);
            t += "\n\n";
        }
    }
    return t;
}

std::string to_json(const driver::ContractResult& r, const PrintOptions& o)
{
    const sigdb::Database* db = o.db;
    const Colors colored(true);
    std::string j = "{\"problems\": {";
    bool first = true;
    for (const driver::Problem& p : r.problems) {
        const FunctionInfo& f = problem_function(r, p);
        if (!first)
            j += ", ";
        first = false;
        json_string(j, hash_of(f));
        j += ": ";
        json_string(j, driver::function_name(db, f));
    }
    j += "}, \"stor_defs\": {}, \"functions\": [";
    first = true;
    for (const FunctionInfo& f : r.final_functions()) {
        if (f.problem)
            continue;
        if (!first)
            j += ", ";
        first = false;
        j += "{\"hash\": ";
        json_string(j, hash_of(f));
        j += ", \"name\": ";
        json_string(j, driver::function_name(db, f));
        j += ", \"print\": ";
        json_string(j, function_text(f, db, colored));
        j += "}";
    }
    j += "]";
    const auto& ints = r.final_internals();
    if (std::any_of(ints.begin(), ints.end(), [](const FunctionInfo& f) { return !f.problem; })) {
        j += ", \"internal\": [";
        first = true;
        for (const FunctionInfo& f : ints) {
            if (f.problem)
                continue;
            const vm::InternalEntry* e = record_of(r, f);
            if (!first)
                j += ", ";
            first = false;
            j += "{\"name\": ";
            json_string(j, hash_of(f));
            j += std::format(", \"entry\": {}, \"params\": {}, \"results\": {}, \"frame\": {}, \"print\": ", f.entry_pc,
                             e ? e->nargs : 0, e ? e->nresults : 0, e ? e->frame : 0);
            json_string(j, internal_text(f, e, colored));
            j += "}";
        }
        j += "]";
    }
    j += "}";
    return j;
}

void explain_trace(std::string& out, std::string_view title, Value trace, const TraceContext& ctx)
{
    const Colors c(ctx.color);
    out += std::format("\n{} {}: {}\n\n", c.green_back, title, c.end);
    append_lines(out, trace, 2);
    out += "\n\n";
}

void explain_text(std::string& out, std::string_view title, std::span<const std::pair<std::string, std::string>> items,
                  bool color)
{
    const Colors c(color);
    out += std::format("\n{} {}: {}\n\n", c.blue_back, title, c.end);
    for (const auto& [name, value] : items)
        out += std::format(" {}{}{}: {}\n", c.gray, name, c.end, value);
    out += "\n";
}

void explain_traits(std::string&, const FunctionInfo&, const TraceContext&) {}

}  // namespace pan::output
