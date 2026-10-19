// Comparisons and truth values: see compare.hpp. The numbers are the
// ranges' (ranges.hpp: RangeQuery); here the logic over them - the facts'
// conditions, BOOL / ISZERO / OR / AND, a known x < a deciding x < b, max /
// min, conditions read as bounds.
#include "algebra/compare.hpp"

#include "algebra/construct.hpp"
#include "algebra/eval.hpp"
#include "algebra/facts.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/intops.hpp"
#include "core/memo.hpp"

namespace pan::alg {

namespace {

// a comparison as a < b (strict) or a <= b, unsigned or signed
struct Cmp {
    Value a, b;
    bool strict, sign;
};

// cond (holds: as it is; else its negation) as a comparison
std::optional<Cmp> as_cmp(Value cond, bool holds) {
    while (cond.is(Op::ISZERO, 1) || cond.is(Op::BOOL, 1)) {
        if (cond.is(Op::ISZERO)) holds = !holds;
        cond = cond[0];
    }
    if (!cond.is_expr() || cond.size() != 2) return std::nullopt;
    const Value x = cond[0], y = cond[1];
    bool sign = false;
    switch (cond.op()) {
        case Op::SLT: sign = true; [[fallthrough]];
        case Op::LT: return holds ? Cmp{x, y, true, sign} : Cmp{y, x, false, sign};
        case Op::SGT: sign = true; [[fallthrough]];
        case Op::GT: return holds ? Cmp{y, x, true, sign} : Cmp{x, y, false, sign};
        case Op::SLE: sign = true; [[fallthrough]];
        case Op::LE: return holds ? Cmp{x, y, false, sign} : Cmp{y, x, true, sign};
        case Op::SGE: sign = true; [[fallthrough]];
        case Op::GE: return holds ? Cmp{y, x, false, sign} : Cmp{x, y, true, sign};
        default: return std::nullopt;
    }
}

bool is_cmp_op(Op op) noexcept {
    switch (op) {
        case Op::LT: case Op::GT: case Op::SLT: case Op::SGT: case Op::EQ:
        case Op::LE: case Op::GE: case Op::SLE: case Op::SGE:
            return true;
        default:
            return false;
    }
}

// the decisions of one question: the facts' bounds gathered once (the
// RangeQuery), the facts' conditions
class Decider {
public:
    Decider(const Facts* facts, Top top) : facts_(facts && !facts->empty() ? facts : nullptr), q_(facts_), top_(top) {}

    RangeQuery& q() { return q_; }

    // a < b / a <= b by the ranges, then by the facts' comparisons
    Tri cmp(const Cmp& c) {
        Tri t = c.sign ? (c.strict ? q_.slt(c.a, c.b, top_) : q_.sle(c.a, c.b, top_))
                       : (c.strict ? q_.lt(c.a, c.b, top_) : q_.le(c.a, c.b, top_));
        if (t != Tri::None || !facts_) return t;
        if (chain(c)) return Tri::True;
        // its negation: b <= a (a < b), b < a (a <= b)
        if (chain(Cmp{c.b, c.a, !c.strict, c.sign})) return Tri::False;
        return Tri::None;
    }

    Tri decide_op(Op op, Value a, Value b) {
        switch (op) {
            case Op::LT: return cmp(Cmp{a, b, true, false});
            case Op::GT: return cmp(Cmp{b, a, true, false});
            case Op::LE: return cmp(Cmp{a, b, false, false});
            case Op::GE: return cmp(Cmp{b, a, false, false});
            case Op::SLT: return cmp(Cmp{a, b, true, true});
            case Op::SGT: return cmp(Cmp{b, a, true, true});
            case Op::SLE: return cmp(Cmp{a, b, false, true});
            case Op::SGE: return cmp(Cmp{b, a, false, true});
            case Op::EQ: {
                Tri t = q_.eq(a, b, top_);
                if (t != Tri::None || !facts_) return t;
                // a < b or b < a known: not equal
                if (chain(Cmp{a, b, true, false}) || chain(Cmp{b, a, true, false})) return Tri::False;
                return Tri::None;
            }
            default:
                return Tri::None;
        }
    }

