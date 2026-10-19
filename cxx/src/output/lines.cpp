// The lines of the text (python prettify.pretty_line, pprint_logic,
// sequential_setvars, add_breaks, check_word; the --verbose lines of
// assembly): a trace's lines, each indented, a block 4 spaces deeper.
#include <algorithm>
#include <format>
#include <unordered_set>

#include "analysis/safemath.hpp"
#include "core/budget.hpp"
#include "core/contract.hpp"
#include "output/print.hpp"
#include "sigdb.hpp"

namespace pan::output::detail {

namespace {

constexpr u32 INDENT_LEN = 4;

bool is_small(Value v, i64 x) noexcept { return v.is_small() && v.small_val() == x; }

// python's ENDS_PATH: what a path ends with, not going on after it
bool ends_path(Value l) noexcept
{
    switch (l.op()) {
        case Op::RETURN:
        case Op::STOP:
        case Op::SELFDESTRUCT:
        case Op::INVALID:
        case Op::REVERT:
        case Op::CONTINUE:
        case Op::BREAK:
        case Op::UNDEFINED:
        case Op::LEAVE:
            return true;
        default:
            return false;
    }
}

// an IF with an else (python's 4-tuple): its false branch has lines
bool two_sided(Value l) noexcept { return l.is(Op::IF, 3) && l[2].is_list() && l[2].size() > 0; }

// python's check_word(branch): require if the branch only reverts (with no
// data), assert if it's only an invalid
const char* check_word(Value branch) noexcept
{
    if (!branch.is_list() || branch.size() != 1)
        return nullptr;
    const Value l = branch[0];
    if (l.is(Op::REVERT, 1) && (l[0].is_none() || l[0].nil()))
        return "require";
    if (l.is(Op::INVALID))
        return "assert";
    return nullptr;
}

// python's breaks(add_breaks(branch)): the branch, with its break, ends with one
bool breaks_after(Value branch, bool add_breaks) noexcept
{
    if (!branch.is_list() || branch.size() == 0)
        return add_breaks;
    const Value last = branch[branch.size() - 1];
    if (last.is(Op::BREAK))
        return true;
    if (!add_breaks)
        return false;
    if (ends_path(last) || two_sided(last))
        return false;
    return true;
}

// does v mention the name (python contains)
bool contains(Value v, Value name, std::unordered_set<u64>& seen)
{
    if (v == name)
        return true;
    if (!v.is_node())
        return false;
    const u8 nf = name_flags(name.name_kind());
    if (nf && !(v.flags() & nf))
        return false;
    if (!v.is_expr() && !v.is_list())
        return false;
    if (!seen.insert(v.raw()).second)
        return false;
    for (const Value a : v.args())
        if (contains(a, name, seen))
            return true;
    return false;
}
bool contains(Value v, Value name)
{
    check_stack();
    std::unordered_set<u64> seen;
    return contains(v, name, seen);
}

// does a WHILE anywhere in v hold a CONTINUE of the loop id (python continues_from_inside)
bool continue_of(Value v, Value id, std::unordered_set<u64>& seen)
{
    if (!v.is_expr() && !v.is_list())
        return false;
    if (!(v.flags() & F_LOOPCTL))
        return false;
    if (!seen.insert(v.raw()).second)
        return false;
    if (v.is(Op::CONTINUE) && v.size() >= 1 && v[0] == id)
        return true;
    for (const Value a : v.args())
        if (continue_of(a, id, seen))
            return true;
    return false;
}
bool continues_from_inside(Value path, Value id)
{
    std::vector<Value> todo{path};
    std::unordered_set<u64> seen, seen2;
    while (!todo.empty()) {
        const Value t = todo.back();
        todo.pop_back();
        if (!t.is_expr() && !t.is_list())
            continue;
        if (!(t.flags() & F_LOOPCTL) || !seen.insert(t.raw()).second)
            continue;
        if (t.is(Op::WHILE, 4) && continue_of(t[1], id, seen2))
            return true;
        for (const Value a : t.args())
            todo.push_back(a);
    }
    return false;
}

}  // namespace

// ---- the line printer ----------------------------------------------------------------------

struct LineImpl {
    Printer& p;
    Out& o;
    const FnEnv& env;
    // sequential_setvars' copies: a name printed as another
    struct Subst {
        Value name;
        std::string text;
    };

    explicit LineImpl(Printer& pr) : p(pr), o(pr.out()), env(pr.env()) {}

    void start(u32 indent) { o.spaces(indent); }
    void nl() { o.put('\n'); }

    // python's prettify(e, parentheses=False)
    void pret(Value e) { p.exp(e, P_NONE, false); }
    void cond(Value c) { p.exp(c, P_NONE, true); }

    // ---- pprint_logic ----
    void lines(Value trace, u32 indent, std::span<const Printer::LoopRef> loops, bool add_breaks)
    {
        check_stack();
        if (!trace.is_list()) {
            line(trace, indent, loops, false);
            return;
        }
        const u32 n = trace.size();
        if (n == 0) {
            if (add_breaks) {
                start(indent);
                green("break");
                nl();
            }
            return;
        }
        for (u32 i = 0; i < n; ++i) {
            poll();
            const Value l = trace[i];
            const bool last = i + 1 == n;
            if (last && indent == 2 && l.is(Op::STOP) && !add_breaks)
                continue;  // (don't print the last stop)
            line(l, indent, loops, last && add_breaks);
        }
        if (add_breaks) {
            const Value l = trace[n - 1];
            if (!ends_path(l) && !l.is(Op::IF) && !l.is(Op::MERGED_IF)) {
                start(indent);
                green("break");
                nl();
            }
        }
    }

    void green(std::string_view t)
    {
        o.code(Col::green);
        o.put(t);
        o.end();
    }

