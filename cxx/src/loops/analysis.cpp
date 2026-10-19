// Loop analyses (python parse_counters, extract_setmems, while_touches_mem,
// while_uses_mem, leaves_loop; asm loops.s): summaries and induction
// variables, per WHILE node, memoized.
//
// The induction (python parse_counters as a proof): a WHILE(cond, body, id,
// S0) whose cond compares u = v + c (v a variable of the loop, c an int)
// with a bound b nothing the loop changes is read in, v set nowhere in the
// loop but by its CONTINUEs, each adding the same constant d to it. Then u
// runs s + c, s + c + d, ... (mod 2^256) while the condition holds, and
// when it can't wrap on its way to b (proven from b's range) the iterations
// are, from u's start s_u (x = max(b, s_u) - s_u, never negative):
//   u < b,  d > 0, b <= 2^256 - d:      ceil(x / d)
//   u <= b, d > 0, b <= 2^256 - 1 - d:  the same with b + 1
//   u > b,  d < 0, b >= -d - 1:         ceil((max(s_u, b) - b) / -d)
//   u >= b, d < 0, b >= -d:             the same with b - 1
//   u != b, d = 1 (-1):                 b - s_u (s_u - b), mod 2^256: exact
// (ceil(x / e) = (x + e - 1) / e: no wrap, x <= b). The other variables w
// that every CONTINUE moves by the same amount e_w (nothing the loop changes
// read in it), set nowhere else in the loop, end at w0 + e_w * trips; the
// counter at s + d * trips. Those endvars hold after the WHILE line when no
// path of the body falls off it (a break: python leaves_loop).
#include "loops/loops.hpp"

#include <algorithm>
#include <deque>
#include <memory_resource>

#include "algebra/compare.hpp"
#include "algebra/construct.hpp"
#include "algebra/eval.hpp"
#include "algebra/linear.hpp"
#include "algebra/ranges.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/errors.hpp"
#include "core/evmint.hpp"
#include "core/order.hpp"
#include "loops/internal.hpp"
#include "mem/memory.hpp"
#include "simplify/effects.hpp"

namespace pan::loops {

using namespace detail;

namespace {

Value small(i64 x) { return Value::small(x); }

// ---- what the body does ----------------------------------------------------------------

// The body of a loop walked once: its CONTINUEs, the names it sets (but by
// its own CONTINUEs' setvars), its jumps out.
struct BodyWalk {
    Value id;
    SmallVec<Value, 8> conts;    // the CONTINUE(id, sv) lines, distinct, in walk order
    SmallVec<Value, 16> sets;    // names set in the body (not the CONTINUEs' setvars of this loop)
    SmallVec<Value, 16> cont_sets;  // names the CONTINUEs of this loop set
    bool continues_outer = false;   // a CONTINUE / GOTO / BREAK of a loop around this one
    bool breaks_id = false;         // a BREAK of this loop
    bool any_set = false;           // a line setting names not known (none today: kept for safety)

    explicit BodyWalk(Value loop_id) : id(loop_id) {}

    static void add(SmallVec<Value, 16>& v, Value x) {
        if (std::find(v.begin(), v.end(), x) == v.end()) v.push_back(x);
    }
    void setvars(Value sv, SmallVec<Value, 16>& into) {
        if (!sv.is_list()) return;
        for (Value x : sv.args())
            if (x.is(Op::SETVAR, 2)) add(into, x[0]);
    }

