// The signature database: the names and parameters of the functions, events
// and errors by selector (python's utils/supplement.py, the asm's sigdb.s).
//
// The source is panoramix's data/abi_dump.xz, one JSON object per line:
//     {"selector": "0xa9059cbb", "abi": {"name": "transfer", "type": "function",
//      "inputs": [{"name": "to", "type": "address"}, ...], ...}}
// It is parsed once (Ragel: sigdb_dump.rl, the types by sigdb_type.rl) into
// a file of our own format, mmap-ed afterwards and read in place. Python
// knows a selector where the dump's last line with that selector has a
// signature that hashes to it (fetch_sig/hashes_to): a quarter of the dump is
// what decompilers guessed - unknown12345678(uint64 _param1) - not
// signatures. Here every selector of the dump has its entry, its best line,
// its Trust told: verified, repaired (a variant of its signature hashes),
// unverified. The checks are made when the file is built.
//
// Everything here reads the file without copying it: the views (Entry, Type,
// Field...) point into the mapping and live as long as their Database. The
// names are raw bytes from a file anybody may have made (the cache directory,
// PANORAMIX_SIGDB, any dump): escape them when printing.
//
// The file (version 2, little-endian; see sigdb.cpp for the details):
//   header   136 bytes: "PANSIGDB", the version, the sizes and offsets of
//            the sections, the dump's SHA-256 (the cache key), size, mtime
//            and path
//   buckets  u32[2^B + 1]: bucket b (the selector's top B bits) is
//            index[buckets[b] .. buckets[b+1])
//   index    {u32 selector, u32 record offset} by selector
//   records  per entry: kind and trust, [an event's topic0], name, the
//            parameters' count, [an event's indexed flags], the parameters
//            (their names as references to the strings, their types as
//            codes, see Type), [the dump's texts of the types not repaired
//            to the letter]
//   strings  the parameters' names, the named types, the texts (varint
//            length, bytes)
// A lookup: the bucket (one cache line), its few index entries (one or
// two), the record (one or two).
#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <iterator>
#include <memory>
#include <optional>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>

#include "sha256.hpp"

namespace pan::sigdb {

// --- the ABI types ---------------------------------------------------------------

// A type's code is a prefix encoding, one byte for the elementary types:
//   0x00..0x1f  uint<8(k+1)>      k = code & 31 (uint8 .. uint256)
//   0x20..0x3f  int<8(k+1)>
//   0x40..0x5f  bytes<k+1>        (bytes1 .. bytes32)
//   0x60 address, 0x61 bool, 0x62 string, 0x63 bytes, 0x64 function
//   0x65 fixed<M>x<N>, 0x66 ufixed<M>x<N>: then a byte M/8 - 1, a byte N
//   0x67 T[]                      then T
//   0x68 T[k]                     then k (varint), then T
//   0x69 a tuple                  then n (varint), then n fields: the
//                                 name (a string reference, varint), T
//   0x6a T storage, 0x6b T memory, 0x6c T calldata: then T
//   0x6d a named type             then its text (a string reference)
// (varint: LEB128, 7 bits a byte, the low ones first.) Whatever text the
// dump has is kept: a type whose text isn't one of these exactly (uint,
// tupleX, uint7, "") is a named type of that text, so that the text of a
// code is always the dump's (python's canonical_type).
enum class TypeKind : std::uint8_t {
    uintN,         // bits(): 8 .. 256
    intN,          // bits(): 8 .. 256
    bytesN,        // size(): 1 .. 32
    address,
    boolean,
    string,
    bytes,
    function,      // an address and a selector: 24 bytes
    fixed,         // fixed<bits()>x<decimals()>
    ufixed,
    array,         // element()[]
    static_array,  // element()[length()]
    tuple,         // fields()
    storage,       // "element() storage": a library's reference to storage (a slot)
    memory,        // "element() memory"
    calldata,      // "element() calldata"
    named,         // a type known by its name only (name()): a contract (IERC20), an
                   // enum or a struct of a library's signature (Lib.Data), or text
                   // that isn't a type
};

class Fields;

class Type {
public:
    TypeKind kind() const noexcept;
    unsigned bits() const noexcept;          // uintN, intN, fixed, ufixed (bytesN: 8 size())
    unsigned size() const noexcept;          // bytesN
    unsigned decimals() const noexcept;      // fixed, ufixed
    std::uint64_t length() const noexcept;   // static_array
    Type element() const noexcept;           // array, static_array, storage, memory, calldata
    Fields fields() const noexcept;          // tuple
    std::string_view name() const noexcept;  // named
    // The ABI's: encoded as an offset in the head (string, bytes, T[], and
    // what holds one). A reference to storage, a named type: one word.
    bool dynamic() const noexcept;
    // The type as in a signature: a tuple as its components' types in
    // parentheses (python's canonical_type).
    std::string text() const;
    void append_text(std::string& out) const;
    // The code itself (its bytes).
    std::span<const std::uint8_t> code() const noexcept;

private:
    friend class Field;
    friend class Database;
    friend class Entry;
    Type(const std::uint8_t* p, const std::uint8_t* strings) noexcept : p_(p), strings_(strings) {}
    const std::uint8_t* p_;
    const std::uint8_t* strings_;
};

// A parameter, or a field of a tuple: its name (empty when the dump has
// none: python calls it _param<i + 1>) and its type.
class Field {
public:
    std::string_view name() const noexcept;
    Type type() const noexcept;

private:
    friend class Fields;
    friend class Database;
    Field(const std::uint8_t* p, const std::uint8_t* strings) noexcept : p_(p), strings_(strings) {}
    const std::uint8_t* p_;
    const std::uint8_t* strings_;
};

// The parameters of an entry, the fields of a tuple: a forward range.
class Fields {
public:
    class iterator {
    public:
        using iterator_category = std::forward_iterator_tag;
        using value_type = Field;
        using difference_type = std::ptrdiff_t;
        iterator() = default;
        Field operator*() const noexcept { return Field(p_, strings_); }
        iterator& operator++() noexcept;
        iterator operator++(int) noexcept
        {
            iterator t = *this;
            ++*this;
            return t;
        }
        bool operator==(const iterator& o) const noexcept { return left_ == o.left_; }