    // a line (python pprint_logic's cases, then pretty_line's); add_breaks:
    // the last of a loop's body (python add_breaks: an IF's branches get theirs)
    void line(Value l, u32 indent, std::span<const Printer::LoopRef> loops, bool add_breaks)
    {
        check_stack();
        switch (l.op()) {
            case Op::WHILE:
                if (l.size() == 4) {
                    while_line(l, indent, loops);
                    return;
                }
                break;
            case Op::CONTINUE:
                if (l.size() == 2) {
                    setvars(l[1], indent);
                    start(indent);
                    green("continue");
                    if (!loops.empty() && loops.back().id != l[0]) {
                        // of a loop the continue is in a loop in
                        int label = -1;
                        for (const Printer::LoopRef& r : loops)
                            if (r.id == l[0]) {
                                label = r.label;
                                break;
                            }
                        if (label > 0)
                            o.put(std::format(" loop{}", label));
                        else
                            o.put(" ?");
                    }
                    nl();
                    return;
                }
                break;
            case Op::BREAK:
                start(indent);
                green("break");
                nl();
                return;
            case Op::REQUIRE:
                if (l.size() == 1 || (l.size() == 2 && (l[1].is_none() || l[1].nil()))) {
                    start(indent);
                    o.put("require ");
                    cond(l[0]);
                    nl();
                    return;
                }
                if (l.size() == 2) {
                    // a check that reverts with data: `if not c: revert with ...`
                    start(indent);
                    o.put("if ");
                    p.negated(l[0]);
                    o.put(':');
                    nl();
                    revert_return(Op::REVERT, l[1], indent + INDENT_LEN);
                    return;
                }
                break;
            case Op::ASSERT:
                if (l.size() == 1) {
                    start(indent);
                    o.put("assert ");
                    cond(l[0]);
                    nl();
                    return;
                }
                break;
            case Op::IF:
            case Op::MERGED_IF:
                if (l.size() == 3) {
                    if_line(l, indent, loops, add_breaks);
                    return;
                }
                break;
            case Op::ASM:
                asm_lines(l, indent);
                return;
            default:
                break;
        }
        pretty_line(l, indent, loops);
    }

    void while_line(Value l, u32 indent, std::span<const Printer::LoopRef> loops)
    {
        const Value c = l[0], body = l[1], id = l[2];
        setvars(l[3], indent);
        int label = 0;
        if (continues_from_inside(body, id))
            label = int(loops.size()) + 1;
        start(indent);
        if (label)
            o.put(std::format("loop{}: ", label));
        o.code(Col::green);
        o.put("while ");
        o.end();
        if (is_small(c, 1) || (c.is(Op::BOOL, 1) && is_small(c[0], 1)) || c.is_true())
            o.put("True");
        else
            cond(c);
        o.code(Col::green);
        o.put(":");
        o.end();
        nl();
        std::vector<Printer::LoopRef> inner(loops.begin(), loops.end());
        inner.push_back({id, label});
        lines(body, indent + INDENT_LEN, inner, true);
    }

    void if_line(Value l, u32 indent, std::span<const Printer::LoopRef> loops, bool add_breaks)
    {
        Value c = l[0], t = l[1], f = l[2];
        const bool f_empty = !f.is_list() || f.size() == 0;
        if (f_empty) {
            // one-sided (only after folding): what follows the if is no else
            if (const char* w = check_word(t)) {
                start(indent);
                o.put(w);
                o.put(' ');
                p.negated(c);
                nl();
                if (add_breaks) {
                    start(indent);
                    green("break");
                    nl();
                }
                return;
            }
            start(indent);
            o.put("if ");
            cond(c);
            o.put(':');
            nl();
            lines(t, indent + INDENT_LEN, loops, false);
            if (add_breaks) {
                start(indent);
                green("break");
                nl();
            }
            return;
        }
        if (const char* w = check_word(f)) {
            start(indent);
            o.put(w);
            o.put(' ');
            cond(c);
            nl();
            lines(t, indent, loops, add_breaks);
            return;
        }
        if (const char* w = check_word(t)) {
            start(indent);
            o.put(w);
            o.put(' ');
            p.negated(c);
            nl();
            lines(f, indent, loops, add_breaks);
            return;
        }
        const bool bt = breaks_after(t, add_breaks), bf = breaks_after(f, add_breaks);
        const bool t_has = t.is_list() && (t.size() > 0 || add_breaks);
        if (bt || (bf && t_has)) {
            // a branch that leaves the loop (see add_breaks): the other one
            // follows the if rather than being its else
            start(indent);
            o.put("if ");
            if (!bt) {
                p.negated(c);
                std::swap(t, f);
            } else {
                cond(c);
            }
            o.put(':');
            nl();
            lines(t, indent + INDENT_LEN, loops, add_breaks);
            lines(f, indent, loops, add_breaks);
            return;
        }
        start(indent);
        o.put("if ");
        cond(c);
        o.put(':');
        nl();
        lines(t, indent + INDENT_LEN, loops, add_breaks);
        start(indent);
        o.put("else:");
        nl();
        lines(f, indent + INDENT_LEN, loops, add_breaks);
    }