    void walk(Value trace, SmallVec<Value, 8>& nested) {
        if (!trace.is_list()) return;
        check_stack();
        for (Value l : trace.args()) {
            poll();
            if (!l.is_expr()) continue;
            switch (l.op()) {
                case Op::SETVAR: add(sets, l[0]); break;
                case Op::PRECOMPILED:
                    if (l.size() == 4) add(sets, l[1]);
                    break;
                case Op::INTERNAL:
                    if (l.size() == 3) {
                        const Value results = l[2];
                        if (results.is_list())
                            for (Value r : results.args()) add(sets, r);
                    }
                    break;
                case Op::IF:
                case Op::MERGED_IF:
                    walk(l[1], nested);
                    walk(l[2], nested);
                    break;
                case Op::LOOP_PATH: walk(l[0], nested); break;
                case Op::WHILE:
                    setvars(l[3], sets);
                    nested.push_back(l[2]);
                    walk(l[1], nested);
                    nested.pop_back();
                    break;
                case Op::LABEL:
                    // (a raw loop in it: its lines are the rest of this trace)
                    setvars(l[1], sets);
                    nested.push_back(l[0]);
                    break;
                case Op::CONTINUE:
                case Op::GOTO:
                    if (l[0] == id) {
                        if (std::find(conts.begin(), conts.end(), l) == conts.end()) conts.push_back(l);
                        setvars(l[1], cont_sets);
                    } else {
                        if (std::find(nested.begin(), nested.end(), l[0]) == nested.end()) continues_outer = true;
                        setvars(l[1], sets);
                    }
                    break;
                case Op::BREAK:
                    if (l[0] == id)
                        breaks_id = true;
                    else if (std::find(nested.begin(), nested.end(), l[0]) == nested.end())
                        continues_outer = true;
                    break;
                default: break;
            }
        }
    }
};

// the module's memos: the summaries kept (references given out), the
// inductions; the indexes forgotten with the context's caches (the ranges
// depend on the algebra's variables)
struct LoopsState final : ModuleState {
    Memo<Value, u32> summary_index;  // WHILE -> 1 + its slot
    std::pmr::deque<LoopSummary> summaries{cx().budget.resource()};
    Memo<Value, u32> induction_index;  // WHILE -> 1 + its slot (in inductions), or 0x80000000 for none
    std::pmr::deque<std::optional<Induction>> inductions{cx().budget.resource()};
    void clear_caches() override {
        summary_index.clear();
        induction_index.clear();
    }
};

LoopsState& lst() { return cx().state<LoopsState>(); }

// ---- the induction -------------------------------------------------------------------------

// side = v + c (v one of the names, c an int): v and c
struct CounterSide {
    Value var;
    Value offset;  // an int Value in [-2^255, 2^255)
};
std::optional<CounterSide> counter_side(Value side, std::span<const Value> names) {
    if (side.is_name()) {
        if (std::find(names.begin(), names.end(), side) != names.end()) return CounterSide{side, small(0)};
        return std::nullopt;
    }
    if (!side.is(Op::ADD)) return std::nullopt;
    alg::Linear l = alg::linear(side);
    if (l.terms.size() != 1) return std::nullopt;
    if (!(l.terms[0].coeff == small(1))) return std::nullopt;
    const Value v = l.terms[0].term;
    if (std::find(names.begin(), names.end(), v) == names.end()) return std::nullopt;
    return CounterSide{v, l.constant};
}

// the condition as `u cmp b`, the counter's side u
struct CondForm {
    CounterSide u;
    Cmp cmp;
    Value bound;
};
std::optional<CondForm> cond_form(Value cond, std::span<const Value> names) {
    // c: the condition; flip: whether a and b swap
    auto two = [&](Value a, Value b, Cmp ab, Cmp ba) -> std::optional<CondForm> {
        if (auto ua = counter_side(a, names)) return CondForm{*ua, ab, b};
        if (auto ub = counter_side(b, names)) return CondForm{*ub, ba, a};
        return std::nullopt;
    };
    if (cond.is(Op::BOOL, 1)) cond = cond[0];
    switch (cond.op()) {
        case Op::LT: return cond.size() == 2 ? two(cond[0], cond[1], Cmp::Lt, Cmp::Gt) : std::nullopt;
        case Op::GT: return cond.size() == 2 ? two(cond[0], cond[1], Cmp::Gt, Cmp::Lt) : std::nullopt;
        case Op::LE: return cond.size() == 2 ? two(cond[0], cond[1], Cmp::Le, Cmp::Ge) : std::nullopt;
        case Op::GE: return cond.size() == 2 ? two(cond[0], cond[1], Cmp::Ge, Cmp::Le) : std::nullopt;
        case Op::ISZERO: {
            // a comparison negated (the algebra's normal forms have none: a
            // pass's may)
            const Value x = cond[0];
            if (x.size() != 2) return std::nullopt;
            switch (x.op()) {
                case Op::EQ: return two(x[0], x[1], Cmp::Ne, Cmp::Ne);
                case Op::LT: return two(x[0], x[1], Cmp::Ge, Cmp::Le);  // !(a < b): a >= b
                case Op::GT: return two(x[0], x[1], Cmp::Le, Cmp::Ge);
                case Op::LE: return two(x[0], x[1], Cmp::Gt, Cmp::Lt);
                case Op::GE: return two(x[0], x[1], Cmp::Lt, Cmp::Gt);
                default: return std::nullopt;
            }
        }
        default:
            // the condition itself a counter: it goes on while u != 0
            if (auto u = counter_side(cond, names)) return CondForm{*u, Cmp::Ne, small(0)};
            return std::nullopt;
    }
}

// what the loop changes doesn't reach e's value
bool invariant(const simplify::EffectSummary& loop, Value e) {
    if (e.is_int()) return true;
    return !simplify::changes(loop, simplify::summary(e));
}

std::optional<Induction> compute_induction(Value w) {
    const Value cond = w[0], body = w[1], id = w[2], sv = w[3];
    if (!sv.is_list() || !body.is_list()) return std::nullopt;
    SmallVec<Value, 8> names, starts;
    setvar_names(sv, names);
    setvar_values(sv, starts);
    if (names.empty()) return std::nullopt;
    const std::span<const Value> ns(names.data(), names.size());
    const auto form = cond_form(cond, ns);
    if (!form) return std::nullopt;
    BodyWalk bw(id);
    SmallVec<Value, 8> nested;
    bw.walk(body, nested);
    if (bw.conts.empty()) return std::nullopt;  // (no iteration but the first)
    const Value v = form->u.var;
    // the counter: set nowhere but by the CONTINUEs, each adding the same constant
    if (std::find(bw.sets.begin(), bw.sets.end(), v) != bw.sets.end()) return std::nullopt;
    std::optional<Value> step;
    for (Value c : bw.conts) {
        const Value next = setvar_of(c[1], v);
        if (next.nil()) return std::nullopt;  // (left as it is: a step of 0 there)
        auto d = alg::const_diff(next, v);
        if (!d || *d == small(0)) return std::nullopt;
        if (step && *step != *d) return std::nullopt;
        step = *d;
    }
    const simplify::EffectSummary& eff = simplify::summary(w);
    const Value b = form->bound;
    if (!invariant(eff, b)) return std::nullopt;
    Value s;
    for (usize i = 0; i < names.size(); ++i)
        if (names[i] == v) s = starts[i];
    if (s.nil()) return std::nullopt;

    Induction ind;
    ind.var = v;
    ind.start = s;
    ind.step = *step;
    ind.offset = form->u.offset;
    ind.cmp = form->cmp;
    ind.bound = b;

    // ---- the trip count, when the counter can't wrap on its way --------------------
    const EvmInt d = EvmInt(*step);
    const Value su = alg::add(s, ind.offset);  // u's start
    const alg::Range br = alg::range(b);
    Value trips;
    auto ceil_div = [&](Value x, const EvmInt& e) -> Value {
        if (e == EvmInt(1)) return x;
        return alg::div(alg::add(x, (e - 1).value()), e.value());
    };
    switch (ind.cmp) {
        case Cmp::Lt:
            if (d.sign() > 0 && br.hi <= two_256() - d) trips = ceil_div(alg::sub(alg::max({b, su}), su), d);
            break;
        case Cmp::Le:
            if (d.sign() > 0 && br.hi <= two_256() - 1 - d) {
                const Value b1 = alg::add(b, small(1));
                trips = ceil_div(alg::sub(alg::max({b1, su}), su), d);
            }
            break;
        case Cmp::Gt:
            if (d.sign() < 0 && br.lo >= -d - 1) trips = ceil_div(alg::sub(alg::max({su, b}), b), -d);
            break;
        case Cmp::Ge:
            if (d.sign() < 0 && br.lo >= -d) {
                const Value b1 = alg::sub(b, small(1));
                trips = ceil_div(alg::sub(alg::max({su, b1}), b1), -d);
            }
            break;
        case Cmp::Ne:
            if (d == EvmInt(1))
                trips = alg::sub(b, su);
            else if (d == EvmInt(-1))
                trips = alg::sub(su, b);
            break;
    }
    if (trips.nil()) return ind;
    ind.trips = trips;
    ind.last = alg::add(s, alg::mul(ind.step, trips));

    // ---- the values after the loop -------------------------------------------------------
    // (a path that falls off the body leaves the loop with other values)
    if (falls_through(body) || bw.breaks_id) return ind;
    // (each value made of what the loop doesn't change: the same evaluated
    // after it as before it, where the start values were)
    SmallVec<Value, 8> ends;
    for (usize i = 0; i < names.size(); ++i) {
        const Value x = names[i];
        if (x == v) {
            if (invariant(eff, ind.last)) ends.push_back(mk(Op::SETVAR, x, ind.last));
            continue;
        }
        if (std::find(bw.sets.begin(), bw.sets.end(), x) != bw.sets.end()) continue;
        // its move at every CONTINUE: the same, loop invariant
        Value move;
        bool ok = true;
        for (Value c : bw.conts) {
            Value next = setvar_of(c[1], x);
            Value m = next.nil() ? small(0) : alg::from_linear(alg::linear_diff(next, x));
            if (move.nil())
                move = m;
            else if (move != m)
                ok = false;
            if (!ok) break;
        }
        if (!ok || move.nil() || !invariant(eff, move)) continue;
        const Value end = alg::add(starts[i], alg::mul(move, trips));
        if (invariant(eff, end)) ends.push_back(mk(Op::SETVAR, x, end));
    }
    ind.endvars = mk_list(ends.span());
    return ind;
}

}  // namespace

std::optional<Induction> induction(Value while_line) {
    if (!while_line.is(Op::WHILE, 4)) return std::nullopt;
    LoopsState& st = lst();
    if (const u32* k = st.induction_index.find(while_line)) return st.inductions[*k - 1];
    std::optional<Induction> r = compute_induction(while_line);
    st.inductions.push_back(r);
    st.induction_index.put(while_line, u32(st.inductions.size()));
    return r;
}

// ---- the summary ------------------------------------------------------------------------------

namespace {

// A range RANGE(p, n) the loop reads or writes, over all its iterations,
// made of the values before the loop (NIL when it can't be): n loop
// invariant, p made of the loop's variables and of what the loop doesn't
// change, moving by the same constant D at every CONTINUE, the loop's trips
// proven - iteration j (j < trips: the body's; j <= trips: the
// condition's, the CONTINUEs' values) at p0 + j D, p0 its value at the
// start:
//   D >= 0: RANGE(p0, D k + n)          k = trips - 1 (writes: the body's)
//   D < 0:  RANGE(p0 - |D| k, |D| k + n)    or trips (reads: the condition's too)
// (a loop left before - a break, a halt - runs fewer: inside it too; with
// no iteration the range is past what's needed: an over-approximation).
struct Hull {
    std::span<const Value> names;
    Value setvars;
    std::span<const Value> conts;
    const simplify::EffectSummary* eff;
    const simplify::EffectSummary* others;
    Value trips;

