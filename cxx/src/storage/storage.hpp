// The storage of a contract (lot 9; python storage.py, runtrace.py; asm
// storage.s, storage_vars.s, storage_check.s, storage_getter.s): what its
// variables are, from every access of its functions - STORAGE(size, off,
// slot) read, STORE(size, off, slot, value) written - each at a path from a
// variable (its slot, an element of a mapping or of an array, a member of a
// struct...); their types (from the most of their accesses), their names
// (from the getters); then every access rewritten as its path, the form the
// printer prints (name[key], name[i].field_N, name.length) - checked: the
// form must denote the slot and bits the access reads, else it is printed
// raw (stor[slot]), which always does.
//
// ---- The forms (spec/ops.def 0x160-0x16b, 0x183; ir.md 1.4, 4.3) ----------------
//
// A location (loc) is one of
//   SV(Name(STORVAR, i))  the variable vars[i]: (vars[i].slot, vars[i].off)
//   SI(base, key)         base[key], by the TYPE of base (locate below)
//   SL(base)              base.length: an array's length, the word at base's slot
//   SBL(base)             base.length: a bytes/string's length, DECODED from the
//                         word at base's slot (solidity: s odd -> s >> 1, even ->
//                         (s & 0xff) >> 1)
//   SF(base, n)           base.field_n: the bits from bit n of base on (n a small
//                         int): slot(base) + (bit(base) + n) // 256, bit (bit(base)
//                         + n) % 256 (floor division: n may be negative)
//   SR(slot)              stor[slot]: the word at the slot (an expression)
// and the reads and writes are
//   ST(size, loc, width)  the `size` bits (a small int, 0..256) at the place
//                         of loc: (word >> bit) & (2^size - 1), word = the
//                         slot's (SBL: the decoded length). width (a small int
//                         or None) is the printer's: how wide what is at loc is
//                         (size < width: a cast); no meaning in the semantics.
//   SET(ST(size, loc, width), v)   a line: the bits [bit, bit + size) of the
//                         slot (those under 256) set to the low bits of v, the
//                         others kept (read-modify-write; SBL: a bug)
//   SALL(loc)             a bytes expression: the bytes/string at loc's slot
//                         as solidity's copy to the memory reads it, whatever
//                         the slot holds: len = its length as SBL decodes it;
//                         short or long by the length (not by the low bit):
//                         below 32 the slot word's len high bytes, else len
//                         bytes of the words from keccak(slot) on - in a
//                         getter's ARR(len, SALL(loc)), zero padded: the ABI
//                         encoding it returns
// SV SI SL SBL SF SR are never words: only inside ST, SET's target, SALL, and
// as the base of another loc.
//
// After this stage a function's trace has no STORAGE / STORE / LENGTH /
// LOC / SBYTES left: every access is one of these forms (an access that
// can't be printed as its path: the raw forms, SR-based, below).
#pragma once

#include <memory>
#include <optional>
#include <span>
#include <vector>

#include "core/base.hpp"
#include "core/contract.hpp"
#include "core/evmint.hpp"
#include "core/value.hpp"

namespace pan {

// What is at a location (python storage.py's types): a node of the layout's
// type table, StorageLayout::types[i].
struct StorageType {
    enum class Kind : u8 {
        Value,    // a number of `width` bits at the bit 0 of the place
        Struct,   // words read by their bits (.field_N), over `slots` slots
        Mapping,  // elem at keccak(key . slot) - Vyper: keccak(slot . key); a word key
                  // as its 32 bytes, a bytes key (a DATA: a string's) as its bytes
        Array,    // a dynamic array: its length at the slot, element i at
                  // keccak(slot) + i * stride - or packed (packed_width): w bits
                  // each, 256 / w per slot
        Fixed,    // a fixed array: element i at slot + i * stride, or packed
        Bytes,    // a bytes/string: its word at the slot (solidity: short /
                  // long), its data words at keccak(slot) + i (SI's key: i)
    };
    Kind kind = Kind::Value;
    u16 width = 256;             // Value: its bits, 1..256 (160: an address)
    std::optional<u64> slots;    // Struct: the slots it spans (none: not known)
    u32 elem = 0;                // Mapping, Array, Fixed: the element's type (an index of types)
    u64 stride = 1;              // Array, Fixed: the slots of an element (1 when packed)
    std::optional<u64> length;   // Fixed: its length, when the code checks its indexes
                                 // against one (python fixed_lengths: printed uint8[N])