    private:
        friend class Fields;
        iterator(const std::uint8_t* p, const std::uint8_t* strings, std::size_t left) noexcept
            : p_(p), strings_(strings), left_(left)
        {
        }
        const std::uint8_t* p_ = nullptr;
        const std::uint8_t* strings_ = nullptr;
        std::size_t left_ = 0;
    };

    std::size_t size() const noexcept { return size_; }
    bool empty() const noexcept { return size_ == 0; }
    iterator begin() const noexcept { return iterator(p_, strings_, size_); }
    iterator end() const noexcept { return iterator(nullptr, nullptr, 0); }
    Field operator[](std::size_t i) const noexcept;  // (walks the i before it)

private:
    friend class Type;
    friend class Entry;
    Fields(const std::uint8_t* p, const std::uint8_t* strings, std::size_t n) noexcept
        : p_(p), strings_(strings), size_(n)
    {
    }
    const std::uint8_t* p_;
    const std::uint8_t* strings_;
    std::size_t size_;
};

// --- the entries -----------------------------------------------------------------

// How sure an entry is: its signature hashes to its selector (python's
// fetch_sig: the only ones python knows), a variant of it does (repaired:
// IERC20 written for an address, an enum for uint8, Address, uint256 amount,
// tuple(...), bytes memory...: its codes are the variant's, its texts the
// dump's - written_type), or none does (unverified: what the dump says, read
// the same way, kept for want of better - in panoramix's dump, its own
// guesses: unknown12345678(uint256 _param1)). A selector's entry is its best:
// verified, else repaired, else unverified; among equals, its last line.
enum class Trust : std::uint8_t { verified, repaired, unverified };

// The abi's "type" (python only tells events from the rest).
enum class Kind : std::uint8_t {
    unspecified,  // no "type" (a third of the dump: functions)
    function,
    event,
    error,
    constructor,
    fallback,
    receive,
    other,
};

class Entry {
public:
    std::uint32_t selector() const noexcept { return selector_; }
    Kind kind() const noexcept;
    Trust trust() const noexcept;
    // A name to use: its signature, or a variant of it, hashes to the
    // selector (verified or repaired; python knows the verified ones only,
    // which are all of panoramix's dump). Unverified: a guess, never shown.
    bool known() const noexcept { return trust() != Trust::unverified; }
    // The name, raw bytes as in the dump.
    std::string_view name() const noexcept;
    // The inputs.
    Fields params() const noexcept;
    // Input i's type as the dump writes it, where that isn't its code's text
    // (a repaired entry: IERC20 where the code says address; an unverified
    // one: panoramix's "array", a uint256[]); empty otherwise. For printing:
    // the code is what to decode with.
    std::string_view written_type(std::size_t i) const noexcept;
    // An event's input i is indexed (a topic).
    bool indexed(std::size_t i) const noexcept;
    // An event's topic0: the keccak of its signature (zeros for the rest,
    // and for an unverified event).
    std::span<const std::uint8_t, 32> topic() const noexcept;
    // The selector is the hash of the signature without its spaces (a
    // library of an old compiler: getMin(uint32[]storage)).
    bool hashed_without_spaces() const noexcept;
    // name(type,type...): the signature of the codes - what hashes to the
    // selector (not an unverified entry's).
    std::string signature() const;

private:
    friend class Database;
    Entry(std::uint32_t selector, const std::uint8_t* record, const std::uint8_t* strings) noexcept
        : selector_(selector), record_(record), strings_(strings)
    {
    }
    std::uint32_t selector_;
    const std::uint8_t* record_;
    const std::uint8_t* strings_;
};

// --- the database -----------------------------------------------------------------

// Can't open, read, build or write a database, or the dump isn't one.
class Error : public std::runtime_error {
public:
    // python's build_signature_db failure codes (the asm's sigdb_build):
    // 1 can't read, decompress or write, or a line isn't the JSON expected;
    // -1 the dump goes past the limits (nesting, a line's length, 4 GiB of
    // strings or records)
    enum class Code : int { failed = 1, bad_dump = -1 };
    Error(Code code, const std::string& what) : std::runtime_error(what), code_(code) {}
    Code code() const noexcept { return code_; }

private:
    Code code_;
};

class Mapping;  // the platform's read-only mapping of a file (sigdb_posix.cpp)

class Database {
public:
    // Maps a database file. Throws Error when it can't be read or isn't a
    // database of this format (a file cut short included).
    static std::unique_ptr<Database> open(const std::filesystem::path& file);
    ~Database();
    Database(const Database&) = delete;
    Database& operator=(const Database&) = delete;

