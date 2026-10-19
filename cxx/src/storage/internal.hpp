// The storage analysis' own parts (lot 9 only): the accesses, the paths
// of their slots, the types, the forms and their check, the regrouping of
// split stores, the getters. Python storage.py's functions, by name.
#pragma once

#include <memory_resource>
#include <optional>
#include <span>
#include <vector>

#include "core/base.hpp"
#include "core/contract.hpp"
#include "core/evmint.hpp"
#include "core/memo.hpp"
#include "core/smallvec.hpp"
#include "core/value.hpp"
#include "storage/storage.hpp"

namespace pan::storage::detail {

// ---- accesses ----------------------------------------------------------------------

// STORAGE(size, off, idx) read, STORE(size, off, idx, value) written: the
// key of an access (python's (size, off, idx) tuples)
struct Access {
    Value size, off, idx;
    bool operator==(const Access&) const = default;
    Key3 key() const noexcept { return {size.raw(), off.raw(), idx.raw()}; }
};

// python find_accesses' False / "const" / True
enum class Written : u8 { No, Const, Yes };

// The accesses of traces, in the order they are found (python's dict):
// lookups by key, iteration by order (never the table's).
class Accesses {
public:
    // python find_accesses on a trace (any line, any depth)
    void find(Value trace);
    usize size() const noexcept { return list_.size(); }
    const Access& operator[](usize i) const noexcept { return list_[i]; }
    Written written(usize i) const noexcept { return written_[i]; }
    std::optional<usize> index(const Access& a) const noexcept {
        if (const u32* k = map_.find(a.key())) return *k - 1;
        return std::nullopt;
    }
    bool contains(const Access& a) const noexcept { return map_.find(a.key()) != nullptr; }
    void add(const Access& a, Written w);

private:
    void walk(Value v, Memo<Value, u8>& seen);
    std::vector<Access> list_;
    std::vector<Written> written_;
    Memo<Key3, u32> map_;  // key -> index + 1
};

// the bytes expression test (python memloc.sized): SIZED DATA MEM CALLDATA_BYTES... BYTES
bool is_bytes_expr(Value v) noexcept;
// python word(): a word of a data as its value (SIZED(32, v) of a word v: v)
Value word(Value e);
// python is_word(): e, as an element of a data, is a word (SIZED(32, v) of a word v)
bool is_word(Value e);
// python from_calldata(): a param, a calldata word, or masks of one
bool from_calldata(Value e);

// ---- the paths of the slots --------------------------------------------------------

struct Step {
    enum class Kind : u8 { Map, Data, Off, Blen };
    Kind kind = Kind::Off;
    Value e;                 // Map: the key (a word, or a DATA of a bytes key); Off: the offset
    bool bytes_key = false;  // Map: a bytes key (python kind "bytes")
    bool operator==(const Step&) const = default;
};
using Steps = std::vector<Step>;

// python steps(parse(idx)): the root slot and the steps from it; none: raw
struct Path {
    Word256 root{};
    Steps steps;
    bool operator==(const Path&) const = default;
};

// python hash_constant: (path, delta) when c is delta < 2^16 after a hash
// of the table (keccak(n) n < 4096, keccak(k . n) k < 16, n < 64; Vyper:
// keccak(n . k))
struct HashHit {
    u32 n = 0;
    std::optional<u32> key;  // none: keccak(n) (data); else the mapping's key
    u32 delta = 0;
};
std::optional<HashHit> hash_constant(const Word256& c, Lang lang);
// the table's entries in its order, (hash, its n and key) - the tests'
std::vector<std::pair<Word256, HashHit>> hash_table_entries(Lang lang);

// python steps(parse(idx, lang)), memoized per idx
class Parser {
public:
    explicit Parser(Lang lang) : lang_(lang) {}
    std::optional<Path> parse(Value idx);
    Lang lang() const noexcept { return lang_; }

private:
    std::optional<Path> compute(Value idx);
    Lang lang_;
    Memo<Value, u32> memo_;
    std::vector<std::optional<Path>> paths_;
};

// python linear(): e == stride * index + constant (stride 0: a constant)
struct Lin {
    Value index;    // NIL when stride is 0
    EvmInt stride;  // >= 0
    EvmInt c;
};
Lin linear(Value e);

// python packed(): the index of an element of `width` bits at slot + e,
// bits off, of an array packed 256 / width a slot; NIL if it isn't one
Value packed(Value e, Value off, Value width);

// ---- types (python's tuples: an index of the analysis' type table) ------------------

class Types {
public:
    explicit Types(std::vector<StorageType>& table) : t_(table) {}
    u32 intern(const StorageType& t);
    const StorageType& operator[](u32 i) const noexcept { return t_[i]; }
    u32 value(u16 width);
    u32 structure(std::optional<u64> slots);
    u32 bytes();
    u32 mapping(u32 elem);
    u32 array(StorageType::Kind kind, u32 elem, u64 stride);
    // python elem_width
    u16 elem_width(u32 t) const noexcept;
    std::vector<StorageType>& table() noexcept { return t_; }

private:
    std::vector<StorageType>& t_;
};

// an access of the slot class / root: (steps from the root, size, off, written)
struct RootAccess {
    Steps steps;
    Value size, off;
    Written written = Written::No;
};

// python typeof() (an Error when it can't: python's exceptions there)
u32 type_of(Types& types, std::span<const RootAccess> accs);

// python layout(): the variables (off, end) of a slot from its accesses
struct Range {
    i64 off, end;
    bool operator==(const Range&) const = default;
};
std::vector<Range> fields_layout(std::span<const RootAccess> accs);
std::vector<Range> merge_ranges(std::span<const std::pair<i64, i64>> fields);  // (size, off)

// ---- forms -------------------------------------------------------------------------

struct FormCtx {
    const Types& types;
    Lang lang;
};
// python form(base, t, st, size, off); NIL: Fail
Value form(const FormCtx& c, Value base, u32 type, std::span<const Step> st, i64 size, Value off);
// python raw(size, off, idx, write) for a read; the target of a write
// (NIL: the whole word, set with the bits around kept - python's merged)
Value raw_read(Value size, Value off, Value idx);
Value raw_target(Value size, Value off, Value idx);

// the forms' Values
Value st_form(i64 size, Value loc, std::optional<i64> width);
Value sv_form(u32 var);


// ---- small helpers -------------------------------------------------------------------

inline Value small(i64 n) { return Value::small(n); }
inline bool is_small(Value v, i64 n) { return v.is_small() && v.small_val() == n; }
// a small int's value
inline std::optional<i64> small_of(Value v) {
    if (v.is_small()) return v.small_val();
    return std::nullopt;
}

}  // namespace pan::storage::detail
