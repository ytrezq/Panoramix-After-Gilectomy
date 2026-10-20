// Loop rewrites (python loop_to_setmem, loop_to_setmem_from_storage,
// propagate_storage_in_loops, replace_while_var; asm loops.s), each sound by
// construction:
//
//  - loop_to_setmem: WHILE(cond, {SETMEM(RANGE(p, 32), v), CONTINUE(id, S)},
//    id, S0) whose induction is proven (trips, the last value of every
//    variable), p made of the loop's variables and what the loop doesn't
//    change, moving by D = +-32 every iteration: the iterations write [p0,
//    p0 + 32 trips) (D = 32) or [p_end + 32, p0 + 32) (D = -32), p0 = p at
//    the start, p_end = p after the last iteration - the variables' last
//    values (evaluated where the loop starts), then one SETMEM; the proofs
//    under the path's facts (loops_to_setmems carries them: `require len <=
//    2^32`...) and, for the counter's wrap, lot 4's memory model:
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
//    no form here: such a loop stays. An address may read memory that only
//    the loop's own write could change (the free memory pointer: mem[64] +
//    32 + idx) when that write over all the iterations misses it. In
//    loops_to_setmems (given a function's whole trace) the body may also
//    start with a SETVAR of the SETMEM's value to a name the function never
//    reads (kept by lot 7 for msize), dropped. loops_to_setmems also
//    unrolls a loop whose induction proves it runs once or never (trips 1
//    or 0: the tail of a copy of 20 bytes in words...).
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
#include "algebra/facts.hpp"
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

