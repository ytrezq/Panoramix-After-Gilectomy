// Loop rewrites (python loop_to_setmem, loop_to_setmem_from_storage,
// propagate_storage_in_loops, replace_while_var; asm loops.s), each sound by
// construction:
//
//  - loop_to_setmem: WHILE(cond, {SETMEM(RANGE(p, 32), v), CONTINUE(id, S)},
//    id, S0) whose induction is proven (trips, endvars of every variable), p
//    made of the loop's variables and what the loop doesn't change, moving
//    by D = +-32 every iteration: the iterations write [p0, p0 + 32 trips)
//    (D = 32) or [p_end + 32, p0 + 32) (D = -32), p0 = p at the start, p_end
//    = p after the last iteration - as one SETMEM, then the endvars:
//      v = 0                    SETMEM(range, 0)
//      v = MEM(RANGE(q, 32)), q moving by D too: SETMEM(range, MEM(range of
//          q)), a copy - one SETMEM reads all of its source before it writes,
//          the loop reads each word before the iterations after it write:
//          the same when the loop never reads what it wrote before - its
//          source not behind its destination (D = 32: q0 >= p0, or the two
//          apart), proven; else only `dubious` (python's "we should check
//          for overwrites here, but skipping for now")
//      v = CALLDATALOAD(q), q moving by D: SETMEM(range, CALLDATA_BYTES(...))
//    python's loop_to_setmem_from_storage (its storage range of slots) has
//    no form here: such a loop stays.
//  - propagate_storage_in_loops: a loop variable v starting at h + k (h a
//    SHA3 term the loop doesn't change: a storage array's start) as v' = v -
//    h: its start k, every read of it in the loop v' + h, every write of it
//    there (its CONTINUEs', its setvars) e - h; after the loop v = v' + h set
//    back (lot 7 drops it when nothing reads it). Exact whatever the steps
//    (python's only for additive ones: its TODO).
//  - rename_var: every occurrence of a name.
#include "loops/loops.hpp"

#include <algorithm>
#include <memory_resource>
#include <vector>

#include "algebra/compare.hpp"
#include "algebra/construct.hpp"
#include "algebra/linear.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "loops/internal.hpp"
#include "mem/memory.hpp"
#include "simplify/effects.hpp"