    // python eval_bool(cond, known, symbolic=True) and is_known
    Tri eval(Value c) {
        check_stack();
        if (c.is_int()) return tri(!word_of(c).is_zero());
        if (c.is_bool()) return tri(c.is_true());
        if (!c.is_expr() && !c.is_leaf() && !c.is_name()) return Tri::None;
        if (auto w = eval_const(c)) return tri(!w->is_zero());
        if (facts_) {
            Tri m = facts_->match(c);
            if (m != Tri::None) return m;
        }
        if (c.is_expr()) {
            switch (c.op()) {
                case Op::BOOL:
                    return eval(c[0]);
                case Op::ISZERO:
                    return tri_not(eval(c[0]));
                case Op::OR: {
                    // not 0 when one of them isn't
                    bool all_false = true;
                    for (Value e : c.args()) {
                        Tri t = eval(e);
                        if (t == Tri::True) return Tri::True;
                        if (t != Tri::False) all_false = false;
                    }
                    if (all_false) return Tri::False;
                    break;
                }
                case Op::AND: {
                    // 0 when one of them is; of truth values, not 0 when all are true
                    bool all_true = true;
                    for (Value e : c.args()) {
                        Tri t = eval(e);
                        if (t == Tri::False) return Tri::False;
                        if (t != Tri::True || !is_bool(e)) all_true = false;
                    }
                    if (all_true) return Tri::True;
                    break;
                }
                case Op::LAND: {
                    // python's `and`: a when it's 0, else b
                    Tri a = eval(c[0]);
                    if (a == Tri::False) return Tri::False;
                    Tri b = eval(c[1]);
                    if (a == Tri::True) return b;
                    if (b == Tri::False) return Tri::False;
                    break;
                }
                case Op::LOR: {
                    Tri a = eval(c[0]);
                    if (a == Tri::True) return Tri::True;
                    Tri b = eval(c[1]);
                    if (a == Tri::False) return b;
                    if (b == Tri::True) return Tri::True;
                    break;
                }
                default:
                    if (is_cmp_op(c.op()) && c.size() == 2) {
                        Tri t = decide_op(c.op(), c[0], c[1]);
                        if (t != Tri::None) return t;
                    }
                    break;
            }
        }
        return q_.nonzero(c, top_);
    }

    // cond with the sub-conditions decided made 1 / 0 (truth: only its truth
    // matters there)
    Value decide(Value c, bool truth) {
        check_stack();
        if (!c.is_expr()) return c;
        Tri t = eval(c);
        if (t == Tri::False) return Value::small(0);
        if (t == Tri::True && (truth || is_bool(c))) return Value::small(1);
        switch (c.op()) {
            case Op::BOOL: {
                Value x = decide(c[0], true);
                return x == c[0] ? c : to_bool(x);
            }
            case Op::ISZERO: {
                Value x = decide(c[0], true);
                return x == c[0] ? c : iszero(x);
            }
            case Op::OR:
            case Op::AND: {
                // an OR's truth is its operands'; an AND's only for truth values
                const bool sub = truth && (c.is(Op::OR) || is_bool(c));
                SmallVec<Value, 8> args;
                bool changed = false;
                for (Value e : c.args()) {
                    Value x = decide(e, sub);
                    changed |= x != e;
                    args.push_back(x);
                }
                if (!changed) return c;
                return c.is(Op::OR) ? bor(args.span()) : band(args.span());
            }
            default:
                return c;
        }
    }

private:
    // c proven from one fact's comparison and the ranges: a R1 y known and y
    // R2 b, or x R1 b known and a R2 x
    bool chain(const Cmp& c) {
        bool found = false;
        facts_->each_newest_first([&](const Fact& f) {
            if (f.kind != FactKind::Cond) return true;
            poll();
            Value k = f.a.is(Op::BOOL, 1) ? f.a[0] : f.a;
            if (proves(k, c)) {
                found = true;
                return false;
            }
            if (k.is(Op::AND))  // (an AND that isn't 0: none of them is)
                for (Value e : k.args())
                    if (proves(e, c)) {
                        found = true;
                        return false;
                    }
            return true;
        });
        return found;
    }
    bool proves(Value fact, const Cmp& c) {
        auto fc = as_cmp(fact, true);
        if (!fc || fc->sign != c.sign) return false;
        auto ranges_le = [&](Value x, Value y, bool strict) {
            Tri t = c.sign ? (strict ? q_.slt(x, y, top_) : q_.sle(x, y, top_))
                           : (strict ? q_.lt(x, y, top_) : q_.le(x, y, top_));
            return t == Tri::True;
        };
        // the second step must be strict when c is and the fact isn't
        const bool need = c.strict && !fc->strict;
        if (fc->a == c.a && (fc->b == c.b ? !need : ranges_le(fc->b, c.b, need))) return true;
        if (fc->b == c.b && fc->a != c.a && ranges_le(c.a, fc->a, need)) return true;
        return false;
    }

