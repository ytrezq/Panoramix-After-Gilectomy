// The free-memory floors along a walk of a trace (docs/alloc-floor.md part
// 1; floor.hpp).
#include "simplify/floor.hpp"

#include <algorithm>
#include <deque>
#include <vector>

#include "algebra/compare.hpp"
#include "algebra/construct.hpp"
#include "algebra/linear.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/evmint.hpp"
#include "loops/loops.hpp"
#include "mem/memory.hpp"
#include "simplify/effects.hpp"

namespace pan::simplify {

namespace {

// a floor: of the word at a constant address (key a small int), or of a
// variable (key its name)
struct FloorOf {
    Value key;
    Value floor;
};

void floors_of(const alg::Facts& f, SmallVec<FloorOf, 8>& out) {
    out.clear();
    f.each_newest_first([&](const alg::Fact& x) {
        if (x.kind == alg::FactKind::Floor) out.push_back({x.a, x.b});
        return true;
    });
}

// the floors of f, in their order, as one value (hash-consed: the same
// floors, the same value - the walks' memos are keyed by it); NIL when none
Value floors_key(const alg::Facts& f) {
    if (!f.any_floor()) return Value();
    SmallVec<Value, 32> v;
    f.each_newest_first([&](const alg::Fact& x) {
        if (x.kind == alg::FactKind::Floor) {
            v.push_back(x.a);
            v.push_back(x.b);
        }
        return true;
    });
    return mk_list(std::span<const Value>(v.data(), v.size()));
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
    if (!(v.is_expr() || v.is_list())) return false;
    if (n.is_name() ? !v.has_flags(F_VAR) : !v.has_flags(F_MEM)) return false;
    check_stack();
    for (Value x : v.args())
        if (contains(x, n)) return true;
    return false;
}

// a write of `range` may change what the floor f reads (decided with the
// facts before the write: its range is evaluated there)
bool hits_reads(Value range, Value f, const alg::Facts& facts) {
    if (!f.has_flags(F_MEM)) return false;
    if (!range.is(Op::RANGE, 2)) return true;
    const EffectSummary& fs = summary(f);
    if ((fs.reads_any & S_MEM) || fs.mem_reads.nil()) return true;
    for (Value r : fs.mem_reads.args())
        if (mem::overlaps(range, r, &facts) != Tri::False) return true;
    return false;
}


// s sets the variable v
bool sets_var(const EffectSummary& s, Value v) {
    if (!(s.writes & S_VARS)) return false;
    if ((s.writes_any & S_VARS) || s.var_writes.nil()) return true;
    for (Value w : s.var_writes.args())
        if (w == v) return true;
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

// v reads one of the atoms floored() puts in
bool reads_floor_atom(Value v) {
    if (alg::is_floor_atom(v)) return true;
    if (!(v.is_expr() || v.is_list()) || !v.has_flags(F_VAR)) return false;
    check_stack();
    for (Value x : v.args())
        if (reads_floor_atom(x)) return true;
    return false;
}

// The floor of a variable set to v (evaluated with the facts before the
// SETVAR): v read with its floored words and variables as F + d (floored),
// a sum in which each d is a term of its own, less the d's - v is at least
// that, the d's being >= 0. v itself when it reads nothing floored but is a
// word's floor (the word's value, as the forward pass knows it: _12 =
// ceil32(rds) + 128 where mem[64] = ceil32(rds) + 128 was written). NIL when
// v reads nothing floored (and is no floor), or isn't such a sum, or what's
// left reads the variable itself (its old value).
Value var_floor(Value name, Value v, const alg::Facts& facts) {
    if (v.has_flags(F_MSIZE)) return Value();
    const Value fv = alg::floored(v, facts);
    if (fv == v) {
        if (v.is_name() || contains(v, name)) return Value();
        bool floor = false;
        facts.each_newest_first([&](const alg::Fact& x) {
            if (x.kind == alg::FactKind::Floor && x.a.is_small() && x.b == v) floor = true;
            return !floor;
        });
        return floor ? v : Value();
    }
    SmallVec<Value, 8> rest;
    bool atom = false;
    auto term = [&](Value t) {
        if (alg::is_floor_atom(t)) {
            atom = true;
            return true;
        }
        if (reads_floor_atom(t)) return false;
        rest.push_back(t);
        return true;
    };
    if (fv.is(Op::ADD)) {
        for (Value t : fv.args())
            if (!term(t)) return Value();
    } else if (!term(fv)) {
        return Value();
    }
    if (!atom) return Value();
    const Value lb = rest.empty() ? Value::small(0) : alg::add(rest.span());
    if (contains(lb, name)) return Value();
    return lb;
}

// (at most this many variables' floors at once: the oldest dropped first -
// fewer facts are as sound)
constexpr u32 kMaxVarFloors = 24;

alg::Facts with_var_floor(const alg::Facts& facts, Value name, Value lb) {
    alg::Facts r = facts.without_floor(name);
    SmallVec<FloorOf, 8> fs;
    floors_of(r, fs);
    u32 n = 0;
    Value oldest;
    for (const FloorOf& f : fs)
        if (f.key.is_name()) {
            ++n;
            oldest = f.key;  // (newest first: the last one is the oldest)
        }
    if (n >= kMaxVarFloors) r = r.without_floor(oldest);
    return r.with_floor(name, lb);
}

// A weaker floor than f that a line (its effects others but memory, its
// memory writes) leaves as it is: f's terms it may change dropped, when
// what's left is proven at most f (Top::Memory, with the facts before the
// line - where f is the floor; what's left reads nothing the line changes,
// so it is still at most the word or variable after it). NIL when none:
// a ceil32 of a length read from memory dropped from mem[64]'s floor
// keeps the pointer's floor through a write over that length.
Value weaker(Value f, const EffectSummary& others, Value mem_writes, bool mem_any, const alg::Facts& facts) {
    if (!f.is(Op::ADD)) return Value();
    SmallVec<Value, 8> rest;
    bool dropped = false;
    for (Value t : f.args()) {
        bool changed = affects(others, t);
        if (!changed && t.has_flags(F_MEM)) {
            changed = mem_any || mem_writes.nil();
            if (!changed)
                for (Value w : mem_writes.args())
                    if (hits_reads(w, t, facts)) {
                        changed = true;
                        break;
                    }
        }
        if (changed)
            dropped = true;
        else
            rest.push_back(t);
    }
    if (!dropped || rest.empty()) return Value();
    const Value w = alg::add(rest.span());
    if (alg::le(w, f, alg::Top::Memory, &facts) != Tri::True) return Value();
    return w;
}

// The floors that every write of a line or a loop (its effects e, the
// memory it writes: mem_writes, or anywhere) leaves as they are, decided with
// the floors that stay: a floor one of the writes may change is dropped (or
// weakened to what the writes leave of it: weaker) and the others decided
// again with that, until none changes - the writes run in some order, and
// each is decided where the floors kept still hold (none of the writes before
// it changed them).
// (keep: variables whose floors hold though e sets them - a loop's rising
// variables at its head; grows: words written only by allocations, mem[A] =
// mem[A] + s, s >= 0 - a loop's at its head: they never go down, their writes
// keep their floors)
alg::Facts stable_floors(const alg::Facts& facts, const EffectSummary& e, Value mem_writes, bool mem_any,
                         std::span<const Value> keep = {}, std::span<const u64> grows = {}) {
    if (!facts.any_floor()) return facts;
    alg::Facts r = facts;
    SmallVec<FloorOf, 8> fs;
    // what doesn't depend on a decision first: a variable set again, a floor
    // reading what the line changes (variables, storage, calls... - memory
    // too when no floor decides it: affects())
    EffectSummary others = e;  // (memory aside: decided below with the floors)
    others.writes &= ~S_MEM;
    others.writes_any &= ~S_MEM;
    others.mem_writes = Value();
    floors_of(r, fs);
    for (const FloorOf& f : fs) {
        const bool kept = std::find(keep.begin(), keep.end(), f.key) != keep.end();
        if (f.key.is_name() && !kept && sets_var(e, f.key))
            r = r.without_floor(f.key);
        else if (affects(others, f.floor))
            r = r.with_floor(f.key, weaker(f.floor, others, mem_writes, mem_any, facts));
    }
    if (!(e.writes & S_MEM)) return r;
    for (int round = 0; round < 32; ++round) {
        floors_of(r, fs);
        if (fs.empty()) return r;
        bool changed = false;
        alg::Facts next = r;
        for (const FloorOf& f : fs) {
            const bool word = f.key.is_small();
            if (!word && !f.floor.has_flags(F_MEM)) continue;  // (a variable's: no memory read)
            const bool grows_ok = word && std::find(grows.begin(), grows.end(), u64(f.key.small_val())) != grows.end();
            bool on_word = mem_any || mem_writes.nil(), on_reads = on_word;
            if (!on_word)
                for (Value w : mem_writes.args()) {
                    if (!w.is(Op::RANGE, 2)) {
                        on_word = on_reads = true;
                        break;
                    }
                    if (word && !(grows_ok && w == word_range(u64(f.key.small_val()))) &&
                        mem::overlaps(w, word_range(u64(f.key.small_val())), &r) != Tri::False)
                        on_word = true;
                    if (!on_reads && hits_reads(w, f.floor, r)) on_reads = true;
                    if (on_word) break;
                }
            if (on_word) {
                next = next.without_floor(f.key);
                changed = true;
            } else if (on_reads) {
                next = next.with_floor(f.key, weaker(f.floor, others, mem_writes, mem_any, r));
                changed = true;
            }
        }
        if (!changed) return r;
        r = next;
    }
    return r.without_floors();
}

// every path through v ends in it by a halt, a failure or a leave (none
// jumps nor is undefined): it never gets back to a loop's head nor past it
bool dies(Value v) {
    const u32 c = summary(v).control;
    return (c & C_ENDS) && !(c & (C_JUMPS | C_UNDEFINED));
}

// the conditions of c that s doesn't change (the other facts as they are)
alg::Facts kept_conds(const alg::Facts& c, const EffectSummary& s) {
    if (c.empty() || !s.writes) return c;
    SmallVec<alg::Fact, 32> v, k;
    c.to_vector(v);
    for (const alg::Fact& f : v)
        if (f.kind != alg::FactKind::Cond || !changes(s, summary(f.a))) k.push_back(f);
    return k.size() == v.size() ? c : alg::Facts::from(std::span<const alg::Fact>(k.data(), k.size()));
}

// The lines of t (a loop's body) with the conditions that hold before each
// on its path - the IFs' conditions in their branches, after an IF the one
// of the branch that goes on where the other ends, each dropped where a line
// may change what it reads -: visit(line, conds) on each, false stops (and
// is returned). cont: the paths that go on only (those that end left out).
template <class F>
bool cond_walk(Value t, bool cont, alg::Facts conds, F& visit) {
    if (!t.is_list()) return true;
    check_stack();
    for (Value l : t.args()) {
        poll();
        if (cont && dies(l)) return true;
        if (!visit(l, conds)) return false;
        if (l.is(Op::IF, 3) || l.is(Op::MERGED_IF, 3)) {
            const Value c = l[0];
            if (!(cont && dies(l[1])) && !cond_walk(l[1], cont, conds.with(c, true), visit)) return false;
            if (!(cont && dies(l[2])) && !cond_walk(l[2], cont, conds.with(c, false), visit)) return false;
            const bool t_ends = ends(l[1]), e_ends = ends(l[2]);
            alg::Facts after = kept_conds(conds, summary(l));
            if (t_ends && !e_ends && !changes(summary(l[2]), summary(c)))
                after = after.with(c, false);
            else if (e_ends && !t_ends && !changes(summary(l[1]), summary(c)))
                after = after.with(c, true);
            conds = after;
        } else if (l.is(Op::WHILE, 4)) {
            const alg::Facts in = kept_conds(conds, summary(l));
            if (!cond_walk(l[1], cont, in.with(l[0], true), visit)) return false;
            conds = in;
        } else if (l.is(Op::LOOP_PATH)) {
            if (!cond_walk(l[0], cont, alg::Facts{}, visit)) return false;
            conds = kept_conds(conds, summary(l));
        } else {
            conds = kept_conds(conds, summary(l));
        }
    }
    return true;
}

// an amount in [0, 2^255) where conds hold (Top::Memory: added to an
// address's word, below 2^64, the sum doesn't wrap - it never goes down)
bool never_down(Value d, const alg::Facts& conds) {
    static const EvmInt two255 = EvmInt::pow2(255);
    const alg::Range r = alg::range(d, alg::Top::Memory, conds.empty() ? nullptr : &conds);
    return r.lo.sign() >= 0 && r.hi < two255;
}

// What a loop's floors need of its body, made once per loop (the algebra's
// variables fixed for the run - the caches are cleared with them): its
// stepped variables (LoopSummary::stepped) that never go down - every
// CONTINUE of it sets each to itself plus an amount never_down where it is
// -, and the constant words its body writes only by allocations, SETMEM(
// RANGE(A, 32), mem[A] + s), s never_down where it is - such a word never
// goes down (its other writes are the floors' business); on the paths that
// go on (cont) and on all of them.
struct LoopInfo {
    SmallVec<Value, 4> rising;
    SmallVec<u64, 4> grows[2];  // [0]: all the paths, [1]: those that go on
};

// (a deque: the references given out hold; the index forgotten with the
// caches, the entries kept until the context compacts - as loops::summary's)
struct LoopInfoState final : ModuleState {
    Memo<Value, u32> index;  // the loop -> 1 + its position
    std::deque<LoopInfo> infos;
    void clear_caches() override { index.clear(); }
};

// the allocation SETMEM(RANGE(a, 32), mem[a] + s): s, NIL when it isn't one
Value allocation_step(Value line, u64 a) {
    const Value x = written_word(line[1]), w = word_read(a);
    if (x.nil() || !x.is(Op::ADD)) return Value();
    SmallVec<Value, 8> rest;
    bool once = false;
    for (Value t : x.args()) {
        if (t == w && !once) {
            once = true;
            continue;
        }
        if (contains(t, w)) return Value();
        rest.push_back(t);
    }
    if (!once || rest.empty()) return Value();
    return alg::add(rest.span());
}

const LoopInfo& loop_info(Value loop_line, const loops::LoopSummary& ls) {
    LoopInfoState& st = cx().state<LoopInfoState>();
    if (const u32* k = st.index.find(loop_line)) return st.infos[*k - 1];
    LoopInfo info;
    const Value id = loop_line[2], body = loop_line[1];
    // the rising variables: those the CONTINUEs of the loop (any path that
    // gets back to its head: all of them) step up
    if (!ls.stepped.nil()) {
        SmallVec<Value, 8> cand(ls.stepped.args());
        SmallVec<u8, 8> ok;
        for (usize i = 0; i < cand.size(); ++i) ok.push_back(1);
        bool any_cont = false;
        auto visit = [&](Value l, const alg::Facts& conds) {
            if (!l.is(Op::CONTINUE, 2) || l[0] != id) return true;
            any_cont = true;
            for (usize i = 0; i < cand.size(); ++i) {
                if (!ok[i]) continue;
                Value next;
                if (l[1].is_list())
                    for (Value x : l[1].args())
                        if (x.is(Op::SETVAR, 2) && x[0] == cand[i]) next = x[1];
                if (next.nil()) continue;  // (left as it is there)
                const Value d = alg::from_linear(alg::linear_diff(next, cand[i]));
                if (contains(d, cand[i]) || !never_down(d, conds)) ok[i] = 0;
            }
            return true;
        };
        (void)cond_walk(body, false, alg::Facts{}.with(loop_line[0], true), visit);
        if (any_cont)
            for (usize i = 0; i < cand.size(); ++i)
                if (ok[i]) info.rising.push_back(cand[i]);
    }
    // the growing words
    if (summary(body).writes & S_MEM) {
        for (int c = 0; c < 2; ++c) {
            SmallVec<u64, 4> good, bad;
            auto visit = [&](Value l, const alg::Facts& conds) {
                if (!l.is(Op::SETMEM, 2)) return true;
                auto a = word_at(l[0]);
                if (!a) return true;
                if (std::find(bad.begin(), bad.end(), *a) != bad.end()) return true;
                const Value step = allocation_step(l, *a);
                if (step.nil() || !never_down(step, conds)) {
                    bad.push_back(*a);
                    SmallVec<u64, 4> rest;
                    for (u64 g : good)
                        if (g != *a) rest.push_back(g);
                    good = rest;
                } else if (std::find(good.begin(), good.end(), *a) == good.end()) {
                    good.push_back(*a);
                }
                return true;
            };
            (void)cond_walk(body, c == 1, alg::Facts{}.with(loop_line[0], true), visit);
            info.grows[c] = good;
        }
    }
    st.infos.push_back(info);
    st.index.put(loop_line, u32(st.infos.size()));
    return st.infos.back();
}

}  // namespace

alg::Facts floor_transfer(const alg::Facts& facts, Value line) {
    if (!line.is_expr()) return facts;
    if (line.is(Op::SETMEM, 2)) {
        // (one write, evaluated before it: decided with the facts before it)
        const Value range = line[0];
        alg::Facts r = facts;
        SmallVec<FloorOf, 8> fs;
        floors_of(facts, fs);
        for (const FloorOf& f : fs) {
            if (!range.is(Op::RANGE, 2) || (f.key.is_small() && mem::overlaps(range, word_range(u64(f.key.small_val())),
                                                                              &facts) != Tri::False)) {
                r = r.without_floor(f.key);
            } else if (hits_reads(range, f.floor, facts)) {
                // (what the write leaves of it)
                const EffectSummary& s = summary(line);
                EffectSummary others = s;
                others.writes &= ~S_MEM;
                others.writes_any &= ~S_MEM;
                others.mem_writes = Value();
                r = r.with_floor(f.key, weaker(f.floor, others, s.mem_writes, s.writes_any & S_MEM, facts));
            }
        }
        if (auto a = word_at(range)) {
            Value nf = new_floor(*a, written_word(line[1]), facts.floor_of(*a));
            r = r.with_floor(*a, nf);
        }
        return r;
    }
    if (line.is(Op::SETVAR, 2)) {
        const Value name = line[0];
        const EffectSummary& s = summary(line);
        alg::Facts r = facts.any_floor() ? stable_floors(facts, s, s.mem_writes, s.writes_any & S_MEM) : facts;
        if (alg::var_floor_key(name) && facts.any_floor())
            if (Value lb = var_floor(name, line[1], facts); !lb.nil()) r = with_var_floor(r, name, lb);
        return r;
    }
    if (!facts.any_floor()) return facts;
    const EffectSummary& s = summary(line);
    return stable_floors(facts, s, s.mem_writes, s.writes_any & S_MEM);
}

alg::Facts floor_join(const alg::Facts& into, const alg::Facts& before, const alg::Facts& then_facts,
                      const alg::Facts& else_facts) {
    alg::Facts r = into.without_floors();
    if (!then_facts.any_floor() || !else_facts.any_floor()) return r;
    const alg::Facts t0 = then_facts.without_floors(), e0 = else_facts.without_floors();
    SmallVec<FloorOf, 8> fs;
    floors_of(then_facts, fs);
    for (const FloorOf& f : fs) {
        const Value ft = f.floor, fe = else_facts.floor_of(f.key);
        if (fe.nil()) continue;
        // c qualifies when it is at most the word (the variable) on each
        // path: c <= F there (c and F evaluated at that branch's end, as they
        // are after the IF on that path)
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
        else if (Value fb = before.floor_of(f.key); at_most_both(fb))
            pick = fb;
        if (!pick.nil()) r = r.with_floor(f.key, pick);
    }
    return r;
}

// The loop's rising variables (LoopSummary::rising) with their floors, their
// start values: each value they take is at least that, the start being
// made of what the loop doesn't change (the same at every iteration) -
// added to r, their keys to keep
alg::Facts with_rising(alg::Facts r, Value loop_line, const loops::LoopSummary& ls, const EffectSummary& e,
                       SmallVec<Value, 4>& keep) {
    if (ls.stepped.nil() || !loop_line[3].is_list()) return r;
    for (Value v : loop_info(loop_line, ls).rising) {
        if (!alg::var_floor_key(v)) continue;
        Value start;
        for (Value x : loop_line[3].args())
            if (x.is(Op::SETVAR, 2) && x[0] == v) start = x[1];
        if (start.nil() || start.has_flags(F_MSIZE)) continue;
        bool reads_loop = false;
        if (!ls.written.nil())
            for (Value n : ls.written.args())
                if (contains(start, n)) reads_loop = true;
        if (reads_loop || affects(e, start)) continue;
        r = with_var_floor(r, v, start);
        keep.push_back(v);
    }
    return r;
}

// ---- a loop's floors: its body walked from the floors at its head ----------------------------

// One walk of a loop's body from candidate floors at its head (the
// induction's hypothesis): the candidates that don't stay what they were at
// some point of a path walked - a word written only by allocations stays as
// long as it has a floor (it only grows) -; the floors of the variables the
// body sets, each where it is set (the same at every place, or none); the
// names read before the iteration sets them on some path (a value carried
// from the iteration before, or from before the loop). cont: the paths that
// end in the body left out. A nested loop: its head's floors (floor_loop),
// what it sets set without a floor of ours.
class BodyFloors {
public:
    BodyFloors(const alg::Facts& cand, std::span<const u64> grows, bool cont) : grows_(grows), cont_(cont) {
        floors_of(cand, keys_);
    }

