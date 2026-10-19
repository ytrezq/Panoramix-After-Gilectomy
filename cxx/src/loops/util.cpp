// Lot 6's helpers (internal.hpp): what a trace does, substitutions.
#include "loops/internal.hpp"

#include "algebra/construct.hpp"
#include "algebra/eval.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"

namespace pan::loops::detail {

namespace {

// the jumps found, per (node, loop id): a pure function of the structure
struct JumpState final : ModuleState {
    Memo<Key2, u8> memo;  // 1 + answer
};

}  // namespace

bool has_jump_to(Value v, Value id) {
    if (!(v.is_expr() || v.is_list()) || !v.has_flags(F_LOOPCTL)) return false;
    if (v.is_expr()) {
        switch (v.op()) {
            case Op::GOTO:
            case Op::CONTINUE: return v[0] == id;
            case Op::IF:
            case Op::MERGED_IF:
            case Op::WHILE:
            case Op::LOOP_PATH: break;
            default: return false;  // (a LABEL's setvars: no jump)
        }
    }
    JumpState& st = cx().state<JumpState>();
    const Key2 k{v.raw(), id.raw()};
    if (const u8* r = st.memo.find(k)) return *r == 2;
    check_stack();
    bool found = false;
    if (v.is_list()) {
        for (Value l : v.args())
            if (has_jump_to(l, id)) {
                found = true;
                break;
            }
    } else {
        for (Value a : v.args())
            if (a.is_list() && has_jump_to(a, id)) {
                found = true;
                break;
            }
    }
    st.memo.put(k, found ? 2 : 1);
    return found;
}

bool line_falls_through(Value l) {
    if (!l.is_expr()) return true;
    switch (l.op()) {
        case Op::IF:
        case Op::MERGED_IF: return l.size() < 3 || falls_through(l[1]) || falls_through(l[2]);
        case Op::GOTO:
        case Op::CONTINUE:
        case Op::BREAK: return false;
        default: return !has(l.op(), HALT);
    }
}

bool falls_through(Value trace) {
    if (!trace.is_list() || trace.size() == 0) return true;
    check_stack();
    return line_falls_through(trace[trace.size() - 1]);
}

bool is_check_branch(Value branch) {
    return branch.is_list() && branch.size() != 0 && !branch.has_flags(F_LOOPCTL) && !falls_through(branch);
}

void setvar_names(Value setvars, SmallVec<Value, 8>& out) {
    if (!setvars.is_list()) return;
    for (Value x : setvars.args())
        if (x.is(Op::SETVAR, 2)) out.push_back(x[0]);
}

void setvar_values(Value setvars, SmallVec<Value, 8>& out) {
    if (!setvars.is_list()) return;
    for (Value x : setvars.args())
        if (x.is(Op::SETVAR, 2)) out.push_back(x[1]);
}

Value setvar_of(Value setvars, Value name) {
    if (!setvars.is_list()) return Value();
    for (Value x : setvars.args())
        if (x.is(Op::SETVAR, 2) && x[0] == name) return x[1];
    return Value();
}

namespace {

// a walk of v's nodes, each once (hash-consed DAGs: never a tree's cost);
// f(node) returns true to stop (found), false to go on; descend(node) says
// whether its children are walked
template <class F, class D>
bool walk_find(Value v, F&& f, D&& descend) {
    SmallVec<Value, 64> todo{v};
    MemoSet<Value> seen;
    while (!todo.empty()) {
        poll();
        Value x = todo.back();
        todo.pop_back();
        if (f(x)) return true;
        if (!(x.is_expr() || x.is_list()) || !descend(x)) continue;
        if (!seen.add(x)) continue;
        for (Value a : x.children()) todo.push_back(a);
    }
    return false;
}

// the operands of a line that name what it sets (not reads)
bool is_target(Value line, u32 i) {
    switch (line.op()) {
        case Op::SETVAR: return i == 0;
        case Op::PRECOMPILED: return i == 1;
        case Op::INTERNAL: return i == 2;
        default: return false;
    }
}

}  // namespace

bool reads_name(Value v, Value name) {
    if (v == name) return true;
    if (!(v.is_expr() || v.is_list()) || !v.has_flags(name.flags())) return false;
    SmallVec<Value, 64> todo{v};
    MemoSet<Value> seen;
    while (!todo.empty()) {
        poll();
        Value x = todo.back();
        todo.pop_back();
        if (x == name) return true;
        if (!(x.is_expr() || x.is_list()) || !x.has_flags(name.flags())) continue;
        if (!seen.add(x)) continue;
        for (u32 i = 0; i < x.size(); ++i)
            if (!(x.is_expr() && is_target(x, i))) todo.push_back(x[i]);
    }
    return false;
}

bool reads_any(Value v, std::span<const Value> names) {
    for (Value n : names)
        if (reads_name(v, n)) return true;
    return false;
}

bool sets_name(Value v, Value name) {
    return walk_find(
        v,
        [&](Value x) {
            if (!x.is_expr()) return false;
            switch (x.op()) {
                case Op::SETVAR: return x.size() == 2 && x[0] == name;
                case Op::PRECOMPILED: return x.size() == 4 && x[1] == name;
                case Op::INTERNAL: {
                    if (x.size() != 3) return false;
                    const Value results = x[2];
                    if (results.is_list())
                        for (Value r : results.args())
                            if (r == name) return true;
                    return false;
                }
                default: return false;
            }
        },
        [](Value x) { return x.is_list() || has(x.op(), LINE); });
}

u32 node_count(Value v, u32 cap) {
    if (!(v.is_expr() || v.is_list())) return 1;
    u32 n = 0;
    SmallVec<Value, 64> todo{v};
    while (!todo.empty()) {
        if (++n > cap) return n;
        Value x = todo.back();
        todo.pop_back();
        if (x.is_expr() || x.is_list())
            for (Value a : x.children()) todo.push_back(a);
    }
    return n;
}

// ---- Subst --------------------------------------------------------------------------------

const Value* Subst::find(Value name) const {
    for (const NamePair& p : map_)
        if (p.name == name) return &p.value;
    return nullptr;
}

Value Subst::operator()(Value v) {
    if (v.is_name()) {
        if (const Value* r = find(v)) return *r;
        return v;
    }
    if (!(v.is_expr() || v.is_list()) || !v.has_flags(F_VAR) || map_.empty()) return v;
    if (const Value* r = memo_.find(v)) return *r;
    check_stack();
    SmallVec<Value, 8> args;
    bool changed = false;
    const bool expr = v.is_expr();
    for (u32 i = 0; i < v.size(); ++i) {
        Value a = v[i];
        Value n = expr && is_target(v, i) ? a : (*this)(a);
        if (n != a) changed = true;
        args.push_back(n);
    }
    Value r = v;
    if (changed) r = expr && alg::is_pure(v.op()) ? alg::apply(v.op(), args.span()) : mk_like(v, args.span());
    if (r != v && expr && has(v.op(), LINE)) cx().pcs.inherit(r, v);
    memo_.put(v, r);
    return r;
}

// ---- Renamer ------------------------------------------------------------------------------

Value Renamer::operator()(Value v) {
    if (v.is_name()) {
        for (const NamePair& p : map_)
            if (v == p.name) return p.value;
        return v;
    }
    if (!(v.is_expr() || v.is_list()) || !v.has_flags(F_VAR) || map_.empty()) return v;
    if (const Value* r = memo_.find(v)) return *r;
    check_stack();
    SmallVec<Value, 8> args;
    bool changed = false;
    for (Value a : v.children()) {
        Value n = (*this)(a);
        if (n != a) changed = true;
        args.push_back(n);
    }
    Value r = v;
    if (changed) r = v.is_expr() && alg::is_pure(v.op()) ? alg::apply(v.op(), args.span()) : mk_like(v, args.span());
    if (r != v && v.is_expr() && has(v.op(), LINE)) cx().pcs.inherit(r, v);
    memo_.put(v, r);
    return r;
}

}  // namespace pan::loops::detail
