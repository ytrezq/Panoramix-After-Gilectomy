// Typed calldata (abi_encode.hpp): the types read from the signature
// database's codes, the values drawn, their encoding, the malformations.
#include "abi_encode.hpp"

#include "sigdb.hpp"

#include <algorithm>
#include <array>
#include <cassert>
#include <initializer_list>

namespace validate
{
namespace
{
// The codes of the types (src/sigdb.hpp: Type).
namespace code
{
constexpr std::uint8_t int_base = 0x20, bytes_base = 0x40, address = 0x60, boolean = 0x61,
                       string = 0x62, bytes = 0x63, function = 0x64, fixed = 0x65, ufixed = 0x66,
                       array = 0x67, static_array = 0x68, tuple = 0x69, storage = 0x6a,
                       memory = 0x6b, calldata = 0x6c, named = 0x6d;
constexpr unsigned max_depth = 64;  // of the nesting (the database's)
}  // namespace code

/// The tag of the call's pseudo-random stream (the world's are below 0x80,
/// calls.cpp's 0x80-0x83, probe.cpp's 0x90).
constexpr std::uint8_t k_abi = 0xa0;

/// The sizes saturate here: past AbiType::max_head, too large anyway.
constexpr std::uint64_t too_big = AbiType::max_head + 1;
constexpr std::size_t max_fields = 4096;  // of a tuple

constexpr std::uint64_t add_sat(std::uint64_t a, std::uint64_t b) noexcept
{
    return std::min(a + b, too_big);  // (both at most too_big)
}

constexpr std::uint64_t mul_sat(std::uint64_t a, std::uint64_t b) noexcept
{
    if (a == 0 || b == 0)
        return 0;
    return a > too_big / b ? too_big : std::min(a * b, too_big);
}

const Word word_max = ~Word{0};

/// 2^bits - 1 (bits <= 256).
Word low_mask(unsigned bits) noexcept
{
    return bits >= 256 ? word_max : (Word{1} << bits) - 1;
}

/// The value of the low `bits` bits of w as a signed integer, sign-extended.
Word sign_extend(const Word& w, unsigned bits) noexcept
{
    if (bits >= 256)
        return w;
    const auto v = w & low_mask(bits);
    return (v >> (bits - 1)) != 0 ? v | ~low_mask(bits) : v;
}

Word pow10(unsigned k) noexcept
{
    Word p = 1;
    for (unsigned i = 0; i < k; ++i)
        p *= 10;
    return p;
}

void put_word(Bytes& out, std::size_t at, const Word& w) noexcept
{
    intx::be::unsafe::store(out.data() + at, w);
}

Word get_word(const Bytes& data, std::size_t at) noexcept
{
    return intx::be::unsafe::load<Word>(data.data() + at);
}

// --- the codes --------------------------------------------------------------------

/// A type's code read (sigdb.hpp: Type): a prefix code, varints (LEB128) for
/// the lengths, counts and the string references (skipped: names and the
/// named types' text aren't the encoding's).
class CodeReader
{
public:
    explicit CodeReader(std::span<const std::uint8_t> code) noexcept
      : p_{code.data()}, end_{code.data() + code.size()}
    {}

    bool at_end() const noexcept { return p_ == end_; }

