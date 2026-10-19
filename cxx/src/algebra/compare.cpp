// Comparisons and truth values: see compare.hpp. (First version: trivially
// correct answers; the decisions follow.)
#include "algebra/compare.hpp"

#include "algebra/construct.hpp"
#include "algebra/eval.hpp"
#include "algebra/facts.hpp"
#include "core/context.hpp"

namespace pan::alg {

Tri ge_zero(const Linear& l, Top top, const Facts* facts) {
    Range r = int_range(l, top, facts);
    if (r.lo.sign() >= 0) return Tri::True;
    if (r.hi.sign() < 0) return Tri::False;
    return Tri::None;
}

Tri gt_zero(const Linear& l, Top top, const Facts* facts) {
    Range r = int_range(l, top, facts);
    if (r.lo.sign() > 0) return Tri::True;
    if (r.hi.sign() <= 0) return Tri::False;
    return Tri::None;
}

Tri int_lt(Value, Value, Top, const Facts*) { return Tri::None; }
Tri int_le(Value, Value, Top, const Facts*) { return Tri::None; }

namespace {
Tri const_cmp(Op op, Value a, Value b) {
    auto x = eval_const(a);
    auto y = eval_const(b);
    if (!x || !y) return Tri::None;
    const Word256 xs[2] = {*x, *y};
    auto r = eval_op(op, std::span<const Word256>(xs, 2));
    if (!r) return Tri::None;
    return tri(!r->is_zero());
}
}  // namespace

Tri lt(Value a, Value b, Top, const Facts*) { return const_cmp(Op::LT, a, b); }
Tri le(Value a, Value b, Top, const Facts*) { return const_cmp(Op::LE, a, b); }
Tri eq(Value a, Value b, Top, const Facts*) { return a == b ? Tri::True : const_cmp(Op::EQ, a, b); }
Tri slt(Value a, Value b, Top, const Facts*) { return const_cmp(Op::SLT, a, b); }
Tri sle(Value a, Value b, Top, const Facts*) { return const_cmp(Op::SLE, a, b); }

Tri decide_cmp(Op op, Value a, Value b, Top, const Facts*) {
    switch (op) {
        case Op::LT: case Op::GT: case Op::SLT: case Op::SGT: case Op::EQ:
        case Op::LE: case Op::GE: case Op::SLE: case Op::SGE:
            return const_cmp(op, a, b);
        default:
            return Tri::None;
    }
}

std::optional<Value> max_of(Value, Value, Top, const Facts*) { return std::nullopt; }
std::optional<Value> min_of(Value, Value, Top, const Facts*) { return std::nullopt; }
Value reduce_minmax(Value v, Top, const Facts*) { return v; }

Tri eval_bool(Value cond, const Facts* facts) {
    if (auto w = eval_const(cond)) return tri(!w->is_zero());
    if (facts) return facts->match(cond);
    return Tri::None;
}

Value is_zero(Value cond, const Facts* facts) {
    Tri t = eval_bool(cond, facts);
    if (t == Tri::True) return Value::small(0);
    if (t == Tri::False) return Value::small(1);
    return iszero(cond);
}

Value decide(Value cond, const Facts*) { return cond; }

CondBounds cond_bounds(Value cond) {
    CondBounds res;
    bool neg = false;
    while (cond.is(Op::ISZERO, 1) || cond.is(Op::BOOL, 1)) {
        if (cond.is(Op::ISZERO)) neg = !neg;
        cond = cond[0];
    }
    if (!cond.is_expr() || cond.size() != 2) return res;
    Op op = cond.op();
    switch (op) {
        case Op::LT: case Op::GT: case Op::LE: case Op::GE: case Op::EQ:
        case Op::SLT: case Op::SGT: case Op::SLE: case Op::SGE:
            break;
        default:
            return res;
    }
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
    if (!b.is_int() || a.is_int() || a.is_bool()) return res;
    EvmInt c = Word256::from_value(b).to_int();
    switch (op) {
        case Op::SLT: case Op::SGT: case Op::SLE: case Op::SGE: {
            // signed: as unsigned, of a value below 2^255 and a constant below 2^255
            static const EvmInt two255 = EvmInt::pow2(255);
            if (!(c < two255) || range_bits(a) >= 256 || !(range(a).hi < two255)) return res;
            op = op == Op::SLT ? Op::LT : op == Op::SGT ? Op::GT : op == Op::SLE ? Op::LE : Op::GE;
            break;
        }
        default:
            break;
    }
    if (neg) {
        switch (op) {
            case Op::EQ: return res;  // x != c: no interval
            case Op::LT: op = Op::GE; break;
            case Op::GE: op = Op::LT; break;
            case Op::GT: op = Op::LE; break;
            case Op::LE: op = Op::GT; break;
            default: break;
        }
    }
    const EvmInt& top = word_max();
    EvmInt lo, hi;
    switch (op) {
        case Op::LT: lo = EvmInt(0); hi = c - EvmInt(1); break;
        case Op::LE: lo = EvmInt(0); hi = c; break;
        case Op::GT: lo = c + EvmInt(1); hi = top; break;
        case Op::GE: lo = c; hi = top; break;
        case Op::EQ: lo = c; hi = c; break;
        default: return res;
    }
    if (hi < lo) return res;
    Value vlo = lo.value(), vhi = hi.value();
    res.push_back(CondBound{a, vlo, vhi});
    if (a.is(Op::MIN)) {
        // each of them is at least what the smaller one is
        Value vtop = top.value();
        for (Value x : a.args())
            if (!x.is_int()) res.push_back(CondBound{x, vlo, vtop});
    }
    return res;
}

Value apply_constraint(Value exp, Value) { return exp; }

}  // namespace pan::alg
