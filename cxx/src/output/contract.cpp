// The contract's text (python decompiler.py's printing, function.py's
// Function.print / InternalFunction.print, priority, prettify.pprint_repr):
// the header, the problems, the consts, def storage, def SafeMath, the
// getters, the regular functions by priority, the recursive internal
// functions.
#include <algorithm>
#include <format>

#include "core/dump.hpp"
#include "core/errors.hpp"
#include "core/platform.hpp"
#include "driver/pipeline.hpp"
#include "output/print.hpp"
#include "sigdb.hpp"

namespace pan::output::detail {

namespace {

// does the trace hold a line of op, at any depth (python: "selfdestruct" in str(trace))
bool has_line(Value trace, Op op)
{
    std::vector<Value> todo{trace};
    std::vector<u64> seen;
    while (!todo.empty()) {
        const Value t = todo.back();
        todo.pop_back();
        if (!t.is_list())
            continue;
        if (std::find(seen.begin(), seen.end(), t.raw()) != seen.end())
            continue;
        seen.push_back(t.raw());
        for (const Value l : t.args()) {
            if (l.is(op))
                return true;
            if (l.is_expr())
                for (const Value a : l.args())
                    if (a.is_list())
                        todo.push_back(a);
        }
    }
    return false;
}

// the record of a recursive internal function (its params, frame)
const vm::InternalEntry* record_of(const driver::ContractResult& r, const FunctionInfo& f)
{
    for (const vm::InternalEntry& e : r.internal_entries)
        if (e.entry == f.entry_pc)
            return &e;
    return nullptr;
}

// the return lines of a trace, any depth (python's find_returns)
void returns_of(Value trace, std::vector<Value>& out)
{
    std::vector<Value> todo{trace};
    while (!todo.empty()) {
        const Value t = todo.back();
        todo.pop_back();
        if (!t.is_list())
            continue;
        for (auto it = t.args().rbegin(); it != t.args().rend(); ++it) {
            const Value l = *it;
            if (l.is(Op::RETURN))
                out.push_back(l);
        }
        for (const Value l : t.args())
            if (l.is_expr())
                for (const Value a : l.args())
                    if (a.is_list())
                        todo.push_back(a);
    }
}

}  // namespace

// the function's name in its header (python's color_name)
void function_header_name(Out& o, const FunctionInfo& fn, const FnEnv& env)
{
    switch (fn.kind) {
        case FunctionInfo::Kind::Fallback:
            o.put("_fallback(?)");
            return;
        case FunctionInfo::Kind::Internal:
            o.put(std::format("internal_0x{:x}", fn.entry_pc));
            return;
        case FunctionInfo::Kind::Selector:
            break;
    }
    if (env.known()) {
        const auto e = env.db()->function(fn.selector);
        o.put(db_text(e->name()));
    } else {
        o.put(std::format("unknown{:08x}", fn.selector));
    }
    // name(type name, ...): python's get_func_name / make_names, the names green
    o.put('(');
    bool first = true;
    for (const FnEnv::Param& p : env.params()) {
        if (!first)
            o.put(", ");
        first = false;
        o.put(p.type);
        o.put(' ');
        o.col(Col::green, p.name);
    }
    o.put(')');
}

// One function's text (python Function._print / InternalFunction.print),
// its lines joined with "\n" (no newline at the end).
Out function_text(const driver::ContractResult* r, const FunctionInfo& fn, const PrintOptions& s)
{
    Out o(s.color);
    const FnEnv env(&fn, s.db, fn.trace);
    Printer p(o, env);
    if (fn.kind == FunctionInfo::Kind::Internal) {
        const vm::InternalEntry* rec = r ? record_of(*r, fn) : nullptr;
        const u32 nargs = rec ? rec->nargs : u32(fn.params.size());
        o.col(Col::header, "def ");
        o.put(std::format("internal_0x{:x}(", fn.entry_pc));
        for (u32 k = 0; k < nargs; ++k) {
            if (k)
                o.put(", ");
            o.put(std::format("_param{}", k + 1));
        }
        o.put("): ");
        o.col(Col::gray, std::format("# recursive, a call takes {} of the 1024 words of the stack", rec ? rec->frame : 0));
        o.put('\n');
    } else if (fn.is_const) {
        // const name = what it returns (a return's data)
        std::vector<Value> rets;
        returns_of(fn.trace, rets);
        o.col(Col::header, "const ");
        Out name = o.sub();
        function_header_name(name, fn, env);
        if (name.s.size() >= 2 && name.s.ends_with("()"))
            name.s.resize(name.s.size() - 2);
        o.append(name);
        o.put(" = ");
        o.code(Col::bold);
        if (!rets.empty()) {
            MemoryOpts m;
            m.abi_text = true;
            p.memory_joined(rets[0][0], m);
        }
        o.end();
        return o;
    } else {
        std::string comment;
        const bool payable = !fn.entry.nonpayable;
        if (!payable) {
            // sent ether, it reverts with no data - or, the check of old
            // compilers, it runs an invalid opcode
            comment = "# not payable";
            if (fn.entry.value_fails.is(Op::INVALID))
                comment += " (invalid)";
        }
        if (fn.kind == FunctionInfo::Kind::Fallback) {
            if (payable)
                comment = "# default function";
            else
                comment += ", default function";
        }
        o.col(Col::header, "def ");
        function_header_name(o, fn, env);
        if (payable)
            o.col(Col::header, " payable");
        o.put(": ");
        o.col(Col::gray, comment);
        o.put('\n');
    }
    const usize body = o.s.size();
    if (fn.trace.is_trace())
        p.lines(fn.trace, 2);
    if (o.s.size() == body)
        o.put("  stop\n");
    o.s.pop_back();  // (python's "\n".join)
    return o;
}

// python's pprint_repr of a trace (--repr): the lines as the IR's
// S-expressions, an if's and a while's branches indented
void repr_lines(std::string& out, Value trace, u32 indent)
{
    check_stack();
    if (!trace.is_list())
        return;
    for (const Value l : trace.args()) {
        if (l.is(Op::IF, 3)) {
            out += std::string(indent, ' ') + " [if, " + dump(l[0]) + ", [\n";
            repr_lines(out, l[1], indent + 2);
            out += std::string(indent, ' ') + " ],[\n";
            repr_lines(out, l[2], indent + 2);
            out += std::string(indent, ' ') + " ] \n";
        } else if (l.is(Op::WHILE, 4)) {
            out += std::string(indent, ' ') + " [while, " + dump(l[0]) + ", [\n";
            repr_lines(out, l[1], indent + 2);
            out += std::string(indent, ' ') + " ], \n";
        } else {
            out += std::string(indent, ' ') + " " + dump(l) + ", \n";
        }
    }
}

namespace {

const FunctionInfo& problem_function(const driver::ContractResult& r, const driver::Problem& p)
{
    return p.internal ? r.final_internals()[p.index] : r.final_functions()[p.index];
}

// the same function at another stage (--repr's orig_trace)
const FunctionInfo* at_stage(const driver::ContractResult& r, driver::Stage s, const FunctionInfo& f, bool internal)
{
    const unsigned i = driver::stage_index(s);
    if (!r.kept[i])
        return nullptr;
    for (const FunctionInfo& g : internal ? r.internals[i] : r.functions[i])
        if (g.kind == f.kind && g.selector == f.selector && g.entry_pc == f.entry_pc)
            return &g;
    return nullptr;
}

void check_deadline(i64 deadline)
{
    poll();
    if (deadline && platform::monotonic_ns() > deadline)
        throw Timeout("the post-processing and the text took more than 3 minutes");
}

}  // namespace

std::string contract_text(const driver::ContractResult& r, const PrintOptions& s)
{
    Out t(s.color);
    t.col(Col::gray, "# Palkeoramix decompiler. ");
    t.put('\n');
    if (!r.problems.empty()) {
        t.code(Col::gray);
        t.put("#\n#  I failed with these: \n");
        for (const driver::Problem& pb : r.problems) {
            t.end();
            t.code(Col::gray);
            t.put("#  - ");
            t.end();
            t.code(Col::fail);
            t.put(db_text(driver::function_name(s.db, problem_function(r, pb))));
            t.end();
            t.code(Col::gray);
            t.put('\n');
        }
        t.put("#  All the rest is below.\n#");
        t.end();
        t.put('\n');
    }
    t.put('\n');

    const auto& fns = r.final_functions();
    std::vector<bool> shown(fns.size(), false);
    // the consts: the lower-case names first, the all-caps ones last
    {
        std::vector<usize> consts_lower, consts_upper;
        for (usize i = 0; i < fns.size(); ++i) {
            const FunctionInfo& f = fns[i];
            if (f.problem || !f.is_const)
                continue;
            const std::string name = driver::function_name(s.db, f);
            const bool upper = std::none_of(name.begin(), name.end(), [](char c) { return c >= 'a' && c <= 'z'; });
            (upper ? consts_upper : consts_lower).push_back(i);
        }
        bool any = false;
        for (const auto* list : {&consts_lower, &consts_upper})
            for (const usize i : *list) {
                check_deadline(s.deadline_ns);
                t.append(function_text(&r, fns[i], s));
                t.put('\n');
                shown[i] = true;
                any = true;
            }
        if (any)
            t.put('\n');
    }
    // (def storage: lot 9's layout; def SafeMath: lot 8's table - when they land)
    bool any_shown = std::any_of(shown.begin(), shown.end(), [](bool b) { return b; });
    // the getters
    for (usize i = 0; i < fns.size(); ++i) {
        const FunctionInfo& f = fns[i];
        if (f.problem || shown[i] || !f.getter)
            continue;
        check_deadline(s.deadline_ns);
        t.append(function_text(&r, f, s));
        t.put('\n');
        if (s.repr) {
            t.put('\n');
            std::string rp;
            repr_lines(rp, f.trace, 0);
            t.put(rp);
        }
        t.put('\n');
        shown[i] = true;
        any_shown = true;
    }
    // the regular functions, by priority: the self-destructing ones first,
    // then by the length of their (colored) text
    struct Printed {
        Out text;
        i64 priority;
        usize index;
    };
    std::vector<Printed> printed;
    for (usize i = 0; i < fns.size(); ++i) {
        const FunctionInfo& f = fns[i];
        if (f.problem || shown[i])
            continue;
        check_deadline(s.deadline_ns);
        Out text = function_text(&r, f, s);
        const i64 priority = has_line(f.trace, Op::SELFDESTRUCT) ? -1 : i64(text.python_chars());
        printed.push_back(Printed{std::move(text), priority, i});
    }
    std::stable_sort(printed.begin(), printed.end(),
                     [](const Printed& a, const Printed& b) { return a.priority < b.priority; });
    if (any_shown && !printed.empty()) {
        t.code(Col::gray);
        t.put("#\n#  Regular functions\n#");
        t.end();
        t.put("\n\n");
    }
    for (Printed& p : printed) {
        const FunctionInfo& f = fns[p.index];
        t.append(p.text);
        t.put('\n');
        if (s.returns) {
            std::vector<Value> rets;
            returns_of(f.trace, rets);
            for (const Value rl : rets)
                t.put(dump(rl) + "\n");
        }
        if (s.repr)
            if (const FunctionInfo* g = at_stage(r, driver::Stage::Simplified, f, false)) {
                std::string rp;
                repr_lines(rp, g->trace, 0);
                t.put(rp);
            }
        t.put('\n');
    }
    // the recursive internal functions, by entry
    const auto& ints = r.final_internals();
    if (std::any_of(ints.begin(), ints.end(), [](const FunctionInfo& f) { return !f.problem; })) {
        t.code(Col::gray);
        t.put("#\n#  Internal functions\n#");
        t.end();
        t.put("\n\n");
        for (const FunctionInfo& f : ints) {
            if (f.problem)
                continue;
            check_deadline(s.deadline_ns);
            t.append(function_text(&r, f, s));
            t.put('\n');
            if (s.repr)
                if (const FunctionInfo* g = at_stage(r, driver::Stage::Simplified, f, true)) {
                    std::string rp;
                    repr_lines(rp, g->trace, 0);
                    t.put(rp);
                }
            t.put('\n');
        }
    }
    return std::move(t.s);
}

}  // namespace pan::output::detail
