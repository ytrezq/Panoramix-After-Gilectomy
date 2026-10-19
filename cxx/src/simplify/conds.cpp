// Conditions: cleanup_conds (ifs and whiles whose condition is decided),
// min_ifs, short_circuits (python simplify.cleanup_conds / truth / min_ifs,
// postprocess.short_circuits / logical; asm conds.s, postprocess.s).
#include "simplify/effects.hpp"
#include "simplify/internal.hpp"
#include "simplify/simplify.hpp"

#include "algebra/compare.hpp"
#include "algebra/construct.hpp"
#include "algebra/eval.hpp"
#include "algebra/facts.hpp"
#include "core/context.hpp"
#include "core/intops.hpp"

namespace pan::simplify {

namespace {

Value small(i64 x) { return Value::small(x); }
bool is_int(Value v, i64 x) { return v.is_small() && v.small_val() == x; }

std::optional<Value> negated(Value x) {
    if (x.is(Op::MUL, 2) && is_int(x[0], -1)) return x[1];
    return std::nullopt;
}

// c + x == 0 as a comparison
Value equals(Value x, Value c) {
    if (auto y = negated(x)) return alg::cmp(Op::EQ, *y, alg::word_int(c));
    return alg::cmp(Op::EQ, x, alg::word_int(int_neg(c)));
}

// a - b (one negated term, no constant): a == b is when it's 0
std::optional<Value> difference_eq(Value e) {
    if (!e.is(Op::ADD) || e.size() < 2) return std::nullopt;
    i64 neg = -1;
    for (u32 i = 0; i < e.size(); ++i) {
        if (e[i].is_int()) return std::nullopt;
        if (negated(e[i])) {
            if (neg >= 0) return std::nullopt;
            neg = i;
        }
    }
    if (neg < 0) return std::nullopt;
    SmallVec<Value, 8> others;
    for (u32 i = 0; i < e.size(); ++i)
        if (i64(i) != neg) others.push_back(e[i]);
    return alg::cmp(Op::EQ, alg::add(others.span()), *negated(e[u32(neg)]));
}

// python truth: a simpler condition that holds when cond isn't 0
Value truth(Value cond) {
    for (int k = 0; k < 16; ++k) {
        if (auto y = same_truth_factor(cond)) {
            cond = *y;
            continue;
        }
        break;
    }
    if (cond.is(Op::ADD, 2) && cond[0].is_int()) return alg::iszero(equals(cond[1], cond[0]));
    if (auto eq = difference_eq(cond)) return alg::iszero(*eq);
    if (cond.is(Op::XOR, 2)) return alg::iszero(alg::cmp(Op::EQ, cond[0], cond[1]));
    return alg::truth(cond);
}

// a LIST of simultaneous SETVARs as lines one after the other, when that's
// the same: no value reads a variable one before it set; nullopt otherwise
std::optional<SmallVec<Value, 8>> sequential(Value setvars) {
    SmallVec<Value, 8> out;
    if (!setvars.is_list()) return out;
    for (u32 i = 0; i < setvars.size(); ++i) {
        Value s = setvars[i];
        if (!s.is(Op::SETVAR, 2)) return std::nullopt;
        for (u32 j = 0; j < i; ++j) {
            const EffectSummary& vs = summary(s[1]);
            if (!(vs.reads & S_VARS)) continue;
            if (vs.reads_any & S_VARS) return std::nullopt;
            if (!vs.var_reads.nil())
                for (Value x : vs.var_reads.args())
                    if (x == setvars[j][0]) return std::nullopt;
        }
        out.push_back(s);
    }
    return out;
}

// The conditions known to hold where a line is (the enclosing ifs' and
// whiles', the checks passed - python's cleanup_conds decided its ifs by
// constants alone): lot 3's facts, each condition dropped where a line may
// change what it reads (effects.hpp), so that every fact holds at the point
// of the question.
class Conds {
public:
    Value trace(Value t) {
        if (!t.is_list()) return t;
        check_stack();
        SmallVec<Value, 32> res;
        bool changed = false;
        const u32 n = t.size();
        for (u32 i = 0; i < n; ++i) {
            poll();
            Value line = t[i];
            if (line.is(Op::LABEL, 2)) {
                // a loop's head: what the lines after it change, forgotten
                EffectSummary rest = summary(line);
                for (u32 j = i + 1; j < n; ++j) rest = combine(rest, summary(t[j]), true);
                forget(rest);
                res.push_back(line);
                continue;
            }
            if (line.is(Op::WHILE, 4)) {
                const EffectSummary& ls = summary(line);
                forget(ls);
                Tri ev = decide(line[0]);
                // the body: where the condition holds (and what the loop doesn't change)
                const Saved saved = save();
                assume(line[0]);
                Value path = trace(line[1]);
                restore(saved);
                if (ev == Tri::True && !line[0].is(Op::BOOL, 1)) {
                    res.push_back(mk(Op::WHILE, mk(Op::BOOL, small(1)), path, line[2], line[3]));
                    changed = true;
                    continue;
                }
                if (ev == Tri::False) {
                    // the loop never runs: but what it sets its variables to first
                    if (auto sv = sequential(line[3])) {
                        for (Value x : *sv) res.push_back(x);
                        changed = true;
                        continue;
                    }
                }
                Value r = path == line[1] ? line : mk(Op::WHILE, line[0], path, line[2], line[3]);
                if (r != line) {
                    changed = true;
                    cx().pcs.inherit(r, line);
                }
                res.push_back(r);
                continue;
            }
            if (line.is(Op::IF, 3)) {
                Value cond = truth(line[0]);
                Tri ev = decide(cond);
                if (ev == Tri::True || ev == Tri::False) {
                    // the branch it takes, in its place (its lines walked here)
                    Value b = trace(ev == Tri::True ? line[1] : line[2]);
                    for (Value l : b.args()) res.push_back(l);
                    changed = true;
                    // (what follows: after it, as if its lines were here - they were walked)
                    continue;
                }
                const Saved saved = save();
                assume(cond);
                Value tt = trace(line[1]);
                restore(saved);
                assume(alg::iszero(cond));
                Value ee = trace(line[2]);
                restore(saved);
                const bool t_ends = ends(tt), e_ends = ends(ee);
                forget(summary(line));
                // what follows runs after the branch that goes on, if one ends
                if (t_ends != e_ends) {
                    Value holds = t_ends ? alg::iszero(cond) : cond;
                    if (!changes(summary(t_ends ? ee : tt), summary(holds))) assume(holds);
                }
                if (tt.size() == 0 && ee.size() == 0) {
                    // (once the branches of a merged if are simplified)
                    changed = true;
                    continue;
                }
                if (tt == ee) {
                    // whatever the condition
                    for (Value l : tt.args()) res.push_back(l);
                    changed = true;
                    continue;
                }
                Value r;
                if (tt.size() == 0)
                    r = mk(Op::IF, alg::iszero(cond), ee, tt);
                else
                    r = mk(Op::IF, cond, tt, ee);
                if (r != line) {
                    changed = true;
                    cx().pcs.inherit(r, line);
                }
                res.push_back(r);
                continue;
            }
            forget(summary(line));
            res.push_back(line);
        }
        return changed ? mk_trace(res.span()) : t;
    }

private:
    Tri decide(Value cond) {
        Tri t = alg::eval_bool(cond, known_.empty() ? nullptr : &facts_);
        return t == Tri::True || t == Tri::False ? t : Tri::None;
    }
    // (at most this many: past them, the newer ones aren't kept - fewer
    // facts are as sound; 4000 nested ifs stay linear)
    static constexpr usize kMaxKnown = 32;
    struct Saved {
        SmallVec<Value, 16> known;
        alg::Facts facts;
    };
    Saved save() const { return Saved{known_, facts_}; }
    void restore(const Saved& s) {
        known_ = s.known;
        facts_ = s.facts;
    }
    void assume(Value cond) {
        if (cond.is_int() || known_.size() >= kMaxKnown) return;
        known_.push_back(cond);
        facts_ = facts_.with_cond(cond);
    }
    void rebuild() {
        facts_ = alg::Facts();
        for (Value c : known_) facts_ = facts_.with_cond(c);
    }
    void forget(const EffectSummary& s) {
        if (!s.writes || known_.empty()) return;
        SmallVec<Value, 16> kept;
        for (Value c : known_)
            if (!changes(s, summary(c))) kept.push_back(c);
        if (kept.size() == known_.size()) return;
        known_ = kept;
        rebuild();
    }