    Value of(Value r, bool write) const {
        if (!r.is(Op::RANGE, 2)) return Value();
        const Value p = r[0], n = r[1];
        if (simplify::changes(*eff, simplify::summary(n))) return Value();
        std::optional<Value> d;
        for (Value c : conts) {
            auto dc = move_of(p, names, c[1], *others);
            if (!dc || (d && *d != *dc)) return Value();
            d = dc;
        }
        if (!d) return Value();
        const Value p0 = at(p, names, setvars);
        if (*d == small(0)) return mem::make_range(p0, n);
        const Value k = write ? alg::sub(trips, small(1)) : trips;
        const EvmInt dd(*d);
        if (dd.sign() > 0) return mem::make_range(p0, alg::add(alg::mul(*d, k), n));
        const Value span = alg::mul((-dd).value(), k);
        return mem::make_range(alg::sub(p0, span), alg::add(span, n));
    }
};

// the ranges of a places LIST, each made a hull where it can be
Value hulls(Value ranges, const Hull* h, bool write) {
    if (ranges.nil() || !h) return ranges;
    SmallVec<Value, 16> out;
    bool changed = false;
    for (Value r : ranges.args()) {
        poll();
        Value x = h->of(r, write);
        if (x.nil()) x = r;
        changed |= x != r;
        if (std::find(out.begin(), out.end(), x) == out.end()) out.push_back(x);
    }
    if (!changed) return ranges;
    std::sort(out.begin(), out.end(), StructuralLess{});
    return mk_list(out.span());
}

}  // namespace

const LoopSummary& summary(Value while_line) {
    if (!while_line.is(Op::WHILE, 4)) throw InternalError("loops::summary of something else than a WHILE");
    LoopsState& st = lst();
    if (const u32* k = st.summary_index.find(while_line)) return st.summaries[*k - 1];
    LoopSummary s;
    s.id = while_line[2];
    const simplify::EffectSummary& e = simplify::summary(while_line);
    s.effects = e;
    const Value sv = while_line[3], body = while_line[1];
    SmallVec<Value, 8> vars;
    setvar_names(sv, vars);
    s.vars = mk_list(vars.span());
    BodyWalk bw(s.id);
    SmallVec<Value, 8> nested;
    bw.walk(body, nested);
    SmallVec<Value, 16> written;
    for (Value x : vars) BodyWalk::add(written, x);
    for (Value x : bw.cont_sets) BodyWalk::add(written, x);
    for (Value x : bw.sets) BodyWalk::add(written, x);
    std::sort(written.begin(), written.end(), StructuralLess{});
    s.written = written.empty() ? Value() : mk_list(written.span());
    s.breaks = falls_through(body) || bw.breaks_id;
    s.continues_outer = bw.continues_outer;
    s.continues = u32(bw.conts.size());
    s.ind = induction(while_line);
    // the memory, at the loop's bounds where the induction proves them
    std::optional<Hull> hull;
    simplify::EffectSummary others;
    if (s.ind && !s.ind->trips.nil()) {
        SmallVec<Value, 8> starts;
        setvar_values(sv, starts);
        bool plain_starts = true;
        for (Value x : starts)
            if (reads_any(x, std::span<const Value>(vars.data(), vars.size()))) plain_starts = false;
        bool ok = false;
        others = but_vars(e, std::span<const Value>(vars.data(), vars.size()), ok);
        if (ok && plain_starts)
            hull = Hull{std::span<const Value>(vars.data(), vars.size()), sv,
                        std::span<const Value>(bw.conts.data(), bw.conts.size()), &e, &others, s.ind->trips};
    }
    s.mem_writes = hulls(e.mem_writes, hull ? &*hull : nullptr, true);
    s.mem_reads = hulls(e.mem_reads, hull ? &*hull : nullptr, false);
    s.mem_writes_any = (e.writes_any & simplify::S_MEM) != 0;
    s.mem_reads_any = (e.reads_any & simplify::S_MEM) != 0;
    st.summaries.push_back(s);
    st.summary_index.put(while_line, u32(st.summaries.size()));
    return st.summaries.back();
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
        const Tri t = mem::overlaps(r, range);
        if (t != Tri::False) res = Tri::None;  // (some value of the variables: not every iteration)
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
