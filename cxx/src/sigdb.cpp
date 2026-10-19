// The signature database: its file (reading it, building it), the process's
// one. See sigdb.hpp; the parsers are sigdb_dump.rl and sigdb_type.rl, the
// platform's part sigdb_posix.cpp.
//
// The file, version 2 (little-endian):
//   header (136 bytes)
//     0  "PANSIGDB"
//     8  u32 the version (2)        12  u32 the header's size (136)
//    16  u64 the file's size        24  u8[32] the dump's SHA-256
//    56  u64 the dump's size        64  i64 the dump's mtime (ns)
//    72  u32 the entries (n)        76  u32 B, the bucket bits
//    80  u64 the buckets' offset    88  u64 the index's offset
//    96  u64 the records' offset   104  u64 their size
//   112  u64 the strings' offset   120  u64 their size
//   128  u32 the dump's path (a string reference, 0: none)
//   132  u32 0
//   buckets  u32[2^B + 1]: bucket b, of the selectors whose top B bits are
//            b, is index[buckets[b] .. buckets[b + 1])
//   index    n x {u32 selector, u32 its record's offset in the records},
//            by selector
//   records  by selector (one each: the verified line, else the repaired
//            one, else the unverified one; among equals the last), each:
//            u8 the kind (Kind, bits 0-2) | 8 when the selector is the hash
//               of the signature without its spaces | the Trust << 4 |
//               0x40 when the dump's texts of the types follow
//            [an event: its topic0, 32 bytes: the keccak of python's text
//             (verified), of the variant that hashed (repaired), zeros
//             (unverified)]
//            the name: its length (varint), its bytes
//            the inputs: their count n (varint)
//            [an event: the indexed ones, a bit each, (n + 7) / 8 bytes]
//            n x {the name (a string reference, varint), the type's code}
//            [0x40: n x the dump's text of the type (a string reference, 0:
//             its code's text)]
//   strings  each: its length (varint), its bytes; a reference is its
//            offset (0: the empty string)
// Each section begins at a multiple of 64 bytes. The file is checked when
// it is opened (its sections within it), and each record when it is looked
// up: the views read it unchecked afterwards.
#include "sigdb.hpp"

#include <lzma.h>

#include <algorithm>
#include <atomic>
#include <bit>
#include <condition_variable>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <exception>
#include <mutex>
#include <random>
#include <thread>
#include <utility>

#include "sigdb_impl.hpp"

