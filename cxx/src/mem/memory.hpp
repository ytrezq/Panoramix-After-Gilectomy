// The memory model (lot 4; python core/memloc.py, asm memloc.s and
// widths.s; ir.md 4.2): the widths of bytes expressions, memory ranges and
// how they meet, the slices of what a write wrote, a read assembled from
// the writes before it, and the splits of a write of fields (a SETMEM of
// several fields, a STORE of a slot's packed fields).
//
// Bytes expressions (ir.md 4.2; exec/machine.hpp is the definition): None
// (no bytes), a BYTES node (its bytes), SIZED(n, v) (v's low n bytes
// big-endian - a word -, or v's bytes resized to n: zeroes before them, or
// their last n), DATA(e...) (the concatenation; an ARR element is
// ABI-encoded), MEM(RANGE(p, n)), CALLDATA_BYTES(p, n), CODE_BYTES(p, n),
// RETURNDATA_BYTES(id, p, n), EXTCODE_BYTES(a, RANGE(p, n)) (zero padded
// past their source's end), ARR, SBYTES, SALL. Every byte element carries
// its width: a word is never a byte element without its SIZED (a width is
// never guessed from a mask's shape - the algebra's normal forms keep only
// the word's value). A SETMEM(RANGE(p, n), v) writes v's low n bytes when v
// is a word, v's bytes when it is bytes (exactly n of them).
//
// Ranges: RANGE(start, len), in bytes, of memory. Two ranges are compared
// as integers: the bytes [start, start + len). The comparisons of addresses
// and sizes are lot 3's with alg::Top::Memory (python MEMORY_TOP: the words
// an address or a size is made of are below 2^64 - no execution pays the
// gas for more memory - but what the contract is given unchecked), under
// the path facts when given. A range of length 0 has no bytes: it meets
// nothing, whatever its start. Every answer is a Tri: True / False only
// when it holds for every value of what the ranges are made of; Tri::None
// otherwise - a "may": what may be written is never read as known.
//
// Validity of a value at another point: a write's value (and its range) is
// evaluated where the write is; read later, it stands for the bytes
// written only if nothing between changed what it reads. MemState and fill
// check the memory (the writes they are given: none may change the memory
// a kept value or range reads, msize never kept); the rest of the state
// (storage, calls, variables set again: lot 7's effect summaries) is the
// caller's: forget_flags / forget_name / clear where the trace changes it.
//
// Caps: constant byte strings made here (slices of BYTES nodes, of long
// constants) at most 2^24 bytes (MemoryLimit past it, the asm's); zeroes of
// fresh memory known at most limits::MAX_ZEROES_SIZE bytes at once.
#pragma once

#include <memory_resource>
#include <optional>
#include <span>
#include <vector>

#include "core/base.hpp"
#include "core/ops.hpp"
#include "core/smallvec.hpp"  // SmallVec, Tri
#include "core/value.hpp"

namespace pan::alg {
class Facts;  // algebra/facts.hpp
}