    // ---- python's sequential_setvars: the simultaneous assignments of a
    // continue (a while's first ones), one after the other ----
    void setvars(Value svs, u32 indent)
    {
        if (!svs.is_list() || svs.size() == 0)
            return;
        struct Pending {
            Value name, value;
            std::vector<std::pair<Value, std::string>> subst;  // a name read as its copy
        };
        std::vector<Pending> pending;
        for (const Value sv : svs.args()) {
            if (!sv.is(Op::SETVAR, 2))
                continue;
            if (sv[1] == sv[0])
                continue;  // (x = x)
            pending.push_back(Pending{sv[0], sv[1], {}});
        }
        auto reads = [&](const Pending& q, Value name) {
            for (const auto& [from, _] : q.subst)
                if (from == name)
                    return false;
            return contains(q.value, name);
        };
        int copies = 0;
        while (!pending.empty()) {
            poll();
            bool done = false;
            for (usize i = 0; i < pending.size() && !done; ++i) {
                bool read = false;
                for (usize j = 0; j < pending.size() && !read; ++j)
                    if (j != i && reads(pending[j], pending[i].name))
                        read = true;
                if (!read) {
                    assign(pending[i].name, {}, pending[i].value, pending[i].subst, indent);
                    pending.erase(pending.begin() + i);
                    done = true;
                }
            }
            if (done)
                continue;
            // a swap: a copy of one of them first
            ++copies;
            const std::string copy = env.var_name(copies == 1 ? std::string("_old") : std::format("_old{}", copies));
            const Value name = pending[0].name;
            start(indent);
            o.col(Col::blue, copy);
            o.put(" = ");
            p.exp(name, P_NONE, false);
            nl();
            for (usize j = 1; j < pending.size(); ++j)
                pending[j].subst.emplace_back(name, copy);
        }
    }

    // `name = value`, the names of subst printed as their copies
    void assign(Value name, std::string_view, Value value, const std::vector<std::pair<Value, std::string>>& subst,
                u32 indent)
    {
        start(indent);
        p.exp(name, P_NONE, false);
        o.put(" = ");
        if (subst.empty()) {
            pret(value);
        } else {
            Printer::SubstScope scope(p, subst);
            pret(value);
        }
        nl();
    }

    // ---- --verbose: the lines of assembly ----
    void asm_lines(Value l, u32 indent)
    {
        // python's C.asm("       " + str(stack)), "", "[pc] op param" - comments
        if (l.size() != 4)
            return;
        const Value pc = l[0], opv = l[1], imm = l[2], stack = l[3];
        // the stack
        start(indent);
        o.code(Col::gray);
        o.put("# ");
        o.code(Col::asm_code);
        o.put("       [");
        if (stack.is_list()) {
            // (python's text of its VM's stack: made before the traits and
            // the storage - no param names, raw storage reads)
            AddColor plain(o, false);
            Printer::RawView raw(p);
            for (u32 i = 0; i < stack.size(); ++i) {
                if (i)
                    o.put(", ");
                pret(stack[i]);
            }
        }
        o.put(']');
        o.end();
        o.end();
        nl();
        start(indent);
        o.code(Col::gray);
        o.put("# ");
        o.end();
        nl();
        start(indent);
        o.code(Col::gray);
        o.put("# ");
        const u32 op = opv.is_small() ? u32(opv.small_val()) : 0;
        o.put(std::format("[{}] ", pc.is_small() ? pc.small_val() : 0));
        o.code(Col::asm_code);
        if (op >= 0x80 && op <= 0x8f)
            o.put("dup");
        else if (op >= 0x90 && op <= 0x9f)
            o.put("swap");
        else
            o.put(op_name(Op(op)));
        o.end();
        if (op >= 0x5f && op <= 0x9f) {
            o.put(' ');
            o.code(Col::asm_code);
            if (op >= 0x80)
                o.put(std::to_string(op >= 0x90 ? op - 0x8f : op - 0x7f));
            else if (imm.is_int()) {
                const EvmInt v(imm);
                static const EvmInt limit(i64(0x1000000000));
                o.put(v > limit ? int_hex(v) : int_dec(v));
            }
            o.end();
        }
        o.end();
        nl();
    }

