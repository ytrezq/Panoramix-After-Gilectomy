// The JSON (rule 7: the format is ours): python's decompilation.json's keys
// (problems, stor_defs, functions with their names, traits, text, trace and
// params, safemath, internal), each trace as a shallow table of its
// distinct nodes - hash-consing makes a trace a DAG: each shared node once,
// referred to by its index (a trace's JSON is as big as its nodes, never as
// deep as it nests).
#include <algorithm>
#include <format>
#include <unordered_map>

#include "core/budget.hpp"
#include "core/node.hpp"
#include "driver/pipeline.hpp"
#include "output/print.hpp"
#include "sigdb.hpp"

namespace pan::output::detail {

namespace {

// a JSON string of UTF-8 text (the text is: the names escaped, the
// contract's strings printable): the control characters, DEL, " and \ escaped
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
                if (b < 0x20 || b == 0x7f)
                    out += std::format("\\u{:04x}", b);
                else
                    out += ch;
        }
    }
    out += '"';
}

std::string_view name_kind_text(NameKind k) noexcept
{
    switch (k) {
        case NameKind::TMP: return "tmp";
        case NameKind::LOOP: return "loop";
        case NameKind::MSIZE_VAR: return "msize";
        case NameKind::PRECOMPILE: return "precompile";
        case NameKind::PARAM: return "param";
        case NameKind::STORVAR: return "storvar";
        case NameKind::FUNC: return "func";
        case NameKind::FALLBACK: return "fallback";
        case NameKind::INTERNAL: return "internal";
        case NameKind::LOOP_ID: return "loopid";
        case NameKind::SAFEMATH_PARAM: return "safemath_param";
    }
    return "name";
}

// A trace as its table of nodes: the EXPR and LIST nodes, operands first.
class NodeTable {
public:
    std::string nodes;  // the JSON array's items, comma separated
    usize count = 0;

    // v's encoding as an operand (its node's index once listed)
    void operand(std::string& out, Value v)
    {
        if (v.is_small()) {
            const i64 x = v.small_val();
            if (x > -(i64(1) << 53) && x < (i64(1) << 53)) {
                out += std::to_string(x);
                return;
            }
            out += "{\"int\": ";
            json_string(out, int_hex(EvmInt(x)));
            out += '}';
            return;
        }
        if (v.nil()) {
            out += "{\"nil\": true}";
            return;
        }
        if (v.is_bool()) {
            out += v.is_true() ? "true" : "false";
            return;
        }
        if (v.is_none()) {
            out += "null";
            return;
        }
        if (v.is_leaf()) {
            out += "{\"leaf\": ";
            json_string(out, op_name(v.op()));
            out += std::format(", \"n\": {}}}", v.leaf_n());
            return;
        }
        if (v.is_name()) {
            out += "{\"name\": ";
            json_string(out, name_kind_text(v.name_kind()));
            out += std::format(", \"id\": {}}}", v.name_id());
            return;
        }
        if (v.is_big()) {
            out += "{\"int\": ";
            json_string(out, int_hex(EvmInt(v)));
            out += '}';
            return;
        }
        if (v.is_bytes()) {
            static constexpr char hx[] = "0123456789abcdef";
            out += "{\"bytes\": \"";
            for (const u8 c : v.bytes()) {
                out += hx[c >> 4];
                out += hx[c & 15];
            }
            out += "\"}";
            return;
        }
        out += std::format("{{\"n\": {}}}", index(v));
    }

    // the index of an EXPR / LIST node, listed (with its operands) when new
    usize index(Value root)
    {
        if (const auto it = ids_.find(root.raw()); it != ids_.end())
            return it->second;
        // operands before their users: an explicit stack (traces nest deep)
        std::vector<std::pair<Value, u32>> todo{{root, 0}};
        while (!todo.empty()) {
            poll();
            auto& [v, next] = todo.back();
            const auto args = v.args();
            bool pushed = false;
            while (next < args.size()) {
                const Value a = args[next++];
                if ((a.is_expr() || a.is_list()) && !ids_.contains(a.raw())) {
                    todo.emplace_back(a, 0);
                    pushed = true;
                    break;
                }
            }
            if (pushed)
                continue;
            const Value done = v;
            todo.pop_back();
            if (ids_.contains(done.raw()))
                continue;
            if (count)
                nodes += ", ";
            nodes += '[';
            if (done.is_expr())
                json_string(nodes, op_name(done.op()));
            else
                nodes += done.is_trace() ? "\"trace\"" : "\"list\"";
            for (const Value a : done.args()) {
                nodes += ", ";
                operand(nodes, a);
            }
            nodes += ']';
            ids_.emplace(done.raw(), count++);
        }
        return ids_.at(root.raw());
    }

private:
    std::unordered_map<u64, usize> ids_;
};

