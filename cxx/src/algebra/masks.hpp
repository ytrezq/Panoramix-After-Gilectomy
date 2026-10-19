// Masks (python core/masks.py, algebra.mask_to_int; asm masks.s): the view
// of a MASK_SHL node as a struct, the recognition of mask constants, and
// structural bit facts (a bound of the bits a value has, the low bits known
// to be 0) - sound, from the shape alone: no ranges, no assumptions.
//
// MASK_SHL(size, off, shl, x) = the bits [off, off + size) of x, moved left
// by shl (right when negative), mod 2^256 (eval.hpp: mask_shl_word). The
// fields are small signed ints, or word expressions read as signed numbers
// (a shift computed at runtime). The canonical concrete form (construct.hpp,
// mask()) keeps every bit it takes:
//   0 < size,  0 <= off,  off + size <= 256,  0 <= off + shl,
//   off + size + shl <= 256,  and not (off == 0 && size + shl == 256): that
//   one is x times 2^shl, MUL(2^shl, x) (x itself for shl = 0).
#pragma once

#include <optional>

#include "core/evmint.hpp"
#include "core/value.hpp"

namespace pan::alg {

// a MASK_SHL's operands, by name
struct MaskShl {
    Value size, off, shl, x;

    // the three fields are small ints
    bool concrete() const noexcept { return size.is_small() && off.is_small() && shl.is_small(); }
    // (concrete() only)
    i64 isize() const noexcept { return size.small_val(); }
    i64 ioff() const noexcept { return off.small_val(); }
    i64 ishl() const noexcept { return shl.small_val(); }
    // where the field ends up: bits [lo(), hi()) of the result (concrete only)
    i64 lo() const noexcept { return ioff() + ishl(); }
    i64 hi() const noexcept { return ioff() + isize() + ishl(); }
};

// v is a MASK_SHL: its fields
std::optional<MaskShl> as_mask(Value v) noexcept;
// v as a mask of something: a MASK_SHL's fields; x * 2^p (MUL(2^p, x)) as
// {256 - p, 0, p, x}; anything else as {256, 0, 0, v}
MaskShl mask_view(Value v);

// (size, off) of a mask constant: bits [off, off + size) set, the others 0
// (python masks.to_mask). Also the symbolic 2^(k*e) - 1 forms of python's
// to_mask (SUB(EXP(2^k, e), 1), ADD(-1, EXP(2^k, e))): {k*e, 0} - only when
// e * k is proven below 2^256 structurally (max_bits).
struct MaskFields {
    Value size, off;
};
std::optional<MaskFields> to_mask(Value v);
// (size, off) of the complement of a mask constant (python to_neg_mask):
// v = ~mask(size, off); NOT(m) of a mask m too
std::optional<MaskFields> to_neg_mask(Value v);
// k when w == 2^k
std::optional<u32> log2_exact(const Word256& w) noexcept;

// k when v is the int 2^k (k < 256: a word)
std::optional<u32> to_exp2(Value v);

// the byte-rounded mask that covers the set bits of w: (size, off), both
// multiples of 8 (python find_mask: the printer's casts)
struct BitSpan {
    u32 size, off;
};
BitSpan find_mask(const Word256& w) noexcept;
// (size, off) when the set bits of w are one run: bits [off, off + size)
std::optional<BitSpan> as_bit_run(const Word256& w) noexcept;

// x may be wider than a word (python algebra.may_be_wide): a byte string of
// more than 32 bytes, or not known to be at most 32 (DATA, ARR, SALL,
// SBYTES, SIZED / MEM / CALLDATA_BYTES / CODE_BYTES / RETURNDATA_BYTES /
// EXTCODE_BYTES of a length that isn't an int <= 32). A mask of it keeps
// its fields as given (bits past 256 exist); the Evaluator asks the env.
bool may_be_wide(Value x) noexcept;

// ---- structural bit facts (sound for every value of the leaves) ----------

// v < 2^max_bits(v) as a word, for any value of what v is made of: ints
// their bit length; comparisons, ISZERO, BOOL 1; BYTE 8; CLZ 9; concrete
// masks their top; AND the least of its operands', OR/XOR the most; SHR by
// a constant k: 256 - k; DIV by a constant; MOD by b: bits(b); sums of
// non-negative terms and products of non-negative ones while they can't
// wrap; STORAGE(size, off >= 0, _) size; else 256.
u32 max_bits(Value v);
// the low bits of v known to be 0 (python simplify.low_zero_bits, as words)
u32 low_zero_bits(Value v);

}  // namespace pan::alg