    // ---- pretty_line ----
    void pretty_line(Value l, u32 indent, std::span<const Printer::LoopRef> loops)
    {
        (void)loops;
        const Op op = l.op();
        const u32 n = l.is_expr() ? l.size() : 0;
        switch (op) {
            case Op::LOG0:
            case Op::LOG1:
            case Op::LOG2:
            case Op::LOG3:
            case Op::LOG4:
                if (n >= 1) {
                    log_line(l, indent);
                    return;
                }
                break;
            case Op::CALL:
            case Op::CALLCODE:
                if (n == 6) {
                    call_line(op, l[2], l[1], l[3], l[4], l[5], indent);
                    return;
                }
                break;
            case Op::DELEGATECALL:
            case Op::STATICCALL:
                if (n == 5) {
                    call_line(op, l[2], l[1], Value::small(0), l[3], l[4], indent);
                    return;
                }
                break;
            case Op::SELFDESTRUCT:
                if (n == 1) {
                    start(indent);
                    o.col(Col::warning, "selfdestruct(");
                    {
                        Out a = o.sub();
                        a.add_color = false;
                        Printer pa(a, env);
                        pa.exp(l[0], P_NONE, false);
                        o.col(Col::fail, a.s);
                    }
                    o.col(Col::warning, ")");
                    nl();
                    return;
                }
                break;
            case Op::PRECOMPILED:
                if (n == 4) {
                    start(indent);
                    o.col(Col::blue, l[1].is_name() ? env.name_text(l[1]) : std::string("precompiled"));
                    o.put(" = ");
                    o.put(precompile_func(l[2].is_small() ? u32(l[2].small_val()) : 0));
                    o.put('(');
                    p.memory_joined(l[3], {});
                    o.put(") ");
                    o.code(Col::gray);
                    o.put("# precompiled");
                    o.end();
                    nl();
                    return;
                }
                break;
            case Op::CREATE:
                if (n == 3) {
                    start(indent);
                    o.put("create contract with ");
                    pret(l[1]);
                    o.put(" wei");
                    nl();
                    start(indent);
                    o.put("                code: ");
                    p.memory_joined(l[2], {});
                    nl();
                    return;
                }
                break;
            case Op::CREATE2:
                if (n == 4) {
                    start(indent);
                    o.put("create2 contract with ");
                    pret(l[1]);
                    o.put(" wei");
                    nl();
                    start(indent);
                    o.put("                salt: ");
                    pret(l[3]);
                    nl();
                    start(indent);
                    o.put("                code: ");
                    p.memory_joined(l[2], {});
                    nl();
                    return;
                }
                break;
            case Op::LABEL:
                if (n == 2) {
                    start(indent);
                    o.code(Col::green);
                    o.put("label ");
                    pret(l[0]);
                    o.put(" setvars: [");
                    setvar_list(l[1]);
                    o.put(']');
                    o.end();
                    nl();
                    return;
                }
                break;
            case Op::GOTO:
                if (n == 2) {
                    start(indent);
                    o.code(Col::green);
                    o.put("continue ");
                    pret(l[0]);
                    o.put(" [");
                    setvar_list(l[1]);
                    o.put(']');
                    o.end();
                    nl();
                    return;
                }
                break;
            case Op::SETVAR:
                if (n == 2) {
                    start(indent);
                    p.exp(l[0], P_NONE, false);
                    o.put(" = ");
                    pret(l[1]);
                    nl();
                    return;
                }
                break;
            case Op::INTERNAL:
                if (n == 3) {
                    // the call of a recursive internal function, the variables of its results
                    start(indent);
                    if (l[2].is_list() && l[2].size()) {
                        for (u32 i = 0; i < l[2].size(); ++i) {
                            if (i)
                                o.put(", ");
                            p.exp(l[2][i], P_NONE, false);
                        }
                        o.put(" = ");
                    }
                    o.put(std::format("internal_0x{:x}(", l[0].is_small() ? u64(l[0].small_val()) : 0));
                    if (l[1].is_list())
                        for (u32 i = 0; i < l[1].size(); ++i) {
                            if (i)
                                o.put(", ");
                            pret(l[1][i]);
                        }
                    o.put(')');
                    nl();
                    return;
                }
                break;
            case Op::LEAVE:
                if (n == 1) {
                    // the end of a recursive internal function: its results
                    start(indent);
                    o.put("return");
                    if (l[0].is_list() && l[0].size()) {
                        o.put(' ');
                        for (u32 i = 0; i < l[0].size(); ++i) {
                            if (i)
                                o.put(", ");
                            pret(l[0][i]);
                        }
                    }
                    nl();
                    return;
                }
                break;
            case Op::SETMEM:
                if (n == 2) {
                    setmem_line(l[0], l[1], indent);
                    return;
                }
                break;
            case Op::STORE:
                if (n == 4) {
                    store_line(l[0], l[1], l[2], l[3], indent);
                    return;
                }
                break;
            case Op::SET:
                if (n == 2) {
                    // lot 9's write of the storage: SET(ST(size, loc, width), v)
                    start(indent);
                    assign(l[0], l[1], [&] { pret(l[0]); });
                    nl();
                    return;
                }
                break;
            case Op::TSTORE:
                if (n == 2) {
                    start(indent);
                    o.col(Col::gray, "transient[");
                    pret(l[0]);
                    o.col(Col::gray, "]");
                    o.put(" = ");
                    pret(l[1]);
                    nl();
                    return;
                }
                break;
            case Op::STOP:
                start(indent);
                o.put("stop");
                nl();
                return;
            case Op::UNDEFINED: {
                start(indent);
                o.code(Col::warning);
                o.put("...");
                o.end();
                o.code(Col::gray);
                o.put("  # Decompilation aborted, sorry: ");
                o.put(undefined_reason(l));
                o.end();
                nl();
                return;
            }
            case Op::INVALID:
                // not a revert: all the gas is used (an assert of solidity < 0.8, a
                // jump to where it can't)
                start(indent);
                o.put("invalid");
                nl();
                return;
            case Op::REVERT:
            case Op::RETURN:
                if (n == 1) {
                    revert_return(op, l[0], indent);
                    return;
                }
                break;
            default:
                break;
        }
        // anything else: its op and operands
        start(indent);
        o.put(op_name(op));
        if (n) {
            o.put(' ');
            for (u32 i = 0; i < n; ++i) {
                if (i)
                    o.put(", ");
                p.exp(l[i], P_NONE, false);
            }
        }
        nl();
    }

    static std::string_view precompile_func(u32 a) noexcept
    {
        switch (a) {
            case 1: return "ecrecover";
            case 2: return "sha256hash";
            case 3: return "ripemd160hash";
            case 4: return "identity";
            case 5: return "bigModExp";
            case 6: return "bn256Add";
            case 7: return "bn256ScalarMul";
            case 8: return "bn256Pairing";
            default: return "precompiled";
        }
    }

    // python's tuple of the undefined line's reasons
    static std::string undefined_reason(Value l)
    {
        const u32 r = l.size() >= 1 && l[0].is_small() ? u32(l[0].small_val()) : 0;
        switch (UndefinedReason(r)) {
            case UndefinedReason::UNFINISHED: return "(\"decompilation didn't finish\",)";
            case UndefinedReason::COMPUTED_JUMP:
                return std::format("('jump to a parameter computed at runtime', {})",
                                   l.size() >= 2 && l[1].is_small() ? l[1].small_val() : 0);
            case UndefinedReason::AMBIGUOUS_CALL:
                return std::format("('return data of a call that depends on the path', {})",
                                   l.size() >= 2 && l[1].is_small() ? l[1].small_val() : 0);
        }
        return "('unknown',)";
    }

    void setvar_list(Value svs)
    {
        if (!svs.is_list())
            return;
        for (u32 i = 0; i < svs.size(); ++i) {
            if (i)
                o.put(", ");
            const Value sv = svs[i];
            if (sv.is(Op::SETVAR, 2)) {
                p.exp(sv[0], P_NONE, false);
                o.put(" = ");
                pret(sv[1]);
            } else {
                pret(sv);
            }
        }
    }