namespace pan::loops {

using namespace detail;

namespace {

Value small(i64 x) { return Value::small(x); }

}  // namespace

Value loop_to_setmem(Value w, const RewriteOptions& opts) {
    if (!w.is(Op::WHILE, 4)) return w;
    const Value body = w[1], sv = w[3];
    if (!body.is_list() || body.size() != 2 || !sv.is_list()) return w;
    const Value sm = body[0], cont = body[1];
    if (!sm.is(Op::SETMEM, 2) || !cont.is(Op::CONTINUE, 2) || cont[0] != w[2]) return w;
    const Value r = sm[0], v = sm[1];
    if (!r.is(Op::RANGE, 2) || r[1] != small(32)) return w;
    const auto ind = induction(w);
    if (!ind || ind->trips.nil() || ind->endvars.nil()) return w;
    SmallVec<Value, 8> names;
    setvar_names(sv, names);
    const std::span<const Value> ns(names.data(), names.size());
    // every variable's value after the loop known
    if (ind->endvars.size() != names.size()) return w;
    for (Value e : ind->endvars.args())
        if (reads_any(e[1], ns)) return w;
    bool ok = false;
    const simplify::EffectSummary others = but_vars(simplify::summary(w), ns, ok);
    if (!ok) return w;
    const Value p = r[0];
    const auto dp = move_of(p, ns, cont[1], others);
    if (!dp || !(*dp == small(32) || *dp == small(-32))) return w;
    const bool up = *dp == small(32);
    const Value len = alg::mul(small(32), ind->trips);
    // the lowest address written, as the loop starts
    auto low = [&](Value addr) {
        const Value first = at(addr, ns, sv);
        if (up) return first;
        return alg::add(at(addr, ns, ind->endvars), small(32));
    };
    const Value p_lo = low(p);
    Value value;
    if (v == small(0)) {
        value = small(0);
    } else if (v.is(Op::MEM, 1) && v[0].is(Op::RANGE, 2) && v[0][1] == small(32)) {
        const Value q = v[0][0];
        const auto dq = move_of(q, ns, cont[1], others);
        if (!dq || *dq != *dp) return w;
        const Value q_lo = low(q);
        if (!opts.dubious) {
            // the loop never reads a word it wrote: the source not behind the
            // destination in the copy's direction, or apart
            const Value dst = mem::make_range(p_lo, len), src = mem::make_range(q_lo, len);
            const bool apart = mem::overlaps(dst, src) == Tri::False;
            const bool ahead = up ? alg::le(p_lo, q_lo) == Tri::True : alg::le(q_lo, p_lo) == Tri::True;
            if (!apart && !ahead) return w;
        }
        value = mk(Op::MEM, mem::make_range(q_lo, len));
    } else if (v.is(Op::CALLDATALOAD, 1)) {
        const Value q = v[0];
        const auto dq = move_of(q, ns, cont[1], others);
        if (!dq || *dq != *dp) return w;
        value = mk(Op::CALLDATA_BYTES, low(q), len);
    } else {
        return w;
    }
    SmallVec<Value, 8> lines;
    Value set = mk(Op::SETMEM, mem::make_range(p_lo, len), value);
    // (the endvars run after it: what they read unchanged by it)
    for (Value e : ind->endvars.args())
        if (simplify::affects(set, e[1])) return w;
    cx().pcs.inherit(set, sm);
    lines.push_back(set);
    for (Value e : ind->endvars.args()) lines.push_back(e);
    return mk_trace(lines.span());
}

Value loops_to_setmems(Value trace, const RewriteOptions& opts) {
    if (!trace.is_list() || !trace.has_flags(F_LOOPCTL)) return trace;
    check_stack();
    SmallVec<Value, 32> out;
    bool changed = false;
    for (Value l : trace.args()) {
        poll();
        if (!l.is_expr() || !l.has_flags(F_LOOPCTL)) {
            out.push_back(l);
            continue;
        }
        switch (l.op()) {
            case Op::IF:
            case Op::MERGED_IF: {
                Value t = loops_to_setmems(l[1], opts), e = loops_to_setmems(l[2], opts);
                Value r = mk_like(l, std::span<const Value>({l[0], t, e}));
                cx().pcs.inherit(r, l);
                changed |= r != l;
                out.push_back(r);
                break;
            }
            case Op::WHILE: {
                Value b = loops_to_setmems(l[1], opts);
                Value x = b == l[1] ? l : mk(Op::WHILE, l[0], b, l[2], l[3]);
                if (x != l) cx().pcs.inherit(x, l);
                Value r = loop_to_setmem(x, opts);
                if (r.is_list()) {
                    for (Value y : r.args()) out.push_back(y);
                    changed = true;
                } else {
                    changed |= r != l;
                    out.push_back(r);
                }
                break;
            }
            default: out.push_back(l); break;
        }
    }
    return changed ? mk_trace(out.span()) : trace;
}

// ---- propagate_storage_in_loops ------------------------------------------------------------------

namespace {

// the SHA3 term of a start value (a storage array's start: python
// storage_sha3), NIL when none
Value sha3_term(Value s) {
    if (s.is(Op::SHA3)) return s;
    if (!s.is(Op::ADD)) return Value();
    alg::Linear l = alg::linear(s);
    for (const alg::LinTerm& t : l.terms)
        if (t.term.is(Op::SHA3) && t.coeff == small(1)) return t.term;
    return Value();
}

// the loop's lines with v read as v + h and set as e - h (e read so too):
// the body, the condition; not the WHILE's own setvars (the values before
// the loop)
class Shift {
public:
    Shift(Value v, Value h) : v_(v), h_(h) { reads_.add(v, alg::add(v, h)); }

    Value expr(Value e) { return reads_(e); }

    // a LIST of SETVARs (a CONTINUE's, a nested WHILE's): v's set as e - h
    Value setvars(Value sv) {
        if (!sv.is_list()) return sv;
        SmallVec<Value, 8> items;
        bool changed = false;
        for (Value x : sv.args()) {
            Value y = x;
            if (x.is(Op::SETVAR, 2)) {
                Value e = reads_(x[1]);
                if (x[0] == v_) e = alg::sub(e, h_);
                if (e != x[1]) y = mk(Op::SETVAR, x[0], e);
            }
            changed |= y != x;
            items.push_back(y);
        }
        return changed ? mk_like(sv, items.span()) : sv;
    }