namespace pan::sigdb {

static_assert(std::endian::native == std::endian::little, "the file is read in place");

namespace {

constexpr char magic[8] = {'P', 'A', 'N', 'S', 'I', 'G', 'D', 'B'};
constexpr std::uint32_t version = 2;
constexpr std::size_t header_size = 136;
constexpr std::size_t section_align = 64;
constexpr unsigned max_bucket_bits = 24;
constexpr std::uint64_t max_line = 256u << 20;  // a line of the dump, decompressed
constexpr std::uint64_t max_params = 1u << 20;  // of an entry
constexpr std::uint64_t max_xz_memory = 1u << 30;  // the decompressor's (the dump's: 64 MiB)

std::atomic<LogSink> log_sink{nullptr};

std::uint32_t load32(const std::uint8_t* p) noexcept
{
    std::uint32_t v;
    std::memcpy(&v, p, 4);
    return v;
}
std::uint64_t load64(const std::uint8_t* p) noexcept
{
    std::uint64_t v;
    std::memcpy(&v, p, 8);
    return v;
}
void store32(std::uint8_t* p, std::uint32_t v) noexcept { std::memcpy(p, &v, 4); }
void store64(std::uint8_t* p, std::uint64_t v) noexcept { std::memcpy(p, &v, 8); }

// --- Keccak-256 ---

constexpr std::array<std::uint64_t, 24> keccak_rc = {
    0x0000000000000001, 0x0000000000008082, 0x800000000000808a, 0x8000000080008000,
    0x000000000000808b, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
    0x000000000000008a, 0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
    0x000000008000808b, 0x800000000000008b, 0x8000000000008089, 0x8000000000008003,
    0x8000000000008002, 0x8000000000000080, 0x000000000000800a, 0x800000008000000a,
    0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008};
// A round of Keccak-f[1600] from a into e: theta, then rho and pi with chi
// a plane at a time (the lane x + 5y goes to y + 5 ((2x + 3y) mod 5), rotated:
// each plane's five lanes are read as they are needed), iota.
inline void keccak_round(const std::uint64_t* a, std::uint64_t* e, std::uint64_t rc) noexcept
{
    using std::rotl;
    std::uint64_t c0 = a[0] ^ a[5] ^ a[10] ^ a[15] ^ a[20];
    std::uint64_t c1 = a[1] ^ a[6] ^ a[11] ^ a[16] ^ a[21];
    std::uint64_t c2 = a[2] ^ a[7] ^ a[12] ^ a[17] ^ a[22];
    std::uint64_t c3 = a[3] ^ a[8] ^ a[13] ^ a[18] ^ a[23];
    std::uint64_t c4 = a[4] ^ a[9] ^ a[14] ^ a[19] ^ a[24];
    std::uint64_t d0 = c4 ^ rotl(c1, 1), d1 = c0 ^ rotl(c2, 1), d2 = c1 ^ rotl(c3, 1);
    std::uint64_t d3 = c2 ^ rotl(c4, 1), d4 = c3 ^ rotl(c0, 1);
    std::uint64_t b0, b1, b2, b3, b4;
    auto chi = [&](std::uint64_t* out) {
        out[0] = b0 ^ (~b1 & b2);
        out[1] = b1 ^ (~b2 & b3);
        out[2] = b2 ^ (~b3 & b4);
        out[3] = b3 ^ (~b4 & b0);
        out[4] = b4 ^ (~b0 & b1);
    };
    b0 = a[0] ^ d0, b1 = rotl(a[6] ^ d1, 44), b2 = rotl(a[12] ^ d2, 43);
    b3 = rotl(a[18] ^ d3, 21), b4 = rotl(a[24] ^ d4, 14);
    chi(e);
    e[0] ^= rc;
    b0 = rotl(a[3] ^ d3, 28), b1 = rotl(a[9] ^ d4, 20), b2 = rotl(a[10] ^ d0, 3);
    b3 = rotl(a[16] ^ d1, 45), b4 = rotl(a[22] ^ d2, 61);
    chi(e + 5);
    b0 = rotl(a[1] ^ d1, 1), b1 = rotl(a[7] ^ d2, 6), b2 = rotl(a[13] ^ d3, 25);
    b3 = rotl(a[19] ^ d4, 8), b4 = rotl(a[20] ^ d0, 18);
    chi(e + 10);
    b0 = rotl(a[4] ^ d4, 27), b1 = rotl(a[5] ^ d0, 36), b2 = rotl(a[11] ^ d1, 10);
    b3 = rotl(a[17] ^ d2, 15), b4 = rotl(a[23] ^ d3, 56);
    chi(e + 15);
    b0 = rotl(a[2] ^ d2, 62), b1 = rotl(a[8] ^ d3, 55), b2 = rotl(a[14] ^ d4, 39);
    b3 = rotl(a[15] ^ d0, 41), b4 = rotl(a[21] ^ d1, 2);
    chi(e + 20);
}

void keccak_f(std::uint64_t a[25]) noexcept
{
    std::uint64_t e[25];
    for (std::size_t i = 0; i < keccak_rc.size(); i += 2) {
        keccak_round(a, e, keccak_rc[i]);
        keccak_round(e, a, keccak_rc[i + 1]);
    }
}

}  // namespace

std::array<std::uint8_t, 32> keccak256(std::string_view data) noexcept
{
    constexpr std::size_t rate = 136;
    std::uint64_t a[25] = {};
    const auto* p = reinterpret_cast<const std::uint8_t*>(data.data());
    std::size_t n = data.size();
    for (; n >= rate; p += rate, n -= rate) {
        for (std::size_t i = 0; i < rate / 8; i++)
            a[i] ^= load64(p + 8 * i);
        keccak_f(a);
    }
    std::uint8_t last[rate] = {};
    std::memcpy(last, p, n);
    last[n] = 0x01;  // (Keccak's padding, not SHA-3's)
    last[rate - 1] |= 0x80;
    for (std::size_t i = 0; i < rate / 8; i++)
        a[i] ^= load64(last + 8 * i);
    keccak_f(a);
    std::array<std::uint8_t, 32> out;
    std::memcpy(out.data(), a, 32);
    return out;
}

void log(int level, std::string_view message)
{
    if (LogSink sink = log_sink.load(std::memory_order_acquire))
        sink(level, "panoramix.sigdb", message);
}

void set_log_sink(LogSink sink) noexcept { log_sink.store(sink, std::memory_order_release); }

// --- the types' codes ----------------------------------------------------------------

StringPool::StringPool() : slots_(std::size_t{1} << 16, 0), seed_(std::random_device{}())
{
    bytes_.push_back('\0');  // (offset 0: the empty string)
}

// (seeded: a dump made to collide can't make the build quadratic)
std::uint64_t StringPool::hash(std::string_view s) const noexcept
{
    std::uint64_t h = seed_ ^ (s.size() * 0x9e3779b97f4a7c15);
    const char* p = s.data();
    std::size_t n = s.size();
    for (; n >= 8; p += 8, n -= 8) {
        std::uint64_t v;
        std::memcpy(&v, p, 8);
        h = std::rotl((h ^ v) * 0xbf58476d1ce4e5b9, 31);
    }
    std::uint64_t v = 0;
    std::memcpy(&v, p, n);
    h = (h ^ v) * 0x94d049bb133111eb;
    h ^= h >> 29;
    h *= 0xbf58476d1ce4e5b9;
    return h ^ (h >> 32);
}

void StringPool::grow()
{
    std::vector<std::uint64_t> old(slots_.size() * 2, 0);
    old.swap(slots_);
    std::size_t mask = slots_.size() - 1;
    for (std::uint64_t slot : old) {
        if (!slot)
            continue;
        std::string_view s = string_at(reinterpret_cast<const std::uint8_t*>(bytes_.data()),
                                       (slot & 0xffffffff) - 1);
        std::size_t i = hash(s) & mask;
        while (slots_[i])
            i = (i + 1) & mask;
        slots_[i] = slot;
    }
}

std::uint32_t StringPool::intern(std::string_view s)
{
    if (s.empty())
        return 0;
    std::uint64_t h = hash(s);
    std::size_t mask = slots_.size() - 1, i = h & mask;
    for (; slots_[i]; i = (i + 1) & mask)
        if ((slots_[i] >> 32) == (h >> 32)) {
            std::uint64_t at = (slots_[i] & 0xffffffff) - 1;
            if (string_at(reinterpret_cast<const std::uint8_t*>(bytes_.data()), at) == s)
                return static_cast<std::uint32_t>(at);
        }
    std::size_t at = bytes_.size();
    if (at + s.size() + 10 >= UINT32_MAX)
        throw Error(Error::Code::bad_dump, "the signature dump's strings go past 4 GiB");
    put_varint(bytes_, s.size());
    bytes_.append(s);
    slots_[i] = (h >> 32) << 32 | (at + 1);
    if (++count_ * 2 > slots_.size())
        grow();
    return static_cast<std::uint32_t>(at);
}

bool check_string(std::uint64_t ref, const std::uint8_t* strings,
                  std::uint64_t strings_size) noexcept
{
    if (ref >= strings_size)
        return false;
    const std::uint8_t* p = strings + ref;
    std::uint64_t len;
    if (!get_varint(p, strings + strings_size, len))
        return false;
    return len <= static_cast<std::uint64_t>(strings + strings_size - p);
}

bool skip_type(const std::uint8_t*& p, const std::uint8_t* end, const std::uint8_t* strings,
               std::uint64_t strings_size, unsigned depth) noexcept
{
    if (p == end || depth > code::max_depth)
        return false;
    std::uint8_t c = *p++;
    if (c < code::address)
        return true;
    std::uint64_t v;
    switch (c) {
    case code::address:
    case code::boolean:
    case code::string:
    case code::bytes:
    case code::function:
        return true;
    case code::fixed:
    case code::ufixed:
        if (end - p < 2 || p[0] > 31 || p[1] > 80)
            return false;
        p += 2;
        return true;
    case code::array:
    case code::storage:
    case code::memory:
    case code::calldata:
        return skip_type(p, end, strings, strings_size, depth + 1);
    case code::static_array:
        return get_varint(p, end, v) && skip_type(p, end, strings, strings_size, depth + 1);
    case code::tuple:
        if (!get_varint(p, end, v) || v > max_params)
            return false;
        for (std::uint64_t i = 0; i < v; i++) {
            std::uint64_t name;
            if (!get_varint(p, end, name) || !check_string(name, strings, strings_size) ||
                !skip_type(p, end, strings, strings_size, depth + 1))
                return false;
        }
        return true;
    case code::named:
        return get_varint(p, end, v) && check_string(v, strings, strings_size);
    default:
        return false;
    }
}

namespace {

// past a code already checked
const std::uint8_t* skip_code(const std::uint8_t* p) noexcept
{
    std::uint8_t c = *p++;
    switch (c) {
    case code::fixed:
    case code::ufixed:
        return p + 2;
    case code::array:
    case code::storage:
    case code::memory:
    case code::calldata:
        return skip_code(p);
    case code::static_array:
        get_varint(p);
        return skip_code(p);
    case code::tuple: {
        std::uint64_t n = get_varint(p);
        for (std::uint64_t i = 0; i < n; i++) {
            get_varint(p);
            p = skip_code(p);
        }
        return p;
    }
    case code::named:
        get_varint(p);
        return p;
    default:
        return p;
    }
}

void append_number(std::string& out, std::uint64_t v)
{
    char digits[20];
    int n = 0;
    do {
        digits[n++] = static_cast<char>('0' + v % 10);
        v /= 10;
    } while (v);
    while (n)
        out.push_back(digits[--n]);
}

}  // namespace

void append_type_text(const std::uint8_t*& p, const std::uint8_t* strings, std::string& out)
{
    std::uint8_t c = *p++;
    if (c < code::int_base) {
        out += "uint";
        append_number(out, (c - code::uint_base + 1u) * 8);
        return;
    }
    if (c < code::bytes_base) {
        out += "int";
        append_number(out, (c - code::int_base + 1u) * 8);
        return;
    }
    if (c < code::address) {
        out += "bytes";
        append_number(out, c - code::bytes_base + 1u);
        return;
    }
    switch (c) {
    case code::address:
        out += "address";
        return;
    case code::boolean:
        out += "bool";
        return;
    case code::string:
        out += "string";
        return;
    case code::bytes:
        out += "bytes";
        return;
    case code::function:
        out += "function";
        return;
    case code::fixed:
    case code::ufixed:
        out += c == code::fixed ? "fixed" : "ufixed";
        append_number(out, (p[0] + 1u) * 8);
        out += 'x';
        append_number(out, p[1]);
        p += 2;
        return;
    case code::array:
        append_type_text(p, strings, out);
        out += "[]";
        return;
    case code::static_array: {
        std::uint64_t k = get_varint(p);
        append_type_text(p, strings, out);
        out += '[';
        append_number(out, k);
        out += ']';
        return;
    }
    case code::tuple: {
        std::uint64_t n = get_varint(p);
        out += '(';
        for (std::uint64_t i = 0; i < n; i++) {
            if (i)
                out += ',';
            get_varint(p);  // (the field's name: not in the signature)
            append_type_text(p, strings, out);
        }
        out += ')';
        return;
    }
    case code::storage:
    case code::memory:
    case code::calldata:
        append_type_text(p, strings, out);
        out += c == code::storage ? " storage" : c == code::memory ? " memory" : " calldata";
        return;
    case code::named:
        out += string_at(strings, get_varint(p));
        return;
    default:
        return;
    }
}

// --- the views -------------------------------------------------------------------------

TypeKind Type::kind() const noexcept
{
    std::uint8_t c = *p_;
    if (c < code::int_base)
        return TypeKind::uintN;
    if (c < code::bytes_base)
        return TypeKind::intN;
    if (c < code::address)
        return TypeKind::bytesN;
    switch (c) {
    case code::address:
        return TypeKind::address;
    case code::boolean:
        return TypeKind::boolean;
    case code::string:
        return TypeKind::string;
    case code::bytes:
        return TypeKind::bytes;
    case code::function:
        return TypeKind::function;
    case code::fixed:
        return TypeKind::fixed;
    case code::ufixed:
        return TypeKind::ufixed;
    case code::array:
        return TypeKind::array;
    case code::static_array:
        return TypeKind::static_array;
    case code::tuple:
        return TypeKind::tuple;
    case code::storage:
        return TypeKind::storage;
    case code::memory:
        return TypeKind::memory;
    case code::calldata:
        return TypeKind::calldata;
    default:
        return TypeKind::named;
    }
}

unsigned Type::bits() const noexcept
{
    std::uint8_t c = *p_;
    if (c < code::address)
        return ((c & 31u) + 1) * 8;
    if (c == code::fixed || c == code::ufixed)
        return (p_[1] + 1u) * 8;
    return 0;
}

unsigned Type::size() const noexcept
{
    std::uint8_t c = *p_;
    return c >= code::bytes_base && c < code::address ? (c & 31u) + 1 : 0;
}

unsigned Type::decimals() const noexcept
{
    std::uint8_t c = *p_;
    return c == code::fixed || c == code::ufixed ? p_[2] : 0;
}

std::uint64_t Type::length() const noexcept
{
    if (*p_ != code::static_array)
        return 0;
    const std::uint8_t* q = p_ + 1;
    return get_varint(q);
}

Type Type::element() const noexcept
{
    const std::uint8_t* q = p_ + 1;
    switch (*p_) {
    case code::static_array:
        get_varint(q);
        [[fallthrough]];
    case code::array:
    case code::storage:
    case code::memory:
    case code::calldata:
        return Type(q, strings_);
    default:
        return *this;
    }
}

Fields Type::fields() const noexcept
{
    if (*p_ != code::tuple)
        return Fields(nullptr, strings_, 0);
    const std::uint8_t* q = p_ + 1;
    std::uint64_t n = get_varint(q);
    return Fields(q, strings_, static_cast<std::size_t>(n));
}

std::string_view Type::name() const noexcept
{
    if (*p_ != code::named)
        return {};
    const std::uint8_t* q = p_ + 1;
    return string_at(strings_, get_varint(q));
}

bool Type::dynamic() const noexcept
{
    switch (kind()) {
    case TypeKind::string:
    case TypeKind::bytes:
    case TypeKind::array:
        return true;
    case TypeKind::static_array:
    case TypeKind::memory:
    case TypeKind::calldata:
        return element().dynamic();
    case TypeKind::tuple:
        for (Field f : fields())
            if (f.type().dynamic())
                return true;
        return false;
    default:
        return false;
    }
}

std::string Type::text() const
{
    std::string s;
    append_text(s);
    return s;
}

void Type::append_text(std::string& out) const
{
    const std::uint8_t* q = p_;
    append_type_text(q, strings_, out);
}

std::span<const std::uint8_t> Type::code() const noexcept
{
    return {p_, static_cast<std::size_t>(skip_code(p_) - p_)};
}

std::string_view Field::name() const noexcept
{
    const std::uint8_t* q = p_;
    return string_at(strings_, get_varint(q));
}

Type Field::type() const noexcept
{
    const std::uint8_t* q = p_;
    get_varint(q);
    return Type(q, strings_);
}

Fields::iterator& Fields::iterator::operator++() noexcept
{
    get_varint(p_);
    p_ = skip_code(p_);
    left_--;
    return *this;
}

Field Fields::operator[](std::size_t i) const noexcept
{
    iterator it = begin();
    while (i--)
        ++it;
    return *it;
}

namespace {
constexpr std::uint8_t kind_mask = 7, no_spaces = 8, trust_shift = 4, trust_mask = 0x30,
                         has_written = 0x40;
const std::array<std::uint8_t, 32> no_topic{};

// the record's parts: past the kind and the topic, the name
const std::uint8_t* record_name(const std::uint8_t* record) noexcept
{
    return record + 1 + ((record[0] & kind_mask) == static_cast<int>(Kind::event) ? 32 : 0);
}
}  // namespace

Kind Entry::kind() const noexcept { return static_cast<Kind>(record_[0] & kind_mask); }

Trust Entry::trust() const noexcept
{
    return static_cast<Trust>((record_[0] & trust_mask) >> trust_shift);
}

std::string_view Entry::written_type(std::size_t i) const noexcept
{
    if (!(record_[0] & has_written))
        return {};
    const std::uint8_t* q = record_name(record_);
    q += get_varint(q);
    std::uint64_t n = get_varint(q);
    if (i >= n)
        return {};
    if (kind() == Kind::event)
        q += (n + 7) / 8;
    for (std::uint64_t k = 0; k < n; k++) {  // (past the inputs)
        get_varint(q);
        q = skip_code(q);
    }
    for (std::size_t k = 0; k < i; k++)
        get_varint(q);
    return string_at(strings_, get_varint(q));
}

bool Entry::hashed_without_spaces() const noexcept { return record_[0] & no_spaces; }

std::span<const std::uint8_t, 32> Entry::topic() const noexcept
{
    if (kind() != Kind::event)
        return std::span<const std::uint8_t, 32>(no_topic);
    return std::span<const std::uint8_t, 32>(record_ + 1, 32);
}

std::string_view Entry::name() const noexcept
{
    const std::uint8_t* q = record_name(record_);
    std::uint64_t len = get_varint(q);
    return {reinterpret_cast<const char*>(q), static_cast<std::size_t>(len)};
}

Fields Entry::params() const noexcept
{
    const std::uint8_t* q = record_name(record_);
    q += get_varint(q);
    std::uint64_t n = get_varint(q);
    if (kind() == Kind::event)
        q += (n + 7) / 8;
    return Fields(q, strings_, static_cast<std::size_t>(n));
}

bool Entry::indexed(std::size_t i) const noexcept
{
    if (kind() != Kind::event)
        return false;
    const std::uint8_t* q = record_name(record_);
    q += get_varint(q);
    std::uint64_t n = get_varint(q);
    return i < n && (q[i / 8] >> (i % 8) & 1);
}

std::string Entry::signature() const
{
    std::string s(name());
    s += '(';
    bool first = true;
    for (Field f : params()) {
        if (!first)
            s += ',';
        first = false;
        f.type().append_text(s);
    }
    s += ')';
    return s;
}

// --- the database --------------------------------------------------------------------

Database::Database(std::unique_ptr<Mapping> map) : map_(std::move(map)) {}
Database::~Database() = default;

std::unique_ptr<Database> Database::open(const std::filesystem::path& file)
{
    auto map = Mapping::open(file);
    std::span<const std::uint8_t> b = map->bytes();
    auto bad = [&](const char* why) {
        return Error(Error::Code::failed, file.string() + " isn't a signature database (" + why + ")");
    };
    if (b.size() < header_size || std::memcmp(b.data(), magic, 8) != 0)
        throw bad("not this format");
    const std::uint8_t* h = b.data();
    if (load32(h + 8) != version || load32(h + 12) != header_size)
        throw bad("another version");
    if (load64(h + 16) != b.size())
        throw bad("cut short");
    std::uint64_t count = load32(h + 72);
    unsigned bits = load32(h + 76);
    std::uint64_t buckets = load64(h + 80), index = load64(h + 88);
    std::uint64_t records = load64(h + 96), records_size = load64(h + 104);
    std::uint64_t strings = load64(h + 112), strings_size = load64(h + 120);
    auto within = [&](std::uint64_t off, std::uint64_t len) {
        return off >= header_size && off % 4 == 0 && off <= b.size() && len <= b.size() - off;
    };
    if (bits > max_bucket_bits || !within(buckets, ((std::uint64_t{1} << bits) + 1) * 4) ||
        !within(index, count * 8) || !within(records, records_size) ||
        !within(strings, strings_size) || strings_size == 0 || b[strings] != 0)
        throw bad("its sections");

    std::unique_ptr<Database> db(new Database(std::move(map)));
    db->buckets_ = h + buckets;
    db->index_ = h + index;
    db->records_ = h + records;
    db->records_size_ = records_size;
    db->strings_ = h + strings;
    db->strings_size_ = strings_size;
    db->count_ = static_cast<std::size_t>(count);
    db->bucket_bits_ = bits;
    std::memcpy(db->dump_sha256_.data(), h + 24, 32);
    db->dump_size_ = load64(h + 56);
    db->dump_mtime_ = static_cast<std::int64_t>(load64(h + 64));
    db->dump_path_ = load32(h + 128);
    if (!check_string(db->dump_path_, db->strings_, strings_size))
        throw bad("its dump's path");
    // the buckets: the index whole between the first and the last; each
    // bucket is checked where a lookup reads it (function: within the index),
    // not all of them here - the open stays O(1), its pages untouched
    const std::uint8_t* bk = h + buckets;
    if (load32(bk) != 0 || load32(bk + 4 * (std::uint64_t{1} << bits)) != count)
        throw bad("its buckets");
    return db;
}

std::size_t Database::file_size() const noexcept { return map_->bytes().size(); }

std::filesystem::path Database::dump_path() const
{
    std::string_view s = string_at(strings_, dump_path_);  // (UTF-8)
    return std::filesystem::path(std::u8string(reinterpret_cast<const char8_t*>(s.data()), s.size()));
}

namespace {
// a record checked whole: within the records, its strings within the strings
bool check_record(const std::uint8_t* p, const std::uint8_t* end, const std::uint8_t* strings,
                  std::uint64_t strings_size) noexcept
{
    if (p >= end)
        return false;
    std::uint8_t head = *p++;
    if (head & 0x80 || (head & trust_mask) >> trust_shift > static_cast<int>(Trust::unverified))
        return false;
    bool event = (head & kind_mask) == static_cast<int>(Kind::event);
    if (event) {
        if (end - p < 32)
            return false;
        p += 32;
    }
    std::uint64_t len, n;
    if (!get_varint(p, end, len) || len > static_cast<std::uint64_t>(end - p))
        return false;
    p += len;
    if (!get_varint(p, end, n) || n > max_params)
        return false;
    if (event) {
        if (static_cast<std::uint64_t>(end - p) < (n + 7) / 8)
            return false;
        p += (n + 7) / 8;
    }
    for (std::uint64_t i = 0; i < n; i++) {
        std::uint64_t name;
        if (!get_varint(p, end, name) || !check_string(name, strings, strings_size))
            return false;
        if (!skip_type(p, end, strings, strings_size))  // (the type, its strings)
            return false;
    }
    if (head & has_written)
        for (std::uint64_t i = 0; i < n; i++) {
            std::uint64_t ref;
            if (!get_varint(p, end, ref) || !check_string(ref, strings, strings_size))
                return false;
        }
    return true;
}
}  // namespace

std::optional<Entry> Database::entry_at(std::size_t i) const noexcept
{
    const std::uint8_t* e = index_ + 8 * i;
    std::uint32_t off = load32(e + 4);
    if (off >= records_size_ ||
        !check_record(records_ + off, records_ + records_size_, strings_, strings_size_))
        return std::nullopt;
    return Entry(load32(e), records_ + off, strings_);
}

std::optional<Entry> Database::at(std::size_t i) const noexcept
{
    if (i >= count_)
        return std::nullopt;
    return entry_at(i);
}

std::optional<Entry> Database::function(std::uint32_t selector) const noexcept
{
    std::uint32_t b = bucket_bits_ ? selector >> (32 - bucket_bits_) : 0;
    std::uint32_t lo = load32(buckets_ + 4 * b), hi = load32(buckets_ + 4 * b + 4);
    if (hi > count_)
        return std::nullopt;  // (a damaged bucket: its selectors unknown)
    for (std::uint32_t i = lo; i < hi; i++) {
        std::uint32_t s = load32(index_ + 8 * i);
        if (s == selector)
            return entry_at(i);
        if (s > selector)
            break;
    }
    return std::nullopt;
}

std::optional<Entry> Database::event(std::span<const std::uint8_t, 32> topic) const noexcept
{
    std::uint32_t selector = std::uint32_t{topic[0]} << 24 | std::uint32_t{topic[1]} << 16 |
                             std::uint32_t{topic[2]} << 8 | topic[3];
    std::optional<Entry> e = function(selector);
    if (!e || e->kind() != Kind::event || e->trust() == Trust::unverified ||
        !std::ranges::equal(e->topic(), topic))
        return std::nullopt;
    return e;
}

// --- the builder ------------------------------------------------------------------------

namespace {

// The entries of the dump, as they come, each line's record made: verified
// (its signature hashes to its selector, as python checks it), repaired (a
// variant of it does: IERC20 written for an address...), or unverified (none
// does: kept for want of better - panoramix's guesses, unknown12345678(...)).
class Builder final : public EntrySink {
public:
    struct Item {
        std::uint32_t selector;
        Trust trust;
        std::uint64_t offset;  // its record in records
        std::uint32_t size;
    };

