// Comparisons decided by ranges, truth values decided by ranges and path
// facts (python algebra.ge_zero lt_op le_op max_op min_op _max_op,
// arithmetic.is_zero / eval_bool, vm.is_known, simplify.cond_bounds
// decide_le apply_constraint; asm ranges.s, conds.s). (python's max_to_add
// isn't: a comparison with a MAX / MIN is decided by its operands.)
//
// Every answer is Tri (core/smallvec.hpp): True / False only when it holds
// for every value of what the operands are made of (within top's
// assumptions and the facts given: ranges.hpp), Tri::None when that depends
// on them. A decision never rests on a sum read as an integer unless its
// no-wrap condition is proven: x + 1 > x stays None (x = 2^256 - 1).
//
// Two kinds of comparisons:
//  - of WORDS (lt, le, eq, slt, sle, decide_cmp): the EVM's, what the IR's
//    LT GT ... mean - the ones to use on expressions.
//  - of INTEGERS (ge_zero, gt_zero, int_lt, int_le): python's lt_op / le_op,
//    on the integers of the linear forms (linear.hpp: constant + sum(coeff *
//    word(term)), not reduced mod 2^256) - for mask fields (read as signed
//    integers) and for whoever reasons on sums as integers on purpose.
#pragma once

#include <optional>

#include "algebra/linear.hpp"
#include "algebra/ranges.hpp"
#include "core/ops.hpp"
#include "core/smallvec.hpp"  // Tri
#include "core/value.hpp"

namespace pan::alg {

class Facts;  // algebra/facts.hpp

// ---- Tri helpers --------------------------------------------------------------

inline std::optional<bool> as_bool(Tri t) noexcept {
    if (t == Tri::True) return true;
    if (t == Tri::False) return false;
    return std::nullopt;
}
inline Tri tri_of(std::optional<bool> b) noexcept { return b ? tri(*b) : Tri::None; }
inline Tri tri_not(Tri t) noexcept {
    if (t == Tri::True) return Tri::False;
    if (t == Tri::False) return Tri::True;
    return t;
}
inline bool decided(Tri t) noexcept { return t == Tri::True || t == Tri::False; }

// ---- integers (python's comparisons of sums) ------------------------------------

// I >= 0 / I > 0 for the integer I of the linear form (python ge_zero)
Tri ge_zero(const Linear& l, Top top = Top::Word, const Facts* facts = nullptr);
Tri gt_zero(const Linear& l, Top top = Top::Word, const Facts* facts = nullptr);
// I(a) < I(b), I(a) <= I(b) for the integers of a's and b's linear forms
// (python lt_op, le_op - max operands handled as python: below the largest)
Tri int_lt(Value a, Value b, Top top = Top::Word, const Facts* facts = nullptr);
Tri int_le(Value a, Value b, Top top = Top::Word, const Facts* facts = nullptr);

// ---- words (the EVM's comparisons) ---------------------------------------------

// word(a) < word(b), unsigned
Tri lt(Value a, Value b, Top top = Top::Word, const Facts* facts = nullptr);
// word(a) <= word(b), unsigned
Tri le(Value a, Value b, Top top = Top::Word, const Facts* facts = nullptr);
// word(a) == word(b)
Tri eq(Value a, Value b, Top top = Top::Word, const Facts* facts = nullptr);
// a < b, a <= b as signed words (two's complement)
Tri slt(Value a, Value b, Top top = Top::Word, const Facts* facts = nullptr);
Tri sle(Value a, Value b, Top top = Top::Word, const Facts* facts = nullptr);
// op(a, b), op one of LT GT SLT SGT EQ LE GE SLE SGE (the IR's operand
// order); Tri::None for any other op
Tri decide_cmp(Op op, Value a, Value b, Top top = Top::Word, const Facts* facts = nullptr);

// ---- max / min (unsigned words) ---------------------------------------------------

// the larger / smaller of a and b when a comparison decides which (python
// max_op, min_op): a or b; nullopt when it depends
std::optional<Value> max_of(Value a, Value b, Top top = Top::Word, const Facts* facts = nullptr);
std::optional<Value> min_of(Value a, Value b, Top top = Top::Word, const Facts* facts = nullptr);
// MAX(...) / MIN(...) (any depth below: the operands as they are) with the
// operands that can't be the result dropped (python _max_op, simplify_max):
// one operand when the others are; v itself when nothing is decided (and
// any other value as it is)
Value reduce_minmax(Value v, Top top = Top::Word, const Facts* facts = nullptr);

// ---- truth values --------------------------------------------------------------

// whether cond holds (a word: true when it isn't 0) for every value of what
// it's made of where the facts hold (python eval_bool(exp, known,
// symbolic=True) and vm.is_known together): constants, the facts'
// conditions (the same condition, its negation, BOOL / ISZERO / OR / AND
// through them, a known x < a deciding x < b), and the comparisons and
// values decided by ranges - Top::Word only: sound for every execution, the
// VM prunes its jumps with it.
Tri eval_bool(Value cond, const Facts* facts = nullptr);
// what decided eval_bool's answers, on this thread (for the tools and the
// tests: python decided with constants and the facts' conditions alone -
// `beyond` counts what only the ranges, the comparisons taken apart and the
// facts' comparisons chained decide)
struct EvalStats {
    u64 calls = 0;      // eval_bool
    u64 constant = 0;   // its value (eval_const)
    u64 matched = 0;    // a fact's condition, or its negation (Facts::match: python's is_known)
    u64 beyond = 0;     // the rest
    u64 undecided = 0;
};
EvalStats& eval_stats() noexcept;

// cond == 0 as an expression: alg::iszero (the structural one: ISZERO
// pushed through comparisons, BOOL, OR, AND) with what eval_bool decides:
// the int 1 / 0 when decided
Value is_zero(Value cond, const Facts* facts = nullptr);
// cond with the sub-conditions (comparisons, truth values below BOOL /
// ISZERO / OR / AND) that eval_bool decides replaced by 1 / 0, and
// renormalized (python's cleanup of known conditions); cond itself when
// nothing is decided
Value decide(Value cond, const Facts* facts = nullptr);

// ---- conditions as bounds (python simplify.cond_bounds, decide_le, apply_constraint) --

// what cond (known to hold) says of expressions compared with constants:
// x in [lo, hi] (CondBound, ranges.hpp: unsigned words; a signed comparison
// when x < 2^255 for sure and the constant is below 2^255; through ISZERO /
// BOOL; x itself: not 0, ISZERO(x): 0; an AND that holds: each of its
// operands; an OR that doesn't: none of them; the operands of a MIN
// compared from below: each is at least lo)
CondBounds cond_bounds(Value cond);
// exp where cond holds: its MIN / MAX that cond decides made the operand
// they are (python apply_constraint: min(32, returndatasize) is 32 once
// returndatasize >= 32 is known); exp itself when nothing changes
Value apply_constraint(Value exp, Value cond);

}  // namespace pan::alg
