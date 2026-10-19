// The linear form of an expression, with the wrap explicit (design note 3:
// the first weakness of python, whose sums were integers in value_range).
//
// An EVM ADD is mod 2^256. linear(v) reads v as
//
//     v  ==  constant + sum(coeff_i * term_i)   (mod 2^256)
//
// for every value of the leaves, where constant and the coefficients are
// ints in [-2^255, 2^255) (signed_int; coefficients never 0) and every term
// is a word (in [0, 2^256)) that is neither an int, nor an ADD, nor a
// constant times something. The congruence always holds; the INTEGER
//
//     I  =  constant + sum(coeff_i * word(term_i))
//
// equals v's word only when 0 <= I < 2^256 for every value of the leaves:
// a comparison of sums as integers (lot 3: ranges, compare) is sound only
// with that no-wrap side condition proven - never x + 1 > x for free (x =
// 2^256 - 1 wraps it to 0).
//
// The canonical sum (construct.hpp add) IS the linear form: linear() of a
// normal sum only reads it; anything else is normalized first (memoized).
#pragma once

#include <optional>

#include "core/evmint.hpp"
#include "core/smallvec.hpp"
#include "core/value.hpp"

namespace pan::alg {

struct LinTerm {
    Value term;   // the base: not an int, an ADD, nor MUL(int, ...)
    Value coeff;  // an int Value in [-2^255, 2^255), never 0
};

struct Linear {
    Value constant = Value::small(0);  // an int Value in [-2^255, 2^255)
    SmallVec<LinTerm, 6> terms;        // distinct terms, in compare() order

    bool is_const() const noexcept { return terms.empty(); }
    EvmInt constant_int() const { return EvmInt(constant); }
    EvmInt coeff_int(usize i) const { return EvmInt(terms[i].coeff); }
    // the coefficient of t (0 when t isn't a term)
    Value coeff_of(Value t) const noexcept;
};

// v's linear form (an int: no terms; a non-sum: itself times 1)
Linear linear(Value v);
// the canonical sum of a linear form (construct.hpp add's normal form)
Value from_linear(const Linear& l);
// a - b as a linear form: is_const() when they differ by a constant (mod 2^256)
Linear linear_diff(Value a, Value b);
// the constant a - b is (mod 2^256, in [-2^255, 2^255)), when it is one
std::optional<Value> const_diff(Value a, Value b);

}  // namespace pan::alg