namespace {

// what a line writes but variables, as the content flags of the facts it
// may make wrong
u8 changed_flags(const simplify::EffectSummary& s) {
    u8 f = 0;
    if (s.writes & (simplify::S_MEM | simplify::S_MSIZE)) f |= F_MEM | F_MSIZE;
    if (s.writes & simplify::S_STORAGE) f |= F_STORAGE;
    if (s.writes & (simplify::S_TRANSIENT | simplify::S_ACCOUNT | simplify::S_CALLRES)) f |= F_STATE;
    return f;
}

// the facts but those that read one of the names (a LIST)
alg::Facts forget_names(const alg::Facts& facts, Value names) {
    if (!names.is_list() || names.size() == 0) return facts;
    SmallVec<Value, 8> ns;
    for (Value n : names.args()) ns.push_back(n);
    const std::span<const Value> span(ns.data(), ns.size());
    SmallVec<alg::Fact, 32> all, kept;
    facts.to_vector(all);
    for (const alg::Fact& f : all)
        if (!(reads_any(f.a, span) || reads_any(f.b, span) || reads_any(f.c, span) ||
              (f.kind == alg::FactKind::VarBits && std::find(ns.begin(), ns.end(), f.a) != ns.end())))
            kept.push_back(f);
    if (kept.size() == all.size()) return facts;
    return alg::Facts::from(std::span<const alg::Fact>(kept.data(), kept.size()));
}

// the facts that still hold after the line: those reading what it changes
// dropped (the variables it sets by name when it says which)
alg::Facts forget(const alg::Facts& facts, Value line) {
    if (facts.empty()) return facts;
    const simplify::EffectSummary& s = simplify::summary(line);
    const u8 f = changed_flags(s);
    alg::Facts r = f ? facts.forget_flags(f) : facts;
    if (s.writes & simplify::S_VARS) {
        if ((s.writes_any & simplify::S_VARS) || s.var_writes.nil())
            r = r.forget_flags(F_VAR);
        else
            r = forget_names(r, s.var_writes);
    }
    return r;
}

// The range a loop writes over all its iterations (made of the values where
// it starts) misses every memory range x reads, each made of what the loop
// doesn't change (not its variables, not what's in memory): then no
// iteration's write changes what x reads - by induction, each reads it as
// it was where the loop starts.
bool misses(Value dst, Value x, std::span<const Value> ns, const alg::Facts* facts) {
    const simplify::EffectSummary& e = simplify::summary(x);
    if (!(e.reads & simplify::S_MEM)) return true;
    if ((e.reads_any & simplify::S_MEM) || e.mem_reads.nil()) return false;
    for (Value r : e.mem_reads.args()) {
        if (reads_any(r, ns) || (simplify::summary(r).reads & simplify::S_MEM)) return false;
        if (mem::overlaps(dst, r, facts) != Tri::False) return false;
    }
    return true;
}

// the names no line of the function reads (its trace's summary)
struct Unread {
    bool known = false;
    Value reads;  // LIST of the names read anywhere, NIL for none
    bool has(Value n) const {
        if (!known || !n.is_name()) return false;
        if (reads.nil()) return true;
        for (Value x : reads.args())
            if (x == n) return false;
        return true;
    }
};

// a word's 32 bytes written as they are: SIZED(32, x) is x
Value word_value(Value x) { return x.is(Op::SIZED, 2) && x[0] == small(32) ? x[1] : x; }

// loop_to_setmem where the path's facts hold (they bound what the proofs
// read: lengths checked against 2^32...); the trip count's wrap proven
// under lot 4's memory model too (Top::Memory: a counter that moves the
// address of a write every iteration never wraps in a run that pays for its
// memory). The variables' last values, evaluated where the loop starts, are
// set first, then the SETMEM (made of the values there too). The body: the
// SETMEM and the CONTINUE - or before them a SETVAR of the SETMEM's value to
// a name the function reads nowhere (kept for msize: the SETMEM reads the
// same bytes), dropped.
Value to_setmem(Value w, const RewriteOptions& opts, const alg::Facts* facts, const Unread* unread) {
    if (!w.is(Op::WHILE, 4)) return w;
    const Value body = w[1], sv = w[3];
    if (!body.is_list() || !sv.is_list()) return w;
    Value sm, cont;
    if (body.size() == 2) {
        sm = body[0];
        cont = body[1];
    } else if (body.size() == 3 && unread && body[0].is(Op::SETVAR, 2) && unread->has(body[0][0])) {
        sm = body[1];
        cont = body[2];
        if (!sm.is(Op::SETMEM, 2) || word_value(body[0][1]) != word_value(sm[1])) return w;
    } else {
        return w;
    }
    if (!sm.is(Op::SETMEM, 2) || !cont.is(Op::CONTINUE, 2) || cont[0] != w[2]) return w;
    const Value r = sm[0], v = word_value(sm[1]);
    if (!r.is(Op::RANGE, 2) || r[1] != small(32)) return w;
    Value finals;
    const auto ind = induction_at(w, alg::Top::Memory, facts, &finals);
    if (!ind || ind->trips.nil() || finals.nil()) return w;
    SmallVec<Value, 8> names;
    setvar_names(sv, names);
    const std::span<const Value> ns(names.data(), names.size());
    // every variable's last value, made of the values where the loop starts
    if (finals.size() != names.size()) return w;
    for (Value e : finals.args())
        if (reads_any(e[1], ns)) return w;
    bool ok = false;
    const simplify::EffectSummary others = but_vars(simplify::summary(w), ns, ok);
    if (!ok) return w;
    // (an address may read memory only the loop's SETMEM - its only write -
    // could change, the free memory pointer...: checked once the range it
    // writes over all the iterations is known)
    simplify::EffectSummary others_nw = others;
    others_nw.writes &= ~simplify::S_MEM;
    others_nw.writes_any &= ~simplify::S_MEM;
    others_nw.mem_writes = Value();
    SmallVec<Value, 2> deferred;
    auto moves = [&](Value x) -> std::optional<Value> {
        if (auto d = move_of(x, ns, cont[1], others)) return d;
        auto d = move_of(x, ns, cont[1], others_nw);
        if (d) deferred.push_back(x);
        return d;
    };
    const Value p = r[0];
    const auto dp = moves(p);
    if (!dp || !(*dp == small(32) || *dp == small(-32))) return w;
    const bool up = *dp == small(32);
    const Value len = alg::mul(small(32), ind->trips);
    // the lowest address written, as the loop starts
    auto low = [&](Value addr) {
        const Value first = at(addr, ns, sv);
        if (up) return first;
        return alg::add(at(addr, ns, finals), small(32));
    };
    const Value p_lo = low(p);
    Value value;
    if (v == small(0)) {
        value = small(0);
    } else if (v.is(Op::MEM, 1) && v[0].is(Op::RANGE, 2) && v[0][1] == small(32)) {
        const Value q = v[0][0];
        const auto dq = moves(q);
        if (!dq || *dq != *dp) return w;
        const Value q_lo = low(q);
        if (!opts.dubious) {
            // the loop never reads a word it wrote: the source not behind the
            // destination in the copy's direction, or apart
            const Value dst = mem::make_range(p_lo, len), src = mem::make_range(q_lo, len);
            const bool apart = mem::overlaps(dst, src, facts) == Tri::False;
            const bool ahead = up ? alg::le(p_lo, q_lo, alg::Top::Memory, facts) == Tri::True
                                  : alg::le(q_lo, p_lo, alg::Top::Memory, facts) == Tri::True;
            if (!apart && !ahead) return w;
        }
        value = mk(Op::MEM, mem::make_range(q_lo, len));
    } else if (v.is(Op::CALLDATALOAD, 1)) {
        const Value q = v[0];
        const auto dq = moves(q);
        if (!dq || *dq != *dp) return w;
        value = mk(Op::CALLDATA_BYTES, low(q), len);
    } else {
        return w;
    }
    // what the addresses read that the SETMEM could change: missed by every
    // iteration's write (by induction over them: each reads it as it was)
    const Value dst = mem::make_range(p_lo, len);
    for (Value x : deferred)
        if (!misses(dst, x, ns, facts)) return w;
    Value set = mk(Op::SETMEM, dst, value);
    // (the SETMEM runs after the variables are set: none read in it)
    if (reads_any(set, ns)) return w;
    cx().pcs.inherit(set, sm);
    SmallVec<Value, 8> lines;
    for (Value e : finals.args()) lines.push_back(e);
    lines.push_back(set);
    return mk_trace(lines.span());
}

// The SETVARs of a LIST of them as lines, in an order that sets them all at
// once (a value read before a name it reads is set: a name's SETVAR after
// every other one reading it); false when there's none (a cycle, a name set
// twice).
bool one_by_one(Value setvars, SmallVec<Value, 8>& out) {
    out.clear();
    if (!setvars.is_list()) return false;
    SmallVec<Value, 8> pending;
    for (Value x : setvars.args()) {
        if (!x.is(Op::SETVAR, 2)) return false;
        for (Value y : pending)
            if (y[0] == x[0]) return false;
        pending.push_back(x);
    }
    while (!pending.empty()) {
        bool found = false;
        for (usize j = 0; j < pending.size() && !found; ++j) {
            bool read = false;
            for (usize i = 0; i < pending.size() && !read; ++i)
                read = i != j && reads_name(pending[i][1], pending[j][0]);
            if (read) continue;
            out.push_back(pending[j]);
            for (usize k = j; k + 1 < pending.size(); ++k) pending[k] = pending[k + 1];
            pending.pop_back();
            found = true;
        }
        if (!found) return false;
    }
    return true;
}

// A loop the induction proves runs its body once (trips 1) or never (trips
// 0) - its condition false at the start, or after the first iteration:
// its start values set (none reads a variable of the loop: one by one is
// all at once), then (trips 1) the body once - lines without a jump back to
// the loop but its last, the CONTINUE that ends it, made its SETVARs (in an
// order that sets them all at once). (A path that leaves the body otherwise
// - a halt, a jump to a loop around it - does the same where it's unrolled.)
// The lines replacing the loop, false when it isn't one.
bool run_once(Value w, const alg::Facts* facts, SmallVec<Value, 32>& out) {
    out.clear();
    if (!w.is(Op::WHILE, 4)) return false;
    const Value body = w[1], id = w[2], sv = w[3];
    if (!body.is_list() || !sv.is_list()) return false;
    const auto ind = induction_at(w, alg::Top::Word, facts, nullptr);
    if (!ind || !ind->trips.is_int()) return false;
    const bool once = ind->trips == small(1);
    if (!once && ind->trips != small(0)) return false;
    SmallVec<Value, 8> names;
    setvar_names(sv, names);
    const std::span<const Value> ns(names.data(), names.size());
    for (Value x : sv.args())
        if (!x.is(Op::SETVAR, 2) || reads_any(x[1], ns)) return false;
    for (usize i = 0; i < names.size(); ++i)
        for (usize j = 0; j < i; ++j)
            if (names[i] == names[j]) return false;
    SmallVec<Value, 8> next;
    if (once) {
        if (body.size() == 0) return false;
        const Value last = body[body.size() - 1];
        if (!last.is(Op::CONTINUE, 2) || last[0] != id) return false;
        for (usize i = 0; i + 1 < body.size(); ++i)
            if (has_jump_to(body[i], id)) return false;
        if (summary(w).breaks) return false;
        if (!one_by_one(last[1], next)) return false;
    }
    for (Value x : sv.args()) {
        cx().pcs.inherit(x, w);
        out.push_back(x);
    }
    if (once) {
        for (usize i = 0; i + 1 < body.size(); ++i) out.push_back(body[i]);
        for (Value x : next) {
            cx().pcs.inherit(x, body[body.size() - 1]);
            out.push_back(x);
        }
    }
    return true;
}

// loops_to_setmems' walk: the path's facts carried (an IF's condition in its
// branches, after it what the branch that goes on knows; what a line writes
// forgotten after it, what a loop writes in it and after it)
class SetmemWalk {
public:
    SetmemWalk(const RewriteOptions& o, const Unread& u) : opts_(o), unread_(u) {}