    // python's prettify(("setmem", range, val)): mem[...] = its data
    void setmem_line(Value range, Value val, u32 indent)
    {
        start(indent);
        // python's mem of the range
        if (range.is(Op::RANGE, 2)) {
            o.col(Col::header, "mem[");
            pret(range[0]);
            if (!is_small(range[1], 32)) {
                o.col(Col::header, " len ");
                pret(range[1]);
            }
            o.col(Col::header, "]");
        } else {
            o.col(Col::header, "mem[");
            pret(range);
            o.col(Col::header, "]");
        }
        o.put(" = ");
        // python's setmem_value (fix_widths): bytes of the range's width as they are
        if (val.is(Op::SIZED, 2) && range.is(Op::RANGE, 2) && val[0] == range[1])
            val = val[1];
        p.memory_joined(val, {});
        nl();
    }

    // python's set of storage.raw (the storage analysis' failure): the slot,
    // the bits written; x += v, x++...
    void store_target(Value size, Value off, Value slot)
    {
        if (size.is_small() && off.is_small() && off.small_val() >= 0) {
            const i64 s = size.small_val(), f = off.small_val();
            const bool cast = s != 256 - f;
            if (cast)
                o.col(Col::gray, s == 160 ? std::string("address(") : std::format("uint{}(", s));
            o.col(Col::green, "stor[");
            pret(slot);
            o.col(Col::green, "]");
            if (f > 0) {
                o.col(Col::green, ".field_");
                o.put(std::to_string(f));
            }
            if (cast)
                o.col(Col::gray, ")");
            return;
        }
        o.put("Mask(");
        pret(size);
        o.put(", ");
        pret(off);
        o.put(", ");
        o.col(Col::green, "stor[");
        pret(slot);
        o.col(Col::green, "]");
        o.put(')');
    }

    void store_line(Value size, Value off, Value slot, Value val, u32 indent)
    {
        start(indent);
        // (the value's reads of the place: STORAGE(size, off, slot))
        auto same = [&](Value r) { return r.is(Op::STORAGE, 3) && r[0] == size && r[1] == off && r[2] == slot; };
        assign_if(val, same, [&] { store_target(size, off, slot); });
        nl();
    }

    // python's ("set", idx, val) line: idx++, idx--, idx += v, idx -= v,
    // idx = val - `same` tells the reads of idx in val
    template <class Same, class Target>
    void assign_if(Value val, Same&& same, Target&& target)
    {
        if (val.is(Op::ADD, 2)) {
            const Value a = val[0], b = val[1];
            if (a.is_int() && same(b)) {
                const EvmInt v = display_int(EvmInt(a));
                target();
                if (v == -1)
                    o.put("--");
                else if (v == 1)
                    o.put("++");
                else if (v.sign() < 0) {
                    o.put(" -= ");
                    p.integer(-v, P_NONE);
                } else {
                    o.put(" += ");
                    p.integer(v, P_NONE);
                }
                return;
            }
            if (same(a) && b.is(Op::MUL, 2) && is_small(b[0], -1)) {
                target();
                o.put(" -= ");
                pret(b[1]);
                return;
            }
            if (same(a)) {
                target();
                o.put(" += ");
                pret(b);
                return;
            }
            if (same(b) && a.is(Op::MUL, 2) && is_small(a[0], -1)) {
                target();
                o.put(" -= ");
                pret(a[1]);
                return;
            }
            if (same(b)) {
                target();
                o.put(" += ");
                pret(a);
                return;
            }
        }
        target();
        o.put(" = ");
        pret(val);
    }

    template <class Target>
    void assign(Value idx, Value val, Target&& target)
    {
        assign_if(val, [&](Value r) { return r == idx; }, target);
    }

    // python's revert / return lines
    void revert_return(Op op, Value param, u32 indent)
    {
        const bool revert = op == Op::REVERT;
        if (revert && (param.is_none() || param.nil())) {
            start(indent);
            o.put("revert");
            nl();
            return;
        }
        if (param.is(Op::MEM, 1) && param[0].is(Op::RANGE, 2)) {
            const Value idx = param[0][0], len = param[0][1];
            start(indent);
            o.put(revert ? "revert with memory" : "return memory");
            nl();
            if (len.is(Op::SUB, 2) && len[1] == idx) {
                start(indent);
                o.put("  from  ");
                pret(idx);
                nl();
                start(indent);
                o.put("    to ");
                pret(len[0]);
                nl();
            } else {
                start(indent);
                o.put("  from ");
                pret(idx);
                nl();
                start(indent);
                o.put("   ");
                o.col(Col::warning, "len");
                o.put(' ');
                pret(len);
                nl();
            }
            return;
        }
        const std::string_view word = revert ? "revert with" : "return";
        std::vector<Out> res;
        MemoryOpts m;
        m.abi_text = true;
        m.selector = revert;
        if (revert && param.is(Op::SIZED, 2) && is_small(param[0], 4) && param[1].is_int())
            p.memory_elements(std::span<const Value>(&param, 1), m, res);  // (a custom error without params)
        else
            p.memory(param, m, res);
        if (res.empty()) {
            // no data
            start(indent);
            o.put(revert ? "revert" : "stop");
            nl();
            return;
        }
        // Panic(code)
        if (revert && param.is(Op::DATA, 2) && is_selector(param[0], 0x4e487b71)) {
            const Value code_el = param[1];
            Value code;
            if (code_el.is(Op::SIZED, 2) && is_small(code_el[0], 32) && code_el[1].is_int())
                code = code_el[1];
            else if (code_el.is_int())
                code = code_el;
            if (code.is_int()) {
                start(indent);
                o.put(word);
                o.put(" Panic(");
                const EvmInt c(code);
                o.put(int_dec(c));
                o.put(") ");
                if (const char* why = panic_text(c)) {
                    o.put(' ');
                    o.code(Col::gray);
                    o.put("# ");
                    o.put(why);
                    o.end();
                }
                nl();
                return;
            }
        }
        // revert("...") / require(..., "...")
        if (revert && param.is(Op::DATA) && param.size() >= 1 && is_selector(param[0], 0x08c379a0) && res.size() == 2 &&
            !res[1].s.empty() && res[1].s[0] == '\'') {
            start(indent);
            o.put(word);
            o.put(' ');
            o.append(res[1]);
            nl();
            return;
        }
        u64 chars = 0;
        for (usize i = 0; i < res.size(); ++i)
            chars += res[i].visible_chars() + (i ? 2 : 0);
        if (chars < 120 || !param.is(Op::DATA)) {
            start(indent);
            o.put(word);
            o.put(' ');
            for (usize i = 0; i < res.size(); ++i) {
                if (i)
                    o.put(", ");
                o.append(res[i]);
            }
            nl();
            return;
        }
        // long returns split into lines (kitties.getKitten); a sole 32 first
        // (an array, probably) goes with the next one
        if (res.size() > 1 && res[0].s == "32") {
            Out merged = res[1].sub();
            merged.put("32, ");
            merged.append(res[1]);
            res.erase(res.begin());
            res[0] = std::move(merged);
        }
        if (res.size() == 1) {
            start(indent);
            o.put(word);
            o.put(' ');
            o.append(res[0]);
            nl();
            return;
        }
        start(indent);
        o.put(word);
        o.put(' ');
        o.append(res[0]);
        o.put(", ");
        nl();
        for (usize i = 1; i < res.size(); ++i) {
            start(indent);
            o.spaces(word.size() + 1);
            o.append(res[i]);
            if (i + 1 < res.size())
                o.put(',');
            nl();
        }
    }

