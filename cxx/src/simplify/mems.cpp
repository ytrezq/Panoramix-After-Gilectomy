// cleanup_mems (python simplify.cleanup_mems / replace_mem / trace_uses_mem,
// asm cleanup.s), as two walks of the structured trace:
//
//  1. forward, with lot 4's MemState (what's known of the memory here):
//     every memory read (MEM(RANGE)) replaced by what the writes before it
//     wrote (python replace_mem / fill_mem), a line's reads resolved before
//     its own write; an IF: each branch from the state before it, after it
//     what the branches that go on agree on; a WHILE, a LABEL: what the loop
//     changes forgotten first; the other state a piece's value reads
//     (storage, calls, variables set again) forgotten where a line changes
//     it (effects.hpp).
//  2. backward, the memory live (read later on some path): a SETMEM no read
//     may see dropped (python: kept while the rest of the trace uses it).
//     At a CONTINUE / GOTO, whatever the loop reads anywhere is live; an
//     INTERNAL, a LEAVE, an UNDEFINED read all of it.
//
// Not in a trace that reads msize (run_flags().msize): which memory a run
// touches would change what it reads there.
#include "simplify/effects.hpp"
#include "simplify/internal.hpp"
#include "simplify/simplify.hpp"

#include <vector>

#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/memo.hpp"
#include "algebra/compare.hpp"
#include "algebra/construct.hpp"
#include "loops/loops.hpp"
#include "mem/memory.hpp"

namespace pan::simplify {

namespace {

// ---- forward: reads replaced --------------------------------------------------------------

// what a line (its summary) changes, forgotten from what's known of the memory
void forget(mem::MemState& st, const EffectSummary& s) {
    if (!s.writes) return;
    if (s.writes & S_STORAGE) st.forget_flags(F_STORAGE);
    if (s.writes & (S_TRANSIENT | S_ACCOUNT | S_CALLRES)) st.forget_flags(F_STATE);
    if (s.writes & S_VARS) {
        if (s.writes_any & S_VARS)
            st.forget_flags(F_VAR);
        else if (!s.var_writes.nil())
            for (Value v : s.var_writes.args()) st.forget_name(v);
    }
    if (s.writes & S_MEM) {
        if (s.writes_any & S_MEM) {
            st.clear();
        } else if (!s.mem_writes.nil()) {
            // a range a loop writes may read what the loop changes: it is
            // then anywhere
            for (Value r : s.mem_writes.args()) {
                if (changes(s, summary(r))) {
                    st.clear();
                    return;
                }
            }
            for (Value r : s.mem_writes.args()) st.write(r, Value());
        }
    }
}

// st where cond holds: the MINs / MAXs of its pieces that cond decides
// (python replace_mem's apply_constraint: min(32, return_data.size) is 32
// once return_data.size >= 32 is checked) - the pieces' expressions are
// evaluated here, where cond holds
mem::MemState constrained(const mem::MemState& st, Value cond) {
    if (st.fresh() || st.pieces().empty()) return st;
    SmallVec<mem::MemState::Piece, 16> ps;
    bool any = false;
    for (const auto& p : st.pieces()) {
        Value r = alg::apply_constraint(p.range, cond);
        Value v = alg::apply_constraint(p.value, cond);
        if (r != p.range || v != p.value) any = true;
        ps.push_back({r, v});
    }
    if (!any) return st;
    mem::MemState s2(false, st.facts());
    for (const auto& p : ps) s2.write(p.range, p.value);
    return s2;
}

// what a loop changes (lot 6's summary: the names it sets, the memory any
// iteration may write), forgotten from what's known at its head
void forget_loop(mem::MemState& st, Value while_line) {
    const loops::LoopSummary& ls = loops::summary(while_line);
    const EffectSummary& e = ls.effects;
    if (!ls.written.nil())
        for (Value n : ls.written.args()) st.forget_name(n);
    if ((e.writes & S_VARS) && (e.writes_any & S_VARS)) st.forget_flags(F_VAR);
    if (e.writes & S_STORAGE) st.forget_flags(F_STORAGE);
    if (e.writes & (S_TRANSIENT | S_ACCOUNT | S_CALLRES)) st.forget_flags(F_STATE);
    if (ls.mem_writes_any || ((e.writes & S_MEM) && ls.mem_writes.nil())) {
        st.clear();
        return;
    }
    if (ls.mem_writes.nil()) return;
    // (a range that reads what the loop changes but its variables - memory,
    // storage - isn't where the writes are: anywhere)
    EffectSummary others = e;
    others.writes &= ~S_VARS;
    others.writes_any &= ~S_VARS;
    others.var_writes = Value();
    for (Value r : ls.mem_writes.args())
        if (changes(others, summary(r))) {
            st.clear();
            return;
        }
    for (Value r : ls.mem_writes.args()) st.write(r, Value());
}

class Forward {
public:
    Value walk(Value trace, mem::MemState& st) {
        if (!trace.is_list()) return trace;
        check_stack();
        SmallVec<Value, 32> out;
        bool changed = false;
        for (u32 i = 0; i < trace.size(); ++i) {
            poll();
            Value l = trace[i];
            Value r = line(l, st, trace, i);
            if (r != l) changed = true;
            out.push_back(r);
        }
        return changed ? mk_trace(out.span()) : trace;
    }

private:
    // e (at pos) with its memory reads replaced by what's known
    Value reads(Value e, Pos pos, const mem::MemState& st) {
        if (!e.has_flags(F_MEM)) return e;
        if (!(e.is_expr() || e.is_list())) return e;
        check_stack();
        SmallVec<Value, 8> args;
        bool changed = false;
        const Op op = e.op();
        for (u32 i = 0; i < e.size(); ++i) {
            Value a = e[i];
            Value n = e.is_list() ? reads(a, Pos::Word, st) : reads(a, operand_pos(op, i, e.size()), st);
            if (n != a) changed = true;
            args.push_back(n);
        }
        Value r = changed ? mk_like_checked(e, args.span()) : e;
        if (r.is(Op::MEM, 1) && r[0].is(Op::RANGE, 2)) {
            if (pos == Pos::Word) {
                if (auto w = st.read_word(r[0])) return *w;
            } else {
                if (auto b = st.read(r[0])) return *b;
            }
        }
        return r;
    }
    Value line_reads(Value l, const mem::MemState& st) {
        return map_line_exprs(l, [&](Value e, Pos pos) { return reads(e, pos, st); });
    }