    void entry(const RawEntry& e) override
    {
        if (!e.selector_ok || !e.ok)
            return;  // (a key python never asks for; a line python can't read)
        Item item{e.selector, Trust::verified, records.size(), 0};
        if (!check(e))
            item.trust = repair(e) ? Trust::repaired : Trust::unverified;
        encode(e, item.trust);
        item.size = static_cast<std::uint32_t>(records.size() - item.offset);
        items.push_back(item);
    }

    StringPool pool;
    std::string records;
    std::vector<Item> items;

private:
    static constexpr std::size_t max_variants = 256;  // of a signature (2^-24 of a false match)

    static std::uint32_t be32(const std::array<std::uint8_t, 32>& h)
    {
        return std::uint32_t{h[0]} << 24 | std::uint32_t{h[1]} << 16 | std::uint32_t{h[2]} << 8 |
               h[3];
    }

    // text hashes to the selector, or text without its spaces does (the
    // hash of text kept: a verified event's topic, as python checks it; and
    // the hash of the text that matched: a repaired one's)
    bool hashes(const std::string& text, std::uint32_t selector)
    {
        hash_ = keccak256(text);
        matched_hash_ = hash_;
        no_spaces_ = false;
        if (be32(hash_) == selector)
            return true;
        if (text.find(' ') == std::string::npos)
            return false;
        std::string squeezed;
        std::ranges::copy_if(text, std::back_inserter(squeezed), [](char c) { return c != ' '; });
        matched_hash_ = keccak256(squeezed);
        no_spaces_ = be32(matched_hash_) == selector;
        return no_spaces_;
    }