    bool operator==(const StorageType&) const = default;
};

// A variable of the contract: a root slot, or a field of a slot whose bits
// hold several (packed: `uint8 a; address b;` in one slot).
struct StorageVar {
    Word256 slot{};  // its slot (any word: EIP-1967's hashes are)
    u16 off = 0;     // its first bit in the slot (0..255): a field of a packed slot
    u32 type = 0;    // its type (an index of StorageLayout::types); a field is a Value
    // Its name (text: lot 10's only):
    //  - getter set: the name of that function's signature (the signature
    //    database's entry of the selector, verified), python's
    //    f.name.split("(")[0] - without its "get" when strip_get (getBalance ->
    //    balance: the 4th character lowercased, the 3 first dropped);
    //  - else python's default: stor<slot> (slot < 2^32, decimal), else
    //    "stor" + the first 4 hex digits of the slot, uppercase (storA66D);
    //    a field at off > 0: + "_<off>" (stor0_160).
    // Names may collide (two getters of one name, a getter named like a
    // default): python's unique() is the printer's - the vars in this order,
    // a name already taken + "_<slot>" (slot < 2^32 decimal, else its first 8
    // hex digits), then "_2", "_3"... while taken.
    std::optional<u32> getter;
    bool strip_get = false;

    bool operator==(const StorageVar&) const = default;
};

// The contract's storage: what the forms SV and SI refer to - lot 11's
// machine computes the slots from it (storage::locate), lot 10 prints the
// `def storage:` block (python's header: one line per var, in this order)
// and the names. Immutable once made (shared between the stages' results).
struct StorageLayout {
    Lang lang = Lang::Solidity;    // Solidity or Vyper (the mapping hash order); never Unknown
    std::vector<StorageType> types;
    std::vector<StorageVar> vars;  // Name(STORVAR, i) is vars[i]; sorted by (slot, off), distinct

    // a packed element's width (python elem_width): a Value type of w bits,
    // 8 <= w < 256, w dividing 256 -> w; anything else 256 (not packed)
    u16 packed_width(u32 type) const noexcept;
};

namespace storage {

// ---- the analysis --------------------------------------------------------------------

struct Options {
    i64 deadline_ns = 0;        // monotonic (0: none): Timeout past it, checked as it goes
    bool bytes_getters = true;  // python bytes_getter: the getters of a bytes/string run and rewritten
};

// The storage analysis of a contract (python rewrite_functions; lot 12's
// contract phase, Stage::Analysed): every function's and internal
// function's trace (those with a problem or no trace skipped) rewritten in
// place to the forms above, and the layout they refer to. On cx(); every
// trace is made aside first and swapped in at the end: an exception
// (Error, Timeout...) leaves every trace as it was. The language: shared.lang
// (the metadata's), else the vote of the mapping hashes (python language()).
std::shared_ptr<const StorageLayout> analyse(std::span<FunctionInfo> functions, std::span<FunctionInfo> internals,
                                             const ContractShared& shared, const Options& opts = {});

// python rewrite_raw (the analysis failed: "Storage postprocessing failed.
// This is very bad!"): every access as the slot it is - ST(size, SR(slot), 256)
// and the like - with a layout of no variable (lang only). In place, made
// aside first as analyse.
std::shared_ptr<const StorageLayout> rewrite_raw(std::span<FunctionInfo> functions, std::span<FunctionInfo> internals,
                                                 Lang lang);

// ---- the semantics of the forms on concrete values -------------------------------------
// (the trace machine's, and the analysis' own check: one definition)

// What locate needs of its caller: the word and the bytes of an expression
// (the machine's ev / evb; the check's random worlds).
class Eval {
public:
    virtual Word256 word(Value e) = 0;
    // e's bytes appended (a bytes expression: DATA, SIZED, MEM... - a mapping's bytes key)
    virtual void bytes(Value e, std::vector<u8>& out) = 0;

protected:
    ~Eval() = default;
};

// The place a location form is at.
struct Place {
    Word256 slot{};
    u32 bit = 0;                // 0..255
    bool length = false;        // SBL: the decoded bytes length of the slot is read there
    std::optional<u32> type;    // what is at it (SV, SI: a type of the layout); none:
                                // SR, SF, SL, SBL (no SI over them)
};

// The place of loc (SV SI SL SBL SF SR) - InternalError when it isn't one
// the layout has (the machine's Status::Bug): a STORVAR past vars, an SI
// over a place of no type or of a Value/Struct, anything else than a
// location. Eval's own exceptions go through.
//   SI(base, key) by base's type (base's bit ignored):
//     Mapping: keccak(K ++ w32(slot)) (Vyper: w32(slot) ++ K), K = bytes(key)
//              when key is a bytes expression, else w32(word(key)); type elem
//     Bytes:   keccak(w32(slot)) + word(key); no type
//     Array:   start = keccak(w32(slot)); Fixed: start = slot; i = word(key);
//              packed (w = packed_width(elem) < 256, per = 256 / w): start + i / per,
//              bit w * (i % per); else start + i * stride, bit 0; type elem
// (all mod 2^256)
Place locate(const StorageLayout& layout, Value loc, Eval& eval);

// solidity's length of the bytes at a slot from its word s: s odd -> s >> 1,
// else (s & 0xff) >> 1 (SBL)
Word256 bytes_length(const Word256& word) noexcept;

// keccak-256 of a word's 32 bytes, big-endian (the data of an array, a bytes)
Word256 keccak_word(const Word256& w) noexcept;

}  // namespace storage
}  // namespace pan