    Value line(Value l, mem::MemState& st, Value trace, u32 i) {
        if (!l.is_expr()) return l;
        switch (l.op()) {
            case Op::IF:
            case Op::MERGED_IF: {
                Value cond = reads(l[0], Pos::Word, st);
                mem::MemState st_t = constrained(st, cond), st_e = constrained(st, alg::iszero(cond));
                Value t = walk(l[1], st_t);
                Value e = walk(l[2], st_e);
                const bool t_ends = ends(t), e_ends = ends(e);
                if (t_ends && !e_ends) {
                    st = std::move(st_e);
                } else if (e_ends && !t_ends) {
                    st = std::move(st_t);
                } else if (!t_ends && !e_ends) {
                    st_t.meet(st_e);
                    st = std::move(st_t);
                }
                Value r = mk_like(l, std::span<const Value>({cond, t, e}));
                cx().pcs.inherit(r, l);
                return r;
            }
            case Op::WHILE: {
                Value sv = map_line_exprs(mk(Op::CONTINUE, l[2], l[3]), [&](Value e, Pos pos) { return reads(e, pos, st); });
                forget_loop(st, l);
                mem::MemState inside(st);
                Value cond = reads(l[0], Pos::Word, inside);
                Value body = walk(l[1], inside);
                Value r = mk(Op::WHILE, cond, body, l[2], sv[1]);
                cx().pcs.inherit(r, l);
                return r;
            }
            case Op::LABEL: {
                Value r = line_reads(l, st);
                forget(st, summary(r));
                EffectSummary rest;
                for (u32 j = i + 1; j < trace.size(); ++j) rest = combine(rest, summary(trace[j]), true);
                forget(st, rest);
                return r;
            }
            case Op::LOOP_PATH: {
                forget(st, summary(l));
                mem::MemState inside(st);
                Value t = walk(l[0], inside);
                return t == l[0] ? l : mk(Op::LOOP_PATH, t, l[1]);
            }
            case Op::SETMEM: {
                Value r = line_reads(l, st);
                if (r != l) cx().pcs.inherit(r, l);
                // (its other effects: none; its write)
                if (r[0].is(Op::RANGE, 2))
                    st.write(r[0], r[1]);
                else
                    st.clear();
                return r;
            }
            default: break;
        }
        Value r = line_reads(l, st);
        if (r != l) cx().pcs.inherit(r, l);
        forget(st, summary(r));
        return r;
    }
};

// ---- backward: dead writes ------------------------------------------------------------------

constexpr usize kMaxLive = 64;

struct Live {
    bool all = false;
    std::vector<Value> ranges;  // RANGEs that may be read later