    static bool is_selector(Value el, u32 sel) noexcept
    {
        return el.is(Op::SIZED, 2) && is_small(el[0], 4) && is_small(el[1], sel);
    }

    static const char* panic_text(const EvmInt& c) noexcept
    {
        if (!c.fits_i64())
            return nullptr;
        switch (c.to_i64()) {
            case 0x00: return "Used for generic compiler inserted panics.";
            case 0x01: return "If you call assert with an argument that evaluates to false.";
            case 0x11:
                return "If an arithmetic operation results in underflow or overflow outside of an unchecked { ... } block.";
            case 0x12: return "If you divide or modulo by zero (e.g. 5 / 0 or 23 % 0).";
            case 0x21: return "If you convert a value that is too big or negative into an enum type.";
            case 0x22: return "If you access a storage byte array that is incorrectly encoded.";
            case 0x31: return "If you call .pop() on an empty array.";
            case 0x32:
                return "If you access an array, bytesN or an array slice at an out-of-bounds or negative index (i.e. x[i] "
                       "where i >= x.length or i < 0).";
            case 0x41: return "If you allocate too much memory or create an array that is too large.";
            case 0x51: return "If you call a zero-initialized variable of internal function type.";
            default: return nullptr;
        }
    }

    // ---- calls ----
    // python's split_selector + callee_name: the selector of the call
    struct Callee {
        Value fname;                      // the selector element, or NIL
        std::span<const Value> params;    // the params' elements (rest of a DATA)
        Value single;                     // the params when they're one value (not a DATA)
        bool none = true;                 // no params
    };

    Callee split_selector(Value fname, Value fparams)
    {
        Callee c;
        c.fname = fname.is_none() ? Value() : fname;
        if (!c.fname.nil()) {
            set_params(c, fparams);
            return c;
        }
        if (fparams.is(Op::SIZED, 2) && is_small(fparams[0], 4) && fparams[1].is_int()) {
            c.fname = fparams;
            return c;
        }
        if (fparams.is(Op::DATA) && fparams.size() >= 1 && fparams[0].is(Op::SIZED, 2) && is_small(fparams[0][0], 4) &&
            fparams[0][1].is_int()) {
            c.fname = fparams[0];
            const auto rest = fparams.args().subspan(1);
            if (rest.size() > 1) {
                c.params = rest;
                c.none = false;
            } else if (rest.size() == 1) {
                c.single = rest[0];
                c.none = false;
            }
            return c;
        }
        set_params(c, fparams);
        return c;
    }
    static void set_params(Callee& c, Value fparams)
    {
        if (fparams.is_none() || fparams.nil())
            return;
        c.none = false;
        if (fparams.is(Op::DATA)) {
            c.params = fparams.args();
            return;
        }
        c.single = fparams;
    }

    // python's callee_name: true when written
    bool callee_name(Value fname)
    {
        if (fname.nil())
            return false;
        Value sel = fname;
        if (fname.is(Op::SIZED, 2) && is_small(fname[0], 4) && fname[1].is_int())
            sel = fname[1];
        if (sel.is_int()) {
            const EvmInt v(sel);
            if (v.sign() >= 0 && v.bit_length() <= 32) {
                const u32 s = u32(v.to_u64().value_or(0));
                if (!known_fname(o, env.db(), s))
                    o.put(std::format("unknown{:08x}(?)", s));
                return true;
            }
        }
        if (sel.is(Op::MEM)) {
            pret(sel);
            return true;
        }
        return false;
    }
    bool has_callee_name(Value fname) const noexcept
    {
        if (fname.nil())
            return false;
        Value sel = fname;
        if (fname.is(Op::SIZED, 2) && is_small(fname[0], 4) && fname[1].is_int())
            sel = fname[1];
        if (sel.is_int()) {
            const EvmInt v(sel);
            return v.sign() >= 0 && v.bit_length() <= 32;
        }
        return sel.is(Op::MEM);
    }

