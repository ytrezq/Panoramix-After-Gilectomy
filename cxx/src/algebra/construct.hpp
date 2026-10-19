// The algebra's constructors (python algebra.add_op sub_op mul_op div_op
// mask_op shl_op shr_op or_op, vm.and_op, arithmetic.is_zero, Stack.simplify;
// asm algebra.s, arith.s): every expression of the pipeline is made through
// them, in the normal forms below - two expressions built from the same
// operations on the same operands are the same node.
//
// Semantics: EVM words, everything mod 2^256 (ir.md 4.3; eval.hpp is the
// definition). A constructor never changes the value: for any value of the
// leaves, eval(ctor(args)) == the EVM operation on eval(args) (the doctests
// check it on random and edge words). They decide only what holds for every
// value (structure, constants): what needs ranges or path facts is lot 3's
// (algebra/ranges.hpp, compare.hpp).
//
// Normal forms (concrete constants; every operand already normal):
//  - an int result: the word, in [0, 2^256) (word_int).
//  - sums: ADD(c, t1, ..., tn), flattened; c the constant in
//    [-2^255, 2^255) (signed_int), first, absent when 0; n >= 1 terms,
//    n + (c != 0) >= 2. A term is a base b, or MUL(k, b...) with k an int
//    in [-2^255, 2^255) other than 0 and 1; a base is anything but an int,
//    an ADD, or a MUL whose first operand is an int (a product of several
//    symbolic factors MUL(f1, ..., fm) is one base: MUL(k, f1, ..., fm) is
//    k times it). A term is read as k times a field of a value x (x itself,
//    or MASK_SHL(size, off, shl, x) as 2^(off + shl) times its bits moved
//    to 0); the terms are ordered by x (compare()), then off, then size,
//    one term per field. Terms over the same x that are fields of it combine
//    (try_add: x - (x & 31) is MASK_SHL(251, 5, 0, x), adjacent fields of
//    x are one field).
//  - products: MUL(k, f1, ..., fm), k first (absent when 1, the product is
//    then f1 when m = 1), factors in compare() order, products of sums
//    distributed (while small). 2^p times a field of x is a field
//    (MASK_SHL with p added to its shl); 2^p times anything else stays
//    MUL(2^p, x).
//  - masks: MASK_SHL(size, off, shl, x) in the canonical form of masks.hpp
//    (every bit it takes is kept; size 0 is the int 0); a mask of a mask is
//    one mask when the fields are concrete; AND with a mask constant, SHR
//    and SHL by a constant, DIV by 2^k, BYTE at a constant index are masks;
//    an AND with the complement of a mask is the OR of two masks.
//  - truth values: ISZERO pushed through comparisons (iszero(lt) = ge...),
//    double negations, BOOL (bool of a 0/1 value is itself), OR and AND of
//    truth values (python arithmetic.is_zero).
//  - comparisons LT GT SLT SGT EQ LE GE SLE SGE keep their operands' order;
//    constants folded, x op x folded when x is not volatile (python
//    eval_symbolic), EQ of a and b with a - b a constant folded.
//  - AND, OR: flattened, constants combined, duplicates dropped, the
//    others in their order. XOR, NOT, SAR, SIGNEXTEND, CLZ, ADDMOD, MULMOD,
//    EXP, SDIV, SMOD, MOD, DIV: constants folded, the identities that hold
//    for every value applied (x ^ x = 0, ~~x = x, x % 1 = 0, ...).
//  - MAX, MIN: flattened, constants combined, duplicates dropped, operands
//    in compare() order; nothing decided that needs a comparison (lot 3's).
//
// The constructors are memoized per context where it pays (add of two
// operands, mask). Sizes: SizeLimit past limits::MAX_NODE_COUNT terms; no
// contract number reaches GMP as a shift or exponent unclamped.
#pragma once

#include <initializer_list>
#include <optional>
#include <span>

#include "algebra/masks.hpp"  // MaskShl, max_bits, low_zero_bits...: one include for the constructors' users
#include "core/value.hpp"