namespace pan::mem {

// ---- bytes expressions and their widths ------------------------------------------

// v is a bytes expression: an op of Sort::Bytes (SIZED DATA ARR MEM
// CALLDATA_BYTES CODE_BYTES EXTCODE_BYTES RETURNDATA_BYTES SBYTES SALL), a
// BYTES node, None. (A word - anything else - is not: it needs a SIZED.)
bool is_bytes(Value v) noexcept;

// The bytes b is (python width_of, in bytes): SIZED(n, _) n, DATA the sum of
// its elements', MEM / ..._BYTES their length, a BYTES node its size, None 0,
// an int past 2^256 its minimal big-endian bytes (a long constant); an int
// Value or an expression (alg::add of the parts). nullopt when not known:
// ARR (its ABI encoding goes in two places of a DATA), SBYTES, SALL, a DATA
// of one of them, and a word (not bytes: its width is where it's written).
std::optional<Value> width_of(Value b);
// width_of when it is a small int >= 0
std::optional<u64> width_u64(Value b);

// v as n bytes (n an int or an expression >= 0), what a SETMEM of n bytes
// writes and what SIZED(n, v) is (python with_width / resize_bytes): v
// itself when it is bytes of n bytes for sure; nested SIZED folded
// (SIZED(n, SIZED(m, x)) is SIZED(n, x) when that's the same bytes: n <= m,
// or m >= 32 for a word x; else x's low m bytes masked); a DATA of known
// widths resized by its parts (zeroes before, or its last n bytes, cut
// where they fall: slice); else SIZED(n, v).
Value sized(Value n, Value v);
inline Value sized(i64 n, Value v) { return sized(Value::small(n), v); }

// new_elem, worth what old_elem is (a rewrite of a byte element), as wide
// as old_elem is (python keep_width): new_elem when it is bytes (it says its
// width) or old_elem's width is not known; a word new_elem as SIZED(width
// of old_elem, new_elem). old_elem itself when new_elem can't be made that
// wide (old_elem's width unknown and new_elem a word).
Value keep_width(Value old_elem, Value new_elem);

// The width a word element would be printed with if its SIZED were left
// out (python sizeof, for the printer's fix_widths - lot 10 - and the
// reparsed text's interpreter): MASK_SHL(size, off, shl, _) with concrete
// fields (size + off + shl) / 8, STORAGE(size, ...) / ST(size, ...) size / 8,
// an int past 2^256 its bytes, any other word 32. nullopt when that isn't a
// whole number of bytes in (0, 32] (a bytes expression: nullopt too).
// Display only: never a width for the IR.
std::optional<u32> implicit_width(Value word) noexcept;

// The concatenation of parts as one bytes expression (python data_elements
// and simplify's data rules): nested DATA flattened, parts of no bytes
// dropped (SIZED(0, _), MEM of length 0, None...), contiguous parts merged
// (MEM(RANGE(a, n)) MEM(RANGE(a + n, m)) is MEM(RANGE(a, n + m)), the same
// for CALLDATA_BYTES CODE_BYTES RETURNDATA_BYTES EXTCODE_BYTES; adjacent
// bytes of one word, SIZED(k, mask(8k, 8j, -8j, x)) SIZED(j, mask(8j, 0, 0,
// x)), are SIZED(k + j, mask(8(k + j), 0, 0, x)); adjacent constants of 32
// bytes at most together one SIZED constant). One part: that part; none:
// DATA().
Value concat(std::span<const Value> parts);

// A bytes expression of 32 bytes at most as the word it is read as (its
// big-endian number; python's reads of mem as words): SIZED(n, x) of a
// word x: x's low n bytes (alg::mask; x when n >= 32); DATA of known
// widths: the OR of its parts moved to their places; MEM / RETURNDATA_BYTES
// / CODE_BYTES / EXTCODE_BYTES of 32 bytes at most: itself (a word read);
// CALLDATA_BYTES(p, n): CALLDATALOAD(p) masked to its first n bytes; a
// BYTES node: its int. nullopt when its width isn't a known int <= 32 or a
// part can't be a word (ARR, SALL...).
std::optional<Value> as_word(Value b);

// The bytes [lo, hi) of the bytes expression b (0 <= lo <= hi <= width:
// the caller's; lo, hi ints or expressions) as a bytes expression of hi - lo
// bytes (python slice_exp): SIZED(n, x) of a word x: its bytes there as
// SIZED(hi - lo, alg::mask(...)) (n, lo, hi known ints); MEM / CALLDATA_BYTES
// / CODE_BYTES / RETURNDATA_BYTES / EXTCODE_BYTES: the same source moved
// (any lo, hi); DATA: the parts there (cut where decided); a BYTES node or a
// long constant: the bytes (known lo, hi). b itself for all of it (lo = 0,
// hi = its width). nullopt when it can't be said (ARR, SALL, SBYTES but all
// of them; a cut that isn't decided).
std::optional<Value> slice(Value b, Value lo, Value hi, const alg::Facts* facts = nullptr);

// The operands of a line or an expression that are byte elements (python
// byte_elements): SHA3 and DATA all of them, ARR all but the first (its
// length), RETURN REVERT LOG0..4 the first (the data; None for none), CALL
// CALLCODE 4 and 5 (selector, params), DELEGATECALL STATICCALL 3 and 4,
// CREATE CREATE2 2 (the code), PRECOMPILED 3 (its input), REQUIRE 1 (the
// revert data). Not a SETMEM's value: it is as wide as its range. Empty for
// anything else; positions within v's operands only.
std::span<const u8> byte_operands(Value v) noexcept;

// ---- ranges ------------------------------------------------------------------------

// RANGE(start, len)
Value make_range(Value start, Value len);
// a RANGE(start, len) node
inline bool is_range(Value r) noexcept { return r.is(Op::RANGE, 2); }
// start + len (alg::add)
Value range_end(Value r);

// The ranges share a byte: True for sure, False never (one of them empty,
// or one ends before the other starts), None when it depends (python
// range_overlaps' "may overlap" is `!= Tri::False`).
Tri overlaps(Value r1, Value r2, const alg::Facts* facts = nullptr);
// Every byte of inner is a byte of outer (python range_contains): True for
// sure (inner empty, or within outer), False when a byte of inner is outside
// outer for sure, None when it depends.
Tri contains(Value outer, Value inner, const alg::Facts* facts = nullptr);
// What a write over `write` does to a read of `read`: True when it writes
// every byte of the read (it covers it), False when it writes none of them
// (disjoint; a read of no bytes), None when some or when it depends.
Tri overwrites(Value write, Value read, const alg::Facts* facts = nullptr);
// The parts of read the write may leave as they were (python
// memloc_overwrite): ranges whose bytes hold every byte of read the write
// doesn't overwrite for sure - the read itself when that isn't decided,
// nothing when it's covered, the part before and the part after the write
// when they're decided (those of no bytes left out).
SmallVec<Value, 2> survivors(Value read, Value write, const alg::Facts* facts = nullptr);

// ---- reads from the writes before them -------------------------------------------

// A write of memory: SETMEM(range, value) (value: a word, its low len bytes;
// bytes, len of them). range NIL: it may write anywhere; value NIL: what it
// writes there isn't known (a loop's writes, a summary's ranges).
struct MemWrite {
    Value range;
    Value value;
};
// a SETMEM line as a MemWrite; anything else {NIL, NIL}
MemWrite as_write(Value setmem_line);

// What's known of the memory at a point of a trace, going forward (python
// replace_mem / splits_mem / _mem_use, as a state): pieces (range, value),
// each range's bytes being its value's - value a bytes expression of its
// range's length, evaluated at this point -, provably disjoint. A write cuts
// or drops the pieces it may change, drops those whose range or value
// reads memory it may change, then adds itself when its value and range
// can stand for its bytes later (no memory it changes read, no msize). A
// read (MEM(range) here) is assembled from the pieces it meets for sure
// (their slices) and MEM parts for the rest - MEM read where the read is is
// always right: an undecided piece only makes the answer less precise.
// fresh: the memory is zeroes where nothing was written (a call's start):
// what no write may have touched reads as zeroes (MAX_ZEROES_SIZE at once).
// Its containers are on the current context's budget.
class MemState {
public:
    struct Piece {
        Value range;  // RANGE(start, len)
        Value value;  // bytes, len of them (width_of): as sized(len, written value)
    };