    Value trace(Value t, alg::Facts facts) {
        if (!t.is_list() || !t.has_flags(F_LOOPCTL)) return t;
        check_stack();
        SmallVec<Value, 32> out;
        bool changed = false;
        for (Value l : t.args()) {
            poll();
            if (!l.is_expr()) {
                out.push_back(l);
                continue;
            }
            switch (l.op()) {
                case Op::IF:
                case Op::MERGED_IF: {
                    const Value c = l[0];
                    const Value tt = l[1].has_flags(F_LOOPCTL) ? trace(l[1], facts.with(c, true)) : l[1];
                    const Value ee = l[2].has_flags(F_LOOPCTL) ? trace(l[2], facts.with(c, false)) : l[2];
                    Value r = mk_like(l, std::span<const Value>({c, tt, ee}));
                    cx().pcs.inherit(r, l);
                    changed |= r != l;
                    out.push_back(r);
                    // (the condition known after it, then what its branches
                    // write forgotten - the condition too if it reads that)
                    const bool t_ends = simplify::ends(tt), e_ends = simplify::ends(ee);
                    if (t_ends && !e_ends)
                        facts = facts.with(c, false);
                    else if (e_ends && !t_ends)
                        facts = facts.with(c, true);
                    facts = forget(facts, r);
                    break;
                }
                case Op::WHILE: {
                    const alg::Facts head = forget(facts, l);
                    Value b = trace(l[1], head.with(l[0], true));
                    Value x = b == l[1] ? l : mk(Op::WHILE, l[0], b, l[2], l[3]);
                    if (x != l) cx().pcs.inherit(x, l);
                    Value r = to_setmem(x, opts_, &head, &unread_);
                    if (r.is_list()) {
                        for (Value y : r.args()) out.push_back(y);
                        changed = true;
                    } else if (run_once(x, &head, once_)) {
                        for (Value y : once_) out.push_back(y);
                        changed = true;
                    } else {
                        changed |= r != l;
                        out.push_back(r);
                    }
                    facts = head;
                    break;
                }
                default:
                    out.push_back(l);
                    facts = forget(facts, l);
                    break;
            }
        }
        return changed ? mk_trace(out.span()) : t;
    }

private:
    const RewriteOptions& opts_;
    const Unread& unread_;
    SmallVec<Value, 32> once_;
};

}  // namespace

Value loop_to_setmem(Value w, const RewriteOptions& opts) { return to_setmem(w, opts, nullptr, nullptr); }

Value loops_to_setmems(Value trace, const RewriteOptions& opts) {
    if (!trace.is_list() || !trace.has_flags(F_LOOPCTL)) return trace;
    // (the trace: a function's - the names it reads)
    Unread unread;
    const simplify::EffectSummary& all = simplify::summary(trace);
    unread.known = !(all.reads_any & simplify::S_VARS);
    unread.reads = all.var_reads;
    SetmemWalk walk(opts, unread);
    return walk.trace(trace, alg::Facts{});
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