    void call_line(Op op, Value addr, Value gas, Value wei, Value sel, Value params, u32 indent)
    {
        const Callee c = split_selector(sel, params);
        // the address: an int as its hex (padded when long)
        auto print_addr = [&](int ctx) {
            if (addr.is_int()) {
                const EvmInt a(addr);
                std::string h = int_hex(a);
                if (op == Op::CALL && h.size() > 24)
                    h = padded_hex(a, 40);
                o.put(h);
                return;
            }
            p.exp(addr, ctx, false);
        };
        const bool named = has_callee_name(c.fname);
        std::string_view funct_pad, value_pad, gas_pad, args_pad;
        start(indent);
        switch (op) {
            case Op::CALL:
                o.put("call ");
                print_addr(P_NONE);
                funct_pad = "   funct ", value_pad = "   value ", gas_pad = "     gas ", args_pad = "    args ";
                break;
            case Op::STATICCALL:
                o.put("static call ");
                print_addr(P_NONE);
                funct_pad = "     funct ", gas_pad = "        gas ", args_pad = "       args ";
                break;
            case Op::DELEGATECALL:
                o.raw_col(Col::warning, "delegate");
                o.put(' ');
                print_addr(P_ATOM);
                funct_pad = "   funct ", gas_pad = "     gas ", args_pad = "    args ";
                break;
            default:  // CALLCODE
                o.raw_col(Col::warning, "codecall");
                o.put(' ');
                print_addr(P_ATOM);
                funct_pad = "   funct ", value_pad = "   value ", gas_pad = "     gas ", args_pad = "    args ";
                break;
        }
        if (named) {
            o.put('.');
            callee_name(c.fname);
        }
        o.put(" with:");
        nl();
        if (!named && !c.fname.nil()) {
            start(indent);
            o.put(funct_pad);
            if (op == Op::DELEGATECALL || op == Op::CALLCODE)
                p.exp(c.fname, P_ATOM, false);
            else
                pret(c.fname);
            nl();
        }
        if (!value_pad.empty() && !is_small(wei, 0)) {
            start(indent);
            o.put(value_pad);
            pret(wei);
            o.put(' ');
            o.code(Col::gray);
            o.put("wei");
            o.end();
            nl();
        }
        start(indent);
        o.put(gas_pad);
        pret(gas);
        nl();
        if (!c.none) {
            std::vector<Out> items;
            MemoryOpts m;
            m.selector = true;
            if (!c.single.nil())
                p.memory(c.single, m, items);
            else
                p.memory_elements(c.params, m, items);
            if (!items.empty()) {
                start(indent);
                o.put(args_pad);
                for (usize i = 0; i < items.size(); ++i) {
                    if (i)
                        o.put(", ");
                    o.append(items[i]);
                }
                nl();
            }
        }
    }

    // ---- logs ----
    void log_line(Value l, u32 indent)
    {
        const Value data = l[0];
        const std::span<const Value> topics = l.args().subspan(1);
        // the params of a log are its data, then its topics after the first,
        // which is the signature of the event (unless it's anonymous)
        std::vector<Out> data_params, topic_params;
        {
            AddColor plain(o, false);
            p.memory(data, {}, data_params);
            for (usize i = 1; i < topics.size(); ++i) {
                Out t = o.sub();
                Printer pt(t, env);
                pt.exp(topics[i], P_NONE, false);
                topic_params.push_back(std::move(t));
            }
        }
        auto join = [](const std::vector<std::string>& v, std::string_view sep) {
            std::string r;
            for (usize i = 0; i < v.size(); ++i) {
                if (i)
                    r += sep;
                r += v[i];
            }
            return r;
        };
        std::vector<std::string> res_params;
        for (const Out& d : data_params)
            res_params.push_back(d.s);
        for (const Out& t : topic_params)
            res_params.push_back(t.s);
        auto gray_line = [&](const std::string& text) {
            start(indent);
            o.col(Col::gray, text);
            nl();
        };
        if (topics.empty()) {
            // a log of no topics: its data, if it has any
            std::string t = "log " + join(res_params, ", ");
            while (!t.empty() && t.back() == ' ')
                t.pop_back();
            gray_line(t);
            return;
        }
        std::optional<sigdb::Entry> abi;
        if (env.db() && topics[0].is_int()) {
            u8 topic[32];
            Word256::from_value(topics[0]).to_be(topic);
            abi = env.db()->event(std::span<const u8, 32>(topic, 32));
        }
        std::vector<std::string> listed;
        for (const Out& d : data_params)
            listed.push_back(d.s);
        for (const Out& t : topic_params)
            listed.push_back("indexed " + t.s);
        if (!abi) {
            std::string e;
            if (topics[0].is_int()) {
                e = padded_hex(EvmInt(topics[0]), 64);
            } else {
                Out t = o.sub();
                t.add_color = false;
                Printer pt(t, env);
                pt.exp(topics[0], P_NONE, false);
                e = t.s;
            }
            gray_line(std::format("log {}:{}{}", e, listed.empty() ? "" : " ", join(listed, ", ")));
            return;
        }
        // the event's inputs (python's fix_input_names: _paramN when unnamed)
        struct Input {
            std::string type, name;
            bool indexed;
        };
        std::vector<Input> inputs;
        {
            usize i = 0;
            for (const sigdb::Field f : abi->params()) {
                Input in;
                std::string t;
                f.type().append_text(t);
                in.type = db_text(t);
                in.name = f.name().empty() ? std::format("_param{}", i + 1) : db_text(f.name());
                in.indexed = abi->indexed(i);
                inputs.push_back(std::move(in));
                ++i;
            }
        }
        const std::string fname = db_text(abi->name());
        std::string e = fname + "(";
        for (usize i = 0; i < inputs.size(); ++i) {
            if (i)
                e += ", ";
            e += inputs[i].type + " " + inputs[i].name;
        }
        e += ")";
        std::vector<usize> not_indexed, indexed;
        for (usize i = 0; i < inputs.size(); ++i)
            (inputs[i].indexed ? indexed : not_indexed).push_back(i);
        if (inputs.empty() && res_params.empty()) {
            gray_line("log " + e);
            return;
        }
        if (not_indexed.size() == data_params.size() && indexed.size() == topic_params.size()) {
            // in_log = not_indexed + indexed, zipped with res_params; printed
            // in the order of the declaration
            std::vector<std::string> by_input(inputs.size());
            usize k = 0;
            for (const usize i : not_indexed)
                by_input[i] = res_params[k++];
            for (const usize i : indexed)
                by_input[i] = res_params[k++];
            auto pline = [&](usize i) {
                return std::format("{}{} {}={}", inputs[i].type, inputs[i].indexed ? " indexed" : "", inputs[i].name,
                                   by_input[i]);
            };
            if (inputs.size() == 1) {
                gray_line(std::format("log {}({})", fname, pline(0)));
                return;
            }
            gray_line(std::format("log {}(", fname));
            gray_line(std::format("      {},", pline(0)));
            for (usize i = 1; i + 1 < inputs.size(); ++i)
                gray_line(std::format("      {},", pline(i)));
            gray_line(std::format("      {})", pline(inputs.size() - 1)));
            return;
        }
        // not the params of the abi - an event of the same signature,
        // indexed otherwise: the signature, then what the log has
        std::string t = std::format("log {}{} {}", e, listed.empty() ? "" : ":", join(listed, ", "));
        while (!t.empty() && t.back() == ' ')
            t.pop_back();
        gray_line(t);
    }

