// The linear form (linear.hpp).
#include "algebra/linear.hpp"

#include <algorithm>

#include "algebra/construct.hpp"
#include "algebra/eval.hpp"
#include "core/context.hpp"
#include "core/order.hpp"

namespace pan::alg {

namespace {

// v as a canonical sum (constructors' normal form; normalize is memoized
// and a normal v is its own normal form)
Value canonical(Value v) {
    if (v.is_int()) return signed_int(v);
    if (!v.is_expr()) return v;
    Value r = normalize(v);
    if (r.is_int()) r = signed_int(r);
    return r;
}

// one term of a canonical sum: (base, coeff)
LinTerm term_of(Value t) {
    if (t.is(Op::MUL) && t.size() >= 2 && t[0].is_int()) {
        if (t.size() == 2) return LinTerm{t[1], signed_int(t[0])};
        return LinTerm{mk(Op::MUL, t.args().subspan(1)), signed_int(t[0])};
    }
    return LinTerm{t, Value::small(1)};
}

}  // namespace

Value Linear::coeff_of(Value t) const noexcept {
    for (const LinTerm& x : terms)
        if (x.term == t) return x.coeff;
    return Value::small(0);
}

Linear linear(Value v) {
    Linear l;
    Value n = canonical(v);
    if (n.is_int()) {
        l.constant = signed_int(n);
        return l;
    }
    if (n.is(Op::ADD)) {
        for (Value t : n.args()) {
            if (t.is_int())
                l.constant = signed_int(t);
            else
                l.terms.push_back(term_of(t));
        }
    } else {
        l.terms.push_back(term_of(n));
    }
    std::sort(l.terms.begin(), l.terms.end(), [](const LinTerm& a, const LinTerm& b) { return compare(a.term, b.term) < 0; });
    return l;
}

Value from_linear(const Linear& l) {
    SmallVec<Value, 8> ops;
    ops.push_back(l.constant);
    for (const LinTerm& t : l.terms) ops.push_back(mul(t.coeff, t.term));
    return add(ops.span());
}

Linear linear_diff(Value a, Value b) { return linear(sub(a, b)); }

std::optional<Value> const_diff(Value a, Value b) {
    if (a == b) return Value::small(0);
    // the canonical sums' constants and symbolic parts
    auto split = [](Value v, Value& c, std::span<const Value>& rest, Value& holder) {
        c = Value::small(0);
        if (v.is_int()) {
            c = v;
            rest = {};
        } else if (v.is(Op::ADD) && v.size() >= 2 && v[0].is_int()) {
            c = v[0];
            rest = v.args().subspan(1);
        } else if (v.is(Op::ADD)) {
            rest = v.args();
        } else {
            holder = v;
            rest = std::span<const Value>(&holder, 1);
        }
    };
    Value ca, cb, ha, hb;
    std::span<const Value> ra, rb;
    Value na = canonical(a), nb = canonical(b);
    split(na, ca, ra, ha);
    split(nb, cb, rb, hb);
    if (ra.size() != rb.size()) return std::nullopt;
    for (usize i = 0; i < ra.size(); ++i)
        if (!(ra[i] == rb[i])) return std::nullopt;
    return signed_int(sub(ca, cb));
}

}  // namespace pan::alg