namespace pan::alg {

// ---- sums and products ------------------------------------------------------

Value add(std::span<const Value> args);
inline Value add(std::initializer_list<Value> args) { return add(std::span<const Value>(args.begin(), args.size())); }
Value add(Value a, Value b);
Value add(Value a, Value b, Value c);
Value sub(Value a, Value b);  // a - b
Value neg(Value a);           // -a (python minus_op)
Value mul(std::span<const Value> args);
inline Value mul(std::initializer_list<Value> args) { return mul(std::span<const Value>(args.begin(), args.size())); }
Value mul(Value a, Value b);

Value div(Value a, Value b);   // a / b (EVM: x / 0 = 0)
Value sdiv(Value a, Value b);
Value mod(Value a, Value b);
Value smod(Value a, Value b);
Value addmod(Value a, Value b, Value n);
Value mulmod(Value a, Value b, Value n);
Value exp(Value base, Value e);

// ---- masks and shifts -------------------------------------------------------

// the bits [off, off + size) of x moved left by shl (python mask_op; shr
// is a negative shl). Fields: small ints, or word expressions.
Value mask(Value size, Value off, Value shl, Value x);
Value mask(i64 size, i64 off, i64 shl, Value x);
// x with the bits [off, off + size) cleared: the OR of the masks below and
// above them (python neg_mask_op)
Value neg_mask(Value size, Value off, Value x);
Value shl(Value shift, Value x);  // EVM order: x << shift
Value shr(Value shift, Value x);  // x >> shift
Value sar(Value shift, Value x);
Value byte(Value idx, Value x);   // the idx-th byte of x, the most significant first
Value signextend(Value b, Value x);

// ---- bitwise ------------------------------------------------------------------

Value band(std::span<const Value> args);  // AND (masks recognized, python vm.and_op)
inline Value band(std::initializer_list<Value> args) { return band(std::span<const Value>(args.begin(), args.size())); }
Value band(Value a, Value b);
Value bor(std::span<const Value> args);   // OR
inline Value bor(std::initializer_list<Value> args) { return bor(std::span<const Value>(args.begin(), args.size())); }
Value bor(Value a, Value b);
Value bxor(Value a, Value b);
Value bnot(Value a);
Value clz(Value a);

// ---- truth values and comparisons --------------------------------------------

// a == 0 as an expression (python arithmetic.is_zero): an int 0/1 when
// known, else ISZERO pushed through comparisons, BOOL, ISZERO, OR, AND
Value iszero(Value a);
// a != 0 as a 0/1 value (BOOL): a itself when it is 0/1 already
Value to_bool(Value a);
// whether a's value is 0 or 1 for every value of the leaves (python is_bool)
bool is_bool(Value a);
// an expression with the same TRUTH as a (zero exactly when a is), not the
// same value: BOOL(x) is x, ISZERO(ISZERO(x)) is x (python
// arithmetic.simplify_bool) - for conditions only (if, while, require)
Value truth(Value a);
// op one of LT GT SLT SGT EQ LE GE SLE SGE
Value cmp(Op op, Value a, Value b);
// MAX, MIN (unsigned), structural only
Value max(std::span<const Value> args);
Value min(std::span<const Value> args);
inline Value max(std::initializer_list<Value> args) { return max(std::span<const Value>(args.begin(), args.size())); }
inline Value min(std::initializer_list<Value> args) { return min(std::span<const Value>(args.begin(), args.size())); }

// ---- bit counts and bytes ----------------------------------------------------

// 8 * nbytes, distributed over a sum (python algebra.bits)
Value bits(Value nbytes);
// nbits as bytes (python algebra.to_bytes): bytes = ceil(nbits / 8) for
// ints, nbits / 8 when nbits is known to be a multiple of 8; rem = the bits
// left over (nbits % 8), nullopt when that isn't known (then bytes is
// nbits >> 3)
struct ToBytes {
    Value bytes;
    std::optional<u32> rem;
};
ToBytes to_bytes(Value nbits);

// ---- the VM's entry, and re-normalization ---------------------------------------

// The normal form of op over these operands (IR operand order: EVM stack
// order). Every pure op (eval.hpp is_pure: ADD..CLZ, MASK_SHL, BOOL, LE..SGE,
// MAX, MIN, LAND, LOR) goes through its constructor; any other op is
// mk(op, args) as it is. InternalError on a wrong operand count.
Value apply(Op op, std::span<const Value> args);
inline Value apply(Op op, std::initializer_list<Value> args) {
    return apply(op, std::span<const Value>(args.begin(), args.size()));
}
// v rebuilt bottom-up through apply (EXPR nodes, any depth; lists and
// immediates as they are): what a substitution needs to be normal again.
// Memoized per context; v itself when it was normal.
Value normalize(Value v);

}  // namespace pan::alg