    void add(Value r) {
        if (all) return;
        for (Value x : ranges)
            if (x == r) return;
        ranges.push_back(r);
        if (ranges.size() > kMaxLive) {
            all = true;
            ranges.clear();
        }
    }
    void unite(const Live& o) {
        if (o.all) {
            all = true;
            ranges.clear();
            return;
        }
        for (Value r : o.ranges) add(r);
    }
    // a write of w may be read later
    bool read(Value w) const {
        if (all) return true;
        for (Value r : ranges)
            if (mem::overlaps(w, r) != Tri::False) return true;
        return false;
    }
    // before a line that changes what a live range reads (its address,
    // its length: memory...), that range isn't the same bytes: anything may
    // be read; before an assignment of variables (a SETVAR, setvars), the
    // range with their values in their place (what it is before it)
    void before(Value line) {
        if (all || ranges.empty()) return;
        const EffectSummary& s = summary(line);
        if (!s.writes) return;
        SmallVec<Value, 8> names, values;
        if (s.writes == S_VARS && assignments(line, names, values)) {
            assign(names, values);
            return;
        }
        before(s);
    }
    void before(const EffectSummary& s) {
        if (all || !s.writes) return;
        for (Value r : ranges)
            if (changes(s, summary(r))) {
                all = true;
                ranges.clear();
                return;
            }
    }
    void assign(std::span<const Value> names, std::span<const Value> values) {
        if (all || names.empty()) return;
        for (Value& r : ranges) r = substitute(r, names, values);
    }
    // the ranges must not read what s changes (a loop's head: ranges valid
    // at every iteration), else anything may be read
    void invariant(const EffectSummary& s) { before(s); }
    // what a write of w leaves to be read from before it
    void overwrite(Value w) {
        if (all) return;
        std::vector<Value> next;
        for (Value r : ranges) {
            if (mem::overlaps(w, r) == Tri::False) {
                next.push_back(r);
                continue;
            }
            for (Value s : mem::survivors(r, w)) next.push_back(s);
        }
        ranges.swap(next);
    }
};

class Backward {
public:
    Value walk(Value trace, Live& live) {
        if (!trace.is_list()) return trace;
        check_stack();
        const u32 n = trace.size();
        const usize mark = loops_.size();
        for (u32 i = 0; i < n; ++i) {
            Value l = trace[i];
            if (l.is(Op::LABEL, 2)) {
                // at the loop's head (any iteration): what follows the trace
                // reads, and what the lines after the label read - when none
                // of those ranges reads what the loop changes
                EffectSummary region;
                for (u32 j = i + 1; j < n; ++j) region = combine(region, summary(trace[j]), true);
                Live head = live;
                add_reads(region, head);
                head.invariant(region);
                loops_.push_back({l[0], std::move(head)});
            }
        }
        SmallVec<Value, 32> out;
        for (u32 i = 0; i < n; ++i) out.push_back(Value());
        bool changed = false;
        for (u32 i = n; i-- > 0;) {
            poll();
            Value l = trace[i];
            Value r = line(l, live);
            if (r != l) changed = true;
            out[i] = r;
        }
        loops_.resize(mark);
        if (!changed) return trace;
        SmallVec<Value, 32> lines;
        for (u32 i = 0; i < n; ++i)
            if (!out[i].nil()) lines.push_back(out[i]);
        return mk_trace(lines.span());
    }

private:
    struct Loop {
        Value id;
        Live head;
    };