    Value trace(Value t) {
        if (!t.is_list()) return t;
        check_stack();
        SmallVec<Value, 32> out;
        bool changed = false;
        for (Value l : t.args()) {
            poll();
            Value r = line(l);
            changed |= r != l;
            out.push_back(r);
        }
        return changed ? mk_trace(out.span()) : t;
    }

private:
    Value line(Value l) {
        if (!l.is_expr()) return l;
        Value r = l;
        switch (l.op()) {
            case Op::SETVAR: {
                Value e = reads_(l[1]);
                if (l[0] == v_) e = alg::sub(e, h_);
                r = e == l[1] ? l : mk(Op::SETVAR, l[0], e);
                break;
            }
            case Op::IF:
            case Op::MERGED_IF:
                r = mk_like(l, std::span<const Value>({reads_(l[0]), trace(l[1]), trace(l[2])}));
                break;
            case Op::WHILE: r = mk(Op::WHILE, reads_(l[0]), trace(l[1]), l[2], setvars(l[3])); break;
            case Op::CONTINUE:
            case Op::GOTO:
            case Op::LABEL: r = mk(l.op(), l[0], setvars(l[1])); break;
            default: r = reads_(l); break;  // (no other line sets v: checked)
        }
        if (r != l) cx().pcs.inherit(r, l);
        return r;
    }

    Value v_, h_;
    Subst reads_;
};

// the loop with its variables starting at a storage array's start moved;
// the lines replacing it (the WHILE, then v set back), or {w}
void propagate_one(Value w, SmallVec<Value, 4>& out) {
    out.clear();
    out.push_back(w);
    const Value sv = w[3];
    if (!sv.is_list()) return;
    SmallVec<Value, 8> names, starts;
    setvar_names(sv, names);
    setvar_values(sv, starts);
    // (a CONTINUE of a loop around it would skip v set back after it)
    if (summary(w).continues_outer) return;
    for (usize i = 0; i < names.size(); ++i) {
        const Value cur = out[0];
        const Value v = names[i];
        const Value h = sha3_term(setvar_of(cur[3], v));
        if (h.nil()) continue;
        // h the same in every iteration and after the loop
        if (simplify::changes(simplify::summary(cur), simplify::summary(h))) continue;
        // v set only by SETVARs and setvars (not a precompile's or an internal call's result)
        bool other = false;
        {
            SmallVec<Value, 64> todo{cur[1]};
            MemoSet<Value> seen;
            while (!todo.empty() && !other) {
                poll();
                Value x = todo.back();
                todo.pop_back();
                if (!(x.is_expr() || x.is_list()) || !seen.add(x)) continue;
                if (x.is(Op::PRECOMPILED, 4) && x[1] == v) other = true;
                if (x.is(Op::INTERNAL, 3) && reads_name(x[2], v)) other = true;
                if (x.is_list() || has(x.op(), LINE))
                    for (Value a : x.children()) todo.push_back(a);
            }
        }
        if (other) continue;
        Shift sh(v, h);
        // the start: e - h; the others' starts as they are (before the loop)
        SmallVec<Value, 8> items;
        const Value cur_sv = cur[3];
        for (Value x : cur_sv.args())
            items.push_back(x.is(Op::SETVAR, 2) && x[0] == v ? mk(Op::SETVAR, v, alg::sub(x[1], h)) : x);
        Value nw = mk(Op::WHILE, sh.expr(cur[0]), sh.trace(cur[1]), cur[2], mk_like(cur_sv, items.span()));
        cx().pcs.inherit(nw, w);
        out[0] = nw;
        Value back = mk(Op::SETVAR, v, alg::add(v, h));
        cx().pcs.inherit(back, w);
        out.push_back(back);
    }
}

}  // namespace

Value propagate_storage_in_loops(Value trace) {
    if (!trace.is_list() || !trace.has_flags(F_LOOPCTL)) return trace;
    check_stack();
    SmallVec<Value, 32> out;
    bool changed = false;
    SmallVec<Value, 4> repl;
    for (Value l : trace.args()) {
        poll();
        if (!l.is_expr() || !l.has_flags(F_LOOPCTL)) {
            out.push_back(l);
            continue;
        }
        switch (l.op()) {
            case Op::IF:
            case Op::MERGED_IF: {
                Value t = propagate_storage_in_loops(l[1]), e = propagate_storage_in_loops(l[2]);
                Value r = mk_like(l, std::span<const Value>({l[0], t, e}));
                cx().pcs.inherit(r, l);
                changed |= r != l;
                out.push_back(r);
                break;
            }
            case Op::WHILE: {
                Value b = propagate_storage_in_loops(l[1]);
                Value x = b == l[1] ? l : mk(Op::WHILE, l[0], b, l[2], l[3]);
                if (x != l) cx().pcs.inherit(x, l);
                propagate_one(x, repl);
                changed |= repl.size() != 1 || repl[0] != l;
                for (Value y : repl) out.push_back(y);
                break;
            }
            default: out.push_back(l); break;
        }
    }
    return changed ? mk_trace(out.span()) : trace;
}

Value rename_var(Value trace, Value from, Value to) {
    if (from == to) return trace;
    Renamer r;
    r.add(from, to);
    return r(trace);
}

}  // namespace pan::loops