    std::optional<AbiType> type(unsigned depth = 0)
    {
        if (p_ == end_ || depth > code::max_depth)
            return std::nullopt;
        const std::uint8_t c = *p_++;
        if (c < code::int_base)
            return AbiType::uint_n(8 * ((c & 31u) + 1));
        if (c < code::bytes_base)
            return AbiType::int_n(8 * ((c & 31u) + 1));
        if (c < code::address)
            return AbiType::bytes_n((c & 31u) + 1);
        std::uint64_t n = 0;
        switch (c)
        {
        case code::address:
            return AbiType::address();
        case code::boolean:
            return AbiType::boolean();
        case code::string:
            return AbiType::string();
        case code::bytes:
            return AbiType::bytes();
        case code::function:
            return AbiType::function();
        case code::fixed:
        case code::ufixed:
        {
            // then a byte M/8 - 1, a byte N: an integer of M bits (scaled by 10^N)
            if (end_ - p_ < 2 || p_[0] > 31)
                return std::nullopt;
            const unsigned bits = 8 * (p_[0] + 1u);
            p_ += 2;
            return c == code::fixed ? AbiType::int_n(bits) : AbiType::uint_n(bits);
        }
        case code::array:
            if (auto e = type(depth + 1))
                return AbiType::array(std::move(*e));
            return std::nullopt;
        case code::static_array:
            if (!varint(n))
                return std::nullopt;
            if (auto e = type(depth + 1))
                return AbiType::static_array(std::move(*e), n);
            return std::nullopt;
        case code::tuple:
        {
            if (!varint(n) || n > max_fields)
                return std::nullopt;
            std::vector<AbiType> fields;
            fields.reserve(static_cast<std::size_t>(n));
            for (std::uint64_t i = 0; i < n; ++i)
            {
                std::uint64_t name = 0;
                if (!varint(name))
                    return std::nullopt;
                auto f = type(depth + 1);
                if (!f)
                    return std::nullopt;
                fields.push_back(std::move(*f));
            }
            return AbiType::tuple(std::move(fields));
        }
        case code::storage:
            // a library's reference to storage: a slot
            if (!type(depth + 1))
                return std::nullopt;
            return AbiType::word();
        case code::memory:
        case code::calldata:
            return type(depth + 1);
        case code::named:
            if (!varint(n))
                return std::nullopt;
            return AbiType::word();
        default:
            return std::nullopt;
        }
    }

private:
    bool varint(std::uint64_t& v) noexcept
    {
        v = 0;
        for (unsigned shift = 0; shift < 64; shift += 7)
        {
            if (p_ == end_)
                return false;
            const std::uint8_t b = *p_++;
            if (shift == 63 && b > 1)
                return false;
            v |= std::uint64_t{b & 0x7fu} << shift;
            if (b < 0x80)
                return true;
        }
        return false;
    }

    const std::uint8_t* p_;
    const std::uint8_t* end_;
};

// --- the pseudo-random values -----------------------------------------------------

/// The pseudo-random stream of a call: the world's hashes of (selector,
/// variant, a counter), 64 bits at a time.
class Draw
{
public:
    Draw(const SeededWorld& world, std::uint32_t selector, unsigned variant) noexcept
      : world_{world}, selector_{selector}, variant_{variant}
    {}

    std::uint64_t bits()
    {
        if (left_ == 0)
        {
            std::array<std::uint8_t, 16> key{};
            for (unsigned i = 0; i < 4; ++i)
            {
                key[i] = static_cast<std::uint8_t>(selector_ >> (24 - 8 * i));
                key[4 + i] = static_cast<std::uint8_t>(variant_ >> (24 - 8 * i));
            }
            for (unsigned i = 0; i < 8; ++i)
                key[8 + i] = static_cast<std::uint8_t>(counter_ >> (56 - 8 * i));
            ++counter_;
            pool_ = world_.hash(k_abi, key);
            left_ = 4;
        }
        --left_;
        return static_cast<std::uint64_t>(pool_ >> (64 * left_));
    }

    /// 0 .. n - 1 (0 when n is 0).
    std::uint64_t below(std::uint64_t n) { return n <= 1 ? 0 : bits() % n; }

    Word word()
    {
        Word w = bits();
        for (int i = 0; i < 3; ++i)
            w = (w << 64) | Word{bits()};
        return w;
    }

    /// An index of `weights`, each one weights[i] / their sum of the time.
    unsigned pick(std::initializer_list<unsigned> weights)
    {
        unsigned total = 0;
        for (const auto w : weights)
            total += w;
        auto r = static_cast<unsigned>(below(total));
        unsigned i = 0;
        for (const auto w : weights)
        {
            if (r < w)
                return i;
            r -= w;
            ++i;
        }
        return i - 1;
    }

private:
    const SeededWorld& world_;
    std::uint32_t selector_;
    unsigned variant_;
    std::uint64_t counter_ = 0;
    Word pool_;
    unsigned left_ = 0;
};

/// The values of a call's arguments: `plain` (the call's variant 0) the
/// likeliest to pass the functions' checks (small numbers, the actors, short
/// arrays), else every kind of value that exercises a branch. The dynamic
/// values stop growing once the budget (of bytes) is spent.
class Values
{
public:
    Values(const SeededWorld& world, Draw& draw, bool plain, std::size_t budget)
      : world_{world}, d_{draw}, plain_{plain}, budget_{static_cast<std::int64_t>(budget)}
    {
        const auto b = world.block();
        timestamp_ = b.timestamp;
        number_ = b.number;
        coinbase_ = b.coinbase;
    }

