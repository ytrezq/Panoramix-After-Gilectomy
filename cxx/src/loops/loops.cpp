// Lot 6's first version (the header's contract, the simplest sound forms):
// make_whiles makes every loop `while True` (its general form); the
// analyses say nothing more than lot 7's effect summaries; the rewrites
// leave their input.
#include "loops/loops.hpp"

#include <algorithm>
#include <deque>
#include <memory_resource>

#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/errors.hpp"
#include "core/order.hpp"
#include "mem/memory.hpp"

namespace pan::loops {

namespace {

Value small(i64 x) { return Value::small(x); }

class Maker {
public:
    Value convert(Value trace) {
        if (!trace.is_list() || !trace.has_flags(F_LOOPCTL)) return trace;
        check_stack();
        SmallVec<Value, 32> out;
        bool changed = false;
        const u32 n = trace.size();
        for (u32 i = 0; i < n; ++i) {
            poll();
            Value l = trace[i];
            if (!l.is_expr() || !l.has_flags(F_LOOPCTL)) {
                out.push_back(l);
                continue;
            }
            switch (l.op()) {
                case Op::IF:
                case Op::MERGED_IF: {
                    Value t = convert(l[1]);
                    Value e = convert(l[2]);
                    Value r = mk_like(l, std::span<const Value>({l[0], t, e}));
                    cx().pcs.inherit(r, l);
                    if (r != l) changed = true;
                    out.push_back(r);
                    break;
                }
                case Op::WHILE: {
                    open_.push_back(l[2]);
                    Value b = convert(l[1]);
                    open_.pop_back();
                    Value r = b == l[1] ? l : mk(Op::WHILE, l[0], b, l[2], l[3]);
                    cx().pcs.inherit(r, l);
                    if (r != l) changed = true;
                    out.push_back(r);
                    break;
                }
                case Op::LABEL: {
                    if (!l[0].is_name(NameKind::LOOP_ID) || !l[1].is_list())
                        throw Unsupported("loops: a malformed LABEL");
                    open_.push_back(l[0]);
                    Value rest = mk_trace(std::span<const Value>(trace.data() + i + 1, n - i - 1));
                    Value body = convert(rest);
                    open_.pop_back();
                    Value w = mk(Op::WHILE, mk(Op::BOOL, small(1)), body, l[0], l[1]);
                    cx().pcs.inherit(w, l);
                    out.push_back(w);
                    return mk_trace(out.span());
                }
                case Op::GOTO:
                case Op::CONTINUE: {
                    if (!l[0].is_name(NameKind::LOOP_ID) || !l[1].is_list())
                        throw Unsupported("loops: a malformed GOTO");
                    if (std::find(open_.begin(), open_.end(), l[0]) == open_.end())
                        throw Unsupported("loops: a GOTO out of its loop");
                    Value r = l.is(Op::GOTO) ? mk(Op::CONTINUE, l[0], l[1]) : l;
                    cx().pcs.inherit(r, l);
                    if (r != l) changed = true;
                    out.push_back(r);
                    break;
                }
                default: out.push_back(l); break;
            }
        }
        return changed ? mk_trace(out.span()) : trace;
    }

private:
    std::vector<Value> open_;  // the loops around: their ids
};

}  // namespace

Value make_whiles(Value trace, std::vector<LoopInfo>& loops, const WhilesOptions& opts) {
    (void)loops;
    (void)opts;
    Maker m;
    return m.convert(trace);
}

void whiles_function(FunctionInfo& fn, const WhilesOptions& opts) {
    fn.trace = make_whiles(fn.trace, fn.loops, opts);
}

void whiles_stage(const std::vector<FunctionInfo>& in, std::vector<FunctionInfo>& out, const WhilesOptions& opts) {
    out = in;
    for (FunctionInfo& f : out) {
        if (f.problem || f.trace.nil()) continue;
        try {
            whiles_function(f, opts);
        } catch (const Error&) {
            f.trace = Value();
            f.problem = 0;
        }
    }
}

std::optional<Induction> induction(Value while_line) {
    (void)while_line;
    return std::nullopt;
}

namespace {

// the summaries made on this context: kept until the context goes (or its
// next compaction), so that the references given out stay valid; the index
// forgotten with the context's caches (the ranges depend on the algebra's
// variables)
struct SummaryState final : ModuleState {
    Memo<Value, u32> index;  // WHILE line -> 1 + its slot
    std::pmr::deque<LoopSummary> slots{cx().budget.resource()};
    void clear_caches() override { index.clear(); }
};

}  // namespace

const LoopSummary& summary(Value while_line) {
    if (!while_line.is(Op::WHILE, 4)) throw InternalError("loops::summary of something else than a WHILE");
    SummaryState& st = cx().state<SummaryState>();
    if (const u32* k = st.index.find(while_line)) return st.slots[*k - 1];
    LoopSummary s;
    s.id = while_line[2];
    const simplify::EffectSummary& e = simplify::summary(while_line);
    s.effects = e;
    SmallVec<Value, 8> vars;
    const Value sv = while_line[3];
    if (sv.is_list())
        for (Value x : sv.args())
            if (x.is(Op::SETVAR, 2)) vars.push_back(x[0]);
    s.vars = mk_list(vars.span());
    s.written = e.var_writes;
    s.mem_writes = e.mem_writes;
    s.mem_reads = e.mem_reads;
    s.mem_writes_any = (e.writes_any & simplify::S_MEM) != 0;
    s.mem_reads_any = (e.reads_any & simplify::S_MEM) != 0;
    s.breaks = true;
    s.continues_outer = true;
    st.slots.push_back(s);
    st.index.put(while_line, u32(st.slots.size()));
    return st.slots.back();
}

namespace {

Tri may_touch(const LoopSummary& s, bool any, Value ranges, Value range) {
    if (any) return Tri::None;
    if (ranges.nil()) return Tri::False;
    // the query must not read what the loop changes (its atoms would be
    // shared with the ranges' free ones)
    if (simplify::changes(s.effects, simplify::summary(range))) return Tri::None;
    Tri res = Tri::False;
    for (Value r : ranges.args()) {
        Tri t = mem::overlaps(r, range);
        if (t == Tri::True) return Tri::None;  // (some value of the variables: not every iteration)
        if (t != Tri::False) res = Tri::None;
    }
    return res;
}

}  // namespace

Tri may_write(Value while_line, Value range) {
    const LoopSummary& s = summary(while_line);
    return may_touch(s, s.mem_writes_any, s.mem_writes, range);
}

Tri may_read(Value while_line, Value range) {
    const LoopSummary& s = summary(while_line);
    return may_touch(s, s.mem_reads_any, s.mem_reads, range);
}

Value loop_to_setmem(Value while_line, const RewriteOptions& opts) {
    (void)opts;
    return while_line;
}

Value loops_to_setmems(Value trace, const RewriteOptions& opts) {
    (void)opts;
    return trace;
}

Value propagate_storage_in_loops(Value trace) { return trace; }

namespace {

class Renamer {
public:
    Renamer(Value from, Value to) : from_(from), to_(to) {}
    Value operator()(Value v) {
        if (v == from_) return to_;
        if (!(v.is_expr() || v.is_list()) || !v.has_flags(F_VAR)) return v;
        if (const Value* r = memo_.find(v)) return *r;
        check_stack();
        SmallVec<Value, 8> args;
        bool changed = false;
        for (Value a : v.children()) {
            Value n = (*this)(a);
            if (n != a) changed = true;
            args.push_back(n);
        }
        Value r = changed ? mk_like(v, args.span()) : v;
        if (r != v && v.is_expr() && has(v.op(), LINE)) cx().pcs.inherit(r, v);
        memo_.put(v, r);
        return r;
    }

private:
    Value from_, to_;
    Memo<Value, Value> memo_;
};

}  // namespace

Value rename_var(Value trace, Value from, Value to) {
    if (from == to) return trace;
    Renamer r(from, to);
    return r(trace);
}

}  // namespace pan::loops
