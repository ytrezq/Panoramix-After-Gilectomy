// The signature database's insides, shared by sigdb.cpp, the Ragel parsers
// (sigdb_dump.rl, sigdb_type.rl), the platform's layer (sigdb_posix.cpp, a
// sigdb_win32.cpp to come) and the tests. Not for the rest of the program:
// see sigdb.hpp.
#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <memory>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

#include "sigdb.hpp"

namespace pan::sigdb {

// --- the platform (sigdb_posix.cpp) -----------------------------------------------

// A file mapped read-only, whole (an empty file: no bytes). What can't be
// mapped (a pipe) is read into memory instead, 1 GiB at most.
class Mapping {
public:
    // Throws Error (Code::failed) when it can't be opened or read.
    static std::unique_ptr<Mapping> open(const std::filesystem::path& path);
    ~Mapping();
    Mapping(const Mapping&) = delete;
    Mapping& operator=(const Mapping&) = delete;
    std::span<const std::uint8_t> bytes() const noexcept { return {data_, size_}; }

private:
    Mapping(const std::uint8_t* data, std::size_t size) noexcept : data_(data), size_(size) {}
    const std::uint8_t* data_;
    std::size_t size_;
    std::vector<std::uint8_t> read_;  // (not mapped: read)
};

namespace platform {

// A regular file's size and modification time (ns since the epoch); nothing
// for anything else (a fifo isn't read again to see if it changed).
struct Stamp {
    std::uint64_t size = 0;
    std::int64_t mtime = 0;
};
std::optional<Stamp> stamp(const std::filesystem::path& path) noexcept;

// The absolute path without links (realpath), or nothing.
std::optional<std::filesystem::path> real_path(const std::filesystem::path& path) noexcept;

// python's cache_dir() (appdirs' user_cache_dir): $XDG_CACHE_HOME/panoramix,
// else $HOME/.cache/panoramix; empty when there is neither.
std::filesystem::path cache_dir();

// A file written next to its place (<path>.<pid>.tmp, made anew: a link
// planted there isn't followed) and renamed there once complete, so that a
// reader never sees one cut short. Its parent directories are made.
class AtomicFile {
public:
    explicit AtomicFile(const std::filesystem::path& path);  // throws Error
    ~AtomicFile();                                           // not committed: removed
    AtomicFile(const AtomicFile&) = delete;
    AtomicFile& operator=(const AtomicFile&) = delete;
    void write(std::span<const std::uint8_t> data);  // throws Error
    void commit();                                   // throws Error

private:
    void flush();
    std::filesystem::path path_, tmp_;
    int fd_ = -1;
    bool committed_ = false;
    std::vector<std::uint8_t> buffer_;
};

}  // namespace platform

// get()'s work (without the once): the database at path, built again first
// when the dump it was built from changed (dump's, when given, else the one
// it names), built when there is none (or not one of this format) and dump
// is given; nullptr when there is none (logged).
std::unique_ptr<Database> load(const std::filesystem::path& path,
                               const std::optional<std::filesystem::path>& dump);

// --- small things ------------------------------------------------------------------

void log(int level, std::string_view message);
inline constexpr int log_debug = 10, log_info = 20, log_warning = 30, log_error = 40;

// Keccak-256 (the EVM's, eth_hash's keccak): the signatures' check.
std::array<std::uint8_t, 32> keccak256(std::string_view data) noexcept;

// LEB128: 7 bits a byte, the low ones first.
inline void put_varint(std::string& out, std::uint64_t v)
{
    while (v >= 0x80) {
        out.push_back(static_cast<char>(static_cast<std::uint8_t>(v) | 0x80));
        v >>= 7;
    }
    out.push_back(static_cast<char>(v));
}
// (in a record already checked: no bounds)
inline std::uint64_t get_varint(const std::uint8_t*& p) noexcept
{
    std::uint64_t v = 0;
    for (unsigned shift = 0;; shift += 7) {
        std::uint8_t b = *p++;
        v |= std::uint64_t{b & 0x7fu} << shift;
        if (b < 0x80)
            return v;
    }
}
// (bounded: false past end, or past 64 bits)
inline bool get_varint(const std::uint8_t*& p, const std::uint8_t* end, std::uint64_t& v) noexcept
{
    v = 0;
    for (unsigned shift = 0; shift < 64; shift += 7) {
        if (p == end)
            return false;
        std::uint8_t b = *p++;
        if (shift == 63 && b > 1)
            return false;
        v |= std::uint64_t{b & 0x7fu} << shift;
        if (b < 0x80)
            return true;
    }
    return false;
}

// The codes of the types (sigdb.hpp: Type).
namespace code {
inline constexpr std::uint8_t uint_base = 0x00, int_base = 0x20, bytes_base = 0x40;
inline constexpr std::uint8_t address = 0x60, boolean = 0x61, string = 0x62, bytes = 0x63,
                              function = 0x64, fixed = 0x65, ufixed = 0x66, array = 0x67,
                              static_array = 0x68, tuple = 0x69, storage = 0x6a,
                              memory = 0x6b, calldata = 0x6c, named = 0x6d;
inline constexpr std::uint8_t last = named;
inline constexpr unsigned max_depth = 64;  // of the types' nesting
}  // namespace code

// The text of the code at p (moved past it); strings: where the string
// references point (the file's strings, or a StringPool's bytes).
void append_type_text(const std::uint8_t*& p, const std::uint8_t* strings, std::string& out);
// p moved past the code (checked: false when it goes past end, is deeper
// than code::max_depth, or refers past the strings).
bool skip_type(const std::uint8_t*& p, const std::uint8_t* end, std::uint64_t strings_size,
               unsigned depth = 0) noexcept;
// A string reference (checked).
bool check_string(std::uint64_t ref, const std::uint8_t* strings, std::uint64_t strings_size) noexcept;
inline std::string_view string_at(const std::uint8_t* strings, std::uint64_t ref) noexcept
{
    const std::uint8_t* p = strings + ref;
    std::uint64_t len = get_varint(p);
    return {reinterpret_cast<const char*>(p), static_cast<std::size_t>(len)};
}

// --- the builder ----------------------------------------------------------------------

// The strings of the file (the parameters' names, the named types, the
// dump's path): each once, its length (varint) then its bytes; a reference is
// its offset. Offset 0: the empty string.
class StringPool {
public:
    StringPool() { bytes_.push_back('\0'); }
    std::uint32_t intern(std::string_view s);  // throws Error past 4 GiB
    const std::string& bytes() const noexcept { return bytes_; }

private:
    struct Hash {
        using is_transparent = void;
        std::size_t operator()(std::string_view s) const noexcept
        {
            return std::hash<std::string_view>{}(s);
        }
    };
    std::string bytes_;
    std::unordered_map<std::string, std::uint32_t, Hash, std::equal_to<>> refs_;
};

// A parameter, or a field of a tuple, as the dump's parser leaves it.
struct RawParam {
    std::string name;           // (decoded: raw bytes)
    std::string type;           // its "type"
    std::string canonical;      // python's canonical_type(type, components)
    std::uint32_t children = 0;      // its components: the parser's arena[children ..
    std::uint32_t child_count = 0;   //   children + child_count)
    bool has_components = false;     // "components" is a list
    bool indexed = false;            // "indexed", truthy
    bool ok = true;                  // nothing python would choke on
};

// The types' parser (sigdb_type.rl): the code of a type's text appended to
// code. The text "tuple" (and its arrays, its reference) is the tuple of the
// parameter's components when it has some: tuple() appends that tuple's code.
// False when the text isn't a type this knows exactly (the caller makes it a
// named type).
class TupleSource {
public:
    virtual bool tuple(std::string& code) = 0;

protected:
    ~TupleSource() = default;
};
bool parse_type(std::string_view text, TupleSource* components, StringPool& pool,
                std::string& code);

// One line of the dump, as its parser hands it to the builder.
struct RawEntry {
    bool has_selector = false, has_abi = false;
    bool selector_ok = false;   // "0x" and 8 lowercase hex digits (python's keys)
    std::uint32_t selector = 0;
    bool ok = false;            // an object, a name, a list of inputs, all of them right
    Kind kind = Kind::unspecified;
    std::string_view name;
    std::span<const RawParam> params;
    std::span<const RawParam> arena;  // what params' children refer to
};

class EntrySink {
public:
    virtual void entry(const RawEntry& e) = 0;

protected:
    ~EntrySink() = default;
};

// The dump's parser (sigdb_dump.rl): lines of text, each one JSON object.
class DumpParser {
public:
    explicit DumpParser(EntrySink& sink);
    ~DumpParser();
    // Complete lines (the last one ended by '\n'). Throws Error (bad_dump)
    // with the line's number when one isn't the JSON expected.
    void parse(const std::uint8_t* p, const std::uint8_t* pe);
    std::uint64_t lines() const noexcept { return line_; }

private:
    struct State;
    std::unique_ptr<State> s_;
    std::uint64_t line_ = 0;
};

}  // namespace pan::sigdb