    AbiValue of(const AbiType& t, unsigned nest = 0)
    {
        using K = AbiType::Kind;
        switch (t.kind())
        {
        case K::uint_n:
            return leaf(uint_n(t.bits()));
        case K::int_n:
            return leaf(int_n(t.bits()));
        case K::bytes_n:
            return leaf(bytes_n(t.size()));
        case K::address:
            return leaf(address());
        case K::boolean:
            return leaf(Word{d_.below(2)});
        case K::function:
            return leaf(function());
        case K::word:
            return leaf(word());
        case K::bytes:
            return bytes(false);
        case K::string:
            return bytes(true);
        case K::array:
        {
            const auto& e = t.element();
            budget_ -= 32;
            auto n = length(nest);
            // what each element adds at least: its head, its tail
            const auto slot = e.dynamic() ? 32 + e.min_size() : e.head_size();
            if (slot != 0)
                n = std::min<std::uint64_t>(n, static_cast<std::uint64_t>(std::max<std::int64_t>(budget_, 0)) / slot);
            std::vector<AbiValue> list;
            list.reserve(static_cast<std::size_t>(n));
            for (std::uint64_t i = 0; i < n; ++i)
                list.push_back(of(e, nest + 1));
            return list;
        }
        case K::static_array:
        {
            std::vector<AbiValue> list;
            list.reserve(static_cast<std::size_t>(t.length()));
            for (std::uint64_t i = 0; i < t.length(); ++i)
                list.push_back(of(t.element(), nest));
            return list;
        }
        case K::tuple:
        {
            std::vector<AbiValue> list;
            list.reserve(t.fields().size());
            for (const auto& f : t.fields())
                list.push_back(of(f, nest));
            return list;
        }
        }
        return Word{0};
    }

private:
    AbiValue leaf(Word w)
    {
        budget_ -= 32;
        return w;
    }

    /// v if it is at most max, else v reduced below it.
    static Word fit(const Word& v, const Word& max) { return v <= max ? v : v % (max + 1); }

    const Word& actor(std::size_t i) const
    {
        const auto actors = world_.actors();
        return actors.empty() ? world_.contract_address() : actors[i % actors.size()];
    }
    Word random_address() { return to_address(d_.word()); }

    Word uint_n(unsigned bits)
    {
        const auto max = low_mask(bits);
        if (plain_)
            switch (d_.pick({8, 22, 25, 25, 20}))
            {
            case 0:
                return 0;
            case 1:
                return 1;
            case 2:
                return fit(2 + d_.below(9), max);
            case 3:
                return fit(pow10(1 + static_cast<unsigned>(d_.below(18))), max);
            default:
                return fit(d_.below(1000), max);
            }
        switch (d_.pick({14, 10, 14, 8, 8, 4, 10, 4, 10, 6, 4, 8}))
        {
        case 0:
            return 0;
        case 1:
            return 1;
        case 2:
            return fit(2 + d_.below(62), max);
        case 3:
            return fit(pow10(1 + static_cast<unsigned>(d_.below(30))), max);
        case 4:
            return max;
        case 5:
            return max - 1;
        case 6:
            return Word{1} << static_cast<unsigned>(d_.below(bits));
        case 7:
            return (Word{1} << static_cast<unsigned>(d_.below(bits))) - 1;
        case 8:
            return d_.word() & max;
        case 9:
        {
            // deadlines and block numbers, past and future
            static constexpr std::int64_t deltas[] = {0, 1, 60, 3600, 86400, 31'536'000, -1, -3600};
            const auto delta = deltas[d_.below(std::size(deltas))];
            const auto& base = d_.below(4) == 0 ? number_ : timestamp_;
            return fit(delta >= 0 ? base + Word{static_cast<std::uint64_t>(delta)}
                                  : base - Word{static_cast<std::uint64_t>(-delta)},
                max);
        }
        case 10:
            return bits >= 160 ? actor(d_.below(8)) : fit(2 + d_.below(62), max);
        default:
            return fit(Word{d_.bits() >> 32}, max);
        }
    }

