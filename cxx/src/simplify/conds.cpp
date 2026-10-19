// Conditions: cleanup_conds (ifs and whiles whose condition is decided),
// min_ifs, short_circuits (python simplify.cleanup_conds / truth / min_ifs,
// postprocess.short_circuits / logical; asm conds.s, postprocess.s).
#include "simplify/effects.hpp"
#include "simplify/internal.hpp"
#include "simplify/simplify.hpp"

#include "algebra/compare.hpp"
#include "algebra/construct.hpp"
#include "algebra/eval.hpp"
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

void conds_into(Value trace, SmallVec<Value, 32>& res, bool& changed);

Value conds_trace(Value trace) {
    if (!trace.is_list()) return trace;
    check_stack();
    SmallVec<Value, 32> res;
    bool changed = false;
    conds_into(trace, res, changed);
    return changed ? mk_trace(res.span()) : trace;
}

void conds_into(Value trace, SmallVec<Value, 32>& res, bool& changed) {
    for (Value line : trace.args()) {
        poll();
        if (line.is(Op::WHILE, 4)) {
            Value path = conds_trace(line[1]);
            Tri ev = alg::eval_bool(line[0]);
            if (ev == Tri::True && !line[0].is(Op::BOOL, 1)) {
                res.push_back(mk(Op::WHILE, mk(Op::BOOL, small(1)), path, line[2], line[3]));
                changed = true;
                continue;
            }
            if (ev == Tri::False) {
                // the loop never runs: but what it sets its variables to first
                if (auto sv = sequential(line[3])) {
                    for (Value s : *sv) res.push_back(s);
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
            Value t = conds_trace(line[1]);
            Value e = conds_trace(line[2]);
            Tri ev = alg::eval_bool(cond);
            if (ev == Tri::True) {
                for (Value l : t.args()) res.push_back(l);
                changed = true;
                continue;
            }
            if (ev == Tri::False) {
                for (Value l : e.args()) res.push_back(l);
                changed = true;
                continue;
            }
            if (t.size() == 0 && e.size() == 0) {
                // (once the branches of a merged if are simplified)
                changed = true;
                continue;
            }
            if (t == e) {
                // whatever the condition
                for (Value l : t.args()) res.push_back(l);
                changed = true;
                continue;
            }
            Value r;
            if (t.size() == 0)
                r = mk(Op::IF, alg::iszero(cond), e, t);
            else
                r = mk(Op::IF, cond, t, e);
            if (r != line) {
                changed = true;
                cx().pcs.inherit(r, line);
            }
            res.push_back(r);
            continue;
        }
        res.push_back(line);
    }
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
