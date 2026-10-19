// Lines: their operands' kinds, the walk of simplify_exps, the line-level
// rules of python's simplify_exp / cleanup_mems (no bytes of data: None,
// writes of nothing dropped).
#include "simplify/internal.hpp"
#include "simplify/simplify.hpp"

#include "algebra/construct.hpp"
#include "core/context.hpp"
#include "mem/memory.hpp"

namespace pan::simplify {

namespace {

struct LineState final : ModuleState {
    Memo<Value, Value> line, trace;
    void clear_caches() override {
        line.clear();
        trace.clear();
    }
};

// the run's flags: kept through a compaction (their entry lines imported)
struct RunState final : ModuleState {
    RunFlags flags;
    Value next_entry;
    bool compact_prepare(Importer& imp) override {
        next_entry = flags.entry_lines.nil() ? Value() : imp(flags.entry_lines);
        return true;
    }
    void compact_commit() noexcept override { flags.entry_lines = next_entry; }
    void compact_abort() noexcept override { next_entry = Value(); }
};

LineState& lst() { return cx().state<LineState>(); }

bool is_int(Value v, i64 x) { return v.is_small() && v.small_val() == x; }

// bytes of none (python: a mem of length 0 is None in a data's place)
bool no_bytes(Value b) {
    if (b.is_none()) return true;
    if (b.is(Op::MEM, 1) && b[0].is(Op::RANGE, 2) && is_int(b[0][1], 0)) return true;
    if (b.is(Op::SIZED, 2) && is_int(b[0], 0)) return true;
    if (b.is(Op::DATA) && b.size() == 0) return true;
    if ((b.is(Op::CALLDATA_BYTES, 2) || b.is(Op::CODE_BYTES, 2)) && is_int(b[1], 0)) return true;
    if (b.is(Op::RETURNDATA_BYTES, 3) && is_int(b[2], 0)) return true;
    return false;
}

// the line rules; NIL: drop the line
Value line_rules(Value l) {
    switch (l.op()) {
        case Op::SETMEM: {
            // a write of no bytes, a copy of memory onto itself: nothing changes
            if (l[0].is(Op::RANGE, 2) && is_int(l[0][1], 0)) return Value();
            if (!run_flags().msize && l[1].is(Op::MEM, 1) && l[1][0] == l[0]) return Value();
            return l;
        }
        case Op::RETURN:
            if (no_bytes(l[0])) return mk(Op::STOP, std::span<const Value>{});
            return l;
        case Op::REVERT:
            if (!l[0].is_none() && no_bytes(l[0])) return mk(Op::REVERT, None);
            return l;
        case Op::LOG0:
        case Op::LOG1:
        case Op::LOG2:
        case Op::LOG3:
        case Op::LOG4:
            if (!l[0].is_none() && no_bytes(l[0])) {
                SmallVec<Value, 6> a(l.args());
                a[0] = None;
                return mk_like(l, a.span());
            }
            return l;
        case Op::CALL:
        case Op::CALLCODE:
        case Op::DELEGATECALL:
        case Op::STATICCALL: {
            const u32 s = l.size() - 2, p = l.size() - 1;
            if ((!l[s].is_none() && no_bytes(l[s])) || (!l[p].is_none() && no_bytes(l[p]))) {
                SmallVec<Value, 6> a(l.args());
                if (no_bytes(a[s])) a[s] = None;
                if (no_bytes(a[p])) a[p] = None;
                return mk_like(l, a.span());
            }
            return l;
        }
        default: return l;
    }
}

}  // namespace

RunFlags& run_flags() { return cx().state<RunState>().flags; }

Arg arg_kind(Op op, u32 i) {
    switch (op) {
        case Op::IF:
        case Op::MERGED_IF: return i == 0 ? Arg::Expr : Arg::Trace;
        case Op::WHILE: return i == 0 ? Arg::Expr : i == 1 ? Arg::Trace : i == 2 ? Arg::Raw : Arg::Setvars;
        case Op::CONTINUE:
        case Op::LABEL:
        case Op::GOTO: return i == 0 ? Arg::Raw : Arg::Setvars;
        case Op::LOOP_PATH: return i == 0 ? Arg::Trace : Arg::Raw;
        case Op::BREAK:
        case Op::UNDEFINED:
        case Op::INVALID:
        case Op::STOP: return Arg::Raw;
        case Op::SETVAR: return i == 0 ? Arg::Raw : Arg::Expr;
        case Op::INTERNAL: return i == 1 ? Arg::Values : Arg::Raw;
        case Op::LEAVE: return Arg::Values;
        case Op::ASM: return i == 3 ? Arg::Values : Arg::Raw;
        case Op::CALL:
        case Op::CALLCODE:
        case Op::DELEGATECALL:
        case Op::STATICCALL:
        case Op::CREATE:
        case Op::CREATE2: return i == 0 ? Arg::Raw : Arg::Expr;
        case Op::PRECOMPILED: return i == 3 ? Arg::Expr : Arg::Raw;
        default: return Arg::Expr;
    }
}

Value mk_like_checked(Value orig, std::span<const Value> args) {
    Value n = mk_like(orig, args);
    if (n == orig) return n;
    return mem::keep_widths(orig, n);
}

Value make_trace(std::span<const Value> lines) { return mk_trace(lines); }

namespace {

Value subst_rec(Value e, std::span<const Value> from, std::span<const Value> to, Memo<Value, Value>& memo) {
    if (e.is_name()) {
        for (usize i = 0; i < from.size(); ++i)
            if (from[i] == e) return to[i];
        return e;
    }
    if (!(e.is_expr() || e.is_list()) || !e.has_flags(F_VAR)) return e;
    if (const Value* r = memo.find(e)) return *r;
    check_stack();
    SmallVec<Value, 8> args;
    bool changed = false;
    for (Value a : e.args()) {
        Value n = subst_rec(a, from, to, memo);
        if (n != a) changed = true;
        args.push_back(n);
    }
    Value r = changed ? mk_like_checked(e, args.span()) : e;
    memo.put(e, r);
    return r;
}

}  // namespace

Value substitute(Value e, std::span<const Value> from, std::span<const Value> to) {
    if (from.empty() || !e.has_flags(F_VAR)) return e;
    Memo<Value, Value> memo;
    return subst_rec(e, from, to, memo);
}

void setvars_of(Value setvars, SmallVec<Value, 8>& names, SmallVec<Value, 8>& values) {
    if (!setvars.is_list()) return;
    for (Value sv : setvars.args())
        if (sv.is(Op::SETVAR, 2)) {
            names.push_back(sv[0]);
            values.push_back(sv[1]);
        }
}

bool assignments(Value line, SmallVec<Value, 8>& names, SmallVec<Value, 8>& values) {
    if (line.is(Op::SETVAR, 2)) {
        names.push_back(line[0]);
        values.push_back(line[1]);
        return true;
    }
    if (line.is(Op::CONTINUE, 2) || line.is(Op::GOTO, 2) || line.is(Op::LABEL, 2)) {
        setvars_of(line[1], names, values);
        return true;
    }
    return false;
}

u32 exp_size(Value e, u32 cap) {
    if (!e.is_expr() && !e.is_list()) return 1;
    u32 n = 1;
    SmallVec<Value, 32> todo;
    for (Value a : e.args()) todo.push_back(a);
    while (!todo.empty()) {
        if (n > cap) return n;
        Value v = todo.back();
        todo.pop_back();
        ++n;
        if (v.is_expr() || v.is_list())
            for (Value a : v.args()) todo.push_back(a);
    }
    return n;
}

Value simplify_line(Value line) {
    if (!line.is_expr()) return line;
    if (const Value* r = lst().line.find(line)) return *r;
    check_stack();
    const Op op = line.op();
    SmallVec<Value, 8> args;
    bool changed = false;
    for (u32 i = 0; i < line.size(); ++i) {
        Value a = line[i];
        Value n = a;
        switch (arg_kind(op, i)) {
            case Arg::Expr: n = simplify_at(a, operand_pos(op, i, line.size())); break;
            case Arg::Trace: n = simplify_exps(a); break;
            case Arg::Setvars:
            case Arg::Values: {
                if (!a.is_list()) break;
                SmallVec<Value, 8> items;
                bool ch = false;
                for (Value x : a.args()) {
                    Value y = x;
                    if (x.is(Op::SETVAR, 2)) {
                        Value e = simplify_word(x[1]);
                        if (e != x[1]) y = mk(Op::SETVAR, x[0], e);
                    } else {
                        y = simplify_word(x);
                    }
                    if (y != x) ch = true;
                    items.push_back(y);
                }
                if (ch) n = mk_like(a, items.span());
                break;
            }
            case Arg::Raw: break;
        }
        if (n != a) changed = true;
        args.push_back(n);
    }
    Value r = changed ? mk_like_checked(line, args.span()) : line;
    r = line_rules(r);
    if (!r.nil() && r != line) cx().pcs.inherit(r, line);
    lst().line.put(line, r);
    return r;
}

Value simplify_exps(Value trace) {
    if (!trace.is_list()) return trace;
    if (const Value* r = lst().trace.find(trace)) return *r;
    SmallVec<Value, 32> out;
    bool changed = false;
    for (Value l : trace.args()) {
        poll();
        Value n = simplify_line(l);
        if (n != l) changed = true;
        if (!n.nil()) out.push_back(n);
    }
    Value r = changed ? mk_trace(out.span()) : trace;
    lst().trace.put(trace, r);
    return r;
}

}  // namespace pan::simplify