    Word int_n(unsigned bits)
    {
        const auto max = low_mask(bits - 1);       // 2^(bits-1) - 1
        const auto min = ~low_mask(bits - 1);      // -2^(bits-1), sign-extended
        const auto neg = [](const Word& v) { return Word{0} - v; };
        const auto small = [&](std::uint64_t n) { return fit(Word{n}, max); };
        if (plain_)
            switch (d_.pick({10, 25, 25, 10, 15, 15}))
            {
            case 0:
                return 0;
            case 1:
                return 1;
            case 2:
                return small(2 + d_.below(9));
            case 3:
                return word_max;  // -1
            case 4:
                return fit(pow10(1 + static_cast<unsigned>(d_.below(18))), max);
            default:
                return neg(small(2 + d_.below(9)));
            }
        switch (d_.pick({14, 8, 8, 14, 7, 7, 3, 3, 12, 10, 6}))
        {
        case 0:
            return 0;
        case 1:
            return 1;
        case 2:
            return word_max;
        case 3:
        {
            const auto v = small(2 + d_.below(62));
            return d_.below(2) == 0 ? v : neg(v);
        }
        case 4:
            return max;
        case 5:
            return min;
        case 6:
            return max - 1;
        case 7:
            return min + 1;
        case 8:
        {
            // +2^k (k < bits - 1), -2^k (k < bits)
            if (d_.below(2) == 0)
                return Word{1} << static_cast<unsigned>(d_.below(bits - 1));
            return neg(Word{1} << static_cast<unsigned>(d_.below(bits)));
        }
        case 9:
            return sign_extend(d_.word(), bits);
        default:
        {
            const auto v = fit(pow10(1 + static_cast<unsigned>(d_.below(30))), max);
            return d_.below(2) == 0 ? v : neg(v);
        }
        }
    }

    Word address()
    {
        if (plain_)
            switch (d_.pick({30, 40, 15, 15}))
            {
            case 0:
                return actor(0);
            case 1:
                return actor(1 + d_.below(world_.actors().size()));
            case 2:
                return world_.contract_address();
            default:
                return random_address();
            }
        switch (d_.pick({18, 20, 12, 14, 14, 8, 6, 4, 4}))
        {
        case 0:
            return actor(0);
        case 1:
            return actor(1 + d_.below(world_.actors().size()));
        case 2:
            return world_.contract_address();
        case 3:
            return 0;
        case 4:
            return random_address();
        case 5:
        {
            // a word of the world's mix, an address of it
            std::array<std::uint8_t, 8> key{};
            for (unsigned i = 0; i < 8; ++i)
                key[i] = static_cast<std::uint8_t>(d_.bits() >> (8 * i));
            return to_address(world_.word(k_abi, key));
        }
        case 6:
            return 1 + d_.below(16);  // the precompiles' and small ones
        case 7:
            return address_mask;
        default:
            return coinbase_;
        }
    }

    Word bytes_n(unsigned size)
    {
        const unsigned pad = 8 * (32 - size);  // the bits of the padding
        const auto left = [&](const Word& v) { return pad >= 256 ? Word{0} : v << pad; };  // v in its `size` bytes
        const auto value = [&](const Word& v) { return left(v & low_mask(8 * size)); };
        if (plain_)
            switch (d_.pick({20, 50, 30}))
            {
            case 0:
                return 0;
            case 1:
                return value(d_.word());
            default:
                return value(1 + d_.below(16));
            }
        switch (d_.pick({18, 46, 8, 8, 10, 10}))
        {
        case 0:
            return 0;
        case 1:
            return value(d_.word());
        case 2:
            return value(word_max);
        case 3:
            return Word{1 + d_.below(255)} << 248;  // its first byte only
        case 4:
            return value(1 + d_.below(16));  // a small number in its bytes
        default:
        {
            // an address: as a bytes32 holds it (right-aligned), or a bytes20
            const auto a = actor(d_.below(world_.actors().size() + 1));
            return size == 20 ? a << 96 : value(a);
        }
        }
    }

    Word function()
    {
        // an address, then a selector
        const auto a = d_.below(3) == 0 ? world_.contract_address() : actor(d_.below(4));
        const Word selector = d_.below(4) == 0 ? 0 : d_.bits() >> 32;
        return (a << 96) | (selector << 64);
    }

    Word word()
    {
        if (plain_)
            switch (d_.pick({15, 20, 20, 30, 15}))
            {
            case 0:
                return 0;
            case 1:
                return 1;
            case 2:
                return 2 + d_.below(6);
            case 3:
                return actor(d_.below(4));
            default:
                return world_.contract_address();
            }
        switch (d_.pick({20, 10, 15, 18, 10, 10, 10, 7}))
        {
        case 0:
            return 0;
        case 1:
            return 1;
        case 2:
            return 2 + d_.below(6);
        case 3:
            return actor(d_.below(4));
        case 4:
            return world_.contract_address();
        case 5:
            return random_address();
        case 6:
            return d_.word();
        default:
            return word_max;
        }
    }