    SmallVec<Value, 8> spoiled;
    struct Var {
        Value name, floor;
        bool ok;
    };
    SmallVec<Var, 16> vars;
    SmallVec<Value, 16> carried;

    // the lines of t from f - the floors and the conditions that hold on
    // the path (an IF's in its branches, the one of the branch that goes on
    // after it, each dropped where a line may change what it reads: a length
    // checked before a copy bounds it) - (set: the names the iteration set so
    // far on the path); false when no path goes on past t
    bool walk(Value t, alg::Facts& f, SmallVec<Value, 16>& set) {
        if (!t.is_list()) return true;
        check_stack();
        for (Value l : t.args()) {
            poll();
            check(f);
            if (cont_ && dies(l)) return false;
            if (!l.is_expr()) continue;
            switch (l.op()) {
                case Op::IF:
                case Op::MERGED_IF: {
                    reads(l[0], set);
                    const Value c = l[0];
                    alg::Facts ft = f.with(c, true), fe = f.with(c, false);
                    SmallVec<Value, 16> st = set, se = set;
                    const bool tg = !(cont_ && dies(l[1])) && walk(l[1], ft, st);
                    const bool eg = !(cont_ && dies(l[2])) && walk(l[2], fe, se);
                    // (a branch that ends - a revert, a CONTINUE, a BREAK -
                    // doesn't go on past the IF)
                    const bool t_on = tg && !ends(l[1]), e_on = eg && !ends(l[2]);
                    if (!t_on && !e_on) return false;
                    if (t_on && e_on) {
                        f = floor_join(kept_conds(f, summary(l)), f, ft, fe);
                        SmallVec<Value, 16> both;
                        for (Value n : st)
                            if (std::find(se.begin(), se.end(), n) != se.end()) both.push_back(n);
                        set = both;
                    } else if (t_on) {
                        f = ft;
                        set = st;
                    } else {
                        f = fe;
                        set = se;
                    }
                    break;
                }
                case Op::WHILE: {
                    reads(l, set);
                    const alg::Facts h = floor_loop(kept_conds(f, summary(l)), l);
                    check(h);
                    f = h;
                    const loops::LoopSummary& ns = loops::summary(l);
                    if (!ns.written.nil())
                        for (Value n : ns.written.args()) note(n, Value());
                    break;
                }
                case Op::LABEL:
                case Op::LOOP_PATH:
                    f = alg::Facts{};
                    check(f);
                    return false;
                case Op::CONTINUE:
                case Op::GOTO:
                case Op::BREAK:
                    // (the path leaves this list: back to a loop's head or
                    // past a loop - checked above, before it)
                    reads(l, set);
                    return false;
                case Op::SETVAR: {
                    reads(l[1], set);
                    const Value x = l[0];
                    note(x, alg::var_floor_key(x) && x.name_kind() == NameKind::TMP ? var_floor(x, l[1], f) : Value());
                    f = after_line(f, l);
                    if (std::find(set.begin(), set.end(), x) == set.end()) set.push_back(x);
                    break;
                }
                default: {
                    reads(l, set);
                    f = after_line(f, l);
                    const EffectSummary& s = summary(l);
                    if ((s.writes & S_VARS) && !s.var_writes.nil())
                        for (Value n : s.var_writes.args()) {
                            note(n, Value());
                            if (std::find(set.begin(), set.end(), n) == set.end()) set.push_back(n);
                        }
                    break;
                }
            }
        }
        check(f);
        return true;
    }