    // python's hashes_to: its signature as python writes it
    bool check(const RawEntry& e)
    {
        text_.assign(e.name);
        text_ += '(';
        for (std::size_t i = 0; i < e.params.size(); i++) {
            if (i)
                text_ += ',';
            text_ += e.params[i].canonical;
        }
        text_ += ')';
        return hashes(text_, e.selector);
    }

    // --- the codes of the types ---

    // The tuple of a parameter's components (TupleSource for parse_type).
    struct Components final : TupleSource {
        Builder& b;
        const RawParam& param;
        std::span<const RawParam> arena;
        Components(Builder& bb, const RawParam& p, std::span<const RawParam> a)
            : b(bb), param(p), arena(a)
        {
        }
        bool tuple(std::string& code) override
        {
            code.push_back(static_cast<char>(code::tuple));
            put_varint(code, param.child_count);
            for (std::uint32_t i = 0; i < param.child_count; i++) {
                const RawParam& c = arena[param.children + i];
                put_varint(code, b.pool.intern(c.name));
                b.type_code(c, arena, code);
            }
            return true;
        }
    };

    // a code made at start: within the depth, its strings there
    bool sound(const std::string& code, std::size_t start) const
    {
        const auto* q = reinterpret_cast<const std::uint8_t*>(code.data() + start);
        const auto* end = reinterpret_cast<const std::uint8_t*>(code.data() + code.size());
        return skip_type(q, end, reinterpret_cast<const std::uint8_t*>(pool.bytes().data()),
                         pool.bytes().size()) &&
               q == end;
    }