    /// An array's length: the deeper, the shorter.
    std::uint64_t length(unsigned nest)
    {
        std::uint64_t n = 0;
        if (plain_)
            n = 1 + d_.pick({50, 30, 20});
        else
        {
            // 0, 1, 2, 3, 4-8, 9-32
            const auto k = d_.pick({20, 28, 18, 12, 12, 10});
            n = k < 4 ? k : k == 4 ? 4 + d_.below(5) : 9 + d_.below(24);
        }
        return nest >= 1 ? std::min<std::uint64_t>(n, nest >= 2 ? 2 : 4) : n;
    }

    /// bytes, or a string (text: letters and digits).
    AbiValue bytes(bool text)
    {
        std::size_t n = 0;
        if (plain_)
            switch (d_.pick({30, 30, 40}))
            {
            case 0:
                n = 1 + d_.below(8);
                break;
            case 1:
                n = 32;
                break;
            default:
                n = 9 + d_.below(56);
                break;
            }
        else
            switch (d_.pick({14, 8, 10, 8, 16, 8, 10, 8, 12, 6}))
            {
            case 0:
                n = 0;
                break;
            case 1:
                n = 1;
                break;
            case 2:
                n = 2 + d_.below(29);
                break;
            case 3:
                n = 31;
                break;
            case 4:
                n = 32;
                break;
            case 5:
                n = 33;
                break;
            case 6:
                n = 64;
                break;
            case 7:
                n = 65 + d_.below(63);
                break;
            case 8:
                n = 128 + d_.below(385);
                break;
            default:
                n = 513 + d_.below(988);
                break;
            }
        budget_ -= 32;
        n = std::min<std::size_t>(n, static_cast<std::size_t>(std::max<std::int64_t>(budget_, 0)));
        budget_ -= static_cast<std::int64_t>((n + 31) / 32 * 32);
        Bytes b;
        b.reserve(n + 32);
        if (text)
        {
            static constexpr char letters[] = "abcdefghijklmnopqrstuvwxyz0123456789";
            for (std::size_t i = 0; i < n; ++i)
                b.push_back(static_cast<std::uint8_t>(letters[d_.below(std::size(letters) - 1)]));
            return b;
        }
        const auto content = plain_ ? d_.pick({50, 50, 0}) : d_.pick({30, 45, 15});
        while (b.size() < n)
        {
            // words of the arguments' kinds (an abi.encode of something), or
            // random bytes, or zeros
            Word w = 0;
            if (content == 0)
                w = d_.below(2) == 0 ? actor(d_.below(4)) : Word{d_.below(4) == 0 ? 0 : 1 + d_.below(1000)};
            else if (content == 1)
                w = d_.word();
            const auto chunk = to_bytes(w);
            b.insert(b.end(), chunk.begin(), chunk.begin() + static_cast<std::ptrdiff_t>(std::min<std::size_t>(32, n - b.size())));
        }
        return b;
    }

    const SeededWorld& world_;
    Draw& d_;
    bool plain_;
    std::int64_t budget_;
    Word timestamp_, number_, coinbase_;
};

// --- the encoding -------------------------------------------------------------------

/// Where the parts of an encoding are: what the malformations change.
struct Layout
{
    struct Offset
    {
        std::size_t at;    ///< the offset's word
        std::size_t base;  ///< the start of its tuple: what it is relative to
    };
    struct Length
    {
        std::size_t at;    ///< the length's word
        std::uint64_t unit;  ///< the bytes of an element after it (1: bytes, string)
    };
    struct Narrow
    {
        std::size_t at;
        const AbiType* type;
    };
    std::vector<Offset> offsets;
    std::vector<Length> lengths;
    std::vector<Narrow> narrow;  ///< the words of the narrow types
};

class Encoder
{
public:
    Encoder(Bytes& out, Layout* layout) noexcept : out_{out}, layout_{layout} {}