    static void add_reads(const EffectSummary& s, Live& live) {
        if (!(s.reads & S_MEM)) return;
        if (s.reads_any & S_MEM) {
            live.all = true;
            live.ranges.clear();
            return;
        }
        if (!s.mem_reads.nil())
            for (Value r : s.mem_reads.args()) live.add(r);
    }
    const Live* loop_head(Value id) const {
        for (usize k = loops_.size(); k-- > 0;)
            if (loops_[k].id == id) return &loops_[k].head;
        return nullptr;
    }

    Value line(Value l, Live& live) {
        if (!l.is_expr()) return l;
        switch (l.op()) {
            case Op::SETMEM: {
                Value w = l[0];
                if (!w.is(Op::RANGE, 2)) {
                    add_reads(summary(l), live);
                    return l;
                }
                if (!live.read(w)) return Value();  // no read sees it
                live.before(l);
                live.overwrite(w);
                // what it reads: its range's and its value's
                add_reads(summary(l), live);
                return l;
            }
            case Op::IF:
            case Op::MERGED_IF: {
                Live lt = live, le = live;
                Value t = walk(l[1], lt);
                Value e = walk(l[2], le);
                live = lt;
                live.unite(le);
                add_reads(summary(l[0]), live);
                Value r = mk_like(l, std::span<const Value>({l[0], t, e}));
                cx().pcs.inherit(r, l);
                return r;
            }
            case Op::WHILE: {
                // at its head (any iteration): what follows it reads and what
                // it reads anywhere, when none of those ranges reads what the
                // loop changes
                const EffectSummary& ls = summary(l);
                Live head = live;
                add_reads(ls, head);
                head.invariant(ls);
                loops_.push_back({l[2], head});
                Live in_body = live;
                Value body = walk(l[1], in_body);
                loops_.pop_back();
                live = head;
                live.unite(in_body);
                // before its setvars (the first iteration's values)
                {
                    SmallVec<Value, 8> names, values;
                    setvars_of(l[3], names, values);
                    live.assign(names, values);
                }
                add_reads(summary(l[3]), live);
                Value r = body == l[1] ? l : mk(Op::WHILE, l[0], body, l[2], l[3]);
                cx().pcs.inherit(r, l);
                return r;
            }
            case Op::CONTINUE:
            case Op::GOTO: {
                const Live* head = loop_head(l[0]);
                if (head) {
                    live = *head;
                } else {
                    live = Live{};
                    live.all = true;
                }
                live.before(l);
                add_reads(summary(l), live);
                return l;
            }
            case Op::LABEL: {
                if (const Live* head = loop_head(l[0])) live.unite(*head);
                live.before(l);
                add_reads(summary(l), live);
                return l;
            }
            case Op::LOOP_PATH: {
                add_reads(summary(l), live);
                return l;
            }
            default: break;
        }
        const EffectSummary& s = summary(l);
        if (s.control & C_UNDEFINED) {
            live = Live{};
            live.all = true;
            return l;
        }
        if (s.control & C_ENDS) live = Live{};
        live.before(l);
        add_reads(s, live);
        return l;
    }

    std::vector<Loop> loops_;
};

}  // namespace

Value cleanup_mems(Value trace) {
    if (!trace.is_list() || run_flags().msize) return trace;
    mem::MemState st(run_flags().fresh);
    Forward fw;
    // what the lines before the trace wrote (the dispatcher's)
    if (run_flags().entry_lines.is_list()) (void)fw.walk(run_flags().entry_lines, st);
    Value t = fw.walk(trace, st);
    Backward bw;
    Live live;
    return bw.walk(t, live);
}

}  // namespace pan::simplify