    // the names v reads that the iteration hasn't set on the path
    void reads(Value v, const SmallVec<Value, 16>& set) {
        const EffectSummary& s = summary(v);
        if (!(s.reads & S_VARS) || s.var_reads.nil()) return;
        for (Value n : s.var_reads.args())
            if (std::find(set.begin(), set.end(), n) == set.end() &&
                std::find(carried.begin(), carried.end(), n) == carried.end())
                carried.push_back(n);
    }

private:
    // the facts after a line l: its floors moved (floor.hpp), the conditions
    // it may change dropped (the same facts when neither changes)
    static alg::Facts after_line(const alg::Facts& f, Value l) {
        const alg::Facts nf = floor_transfer(f, l), kc = kept_conds(f, summary(l));
        if (nf.identity() == f.identity()) return kc;
        if (kc.identity() == f.identity()) return nf;  // (floor_transfer keeps the other facts)
        return floors_from(kc, nf);
    }

    void check(const alg::Facts& f) {
        // (the same facts as last time: nothing to see)
        if (checked_ && f.identity() == checked_id_) return;
        checked_ = true;
        checked_id_ = f.identity();
        floors_of(f, now_);
        for (const FloorOf& k : keys_) {
            if (std::find(spoiled.begin(), spoiled.end(), k.key) != spoiled.end()) continue;
            Value now;
            for (const FloorOf& x : now_)
                if (x.key == k.key) {
                    now = x.floor;
                    break;
                }
            const bool grows = k.key.is_small() &&
                               std::find(grows_.begin(), grows_.end(), u64(k.key.small_val())) != grows_.end();
            if (grows ? now.nil() : now != k.floor) spoiled.push_back(k.key);
        }
    }
    void note(Value x, Value floor) {
        for (Var& v : vars)
            if (v.name == x) {
                if (v.floor != floor) v.ok = false;
                return;
            }
        vars.push_back({x, floor, !floor.nil()});
    }

