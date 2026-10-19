// Value ranges (python algebra.value_range and what rests on it: _linear,
// _term_range, _whole_term_range, set_variables, variants'
// FREE_MEMORY_POINTER; asm ranges.s), with the wrap of EVM sums explicit.
//
// range(v) is an interval [lo, hi] holding v's WORD (its EVM value, in
// [0, 2^256)) for every value of what v is made of - within the assumptions
// of `top` and the path facts given. Sound: a concrete evaluation of v
// (eval.hpp) on any values of its leaves allowed by them lies in it.
//
// Sums are where python was unsound: it read ADD as the integer, so x + 1 >
// x was "true" (wrong for x = 2^256 - 1). Here a sum v = c + sum(k_i * t_i)
// mod 2^256 (linear.hpp) has the integer interval I = [lo, hi] of c +
// sum(k_i * word(t_i)) (each term in its own range; shared terms counted
// once, so (x + 1) - x is 1), and v's word is I - j * 2^256 only when I lies
// within one window [j * 2^256, (j + 1) * 2^256) - proven, else v's range is
// the whole word [0, 2^256 - 1]. The comparisons (compare.hpp) are decided
// on these: never x + 1 > x for free.
//
// Python's mask reading is kept (a sound one): MASK_SHL(size, off, shl, y)
// with concrete fields, off <= 16, shl >= 0, y in [0, 2^(off + size)) and
// no bit pushed past the word, is 2^shl * (y - d), d in [0, 2^off - 1] a
// term of its own (the bits it clears, the same d for the same mask): so
// ceil32(x) - x is in [0, 31] when x + 31 can't wrap.
//
// What the words are (Top):
//  - Top::Word: anything in [0, 2^256 - 1], less for the BOUNDED leaves
//    (calldatasize, returndatasize, codesize, msize, gas: below 2^64 in any
//    execution - gas pays for them), for the variables (AlgebraCtx), for the
//    path facts. Sound for every execution: the only one the VM's path
//    pruning may use.
//  - Top::Memory (python MEMORY_TOP, memory_range): a word a memory address
//    or size is made of is below 2^64 - no execution pays the gas for more
//    memory - except what may not be one (a mask of -x) or what the contract
//    is given unchecked (calldata, a call's return data: a param added to a
//    pointer can wrap) unless small_words says it's small. An assumption of
//    the memory model (lot 4) for the executions that don't run out of gas.
//
// The free memory pointer (python variants.FREE_MEMORY_POINTER): mem[64] is
// at least 0x60 when the loader says the contract is solidity's (on by
// default, as python; AlgebraCtx::set_free_memory_pointer).
//
// Ranges without facts are memoized per context and top (cleared with the
// context's caches: set_variables, set_free_memory_pointer); with facts a
// walk of its own (bounded: past a node budget what's left is the range
// without facts, which is sound).
#pragma once

#include <optional>
#include <span>
#include <utility>

#include "algebra/linear.hpp"
#include "core/evmint.hpp"
#include "core/smallvec.hpp"  // Tri
#include "core/value.hpp"

namespace pan::alg {

class Facts;  // algebra/facts.hpp

// what the words an expression is made of may be (see above)
enum class Top : u8 { Word = 0, Memory = 1 };

// an integer interval, lo <= hi (unbounded integers: a sum's may be past a
// word, or negative)
struct Range {
    EvmInt lo, hi;

    static Range word();                                // [0, 2^256 - 1]
    static Range point(const EvmInt& x) { return Range{x, x}; }
    static Range bits(u32 n);                           // [0, 2^n - 1] (n <= 256)
    static Range of(EvmInt lo, EvmInt hi) { return Range{std::move(lo), std::move(hi)}; }

    bool is_point() const noexcept { return lo == hi; }
    // 0 <= lo and hi <= 2^256 - 1: a word's range
    bool is_word() const noexcept;
    bool contains(const EvmInt& x) const noexcept { return lo <= x && x <= hi; }
    bool contains(const Range& r) const noexcept { return lo <= r.lo && r.hi <= hi; }
    bool excludes_zero() const noexcept { return lo.sign() > 0 || hi.sign() < 0; }
    // the intersection; nullopt when they don't meet
    std::optional<Range> meet(const Range& o) const;
    // the smallest interval holding both
    Range hull(const Range& o) const;
    // the word an integer in this range is, when they're all in one window
    // [j * 2^256, (j + 1) * 2^256): the range moved by -j * 2^256; else
    // [0, 2^256 - 1]
    Range as_word() const;
    bool operator==(const Range&) const = default;
};

// the range of v's WORD for every value of what it's made of, within top's
// assumptions and what the facts say (python value_range, its sums made
// words). v: any word expression (an int, True/False, a leaf, a name, an
// EXPR); a non-word (a LIST, bytes) is [0, 2^256 - 1].
Range range(Value v, Top top = Top::Word, const Facts* facts = nullptr);
// python memory_range: range(v, Top::Memory)
inline Range memory_range(Value v, const Facts* facts = nullptr) { return range(v, Top::Memory, facts); }

// the INTEGER interval of a linear form's I = constant + sum(coeff_i *
// word(term_i)) (linear.hpp: not the word, which is I mod 2^256 - see
// Range::as_word): python's value_range of a sum, with its mask reading
Range int_range(const Linear& l, Top top = Top::Word, const Facts* facts = nullptr);
// the integer interval of v's linear form (python value_range(v) as it was)
Range int_range(Value v, Top top = Top::Word, const Facts* facts = nullptr);

// v < 2^n for every value: the n of range(v)'s top (python
// memloc.max_value_bits, with the ranges): 0 for 0, 256 when unknown
u32 range_bits(Value v, Top top = Top::Word, const Facts* facts = nullptr);
// python is_word: v's linear form, as an integer, is a word (its integer is
// its value: no wrap)
bool is_word(Value v, Top top = Top::Word, const Facts* facts = nullptr);
// python shift_sign: 1 if v's integer is a word (a shift left by it), -1 if
// minus it is (a shift right), 0 if v is 0, nullopt if not known which
std::optional<int> shift_sign(Value v);

// ---- what the ranges assume of a trace: the algebra context ------------------

// python set_variables(values, small): what each variable of the trace being
// simplified is set to, anywhere in it - (name, value) pairs, a name once per
// value: its range is the union of its values' (a cyclic one, whose values
// are made of it, a loop's counter, is a word) - and the words below 2^64
// wherever they're in a memory address or size (simplify.small_words). The
// context's caches are cleared (Context::clear_caches: whatever was decided
// under the old ones, every module's). set_variables({}, {}) forgets them.
void set_variables(std::span<const std::pair<Value, Value>> name_values, std::span<const Value> small);
void clear_variables();
// python variants.set_free_memory_pointer: whether mem[64] is solidity's
// free memory pointer (>= 0x60); clears the caches when it changes
void set_free_memory_pointer(bool on);
bool free_memory_pointer();

// python unchecked(exp, values, small): v is made of a word the contract is
// given (CALLDATALOAD, CALLDATA_BYTES, RETURNDATA_BYTES, a PARAM) not in
// small, through computations (ADD ... MIN/MAX, DATA, SIZED) or variables
// set to such (the context's variables)
bool unchecked(Value v);

}  // namespace pan::alg