    SmallVec<Value, 16> known_;
    alg::Facts facts_;
};

Value conds_trace(Value trace) {
    Conds c;
    return c.trace(trace);
}

// ---- min_ifs ----------------------------------------------------------------------------

Value min_trace(Value trace) {
    if (!trace.is_list()) return trace;
    check_stack();
    SmallVec<Value, 32> res;
    bool changed = false;
    for (Value line : trace.args()) {
        poll();
        Value r = line;
        if (line.is(Op::WHILE, 4)) {
            Value body = min_trace(line[1]);
            if (body != line[1]) r = mk(Op::WHILE, line[0], body, line[2], line[3]);
        } else if (line.is(Op::IF, 3)) {
            Value t = min_trace(line[1]), e = min_trace(line[2]);
            if (t != line[1] || e != line[2]) r = mk(Op::IF, line[0], t, e);
            if (t.size() == 1 && e.size() == 1 && t[0].is(Op::SETVAR, 2) && e[0].is(Op::SETVAR, 2) && t[0][0] == e[0][0]) {
                Value cond = line[0], x = t[0][1], y = e[0][1];
                for (int k = 0; k < 16 && cond.is(Op::ISZERO, 1); ++k) {
                    cond = cond[0];
                    std::swap(x, y);
                }
                const Op op = cond.op();
                if ((op == Op::LT || op == Op::LE || op == Op::GT || op == Op::GE) && cond.size() == 2) {
                    Value a = cond[0], b = cond[1];
                    if (op == Op::GT || op == Op::GE) std::swap(a, b);
                    // v is x where a < b (a <= b), y where it isn't
                    if (x == a && y == b) r = mk(Op::SETVAR, t[0][0], alg::min({a, b}));
                }
            }
        }
        if (r != line) {
            changed = true;
            cx().pcs.inherit(r, line);
        }
        res.push_back(r);
    }
    return changed ? mk_trace(res.span()) : trace;
}

// ---- short circuits -------------------------------------------------------------------------

// python logical: what `if cond: v = t else: v = f` sets v to, as LAND /
// LOR of cond; nullopt where it isn't one
std::optional<Value> logical(Value cond, Value t, Value f) {
    Value res;
    bool lor = false;
    if (t == cond || (is_int(t, 1) && alg::is_bool(cond))) {
        res = mk(Op::LOR, cond, f);
        lor = true;
    } else if (is_int(f, 0) || f == cond) {
        res = mk(Op::LAND, cond, t);
    } else if (is_int(t, 0)) {
        res = mk(Op::LAND, alg::iszero(cond), f);
    } else if (is_int(f, 1)) {
        res = mk(Op::LOR, alg::iszero(cond), t);
        lor = true;
    } else {
        return std::nullopt;
    }
    if (lor && is_int(res[1], 0)) return res[0];  // c or 0: c, 0 where it's false
    if (!lor && is_int(res[1], 1)) return alg::is_bool(res[0]) ? res[0] : alg::to_bool(res[0]);
    return res;
}

Value sc_trace(Value trace) {
    if (!trace.is_list()) return trace;
    check_stack();
    SmallVec<Value, 32> res;
    bool changed = false;
    for (Value line : trace.args()) {
        poll();
        Value r = line;
        if (line.is(Op::IF, 3)) {
            Value t = sc_trace(line[1]), e = sc_trace(line[2]);
            if (t != line[1] || e != line[2]) r = mk(Op::IF, line[0], t, e);
            if (t.size() == 1 && e.size() == 1 && t[0].is(Op::SETVAR, 2) && e[0].is(Op::SETVAR, 2) && t[0][0] == e[0][0])
                if (auto v = logical(line[0], t[0][1], e[0][1])) r = mk(Op::SETVAR, t[0][0], *v);
        } else if (line.is(Op::WHILE, 4)) {
            Value body = sc_trace(line[1]);
            if (body != line[1]) r = mk(Op::WHILE, line[0], body, line[2], line[3]);
        }
        if (r != line) {
            changed = true;
            cx().pcs.inherit(r, line);
        }
        res.push_back(r);
    }
    return changed ? mk_trace(res.span()) : trace;
}

}  // namespace

Value cleanup_conds(Value trace) { return conds_trace(trace); }
Value min_ifs(Value trace) { return min_trace(trace); }
Value short_circuits(Value trace) { return sc_trace(trace); }

}  // namespace pan::simplify