    std::string text_of(const std::string& code, std::size_t start = 0) const
    {
        std::string text;
        const auto* q = reinterpret_cast<const std::uint8_t*>(code.data() + start);
        append_type_text(q, reinterpret_cast<const std::uint8_t*>(pool.bytes().data()), text);
        return text;
    }

    void named(const RawParam& p, std::string& code)
    {
        code.push_back(static_cast<char>(code::named));
        put_varint(code, pool.intern(p.canonical));
    }

    // the code of a parameter's type: what parse_type makes of it, or a
    // named type of python's text (canonical_type) where it can't, where
    // that isn't python's text, or nests too deep
    void type_code(const RawParam& p, std::span<const RawParam> arena, std::string& code)
    {
        std::size_t start = code.size();
        Components comps(*this, p, arena);
        bool python_tuple = p.tuple_text && p.has_components;
        bool ok = parse_type(p.type, python_tuple ? &comps : nullptr, pool, code) &&
                  sound(code, start);
        // ("tuple" substituted: the text must still be python's)
        if (ok && python_tuple)
            ok = text_of(code, start) == p.canonical;
        if (!ok) {
            code.resize(start);
            named(p, code);
        }
    }

    // The tuple of a parameter's components, read leniently.
    struct LenientComponents final : TupleSource {
        Builder& b;
        const RawParam& param;
        std::span<const RawParam> arena;
        Slots& slots;
        LenientComponents(Builder& bb, const RawParam& p, std::span<const RawParam> a, Slots& s)
            : b(bb), param(p), arena(a), slots(s)
        {
        }
        bool tuple(std::string& code) override
        {
            code.push_back(static_cast<char>(code::tuple));
            put_varint(code, param.child_count);
            for (std::uint32_t i = 0; i < param.child_count; i++) {
                const RawParam& c = arena[param.children + i];
                put_varint(code, b.pool.intern(c.name));
                b.lenient_code(c, arena, slots, code);
            }
            return true;
        }
    };

    void lenient_code(const RawParam& p, std::span<const RawParam> arena, Slots& slots,
                      std::string& code)
    {
        std::size_t start = code.size();
        LenientComponents comps(*this, p, arena, slots);
        if (!(parse_type_lenient(p.type, p.has_components ? &comps : nullptr, pool, code, slots) &&
              sound(code, start))) {
            code.resize(start);
            named(p, code);
        }
    }