void trace_json(std::string& out, Value trace)
{
    if (!trace.is_expr() && !trace.is_list()) {
        out += "null";
        return;
    }
    NodeTable t;
    const usize root = t.index(trace);
    out += std::format("{{\"root\": {}, \"nodes\": [", root);
    out += t.nodes;
    out += "]}";
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

// the unfolded trace of a function (python's func.trace): Analysed's, else
// the last kept before the ast
Value json_trace(const driver::ContractResult& r, const FunctionInfo& f, bool internal)
{
    for (const driver::Stage s : {driver::Stage::Analysed, driver::Stage::Simplified, driver::Stage::Whiles,
                                  driver::Stage::Raw}) {
        const unsigned i = driver::stage_index(s);
        if (!r.kept[i])
            continue;
        for (const FunctionInfo& g : internal ? r.internals[i] : r.functions[i])
            if (g.kind == f.kind && g.selector == f.selector && g.entry_pc == f.entry_pc)
                return g.trace;
    }
    return f.trace;
}

std::string_view lang_text(Lang l) noexcept
{
    switch (l) {
        case Lang::Vyper: return "vyper";
        case Lang::Solidity: return "solidity";
        case Lang::Unknown: return "unknown";
    }
    return "unknown";
}

}  // namespace

std::string contract_json(const driver::ContractResult& r, const PrintOptions& o)
{
    PrintOptions colored = o;
    colored.color = true;
    std::string j = "{\"problems\": {";
    bool first = true;
    for (const driver::Problem& p : r.problems) {
        const FunctionInfo& f = problem_function(r, p);
        if (!first)
            j += ", ";
        first = false;
        json_string(j, hash_of(f));
        j += ": ";
        json_string(j, db_text(driver::function_name(o.db, f)));
    }
    j += "}, \"stor_defs\": [], \"lang\": ";
    json_string(j, lang_text(r.lang));
    j += ", \"functions\": [";
    first = true;
    for (const FunctionInfo& f : r.final_functions()) {
        poll();
        if (f.problem)
            continue;
        if (!first)
            j += ", ";
        first = false;
        const FnEnv env(&f, o.db, Value());
        Out plain(false), color(true);
        function_header_name(plain, f, env);
        function_header_name(color, f, env);
        // python's abi_name: name(type,type...)
        std::string abi = plain.s.substr(0, plain.s.find('(')) + "(";
        if (f.kind == FunctionInfo::Kind::Fallback) {
            abi = "_fallback(?)";
        } else {
            bool k = false;
            for (const FnEnv::Param& p : env.params()) {
                if (k)
                    abi += ',';
                k = true;
                abi += p.type;
            }
            abi += ')';
        }
        const Out text = function_text(&r, f, colored);
        u64 lines = 1;
        for (const char c : text.s)
            lines += c == '\n';
        j += "{\"hash\": ";
        json_string(j, hash_of(f));
        j += ", \"name\": ";
        json_string(j, plain.s);
        j += ", \"color_name\": ";
        json_string(j, color.s);
        j += ", \"abi_name\": ";
        json_string(j, abi);
        j += std::format(", \"length\": [{}, {}]", lines, text.python_chars());
        j += std::format(", \"getter\": {}, \"const\": {}", f.getter ? "true" : "false", f.is_const ? "true" : "false");
        const bool payable = !f.entry.nonpayable;
        j += std::format(", \"payable\": {}", payable ? "true" : "false");
        j += ", \"value_fails\": ";
        j += payable ? "null" : f.entry.value_fails.is(Op::INVALID) ? "\"invalid\"" : "\"revert\"";
        j += ", \"print\": ";
        json_string(j, text.s);
        j += ", \"params\": {";
        bool pf = true;
        for (usize k = 0; k < f.params.size(); ++k) {
            if (!pf)
                j += ", ";
            pf = false;
            j += std::format("\"{}\": [", f.params[k].calldata_offset);
            json_string(j, k < env.params().size() ? env.params()[k].type : std::string("uint256"));
            j += ", ";
            json_string(j, k < env.params().size() ? env.params()[k].name : std::format("_param{}", k + 1));
            j += ']';
        }
        j += "}, \"trace\": ";
        trace_json(j, json_trace(r, f, false));
        j += '}';
    }
    j += ']';
    const auto& ints = r.final_internals();
    if (std::any_of(ints.begin(), ints.end(), [](const FunctionInfo& f) { return !f.problem; })) {
        j += ", \"internal\": [";
        first = true;
        for (const FunctionInfo& f : ints) {
            poll();
            if (f.problem)
                continue;
            const vm::InternalEntry* e = nullptr;
            for (const vm::InternalEntry& x : r.internal_entries)
                if (x.entry == f.entry_pc)
                    e = &x;
            if (!first)
                j += ", ";
            first = false;
            j += "{\"name\": ";
            json_string(j, hash_of(f));
            j += std::format(", \"entry\": {}, \"params\": {}, \"results\": {}, \"frame\": {}, \"print\": ", f.entry_pc,
                             e ? e->nargs : 0, e ? e->nresults : 0, e ? e->frame : 0);
            json_string(j, function_text(&r, f, colored).s);
            j += ", \"trace\": ";
            trace_json(j, json_trace(r, f, true));
            j += '}';
        }
        j += ']';
    }
    j += '}';
    return j;
}

}  // namespace pan::output::detail