    explicit MemState(bool fresh = false, const alg::Facts* facts = nullptr);

    // the path facts the comparisons use (may be null)
    void set_facts(const alg::Facts* facts) noexcept { facts_ = facts; }
    const alg::Facts* facts() const noexcept { return facts_; }

    // a SETMEM's write; range NIL: anywhere (everything forgotten, fresh
    // off); value NIL: unknown bytes there
    void write(Value range, Value value);
    void write(const MemWrite& w) { write(w.range, w.value); }
    // nothing known (fresh off)
    void clear() noexcept;
    // the pieces whose range or value has one of these content flags
    // (F_STORAGE before a store, F_STATE before a call...) forgotten
    void forget_flags(u8 content_flags);
    // the pieces whose range or value mentions this name (a variable set
    // again) forgotten
    void forget_name(Value name);

    // MEM(range) here, from what's known: a bytes expression of range's
    // length (concat of slices of pieces, zeroes of fresh memory, MEM parts);
    // nullopt when nothing is known of it (it stays MEM(range))
    std::optional<Value> read(Value range) const;
    // the same as a word (as_word; 32 bytes at most); nullopt when unknown
    // or not a word
    std::optional<Value> read_word(Value range) const;

    // where two paths meet: the pieces both have (the same range and value),
    // fresh when both are, the written ranges of both
    void meet(const MemState& other);

    std::span<const Piece> pieces() const noexcept { return {pieces_.data(), pieces_.size()}; }
    bool fresh() const noexcept { return fresh_; }

private:
    const alg::Facts* facts_ = nullptr;
    bool fresh_ = false;
    std::pmr::vector<Piece> pieces_;
    std::pmr::vector<Value> written_;  // fresh: every range written since the start
};

// MEM(read_range) after the writes, in order (the oldest first; nothing
// else writes memory between them and the read): MemState's read after
// them. nullopt: none of them is known to write any byte of it.
std::optional<Value> fill(Value read_range, std::span<const MemWrite> writes, const alg::Facts* facts = nullptr);

// ---- splits of a write of fields ---------------------------------------------------

// A field of a word: its bits [off, off + size), value the field moved to
// bit 0 (a word below 2^size); zeroes are fields of value 0.
struct Field {
    u32 size, off;
    Value value;
};
// The word as its fields, disjoint, by offset, covering [0, 256) (python
// split_or): the terms of an OR (or one term) that are masks (MASK_SHL with
// concrete fields, a multiple x * 2^k), constants (their byte-rounded span),
// truth values and narrow reads (STORAGE(size, off >= 0, _)) at bit 0;
// zeroes between them; a field followed by zeroes it fits in grown to them.
// nullopt when it isn't such an OR (a term that may have any bit, terms
// whose bits overlap).
std::optional<SmallVec<Field, 8>> split_word(Value word);

// A SETMEM(RANGE(p, n), SIZED(n, v)) (n a known int <= 32) of a v made of
// fields as the SETMEMs of its whole bytes, one per run of bytes a field (or
// fields sharing a byte) is in, zeroes included (python split_setmem): in an
// order where none reads memory one before it wrote (python in_order), else
// not split. {line} when it isn't split.
SmallVec<Value, 4> split_setmem(Value line);

// A STORE(256, 0, slot, v) of a whole slot as the STOREs of its fields
// (python split_store): the field of a byte computed at runtime
// (byte_field_store); a mask of the slot itself (the bits outside it
// zeroed); an OR of fields, the bits the slot keeps not written, zeroes
// merged up to whole bytes (merge_zeros); in an order where none reads
// what one before it wrote. {line} when it isn't split.
SmallVec<Value, 4> split_store(Value line);
// The compiler's store of a field at a byte computed at runtime (an element
// of a packed array: stor[idx] = v * 256^k | ~(mask * 256^k) & stor[idx]):
// STORE(size, 8 * k, idx, v); nullopt when the line isn't that.
std::optional<Value> byte_field_store(Value line);

}  // namespace pan::mem