    const Facts* facts_;
    RangeQuery q_;
    Top top_;
};

}  // namespace

// ---- integers ----------------------------------------------------------------------

Tri ge_zero(const Linear& l, Top top, const Facts* facts) {
    RangeQuery q(facts);
    Range r = q.int_range(l, top);
    if (r.lo.sign() >= 0) return Tri::True;
    if (r.hi.sign() < 0) return Tri::False;
    return Tri::None;
}

Tri gt_zero(const Linear& l, Top top, const Facts* facts) {
    RangeQuery q(facts);
    Range r = q.int_range(l, top);
    if (r.lo.sign() > 0) return Tri::True;
    if (r.hi.sign() <= 0) return Tri::False;
    return Tri::None;
}

namespace {

// python lt_op / le_op: below the largest of a max is below all of them...
Tri int_cmp(Value a, Value b, bool strict, Top top, RangeQuery& q) {
    check_stack();
    if (a.is_int() && b.is_int()) {
        const int c = int_cmp(a, b);
        return tri(strict ? c < 0 : c <= 0);
    }
    // (a MAX's integer is the largest word of its operands: an operand
    // compared by its integer only when that is its word)
    auto word_like = [&](Value t) { return t.is_int() ? int_sign(t) >= 0 : q.int_range(t, top).is_word(); };
    if (a.is(Op::MAX)) {
        bool all = true;
        for (Value t : a.args()) {
            if (!word_like(t)) return Tri::None;
            Tri r = int_cmp(t, b, strict, top, q);
            if (r == Tri::False) return Tri::False;
            if (r != Tri::True) all = false;
        }
        return all ? Tri::True : Tri::None;
    }
    if (b.is(Op::MAX)) {
        bool all_false = true;
        for (Value t : b.args()) {
            if (!word_like(t)) return Tri::None;
            Tri r = int_cmp(a, t, strict, top, q);
            if (r == Tri::True) return Tri::True;
            if (r != Tri::False) all_false = false;
        }
        return all_false ? Tri::False : Tri::None;
    }
    const SignRange s = q.int_diff_sign(a, b, top);
    if (strict ? s.pos() : s.nonneg()) return Tri::True;
    if (strict ? s.nonpos() : s.neg()) return Tri::False;
    return Tri::None;
}

}  // namespace

Tri int_lt(Value a, Value b, Top top, const Facts* facts) {
    RangeQuery q(facts);
    return int_cmp(a, b, true, top, q);
}

Tri int_le(Value a, Value b, Top top, const Facts* facts) {
    RangeQuery q(facts);
    return int_cmp(a, b, false, top, q);
}

// ---- words -------------------------------------------------------------------------

Tri lt(Value a, Value b, Top top, const Facts* facts) { return Decider(facts, top).decide_op(Op::LT, a, b); }
Tri le(Value a, Value b, Top top, const Facts* facts) { return Decider(facts, top).decide_op(Op::LE, a, b); }
Tri eq(Value a, Value b, Top top, const Facts* facts) { return Decider(facts, top).decide_op(Op::EQ, a, b); }
Tri slt(Value a, Value b, Top top, const Facts* facts) { return Decider(facts, top).decide_op(Op::SLT, a, b); }
Tri sle(Value a, Value b, Top top, const Facts* facts) { return Decider(facts, top).decide_op(Op::SLE, a, b); }

Tri decide_cmp(Op op, Value a, Value b, Top top, const Facts* facts) {
    if (!is_cmp_op(op)) return Tri::None;
    return Decider(facts, top).decide_op(op, a, b);
}

// ---- max / min ---------------------------------------------------------------------

namespace {

std::optional<Value> pick(Value a, Value b, bool max, Decider& d) {
    // python max_op: le(a, b) decides; else le(b, a)
    Tri t = d.decide_op(Op::LE, a, b);
    if (t == Tri::True) return max ? b : a;
    if (t == Tri::False) return max ? a : b;
    t = d.decide_op(Op::LE, b, a);
    if (t == Tri::True) return max ? a : b;
    if (t == Tri::False) return max ? b : a;
    return std::nullopt;
}

}  // namespace

std::optional<Value> max_of(Value a, Value b, Top top, const Facts* facts) {
    if (a == b) return a;
    Decider d(facts, top);
    return pick(a, b, true, d);
}

std::optional<Value> min_of(Value a, Value b, Top top, const Facts* facts) {
    if (a == b) return a;
    Decider d(facts, top);
    return pick(a, b, false, d);
}

Value reduce_minmax(Value v, Top top, const Facts* facts) {
    if (!(v.is(Op::MAX) || v.is(Op::MIN)) || v.size() < 2) return v;
    const bool is_max = v.is(Op::MAX);
    Decider d(facts, top);
    // an operand that can't be the result: one at most (least) another
    SmallVec<Value, 8> kept;
    for (Value e : v.args()) {
        poll();
        bool dominated = false;
        for (Value k : kept) {
            Tri t = is_max ? d.decide_op(Op::LE, e, k) : d.decide_op(Op::LE, k, e);
            if (t == Tri::True) {
                dominated = true;
                break;
            }
        }
        if (dominated) continue;
        SmallVec<Value, 8> next;
        for (Value k : kept) {
            Tri t = is_max ? d.decide_op(Op::LE, k, e) : d.decide_op(Op::LE, e, k);
            if (t != Tri::True) next.push_back(k);
        }
        next.push_back(e);
        kept = next;
    }
    if (kept.size() == v.size()) return v;
    if (kept.size() == 1) return kept[0];
    return is_max ? max(kept.span()) : min(kept.span());
}

// ---- truth values -------------------------------------------------------------------

Tri eval_bool(Value cond, const Facts* facts) { return Decider(facts, Top::Word).eval(cond); }

Value is_zero(Value cond, const Facts* facts) {
    Tri t = eval_bool(cond, facts);
    if (t == Tri::True) return Value::small(0);
    if (t == Tri::False) return Value::small(1);
    return iszero(cond);
}

Value decide(Value cond, const Facts* facts) {
    Decider d(facts, Top::Word);
    return d.decide(cond, true);
}

// ---- conditions as bounds ------------------------------------------------------------

namespace {

void bounds_into(Value cond, bool neg, CondBounds& res, u32 depth) {
    check_stack();
    while (cond.is(Op::ISZERO, 1) || cond.is(Op::BOOL, 1)) {
        if (cond.is(Op::ISZERO)) neg = !neg;
        cond = cond[0];
    }
    const EvmInt& top = word_max();
    auto push = [&](Value x, const EvmInt& lo, const EvmInt& hi) {
        if (hi < lo) return;
        res.push_back(CondBound{x, lo.value(), hi.value()});
    };
    if (cond.is_int() || cond.is_bool() || cond.is_none() || cond.nil()) return;
    if (cond.is(Op::AND) && !neg && depth < 4) {
        // an AND that isn't 0: none of them is (truth values: all true)
        for (Value e : cond.args()) bounds_into(e, false, res, depth + 1);
        return;
    }
    if (cond.is(Op::OR) && neg && depth < 4) {
        // an OR that is 0: all of them are
        for (Value e : cond.args()) bounds_into(e, true, res, depth + 1);
        return;
    }
    if (!cond.is_expr() || cond.size() != 2 || !is_cmp_op(cond.op())) {
        // a word: not 0 / 0
        if (neg)
            push(cond, EvmInt(0), EvmInt(0));
        else
            push(cond, EvmInt(1), top);
        return;
    }
    Op op = cond.op();
    Value a = cond[0], b = cond[1];
    if (a.is_int() && !b.is_int()) {
        // c < x is x > c
        std::swap(a, b);
        switch (op) {
            case Op::LT: op = Op::GT; break;
            case Op::GT: op = Op::LT; break;
            case Op::LE: op = Op::GE; break;
            case Op::GE: op = Op::LE; break;
            case Op::SLT: op = Op::SGT; break;
            case Op::SGT: op = Op::SLT; break;
            case Op::SLE: op = Op::SGE; break;
            case Op::SGE: op = Op::SLE; break;
            default: break;
        }
    }
    if (!b.is_int() || a.is_int() || a.is_bool()) return;
    const EvmInt c = word_of(b).to_int();
    switch (op) {
        case Op::SLT: case Op::SGT: case Op::SLE: case Op::SGE: {
            // signed: as unsigned, of a value below 2^255 and a constant below 2^255
            static const EvmInt two255 = EvmInt::pow2(255);
            if (!(c < two255) || !(range(a).hi < two255)) return;
            op = op == Op::SLT ? Op::LT : op == Op::SGT ? Op::GT : op == Op::SLE ? Op::LE : Op::GE;
            break;
        }
        default:
            break;
    }
    if (neg) {
        switch (op) {
            case Op::EQ:
                // x != c: an interval only at the ends
                if (c.is_zero()) push(a, EvmInt(1), top);
                if (c == top) push(a, EvmInt(0), top - EvmInt(1));
                return;
            case Op::LT: op = Op::GE; break;
            case Op::GE: op = Op::LT; break;
            case Op::GT: op = Op::LE; break;
            case Op::LE: op = Op::GT; break;
            default: break;
        }
    }
    EvmInt lo, hi;
    switch (op) {
        case Op::LT: lo = EvmInt(0); hi = c - EvmInt(1); break;
        case Op::LE: lo = EvmInt(0); hi = c; break;
        case Op::GT: lo = c + EvmInt(1); hi = top; break;
        case Op::GE: lo = c; hi = top; break;
        case Op::EQ: lo = c; hi = c; break;
        default: return;
    }
    if (hi < lo) return;
    push(a, lo, hi);
    if (a.is(Op::MIN)) {
        // each of them is at least what the smaller one is
        for (Value x : a.args())
            if (!x.is_int()) push(x, lo, top);
    }
}

}  // namespace

CondBounds cond_bounds(Value cond) {
    CondBounds res;
    bounds_into(cond, false, res, 0);
    return res;
}

// ---- apply_constraint ---------------------------------------------------------------

namespace {

bool has_minmax(Value v, MemoSet<Value>& seen) {
    check_stack();
    if (!v.is_expr()) return false;
    if (v.is(Op::MIN) || v.is(Op::MAX)) return true;
    if (!seen.add(v)) return false;
    for (Value a : v.args())
        if (has_minmax(a, seen)) return true;
    return false;
}

Value constrain(Value v, const Facts& f, Memo<Value, Value>& memo) {
    check_stack();
    if (!v.is_expr()) return v;
    if (const Value* r = memo.find(v)) return *r;
    SmallVec<Value, 8> args;
    bool changed = false;
    for (Value a : v.args()) {
        Value x = constrain(a, f, memo);
        changed |= x != a;
        args.push_back(x);
    }
    Value r = changed ? apply(v.op(), args.span()) : v;
    if (r.is(Op::MIN) || r.is(Op::MAX)) r = reduce_minmax(r, Top::Word, &f);
    memo.put(v, r);
    return r;
}

}  // namespace

Value apply_constraint(Value exp, Value cond) {
    {
        MemoSet<Value> seen;
        if (!has_minmax(exp, seen)) return exp;
    }
    Facts f = Facts().with_cond(cond);
    Memo<Value, Value> memo;
    return constrain(exp, f, memo);
}

}  // namespace pan::alg
