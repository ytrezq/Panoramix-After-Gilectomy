// The free-memory floors along a walk of a trace (docs/alloc-floor.md part
// 1; floor.hpp).
#include "simplify/floor.hpp"

#include "algebra/compare.hpp"
#include "algebra/construct.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "loops/loops.hpp"
#include "mem/memory.hpp"
#include "simplify/effects.hpp"

namespace pan::simplify {

namespace {

struct FloorOf {
    u64 addr;
    Value floor;
};

void floors_of(const alg::Facts& f, SmallVec<FloorOf, 4>& out) {
    out.clear();
    f.each_newest_first([&](const alg::Fact& x) {
        if (x.kind == alg::FactKind::Floor) out.push_back({u64(x.a.small_val()), x.b});
        return true;
    });
}

Value word_range(u64 a) { return mk(Op::RANGE, Value::small(i64(a)), Value::small(32)); }
Value word_read(u64 a) { return mk(Op::MEM, word_range(a)); }

// the constant address of a write of one word: RANGE(A, 32), A a small int
std::optional<u64> word_at(Value range) {
    if (range.is(Op::RANGE, 2) && range[0].is_small() && range[0].small_val() >= 0 && range[1] == Value::small(32))
        return u64(range[0].small_val());
    return std::nullopt;
}

// v reads the node n (hash-consed: one node per value)
bool contains(Value v, Value n) {
    if (v == n) return true;
    if (!(v.is_expr() || v.is_list()) || !v.has_flags(F_MEM)) return false;
    check_stack();
    for (Value x : v.args())
        if (contains(x, n)) return true;
    return false;
}

// a write of `range` may change the word at a, or what the floor f reads
// (decided with the facts before the write: its range is evaluated there)
bool hits(Value range, u64 a, Value f, const alg::Facts& facts) {
    if (!range.is(Op::RANGE, 2)) return true;
    if (mem::overlaps(range, word_range(a), &facts) != Tri::False) return true;
    if (f.has_flags(F_MEM)) {
        const EffectSummary& fs = summary(f);
        if ((fs.reads_any & S_MEM) || fs.mem_reads.nil()) return true;
        for (Value r : fs.mem_reads.args())
            if (mem::overlaps(range, r, &facts) != Tri::False) return true;
    }
    return false;
}

// a SETMEM's value of 32 bytes as the word written; NIL when it isn't one
Value written_word(Value v) {
    if (v.is(Op::SIZED, 2) && v[0] == Value::small(32)) return v[1];
    if (mem::is_bytes(v)) {
        auto w = mem::as_word(v);
        return w ? *w : Value();
    }
    return v;
}

// The floor of the word at a once v is written there: v itself when it
// doesn't read the word; when v is the word plus terms that don't read it
// (an allocation: mem[a] + size), the old floor plus them; else none.
Value new_floor(u64 a, Value v, Value old) {
    if (v.nil() || v.has_flags(F_MSIZE)) return Value();
    const Value w = word_read(a);
    if (!contains(v, w)) return v;
    if (old.nil() || !v.is(Op::ADD)) return Value();
    SmallVec<Value, 8> rest;
    bool once = false;
    for (Value t : v.args()) {
        if (t == w && !once) {
            once = true;
            continue;
        }
        if (contains(t, w)) return Value();
        rest.push_back(t);
    }
    if (!once) return Value();
    rest.push_back(old);
    return alg::add(rest.span());
}

// the floors a summary's writes (anything but a SETMEM's) may change gone
alg::Facts drop_written(const alg::Facts& facts, const EffectSummary& s) {
    if (!facts.any_floor()) return facts;
    SmallVec<FloorOf, 4> fs;
    floors_of(facts, fs);
    alg::Facts r = facts;
    for (const FloorOf& f : fs) {
        bool gone = false;
        if (s.writes & S_MEM) {
            if ((s.writes_any & S_MEM) || s.mem_writes.nil()) {
                gone = true;
            } else {
                for (Value w : s.mem_writes.args())
                    if (hits(w, f.addr, f.floor, facts)) {
                        gone = true;
                        break;
                    }
            }
        }
        // (what the floor reads: variables set again, storage, calls...)
        if (!gone && affects(s, f.floor)) gone = true;
        if (gone) r = r.without_floor(f.addr);
    }
    return r;
}

}  // namespace

alg::Facts floor_transfer(const alg::Facts& facts, Value line) {
    if (!line.is_expr()) return facts;
    if (line.is(Op::SETMEM, 2)) {
        const Value range = line[0];
        alg::Facts r = facts;
        SmallVec<FloorOf, 4> fs;
        floors_of(facts, fs);
        for (const FloorOf& f : fs)
            if (hits(range, f.addr, f.floor, facts)) r = r.without_floor(f.addr);
        if (auto a = word_at(range)) {
            Value nf = new_floor(*a, written_word(line[1]), facts.floor_of(*a));
            r = r.with_floor(*a, nf);
        }
        return r;
    }
    if (!facts.any_floor()) return facts;
    return drop_written(facts, summary(line));
}

alg::Facts floor_join(const alg::Facts& into, const alg::Facts& before, const alg::Facts& then_facts,
                      const alg::Facts& else_facts) {
    alg::Facts r = into.without_floors();
    if (!then_facts.any_floor() || !else_facts.any_floor()) return r;
    const alg::Facts t0 = then_facts.without_floors(), e0 = else_facts.without_floors();
    SmallVec<FloorOf, 4> fs;
    floors_of(then_facts, fs);
    for (const FloorOf& f : fs) {
        const Value ft = f.floor, fe = else_facts.floor_of(f.addr);
        if (fe.nil()) continue;
        // c qualifies when it is at most the word on each path: c <= F there
        // (c and F evaluated at that branch's end, as they are after the IF
        // on that path)
        auto at_most_both = [&](Value c) {
            if (c.nil()) return false;
            if (c != ft && alg::le(c, ft, alg::Top::Memory, &t0) != Tri::True) return false;
            if (c != fe && alg::le(c, fe, alg::Top::Memory, &e0) != Tri::True) return false;
            return true;
        };
        Value pick;
        if (ft == fe)
            pick = ft;
        else if (at_most_both(ft))
            pick = ft;
        else if (at_most_both(fe))
            pick = fe;
        else if (Value fb = before.floor_of(f.addr); at_most_both(fb))
            pick = fb;
        if (!pick.nil()) r = r.with_floor(f.addr, pick);
    }
    return r;
}

alg::Facts floor_loop(const alg::Facts& facts, Value loop_line) {
    if (!facts.any_floor()) return facts;
    if (!loop_line.is(Op::WHILE)) return facts.without_floors();
    const loops::LoopSummary& ls = loops::summary(loop_line);
    SmallVec<FloorOf, 4> fs;
    floors_of(facts, fs);
    alg::Facts r = facts;
    for (const FloorOf& f : fs) {
        // (every iteration's writes, read with the loop's variables as any
        // value: the word unchanged before each, by induction)
        bool gone = ls.mem_writes_any || ((ls.effects.writes & S_MEM) && ls.mem_writes.nil());
        if (!gone && !ls.mem_writes.nil())
            for (Value w : ls.mem_writes.args())
                if (hits(w, f.addr, f.floor, facts)) {
                    gone = true;
                    break;
                }
        if (!gone && affects(ls.effects, f.floor)) gone = true;
        if (gone) r = r.without_floor(f.addr);
    }
    return r;
}

alg::Facts floors_from(const alg::Facts& base, const alg::Facts& src) {
    alg::Facts r = base.without_floors();
    SmallVec<FloorOf, 4> fs;
    floors_of(src, fs);
    for (const FloorOf& f : fs) r = r.with_floor(f.addr, f.floor);
    return r;
}

alg::Facts floor_walk(const alg::Facts& facts, Value v) {
    // (no floor, and nothing that writes memory: none to make - the IFs of a
    // deep nest aren't walked again at every level)
    if (!facts.any_floor() && !(summary(v).writes & S_MEM)) return facts;
    if (v.is_list()) {
        alg::Facts f = facts;
        for (Value l : v.args()) {
            poll();
            f = floor_walk(f, l);
        }
        return f;
    }
    if (!v.is_expr()) return facts;
    switch (v.op()) {
        case Op::IF:
        case Op::MERGED_IF: {
            check_stack();
            // (the branches walked with the floors alone: the other facts
            // hold where the IF starts, not past a line of a branch that
            // may change what they read - nothing here forgets them)
            const alg::Facts base = floors_from(alg::Facts{}, facts);
            const alg::Facts t = floor_walk(base, v[1]), e = floor_walk(base, v[2]);
            const bool t_ends = ends(v[1]), e_ends = ends(v[2]);
            if (t_ends && !e_ends) return floors_from(facts, e);
            if (e_ends && !t_ends) return floors_from(facts, t);
            return floors_from(facts, floor_join(alg::Facts{}, base, t, e));
        }
        case Op::WHILE:
            return floor_loop(facts, v);
        case Op::LABEL:
        case Op::LOOP_PATH:
            return facts.without_floors();
        default:
            return floor_transfer(facts, v);
    }
}

}  // namespace pan::simplify