    bool value(const AbiType& t, const AbiValue& v)
    {
        using K = AbiType::Kind;
        switch (t.kind())
        {
        case K::bytes:
        case K::string:
        {
            const auto* b = std::get_if<Bytes>(&v.value);
            if (b == nullptr)
                return false;
            if (layout_ != nullptr)
                layout_->lengths.push_back({out_.size(), 1});
            append_word(out_, b->size());
            out_.insert(out_.end(), b->begin(), b->end());
            out_.resize(out_.size() + (32 - b->size() % 32) % 32, 0);
            return true;
        }
        case K::array:
        {
            const auto* l = std::get_if<std::vector<AbiValue>>(&v.value);
            if (l == nullptr)
                return false;
            const auto& e = t.element();
            if (layout_ != nullptr)
                layout_->lengths.push_back({out_.size(), e.dynamic() ? 32 : e.head_size()});
            append_word(out_, l->size());
            return sequence([&](std::size_t) -> const AbiType& { return e; }, *l);
        }
        case K::static_array:
        {
            const auto* l = std::get_if<std::vector<AbiValue>>(&v.value);
            if (l == nullptr || l->size() != t.length())
                return false;
            const auto& e = t.element();
            return sequence([&](std::size_t) -> const AbiType& { return e; }, *l);
        }
        case K::tuple:
        {
            const auto* l = std::get_if<std::vector<AbiValue>>(&v.value);
            if (l == nullptr || l->size() != t.fields().size())
                return false;
            return sequence([&](std::size_t i) -> const AbiType& { return t.fields()[i]; }, *l);
        }
        default:
        {
            const auto* w = std::get_if<Word>(&v.value);
            if (w == nullptr)
                return false;
            if (layout_ != nullptr && t.narrow())
                layout_->narrow.push_back({out_.size(), &t});
            append_word(out_, *w);
            return true;
        }
        }
    }

private:
    /// The values of a tuple (T[k]'s, T[]'s elements too): their heads, then
    /// the tails of the dynamic ones, each one's offset in its head.
    template <class TypeAt>
    bool sequence(TypeAt type_at, std::span<const AbiValue> values)
    {
        const auto base = out_.size();
        std::vector<std::size_t> heads;
        for (std::size_t i = 0; i < values.size(); ++i)
        {
            const AbiType& t = type_at(i);
            if (t.dynamic())
            {
                heads.push_back(out_.size());
                if (layout_ != nullptr)
                    layout_->offsets.push_back({out_.size(), base});
                out_.resize(out_.size() + 32, 0);
            }
            else if (!value(t, values[i]))
                return false;
        }
        std::size_t h = 0;
        for (std::size_t i = 0; i < values.size(); ++i)
        {
            const AbiType& t = type_at(i);
            if (!t.dynamic())
                continue;
            put_word(out_, heads[h++], out_.size() - base);
            if (!value(t, values[i]))
                return false;
        }
        return true;
    }

