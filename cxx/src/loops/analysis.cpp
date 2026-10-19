// Loop analyses (python parse_counters, extract_setmems, while_touches_mem,
// while_uses_mem; asm loops.s): summaries and induction variables.
#include "loops/loops.hpp"

#include <algorithm>
#include <deque>
#include <memory_resource>

#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/errors.hpp"
#include "core/order.hpp"
#include "loops/internal.hpp"
#include "mem/memory.hpp"

namespace pan::loops {

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

}  // namespace pan::loops