    SmallVec<FloorOf, 8> keys_, now_;
    std::span<const u64> grows_;
    bool cont_;
    bool checked_ = false;
    u64 checked_id_ = 0;
};

// (the floors alone: the other facts of the walk are added back by the callers)
struct LoopFloors {
    alg::Facts head, inside;
};

// (the floors are all a loop's floors depend on: the memo is keyed by them)
struct LoopFloorsState final : ModuleState {
    Memo<Key3, u32> index;  // (loop, floors, paths) -> 1 + its position
    std::deque<LoopFloors> all;
    void clear_caches() override { index.clear(); }
};

// The floors at a loop's head (head: they hold there at every iteration,
// throughout the paths walked, and after the loop), and with them those of
// the variables its body sets (inside: for the decisions about what its lines
// write - its summary -, each variable at least its floor wherever the
// iteration set it before; none read before it's set, each floor made of
// what the loop doesn't change). cont: the paths that go on (an iteration
// that reverts never gets back); else every path.
//
// By induction over the iterations: the candidates hold at the head of the
// first (they are the facts before it, but those of the variables the loop
// sets - setvars, CONTINUEs: dropped, the rising ones' made anew - and
// those reading what it changes but memory - weakened or dropped); a walk of
// the body from them keeps the ones that stay what they were along every
// path walked (decided with them: true there by the hypothesis, up to the
// point where one doesn't stay - and then it is dropped and the body walked
// again), so they hold at every CONTINUE and BREAK, the next head.
const LoopFloors& loop_floors_of(const alg::Facts& facts, Value loop_line, bool cont) {
    LoopFloorsState& st = cx().state<LoopFloorsState>();
    const Key3 key{loop_line.raw(), floors_key(facts).raw(), u64(cont)};
    if (const u32* k = st.index.find(key)) return st.all[*k - 1];
    const loops::LoopSummary& ls = loops::summary(loop_line);
    const EffectSummary& e = cont ? ls.cont_effects : ls.effects;
    EffectSummary others = e;
    others.writes &= ~S_MEM;
    others.writes_any &= ~S_MEM;
    others.mem_writes = Value();
    // the candidates (the floors alone: the other facts hold at the head,
    // not past a line of the body that changes what they read)
    alg::Facts cand = floors_from(alg::Facts{}, facts);
    if (!ls.written.nil()) {
        SmallVec<FloorOf, 8> fs;
        floors_of(cand, fs);
        for (const FloorOf& f : fs)
            if (f.key.is_name())
                for (Value n : ls.written.args())
                    if (n == f.key) {
                        cand = cand.without_floor(f.key);
                        break;
                    }
    }
    {
        SmallVec<FloorOf, 8> fs;
        floors_of(cand, fs);
        for (const FloorOf& f : fs)
            if (affects(others, f.floor)) cand = cand.with_floor(f.key, weaker(f.floor, others, Value(), false, cand));
    }
    SmallVec<Value, 4> keep;
    cand = with_rising(cand, loop_line, ls, e, keep);
    const SmallVec<u64, 4> grows = loop_info(loop_line, ls).grows[cont ? 1 : 0];
    const std::span<const u64> gs(grows.data(), grows.size());
    // the walks, to a fixpoint
    std::optional<BodyFloors> last;
    for (int round = 0; round < 8; ++round) {
        BodyFloors bf(cand, gs, cont);
        // (the iteration starts where the loop's condition holds)
        alg::Facts f = cand.with(loop_line[0], true);
        SmallVec<Value, 16> set;
        bf.reads(loop_line[0], set);
        (void)bf.walk(loop_line[1], f, set);
        if (bf.spoiled.empty()) {
            last.emplace(std::move(bf));
            break;
        }
        for (Value k : bf.spoiled) cand = cand.without_floor(k);
    }
    LoopFloors r;
    if (last) {
        alg::Facts inside = cand;
        const Value mem_writes = cont ? ls.cont_writes : ls.mem_writes;
        const bool mem_any = cont ? ls.cont_writes_any : ls.mem_writes_any;
        for (const BodyFloors::Var& v : last->vars) {
            if (!v.ok || std::find(last->carried.begin(), last->carried.end(), v.name) != last->carried.end())
                continue;
            // (made of what the loop doesn't change: the same in every iteration)
            Value lb = v.floor;
            if (affects(e, lb)) lb = weaker(lb, others, mem_writes, mem_any || (e.writes_any & S_MEM), cand);
            if (!lb.nil() && !affects(e, lb)) inside = with_var_floor(inside, v.name, lb);
        }
        r.head = cand;
        r.inside = inside;
    }
    st.all.push_back(r);
    st.index.put(key, u32(st.all.size()));
    return st.all.back();
}

// The floors of facts a loop's floors depend on (rel, the floors alone):
// those of the words, and of the variables the loop reads (its condition,
// its body, its start values) or one of those floors reads; the others
// (rest, newest first) only pass through it - no decision about its lines
// reads them (floored() reads a variable's floor where the expression reads
// the variable) - so its floors are made, and memoized, without them.
constexpr u8 kFloorHops = 4;  // (alg::floored's depth)

void split_floors(const alg::Facts& facts, Value loop_line, alg::Facts& rel, SmallVec<FloorOf, 8>& rest) {
    SmallVec<FloorOf, 8> fs;
    floors_of(facts, fs);
    rel = alg::Facts{};
    rest.clear();
    // (names with the number of floors between them and what the loop or a
    // word's floor reads: floored() reads a variable's floor up to
    // kFloorHops floors deep - those further never decide)
    SmallVec<Value, 32> names;
    SmallVec<u8, 32> hops;
    bool all = false;
    auto add_reads = [&](Value v, u8 h) {
        const EffectSummary& s = summary(v);
        if (!(s.reads & S_VARS)) return;
        if ((s.reads_any & S_VARS) || s.var_reads.nil()) {
            all = true;
            return;
        }
        for (Value n : s.var_reads.args()) {
            auto it = std::find(names.begin(), names.end(), n);
            if (it == names.end()) {
                names.push_back(n);
                hops.push_back(h);
            } else if (hops[usize(it - names.begin())] > h) {
                hops[usize(it - names.begin())] = h;
            }
        }
    };
    add_reads(loop_line, 0);
    SmallVec<u8, 8> mark;
    for (const FloorOf& f : fs) {
        mark.push_back(f.key.is_small() ? 1 : 0);
        if (f.key.is_small()) add_reads(f.floor, 0);
    }
    for (bool changed = true; changed && !all;) {
        changed = false;
        for (usize i = 0; i < fs.size(); ++i) {
            if (mark[i]) continue;
            auto it = std::find(names.begin(), names.end(), fs[i].key);
            if (it == names.end()) continue;
            const u8 h = hops[usize(it - names.begin())];
            if (h >= kFloorHops) continue;
            mark[i] = 1;
            add_reads(fs[i].floor, u8(h + 1));
            changed = true;
        }
    }
    // (oldest first: the same order)
    for (usize i = fs.size(); i-- > 0;)
        if (all || mark[i]) rel = rel.with_floor(fs[i].key, fs[i].floor);
    if (!all)
        for (usize i = 0; i < fs.size(); ++i)
            if (!mark[i]) rest.push_back(fs[i]);
}

// a's floors, then b's (newer)
alg::Facts merged(const alg::Facts& a, const alg::Facts& b) {
    SmallVec<FloorOf, 8> fs;
    floors_of(b, fs);
    alg::Facts r = a;
    for (usize i = fs.size(); i-- > 0;) r = r.with_floor(fs[i].key, fs[i].floor);
    return r;
}

// A loop's floors (loop_floors_of) from the floors that it depends on; a
// floor that only passes through is kept when the loop (its paths that go
// on, cont) doesn't set its variable nor change what it reads - the writes
// decided where they are, with the floors inside.
LoopFloors loop_floors(const alg::Facts& facts, Value loop_line, bool cont) {
    alg::Facts rel;
    SmallVec<FloorOf, 8> rest;
    split_floors(facts, loop_line, rel, rest);
    const LoopFloors& lf = loop_floors_of(rel, loop_line, cont);
    if (rest.empty()) return lf;
    const loops::LoopSummary& ls = loops::summary(loop_line);
    const EffectSummary& e = cont ? ls.cont_effects : ls.effects;
    EffectSummary others = e;
    others.writes &= ~S_MEM;
    others.writes_any &= ~S_MEM;
    others.mem_writes = Value();
    const Value mem_writes = cont ? ls.cont_writes : ls.mem_writes;
    const bool mem_any = (cont ? ls.cont_writes_any : ls.mem_writes_any) || (e.writes_any & S_MEM);
    alg::Facts kept;
    for (usize i = rest.size(); i-- > 0;) {
        const FloorOf& f = rest[i];
        if (sets_var(e, f.key) || affects(others, f.floor)) continue;
        bool written = false;
        if (!ls.written.nil())
            for (Value n : ls.written.args()) written |= n == f.key;
        if (written) continue;
        if ((e.writes & S_MEM) && f.floor.has_flags(F_MEM)) {
            bool hit = mem_any || mem_writes.nil();
            if (!hit)
                for (Value w : mem_writes.args())
                    if (hits_reads(w, f.floor, lf.inside)) {
                        hit = true;
                        break;
                    }
            if (hit) continue;
        }
        kept = kept.with_floor(f.key, f.floor);
    }
    return LoopFloors{merged(kept, lf.head), merged(kept, lf.inside)};
}

alg::Facts floor_loop(const alg::Facts& facts, Value loop_line) {
    if (!loop_line.is(Op::WHILE)) return facts.without_floors();
    if (!facts.any_floor() && loops::summary(loop_line).stepped.nil()) return facts;
    return floors_from(facts, loop_floors(facts, loop_line, true).head);
}

alg::Facts floor_loop_all(const alg::Facts& facts, Value loop_line) {
    if (!loop_line.is(Op::WHILE)) return facts.without_floors();
    if (!facts.any_floor() && loops::summary(loop_line).stepped.nil()) return facts;
    return floors_from(facts, loop_floors(facts, loop_line, false).head);
}

alg::Facts floor_loop_inside(const alg::Facts& facts, Value loop_line, bool all_paths) {
    if (!loop_line.is(Op::WHILE)) return facts.without_floors();
    if (!facts.any_floor() && loops::summary(loop_line).stepped.nil()) return facts;
    return floors_from(facts, loop_floors(facts, loop_line, !all_paths).inside);
}

alg::Facts floors_through(const alg::Facts& facts, Value line) {
    if (!facts.any_floor()) return facts;
    if (line.is_list()) {
        const EffectSummary& s = summary(line);
        return stable_floors(facts, s, s.mem_writes, s.writes_any & S_MEM);
    }
    if (!line.is_expr()) return facts;
    switch (line.op()) {
        case Op::WHILE: return floor_loop_all(facts, line);
        case Op::LABEL:
        case Op::LOOP_PATH: return facts.without_floors();
        case Op::IF:
        case Op::MERGED_IF: {
            const EffectSummary& s = summary(line);
            return stable_floors(facts, s, s.mem_writes, s.writes_any & S_MEM);
        }
        default: return facts;
    }
}

alg::Facts floors_from(const alg::Facts& base, const alg::Facts& src) {
    alg::Facts r = base.without_floors();
    SmallVec<FloorOf, 8> fs;
    floors_of(src, fs);
    // (oldest first: the same order)
    for (usize i = fs.size(); i-- > 0;) r = r.with_floor(fs[i].key, fs[i].floor);
    return r;
}

namespace {

// the floors after an IF walked from the floors alone, by (the IF, those
// floors): a walk that meets the same IF again (the copy conversion's, at
// every level of a nest, at every round) doesn't walk it again
struct FloorWalkState final : ModuleState {
    Memo<Key2, u32> index;  // (IF, floors) -> 1 + its position
    std::deque<alg::Facts> after;
    void clear_caches() override { index.clear(); }
};

}  // namespace

alg::Facts floor_walk(const alg::Facts& facts, Value v) {
    // (no floor, and nothing that writes memory or sets a variable: none to
    // make - the IFs of a deep nest aren't walked again at every level)
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
            const Key2 key{v.raw(), floors_key(base).raw()};
            {
                FloorWalkState& st = cx().state<FloorWalkState>();
                if (const u32* k = st.index.find(key)) return floors_from(facts, st.after[*k - 1]);
            }
            const alg::Facts t = floor_walk(base, v[1]), e = floor_walk(base, v[2]);
            const bool t_ends = ends(v[1]), e_ends = ends(v[2]);
            const alg::Facts r = t_ends && !e_ends   ? e
                                 : e_ends && !t_ends ? t
                                                     : floor_join(alg::Facts{}, base, t, e);
            // (the state looked up again: the walks above may have made it)
            FloorWalkState& st = cx().state<FloorWalkState>();
            st.after.push_back(floors_from(alg::Facts{}, r));
            st.index.put(key, u32(st.after.size()));
            return floors_from(facts, r);
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