    // the parameters' codes, read leniently with the slots' choices (each
    // parameter's slots from where the discovery found them)
    void lenient_codes(const RawEntry& e, Slots& slots, std::vector<std::string>& codes)
    {
        codes.resize(e.params.size());
        if (slots.discovering)
            first_slot_.resize(e.params.size());
        for (std::size_t i = 0; i < e.params.size(); i++) {
            if (slots.discovering)
                first_slot_[i] = slots.next;
            else
                slots.next = first_slot_[i];
            codes[i].clear();
            lenient_code(e.params[i], e.arena, slots, codes[i]);
        }
    }

    // a signature of these codes hashes to the selector
    bool hashes(const RawEntry& e, const std::vector<std::string>& codes)
    {
        variant_text_.assign(e.name);
        variant_text_ += '(';
        for (std::size_t i = 0; i < codes.size(); i++) {
            if (i)
                variant_text_ += ',';
            variant_text_ += text_of(codes[i]);
        }
        variant_text_ += ')';
        if (variant_text_ == text_)
            return false;  // (python's text: it doesn't)
        return hashes(variant_text_, e.selector);
    }

    // what a slot may be, the likeliest first (keep: the name itself, as a
    // library's signature has it)
    static std::vector<Choice> candidates(const Slots::Found& f)
    {
        switch (f.hint) {
        case Hint::contract:
            return {Choice::address, Choice::keep};
        case Hint::enumeration:
            return {Choice::uint8, Choice::keep};
        case Hint::structure:
            return f.components ? std::vector{Choice::components, Choice::keep}
                                : std::vector{Choice::keep};
        case Hint::bare:
            break;
        }
        std::vector<Choice> c;
        if (f.components)
            c.push_back(Choice::components);
        for (Choice x : {Choice::address, Choice::uint8, Choice::uint256, Choice::bytes32, Choice::keep})
            c.push_back(x);
        return c;
    }

    // The variants of a signature that doesn't hash: read leniently (its
    // case, aliases, words after the types, references to memory...), its
    // named types made of what they may be. The first that hashes to the
    // selector is the entry (codes_); else the lenient reading with the named
    // types kept is, unverified.
    bool repair(const RawEntry& e)
    {
        Slots slots;
        lenient_codes(e, slots, normalized_);
        codes_ = normalized_;
        if (hashes(e, normalized_))
            return true;
        if (slots.found.empty())
            return false;
        slots.discovering = false;
        std::vector<std::vector<Choice>> cands;
        std::size_t combos = 1, widest = 0;
        for (const Slots::Found& f : slots.found) {
            cands.push_back(candidates(f));
            widest = std::max(widest, cands.back().size());
            combos = combos > max_variants ? combos : combos * cands.back().size();
        }
        std::vector<Choice> a(cands.size());
        auto attempt = [&] {
            slots.assignment = a;
            lenient_codes(e, slots, variant_);
            if (!hashes(e, variant_))
                return false;
            codes_ = variant_;
            return true;
        };
        if (combos <= max_variants) {
            // every choice of every slot, the first candidates first
            std::vector<std::size_t> at(cands.size(), 0);
            for (;;) {
                for (std::size_t i = 0; i < cands.size(); i++)
                    a[i] = cands[i][at[i]];
                if (attempt())
                    return true;
                std::size_t k = at.size();
                while (k > 0 && ++at[k - 1] == cands[k - 1].size())
                    at[--k] = 0;
                if (k == 0)
                    return false;
            }
        }
        // too many: the same choice for them all
        for (std::size_t c = 0; c < widest; c++) {
            for (std::size_t i = 0; i < cands.size(); i++)
                a[i] = cands[i][std::min(c, cands[i].size() - 1)];
            if (attempt())
                return true;
        }
        return false;
    }

    void encode(const RawEntry& e, Trust trust)
    {
        bool event = e.kind == Kind::event;
        // the dump's text of a parameter, where it isn't its code's
        // (repaired, unverified)
        std::vector<std::uint32_t> written;
        if (trust != Trust::verified) {
            written.resize(e.params.size(), 0);
            for (std::size_t i = 0; i < e.params.size(); i++)
                if (text_of(codes_[i]) != e.params[i].canonical)
                    written[i] = pool.intern(e.params[i].canonical);
            if (std::ranges::all_of(written, [](std::uint32_t w) { return w == 0; }))
                written.clear();
        }
        records.push_back(static_cast<char>(
            static_cast<std::uint8_t>(e.kind) | (no_spaces_ && trust != Trust::unverified ? no_spaces : 0) |
            static_cast<std::uint8_t>(trust) << trust_shift | (written.empty() ? 0 : has_written)));
        if (event) {
            if (trust == Trust::unverified)
                records.append(32, '\0');  // (no topic hashes to it)
            else
                records.append(reinterpret_cast<const char*>(
                                   (trust == Trust::verified ? hash_ : matched_hash_).data()),
                               32);
        }
        put_varint(records, e.name.size());
        records.append(e.name);
        put_varint(records, e.params.size());
        if (event) {
            std::size_t at = records.size();
            records.append((e.params.size() + 7) / 8, '\0');
            for (std::size_t i = 0; i < e.params.size(); i++)
                if (e.params[i].indexed)
                    records[at + i / 8] = static_cast<char>(records[at + i / 8] | 1 << (i % 8));
        }
        for (std::size_t i = 0; i < e.params.size(); i++) {
            put_varint(records, pool.intern(e.params[i].name));
            if (trust == Trust::verified)
                type_code(e.params[i], e.arena, records);
            else
                records += codes_[i];
        }
        for (std::uint32_t w : written)
            put_varint(records, w);
    }

    std::string text_, variant_text_;
    std::array<std::uint8_t, 32> hash_{}, matched_hash_{};
    bool no_spaces_ = false;
    std::vector<std::string> normalized_, variant_, codes_;
    std::vector<std::size_t> first_slot_;
};

// The dump decompressed (xz or lzma, as python's lzma.open) by a second
// thread - two fifths of the work - and given to the parser here, in chunks of
// whole lines.
struct LineTooLong {};  // (its number: the parser's, see read_dump)

class Decompressor {
public:
    explicit Decompressor(std::span<const std::uint8_t> xz) : xz_(xz) {}
    ~Decompressor()
    {
        {
            std::lock_guard lock(m_);
            stop_ = true;
        }
        cv_.notify_all();
    }  // (then the thread, declared last, is joined)

    // The next chunk (complete lines, the last one ended by '\n'), empty
    // at the end; throws what the decompression threw.
    std::vector<std::uint8_t> next()
    {
        std::unique_lock lock(m_);
        cv_.wait(lock, [&] { return !ready_.empty() || finished_; });
        if (ready_.empty()) {
            if (error_)
                std::rethrow_exception(error_);
            return {};
        }
        std::vector<std::uint8_t> chunk = std::move(ready_.front());
        ready_.pop_front();
        cv_.notify_all();
        return chunk;
    }
    // a chunk parsed: its buffer for another one
    void recycle(std::vector<std::uint8_t> chunk)
    {
        std::lock_guard lock(m_);
        if (spare_.size() < queue)
            spare_.push_back(std::move(chunk));
    }

private:
    static constexpr std::size_t chunk_size = 4u << 20, queue = 3;