    Bytes& out_;
    Layout* layout_;
};

// --- the malformations ----------------------------------------------------------------

/// A value out of a narrow type's range (v: its value).
Word out_of_range(const AbiType& t, const Word& v, Draw& d)
{
    using K = AbiType::Kind;
    switch (t.kind())
    {
    case K::boolean:
        switch (d.pick({40, 15, 15, 15, 15}))
        {
        case 0:
            return 2;
        case 1:
            return 256;
        case 2:
            return word_max;
        case 3:
            return Word{1} << 255;
        default:
            return 2 + Word{d.bits()};
        }
    case K::address:
        switch (d.pick({40, 15, 15, 15, 15}))
        {
        case 0:
            return v | (Word{1 + d.below(0xffff)} << 160);
        case 1:
            return v | (Word{1} << 255);
        case 2:
            return word_max;
        case 3:
            return Word{1} << 160;
        default:
            return d.word() | (Word{1} << 200);
        }
    case K::uint_n:
    {
        const auto past = Word{1} << t.bits();  // max + 1
        switch (d.pick({35, 15, 20, 30}))
        {
        case 0:
            return past;
        case 1:
            return past + 1 + d.below(100);
        case 2:
            return word_max;
        default:
            return d.word() | past;
        }
    }
    case K::int_n:
    {
        // not the sign extension of `bits` bits
        const auto bits = t.bits();
        switch (d.pick({25, 25, 25, 25}))
        {
        case 0:
            return Word{1} << (bits - 1);  // max + 1
        case 1:
            return low_mask(bits);  // -1, not extended
        case 2:
            return ~low_mask(bits - 1) - 1;  // min - 1
        default:
            return (d.word() & low_mask(bits)) | (Word{1} << bits);
        }
    }
    case K::bytes_n:
    case K::function:
    {
        // something in the padding
        const unsigned pad = t.kind() == K::function ? 64 : 8 * (32 - t.size());
        return v | (d.word() & low_mask(pad)) | 1;
    }
    default:
        return v;
    }
}

/// A bad offset (at: its word, relative to `base`) in data.
Word bad_offset(const Bytes& data, const Layout::Offset& o, Draw& d)
{
    const auto current = get_word(data, o.at);
    const Word past_end = data.size() - o.base;
    Word w = 0;
    switch (d.pick({30, 15, 5, 15, 5, 10, 10, 10}))
    {
    case 0:
        w = past_end + 32 * d.below(3);
        break;
    case 1:
        w = Word{1} << 64;
        break;
    case 2:
        w = low_mask(64);
        break;
    case 3:
        w = word_max;
        break;
    case 4:
        w = Word{1} << 255;
        break;
    case 5:
        w = Word{1} << 32;
        break;
    case 6:
        w = current + 1;  // misaligned
        break;
    default:
        w = current >= 32 ? current - 32 : Word{0};  // into the head
        break;
    }
    return w != current ? w : word_max;
}

/// A bad length (at: its word): its elements would run past the end of the
/// data, or a huge one.
Word bad_length(const Bytes& data, const Layout::Length& l, Draw& d)
{
    const std::uint64_t remaining = data.size() - (l.at + 32);
    const Word least = l.unit == 0 ? Word{1} << 64 : Word{remaining / l.unit + 1};
    switch (d.pick({35, 10, 15, 10, 15, 5, 10}))
    {
    case 0:
        return least;
    case 1:
        return least + 1 + d.below(32);
    case 2:
        return std::max(least, Word{1} << 64);
    case 3:
        return std::max(least, Word{1} << 32);
    case 4:
        return word_max;
    case 5:
        return Word{1} << 255;
    default:
        return std::max(least, low_mask(64));
    }
}

/// One malformation of data (not empty): its kind drawn, the next one when
/// the encoding has nothing of that kind.
Malformation malform(Bytes& data, const Layout& layout, Draw& d)
{
    const auto first = d.pick({35, 20, 20, 25});
    for (unsigned i = 0; i < 4; ++i)
        switch ((first + i) % 4)
        {
        case 0:
            if (!layout.narrow.empty())
            {
                const auto& n = layout.narrow[d.below(layout.narrow.size())];
                put_word(data, n.at, out_of_range(*n.type, get_word(data, n.at), d));
                return Malformation::out_of_range;
            }
            break;
        case 1:
            if (!layout.offsets.empty())
            {
                const auto& o = layout.offsets[d.below(layout.offsets.size())];
                put_word(data, o.at, bad_offset(data, o, d));
                return Malformation::bad_offset;
            }
            break;
        case 2:
            if (!layout.lengths.empty())
            {
                const auto& l = layout.lengths[d.below(layout.lengths.size())];
                put_word(data, l.at, bad_length(data, l, d));
                return Malformation::bad_length;
            }
            break;
        default:
        {
            // a few bytes, a word, anywhere, all of the arguments
            const auto size = data.size();
            std::size_t cut = 0;
            switch (d.pick({35, 25, 25, 15}))
            {
            case 0:
                cut = 1 + d.below(31);
                break;
            case 1:
                cut = 32;
                break;
            case 2:
                cut = 1 + d.below(size);
                break;
            default:
                cut = size;
                break;
            }
            data.resize(size - std::min(cut, size));
            return Malformation::short_data;
        }
        }
    return Malformation::none;
}

void append_selector(Bytes& out, std::uint32_t selector)
{
    for (int i = 3; i >= 0; --i)
        out.push_back(static_cast<std::uint8_t>(selector >> (8 * i)));
}
}  // namespace

// --- AbiType ----------------------------------------------------------------------------

AbiType::AbiType(Kind kind, unsigned bits, std::uint64_t length, std::vector<AbiType> children)
  : kind_{kind}, bits_{bits}, length_{length}, children_{std::move(children)}
{
    switch (kind_)
    {
    case Kind::bytes:
    case Kind::string:
    case Kind::array:
        dynamic_ = true;  // its length, at least
        break;
    case Kind::static_array:
    {
        const auto& e = children_.front();
        dynamic_ = e.dynamic_;
        min_ = mul_sat(length_, e.dynamic_ ? add_sat(32, e.min_) : e.head_);
        head_ = dynamic_ ? 32 : min_;
        break;
    }
    case Kind::tuple:
    {
        std::uint64_t min = 0;
        for (const auto& f : children_)
        {
            dynamic_ = dynamic_ || f.dynamic_;
            min = add_sat(min, f.dynamic_ ? add_sat(32, f.min_) : f.head_);
        }
        min_ = min;
        head_ = dynamic_ ? 32 : min_;
        break;
    }
    default:  // a word
        break;
    }
}

std::optional<AbiType> AbiType::from_code(std::span<const std::uint8_t> code)
{
    CodeReader reader{code};
    auto t = reader.type();
    if (!t || !reader.at_end() || t->min_size() > max_head)
        return std::nullopt;
    return t;
}

AbiType AbiType::uint_n(unsigned bits)
{
    assert(bits >= 8 && bits <= 256 && bits % 8 == 0);
    return {Kind::uint_n, bits, 0, {}};
}

AbiType AbiType::int_n(unsigned bits)
{
    assert(bits >= 8 && bits <= 256 && bits % 8 == 0);
    return {Kind::int_n, bits, 0, {}};
}

AbiType AbiType::bytes_n(unsigned size)
{
    assert(size >= 1 && size <= 32);
    return {Kind::bytes_n, 8 * size, 0, {}};
}

AbiType AbiType::address()
{
    return {Kind::address, 0, 0, {}};
}

AbiType AbiType::boolean()
{
    return {Kind::boolean, 0, 0, {}};
}

AbiType AbiType::function()
{
    return {Kind::function, 0, 0, {}};
}

AbiType AbiType::word()
{
    return {Kind::word, 0, 0, {}};
}

AbiType AbiType::bytes()
{
    return {Kind::bytes, 0, 0, {}};
}

AbiType AbiType::string()
{
    return {Kind::string, 0, 0, {}};
}

AbiType AbiType::array(AbiType element)
{
    std::vector<AbiType> e;
    e.push_back(std::move(element));
    return {Kind::array, 0, 0, std::move(e)};
}

AbiType AbiType::static_array(AbiType element, std::uint64_t length)
{
    std::vector<AbiType> e;
    e.push_back(std::move(element));
    return {Kind::static_array, 0, length, std::move(e)};
}

AbiType AbiType::tuple(std::vector<AbiType> fields)
{
    return {Kind::tuple, 0, 0, std::move(fields)};
}

bool AbiType::narrow() const noexcept
{
    switch (kind_)
    {
    case Kind::uint_n:
    case Kind::int_n:
    case Kind::bytes_n:
        return bits_ < 256;
    case Kind::address:
    case Kind::boolean:
    case Kind::function:
        return true;
    default:
        return false;
    }
}

// --- the encodings ------------------------------------------------------------------------

std::optional<Bytes> abi_encode(const AbiType& type, const AbiValue& value)
{
    Bytes out;
    if (!Encoder{out, nullptr}.value(type, value))
        return std::nullopt;
    return out;
}

AbiCall abi_call(std::uint32_t selector, const AbiType& params, unsigned variant,
    const SeededWorld& world, const AbiConfig& config)
{
    assert(params.kind() == AbiType::Kind::tuple);
    AbiCall call;
    append_selector(call.calldata, selector);
    Draw draw{world, selector, variant};
    const auto args = Values{world, draw, variant == 0, config.budget}.of(params);
    Bytes data;
    Layout layout;
    const bool encoded = Encoder{data, &layout}.value(params, args);
    assert(encoded);  // (the values are of the types' shapes)
    (void)encoded;
    if (!data.empty() && draw.below(100) < config.malformed_percent)
        call.malformation = malform(data, layout, draw);
    call.calldata.insert(call.calldata.end(), data.begin(), data.end());
    return call;
}

// --- AbiEncoder -------------------------------------------------------------------------------

AbiEncoder::AbiEncoder(const pan::sigdb::Database& db, AbiConfig config) : db_{&db}, config_{config} {}

std::optional<AbiType> AbiEncoder::params(std::uint32_t selector) const
{
    const auto entry = db_->function(selector);
    if (!entry || entry->kind() == pan::sigdb::Kind::event)
        return std::nullopt;
    const auto params = entry->params();
    if (params.size() > max_fields)
        return std::nullopt;
    std::vector<AbiType> fields;
    fields.reserve(params.size());
    for (const auto p : params)
    {
        auto t = AbiType::from_code(p.type().code());
        if (!t)
            return std::nullopt;
        fields.push_back(std::move(*t));
    }
    auto tuple = AbiType::tuple(std::move(fields));
    if (tuple.min_size() > AbiType::max_head)
        return std::nullopt;
    return tuple;
}

std::optional<Bytes> AbiEncoder::operator()(std::uint32_t selector, unsigned variant,
    const SeededWorld& world) const
{
    const auto p = params(selector);
    if (!p)
        return std::nullopt;
    return abi_call(selector, *p, variant, world, config_).calldata;
}
}  // namespace validate