    // The entry of a selector (a function, an error... or an event: the
    // dump's entries are by 4 bytes, events by their topic's first ones), or
    // nothing. Python's fetch_sig is the entry where its trust() is verified
    // (python knowing none, though, when a later line of the selector isn't
    // verified); a repaired or unverified entry is for want of one.
    std::optional<Entry> function(std::uint32_t selector) const noexcept;
    // python's event_abi: the event whose topic0 this is (verified or
    // repaired), or nothing.
    std::optional<Entry> event(std::span<const std::uint8_t, 32> topic) const noexcept;

    std::size_t size() const noexcept { return count_; }
    // The i-th entry by selector (i < size()), or nothing when the file is
    // damaged there.
    std::optional<Entry> at(std::size_t i) const noexcept;
    // The dump it was built from: its SHA-256, size, mtime (ns), path.
    const sha256::Digest& dump_sha256() const noexcept { return dump_sha256_; }
    std::uint64_t dump_size() const noexcept { return dump_size_; }
    std::int64_t dump_mtime() const noexcept { return dump_mtime_; }
    std::filesystem::path dump_path() const;
    std::size_t file_size() const noexcept;

private:
    explicit Database(std::unique_ptr<Mapping> map);
    std::optional<Entry> entry_at(std::size_t i) const noexcept;

    std::unique_ptr<Mapping> map_;
    const std::uint8_t* buckets_ = nullptr;
    const std::uint8_t* index_ = nullptr;
    const std::uint8_t* records_ = nullptr;
    const std::uint8_t* strings_ = nullptr;
    std::uint64_t records_size_ = 0, strings_size_ = 0;
    std::size_t count_ = 0;
    unsigned bucket_bits_ = 0;
    sha256::Digest dump_sha256_{};
    std::uint64_t dump_size_ = 0;
    std::int64_t dump_mtime_ = 0;
    std::uint32_t dump_path_ = 0;
};

// Where the database is: $PANORAMIX_SIGDB, else
// $XDG_CACHE_HOME/panoramix/sigdb2.bin, else ~/.cache/panoramix/sigdb2.bin
// (python's cache_dir, the asm's file name with the format's version).
std::filesystem::path default_path();

// The process's database (python's check_supplements, the asm's
// sigdb_load): default_path(), mapped once, by the first caller (the others
// wait). It is built again first when the dump it was built from changed -
// $PANORAMIX_ABI_DUMP's, else the one it names: its size and mtime, then its
// SHA-256 - and built when there is none, or not one of this format, and
// $PANORAMIX_ABI_DUMP names a dump. nullptr when there is none: every
// selector is unknown then (logged once).
const Database* get() noexcept;

struct BuildStats {
    std::uint64_t lines = 0;    // of the dump
    std::uint64_t entries = 0;  // in the database (a selector each)
    std::uint64_t verified = 0, repaired = 0, unverified = 0;  // (of entries)
    std::uint64_t events = 0;
    std::uint64_t file_size = 0;  // bytes
};

// The database file made from a dump (panoramix's abi_dump.xz: xz or lzma,
// one JSON object per line); out empty: default_path(). Written next to its
// place and renamed there once complete. Throws Error.
BuildStats build(const std::filesystem::path& dump, const std::filesystem::path& out = {});

// The messages of this module: python's logging levels (10 debug, 20 info,
// 30 warning, 40 error), the logger "panoramix.sigdb". None by default.
using LogSink = void (*)(int level, std::string_view logger, std::string_view message);
void set_log_sink(LogSink sink) noexcept;

}  // namespace pan::sigdb

namespace pan {
// The front-ends' build-db (the CLI's `build-db`, the module's
// build_signature_db): build(), its messages logged; 0 built, 1 failed, -1
// the dump isn't one it can read. out_path empty: the default path.
int build_signature_db(const std::string& dump_path, const std::string& out_path);
}  // namespace pan