    std::vector<std::uint8_t> take_spare()
    {
        std::lock_guard lock(m_);
        if (spare_.empty())
            return {};
        std::vector<std::uint8_t> b = std::move(spare_.back());
        spare_.pop_back();
        return b;
    }
    // false when stopped
    bool hand_over(std::vector<std::uint8_t> chunk)
    {
        std::unique_lock lock(m_);
        cv_.wait(lock, [&] { return ready_.size() < queue || stop_; });
        if (stop_)
            return false;
        ready_.push_back(std::move(chunk));
        cv_.notify_all();
        return true;
    }

    void run()
    {
        try {
            decompress();
        } catch (...) {
            std::lock_guard lock(m_);
            error_ = std::current_exception();
        }
        {
            std::lock_guard lock(m_);
            finished_ = true;
        }
        cv_.notify_all();
    }

    void decompress()
    {
        lzma_stream strm = LZMA_STREAM_INIT;
        if (lzma_auto_decoder(&strm, max_xz_memory, LZMA_CONCATENATED) != LZMA_OK)
            throw Error(Error::Code::failed, "lzma can't decode");
        struct End {
            lzma_stream* s;
            ~End() { lzma_end(s); }
        } end{&strm};
        strm.next_in = xz_.data();
        strm.avail_in = xz_.size();
        std::vector<std::uint8_t> buf(chunk_size);
        std::size_t len = 0;
        for (;;) {
            strm.next_out = buf.data() + len;
            strm.avail_out = buf.size() - len;
            lzma_ret r = lzma_code(&strm, LZMA_FINISH);
            len = buf.size() - strm.avail_out;
            if (r == LZMA_MEMLIMIT_ERROR)
                throw Error(Error::Code::bad_dump, "its decompression needs more than 1 GiB");
            if (r != LZMA_OK && r != LZMA_STREAM_END)
                throw Error(Error::Code::failed, "lzma error " + std::to_string(r));
            if (r == LZMA_STREAM_END) {
                if (len && buf[len - 1] != '\n') {  // the last line, without its newline
                    buf.resize(std::max(buf.size(), len + 1));
                    buf[len++] = '\n';
                }
                buf.resize(len);
                if (len)
                    hand_over(std::move(buf));
                return;
            }
            if (len < buf.size())
                continue;
            // full: its whole lines go, the rest begins the next chunk
            std::string_view text(reinterpret_cast<const char*>(buf.data()), len);
            std::size_t last = text.rfind('\n');
            if (last == std::string_view::npos) {  // a line longer than the buffer
                if (buf.size() >= max_line)
                    throw LineTooLong{};
                buf.resize(buf.size() * 2);
                continue;
            }
            std::vector<std::uint8_t> next = take_spare();
            next.resize(std::max(chunk_size, len - last - 1 + chunk_size / 2));
            std::copy(buf.begin() + static_cast<std::ptrdiff_t>(last) + 1,
                      buf.begin() + static_cast<std::ptrdiff_t>(len), next.begin());
            len -= last + 1;
            buf.resize(last + 1);
            if (!hand_over(std::move(buf)))
                return;
            buf = std::move(next);
        }
    }