    // ---- the contract's def SafeMath (python safemath.pretty_defs) ----
    void safemath_defs(const SafeMathTable& t)
    {
        constexpr u32 body = 6;
        for (u32 i = 0; i < t.fns.size(); ++i) {
            poll();
            const SafeMathTable::Fn& f = t.fns[i];
            // "  def name(a, b, errorMessage, errorMessage2...):", a comment
            // where the compiler's checks are (a panic)
            std::vector<std::string> params{"a"};
            if (f.params != 1)
                params.emplace_back("b");
            for (u32 k = 0; k < f.messages; ++k)
                params.push_back(k == 0 ? std::string("errorMessage") : std::format("errorMessage{}", k + 1));
            o.put("  ");
            green("def ");
            o.put(safemath_name(t, i));
            o.put('(');
            for (usize k = 0; k < params.size(); ++k) {
                if (k)
                    o.put(", ");
                o.put(params[k]);
            }
            o.put("):");
            if (std::any_of(f.checks.begin(), f.checks.end(),
                            [](const SafeMathTable::Check& c) { return c.kind == SafeMathTable::Fail::Panic; })) {
                o.put("  ");
                o.code(Col::gray);
                o.put("# solidity >= 0.8");
                o.end();
            }
            nl();
            for (const SafeMathTable::Check& c : f.checks)
                safemath_check(c);
            revert_return(Op::RETURN, f.result, body);
        }
    }

    // a check of a function of the SafeMath: python's pprint_logic([("if",
    // cond, [fail_line(kind, message)])], 6) - or, failing with a message
    // parameter, `if cond: revert with errorMessage`
    void safemath_check(const SafeMathTable::Check& c)
    {
        constexpr u32 body = 6;
        if (c.message) {
            start(body);
            o.put("if ");
            cond(c.cond);
            o.put(':');
            nl();
            start(body + INDENT_LEN);
            o.put("revert with ");
            o.put(*c.message == 0 ? std::string("errorMessage") : std::format("errorMessage{}", *c.message + 1));
            nl();
            return;
        }
        switch (c.kind) {
            case SafeMathTable::Fail::Revert:
            case SafeMathTable::Fail::Invalid:
                // python's check_word: require / assert, the condition negated
                start(body);
                o.put(c.kind == SafeMathTable::Fail::Revert ? "require " : "assert ");
                p.negated(c.cond);
                nl();
                return;
            case SafeMathTable::Fail::Panic:
            case SafeMathTable::Fail::Error:
                break;
        }
        start(body);
        o.put("if ");
        cond(c.cond);
        o.put(':');
        nl();
        if (c.kind == SafeMathTable::Fail::Panic) {
            // revert with Panic(code), as python's fail_line makes it
            start(body + INDENT_LEN);
            o.put("revert with Panic(");
            o.put(std::to_string(c.panic));
            o.put(") ");
            if (const char* why = panic_text(EvmInt(i64(c.panic)))) {
                o.put(' ');
                o.code(Col::gray);
                o.put("# ");
                o.put(why);
                o.end();
            }
            nl();
            return;
        }
        // revert with 'message' (the first call's): python's fail_line of it
        if (c.fail.is(Op::REVERT, 1))
            if (const auto m = error_message_text(c.fail[0])) {
                start(body + INDENT_LEN);
                o.put("revert with ");
                o.put(*m);
                nl();
                return;
            }
        if (c.fail.is_expr())
            line(c.fail, body + INDENT_LEN, {}, false);
    }
};

// ---- Printer's entries ----------------------------------------------------------------------

void Printer::lines(Value trace, u32 indent, std::span<const LoopRef> loops, bool add_breaks)
{
    LineImpl x(*this);
    x.lines(trace, indent, loops, add_breaks);
}

void Printer::line(Value l, u32 indent, std::span<const LoopRef> loops)
{
    LineImpl x(*this);
    x.line(l, indent, loops, false);
}

void Printer::safemath_defs(const SafeMathTable& t)
{
    LineImpl x(*this);
    x.safemath_defs(t);
}

}  // namespace pan::output::detail