    std::span<const std::uint8_t> xz_;
    std::mutex m_;
    std::condition_variable cv_;
    std::deque<std::vector<std::uint8_t>> ready_;
    std::vector<std::vector<std::uint8_t>> spare_;
    bool finished_ = false, stop_ = false;
    std::exception_ptr error_;
    std::jthread thread_{[this] { run(); }};  // (last: started once the rest is there)
};

void read_dump(std::span<const std::uint8_t> xz, DumpParser& parser)
{
    Decompressor d(xz);
    for (;;) {
        std::vector<std::uint8_t> chunk;
        try {
            chunk = d.next();
        } catch (const LineTooLong&) {  // (the lines before it parsed)
            throw Error(Error::Code::bad_dump,
                        "line " + std::to_string(parser.lines() + 1) + " is too long");
        }
        if (chunk.empty())
            return;
        parser.parse(chunk.data(), chunk.data() + chunk.size());
        d.recycle(std::move(chunk));
    }
}

std::size_t aligned(std::size_t n) { return (n + section_align - 1) / section_align * section_align; }

// The file: each selector's best line (see the records, above).
BuildStats write_database(Builder& b, const std::filesystem::path& out,
                          const sha256::Digest& sha, const platform::Stamp& stamp,
                          std::uint32_t dump_path, std::uint64_t lines)
{
    std::vector<Builder::Item>& items = b.items;
    if (!std::ranges::is_sorted(items, {}, &Builder::Item::selector))
        std::ranges::stable_sort(items, {}, &Builder::Item::selector);
    // a selector's entry: the verified ones first, then the repaired ones,
    // then the rest; among equals, the last line (python's dict)
    std::vector<const Builder::Item*> kept;
    for (std::size_t i = 0; i < items.size();) {
        const Builder::Item* best = &items[i];
        std::size_t j = i + 1;
        for (; j < items.size() && items[j].selector == items[i].selector; j++)
            if (items[j].trust <= best->trust)
                best = &items[j];
        kept.push_back(best);
        i = j;
    }

    BuildStats stats;
    stats.lines = lines;
    stats.entries = kept.size();
    for (const Builder::Item* it : kept)
        (it->trust == Trust::verified   ? stats.verified
         : it->trust == Trust::repaired ? stats.repaired
                                        : stats.unverified)++;
    unsigned bits = std::min<unsigned>(max_bucket_bits,
                                       std::max(4, static_cast<int>(std::bit_width(kept.size())) - 4));
    std::size_t nbuckets = std::size_t{1} << bits;
    std::uint64_t records_size = 0;
    for (const Builder::Item* it : kept)
        records_size += it->size;
    if (records_size > UINT32_MAX)
        throw Error(Error::Code::bad_dump, "the signature database's records go past 4 GiB");

    std::size_t buckets_off = aligned(header_size);
    std::size_t index_off = aligned(buckets_off + (nbuckets + 1) * 4);
    std::size_t records_off = aligned(index_off + kept.size() * 8);
    std::size_t strings_off = aligned(records_off + records_size);
    const std::string& strings = b.pool.bytes();
    std::size_t file_size = strings_off + strings.size();

    std::vector<std::uint8_t> head(buckets_off, 0);
    std::memcpy(head.data(), magic, 8);
    store32(&head[8], version);
    store32(&head[12], header_size);
    store64(&head[16], file_size);
    std::memcpy(&head[24], sha.data(), 32);
    store64(&head[56], stamp.size);
    store64(&head[64], static_cast<std::uint64_t>(stamp.mtime));
    store32(&head[72], static_cast<std::uint32_t>(kept.size()));
    store32(&head[76], bits);
    store64(&head[80], buckets_off);
    store64(&head[88], index_off);
    store64(&head[96], records_off);
    store64(&head[104], records_size);
    store64(&head[112], strings_off);
    store64(&head[120], strings.size());
    store32(&head[128], dump_path);

    // the buckets, the index
    std::vector<std::uint8_t> table(records_off - buckets_off, 0);
    std::uint8_t* bk = table.data();
    std::uint8_t* ix = table.data() + (index_off - buckets_off);
    std::size_t at = 0;
    std::uint32_t off = 0;
    for (std::size_t bucket = 0; bucket <= nbuckets; bucket++) {
        while (at < kept.size() && (kept[at]->selector >> (32 - bits)) < bucket) {
            store32(ix + 8 * at, kept[at]->selector);
            store32(ix + 8 * at + 4, off);
            off += kept[at]->size;
            at++;
        }
        store32(bk + 4 * bucket, static_cast<std::uint32_t>(at));
    }

    platform::AtomicFile f(out);
    f.write(head);
    f.write(table);
    const auto* rec = reinterpret_cast<const std::uint8_t*>(b.records.data());
    for (const Builder::Item* it : kept) {
        f.write({rec + it->offset, it->size});
        if (static_cast<Kind>(rec[it->offset] & kind_mask) == Kind::event)
            stats.events++;
    }
    std::vector<std::uint8_t> pad(strings_off - (records_off + records_size), 0);
    f.write(pad);
    f.write({reinterpret_cast<const std::uint8_t*>(strings.data()), strings.size()});
    f.commit();
    stats.file_size = file_size;
    return stats;
}

}  // namespace

BuildStats build(const std::filesystem::path& dump, const std::filesystem::path& out_path)
{
    std::filesystem::path out = out_path.empty() ? default_path() : out_path;
    if (out.empty())
        throw Error(Error::Code::failed, "no place for the signature database: set PANORAMIX_SIGDB");
    log(log_info, "Loading " + dump.string() + " into " + out.string() + "...");
    std::unique_ptr<Mapping> xz = Mapping::open(dump);
    sha256::Digest sha = sha256::hash(xz->bytes());
    // where it came from: what tells, later, that it changed (python's
    // dump_version, its size and mtime first) - not a dump that isn't a
    // regular file (a fifo isn't read again)
    std::optional<platform::Stamp> stamp = platform::stamp(dump);
    Builder b;
    std::uint32_t dump_ref = 0;
    if (stamp)
        if (std::optional<std::filesystem::path> real = platform::real_path(dump)) {
            std::u8string u = real->u8string();
            dump_ref = b.pool.intern(std::string_view(reinterpret_cast<const char*>(u.data()), u.size()));
        }

    DumpParser parser(b);
    try {
        read_dump(xz->bytes(), parser);
    } catch (const Error& e) {
        // (the asm's messages: what it can't read, what it reads but refuses)
        if (e.code() == Error::Code::failed)
            throw Error(e.code(), dump.string() + ": " + e.what());
        throw Error(e.code(), dump.string() + " isn't a signature dump this can read: " + e.what());
    }
    xz.reset();
    BuildStats stats =
        write_database(b, out, sha, stamp.value_or(platform::Stamp{}), dump_ref, parser.lines());
    log(log_info, out.string() + " is ready: " + std::to_string(stats.entries) + " signatures (" +
                      std::to_string(stats.verified) + " verified, " + std::to_string(stats.repaired) +
                      " repaired, " + std::to_string(stats.unverified) + " unverified)");
    return stats;
}

// --- the process's database --------------------------------------------------------------

std::filesystem::path default_path()
{
    if (const char* e = std::getenv("PANORAMIX_SIGDB"); e && *e)
        return e;
    std::filesystem::path dir = platform::cache_dir();
    return dir.empty() ? dir : dir / "sigdb2.bin";
}

namespace {

// the dump isn't the one the database was built from: its size or mtime
// differ, then its SHA-256 (no such file: the database is kept)
bool dump_changed(const Database& db, const std::filesystem::path& dump)
{
    std::optional<platform::Stamp> st = platform::stamp(dump);
    if (!st)
        return false;
    if (st->size == db.dump_size() && st->mtime == db.dump_mtime())
        return false;
    try {
        return sha256::hash(Mapping::open(dump)->bytes()) != db.dump_sha256();
    } catch (const Error&) {
        return false;
    }
}

}  // namespace

std::unique_ptr<Database> load(const std::filesystem::path& path,
                               const std::optional<std::filesystem::path>& env_dump)
{
    if (path.empty()) {
        log(log_warning, "no signature database (no HOME, no PANORAMIX_SIGDB): the functions will be unknown");
        return nullptr;
    }
    bool built = false;
    auto rebuild = [&](const std::filesystem::path& dump) {
        built = true;
        try {
            build(dump, path);
        } catch (const Error& e) {
            log(log_error, e.what());
        } catch (const std::exception& e) {
            log(log_error, std::string("building the signature database: ") + e.what());
        }
    };
    for (;;) {
        std::unique_ptr<Database> db;
        std::string why;
        bool exists = platform::stamp(path).has_value();
        try {
            db = Database::open(path);
        } catch (const Error& e) {
            why = e.what();
        }
        if (db) {
            // (once: a build that failed leaves the one there was)
            if (!built) {
                std::filesystem::path dump = env_dump ? *env_dump : db->dump_path();
                if (!dump.empty() && dump_changed(*db, dump)) {
                    db.reset();
                    rebuild(dump);
                    continue;
                }
            }
            log(log_debug, std::to_string(db->size()) + " signatures loaded from " + path.string());
            return db;
        }
        if (!built && env_dump) {
            rebuild(*env_dump);
            continue;
        }
        if (exists)
            log(log_warning, why);
        else
            log(log_warning, "no signature database (" + path.string() +
                                 "): the functions will be unknown; build one with "
                                 "`pancxx build-db abi_dump.xz`");
        return nullptr;
    }
}

const Database* get() noexcept
{
    static std::once_flag once;
    static std::unique_ptr<Database> db;
    std::call_once(once, [] {
        try {
            std::optional<std::filesystem::path> dump;
            if (const char* e = std::getenv("PANORAMIX_ABI_DUMP"); e && *e)
                dump = e;
            db = load(default_path(), dump);
        } catch (const std::exception& e) {
            log(log_error, std::string("the signature database: ") + e.what());
        }
    });
    return db.get();
}

}  // namespace pan::sigdb

int pan::build_signature_db(const std::string& dump_path, const std::string& out_path)
{
    try {
        sigdb::build(dump_path, out_path);
        return 0;
    } catch (const sigdb::Error& e) {
        sigdb::log(sigdb::log_error, e.what());
        return static_cast<int>(e.code());
    } catch (const std::bad_alloc&) {
        sigdb::log(sigdb::log_error, dump_path + ": out of memory");
        return static_cast<int>(sigdb::Error::Code::bad_dump);
    } catch (const std::exception& e) {
        sigdb::log(sigdb::log_error, dump_path + ": " + e.what());
        return static_cast<int>(sigdb::Error::Code::failed);
    }
}
