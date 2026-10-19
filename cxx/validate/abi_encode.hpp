// Typed calldata for the validation (calls.hpp: CallGenerator::Encoder): the
// arguments of the functions the signature database knows, ABI-encoded from
// their parameters' types - the database's codes (src/sigdb.hpp: Type), never
// their text (AGENTS.md rule 1) - with values that exercise the branches of
// the functions: 0, 1, small, the type's max and min, max - 1, powers of two,
// the world's addresses (its actors, the contract, zero), arrays of 0, 1 or a
// few elements, bytes and strings of 0, 1, 31, 32, 33, 64 and more bytes.
// Now and then (AbiConfig::malformed_percent) the encoding is malformed, for
// the functions' own checks: a value out of its type's range (an address
// with high bits, a bool 2, a uint8 256), the calldata cut short, a bad
// offset or length. Everything is a function of the world's seed, the
// selector and the variant of the call. The selectors the database doesn't
// know keep the generator's untyped words.
//
// The encoding is the Solidity ABI's ("Contract ABI Specification"): a tuple
// is the heads of its elements, then the tails of the dynamic ones (string,
// bytes, T[], and T[k] or a tuple holding one), each head of those an offset
// from the start of the tuple; T[k] is a tuple of k T; T[] is its length,
// then the tuple of its elements; bytes and string their length, then their
// bytes padded to a word; uint<N>, address, bool a word, padded on the left;
// int<N> sign-extended; bytes<N> and function left-aligned.
#pragma once

#include "calls.hpp"
#include "world.hpp"

#include <cstdint>
#include <optional>
#include <span>
#include <variant>
#include <vector>

namespace pan::sigdb
{
class Database;
}

namespace validate
{
/// An ABI type, read from its code in the signature database. Holds what the
/// encoding needs: the parameters' names, and the text of the named types,
/// aren't read.
class AbiType
{
public:
    enum class Kind : std::uint8_t
    {
        uint_n,        ///< uint<bits()>; also ufixed<bits()>x<N> (its integer)
        int_n,         ///< int<bits()>, sign-extended; also fixed<bits()>x<N>
        bytes_n,       ///< bytes<size()>, left-aligned
        address,
        boolean,
        function,      ///< an address and a selector, left-aligned (bytes24)
        word,          ///< a word of no known range: a named type (a contract, an
                       ///< enum, a struct of a library), a reference to storage
        bytes,
        string,
        array,         ///< element()[]
        static_array,  ///< element()[length()]
        tuple,         ///< fields()
    };

    /// The longest head of a type (a static array's, a tuple's) that is
    /// encoded, in bytes: a uint256[1000000] parameter is not.
    static constexpr std::uint64_t max_head = 1 << 16;

    /// The type of a code of the signature database (sigdb.hpp: Type::code(),
    /// the whole span): nullopt when it isn't one, or it is too large to
    /// encode (max_head).
    static std::optional<AbiType> from_code(std::span<const std::uint8_t> code);

    static AbiType uint_n(unsigned bits);   ///< bits: 8 .. 256, a multiple of 8
    static AbiType int_n(unsigned bits);
    static AbiType bytes_n(unsigned size);  ///< 1 .. 32
    static AbiType address();
    static AbiType boolean();
    static AbiType function();
    static AbiType word();
    static AbiType bytes();
    static AbiType string();
    static AbiType array(AbiType element);
    static AbiType static_array(AbiType element, std::uint64_t length);
    static AbiType tuple(std::vector<AbiType> fields);  ///< a function's parameters too

    Kind kind() const noexcept { return kind_; }
    /// uint_n, int_n: 8 .. 256; bytes_n: 8 size(); 0 for the rest.
    unsigned bits() const noexcept { return bits_; }
    unsigned size() const noexcept { return kind_ == Kind::bytes_n ? bits_ / 8 : 0; }
    std::uint64_t length() const noexcept { return length_; }
    const AbiType& element() const noexcept { return children_.front(); }  ///< array, static_array
    std::span<const AbiType> fields() const noexcept { return children_; }  ///< tuple
    /// Encoded as an offset in the head of its tuple.
    bool dynamic() const noexcept { return dynamic_; }
    /// The size of its head: 32 when it is dynamic, else that of its whole
    /// encoding (saturated past max_head).
    std::uint64_t head_size() const noexcept { return head_; }
    /// The size of its shortest encoding: its arrays empty, its bytes too
    /// (saturated past max_head).
    std::uint64_t min_size() const noexcept { return min_; }
    /// A word whose values aren't all valid: uint<N> and int<N> of N < 256,
    /// bytes<N> of N < 32, address, bool, function.
    bool narrow() const noexcept;

private:
    AbiType(Kind kind, unsigned bits, std::uint64_t length, std::vector<AbiType> children);

    Kind kind_;
    unsigned bits_ = 0;
    std::uint64_t length_ = 0;
    bool dynamic_ = false;
    std::uint64_t head_ = 32;
    std::uint64_t min_ = 32;
    std::vector<AbiType> children_;
};

/// A value of an ABI type: a word (an elementary type, as it is encoded: an
/// int sign-extended, a bytes<N> left-aligned), bytes (bytes, string), or
/// the values of a list (T[], T[k], a tuple's fields).
struct AbiValue
{
    std::variant<Word, Bytes, std::vector<AbiValue>> value;

    AbiValue() = default;
    AbiValue(Word w) : value{std::move(w)} {}
    AbiValue(Bytes b) : value{std::move(b)} {}
    AbiValue(std::vector<AbiValue> list) : value{std::move(list)} {}
};

/// The ABI encoding of a value of a type (a function's arguments: the tuple
/// of its parameters, without the selector). The words are written as they
/// are (a uint8 of 256 too); nullopt when the value isn't of the type's
/// shape (a word for a list, a list of another length than a T[k]'s).
std::optional<Bytes> abi_encode(const AbiType& type, const AbiValue& value);

/// How a call's encoding was made malformed.
enum class Malformation : std::uint8_t
{
    none,
    out_of_range,  ///< a value out of its type's range
    short_data,    ///< the calldata cut short
    bad_offset,    ///< an offset past the end, huge or misaligned
    bad_length,    ///< a length of more than the calldata holds, or huge
};

struct AbiConfig
{
    /// Of the calls with arguments: a malformed encoding.
    unsigned malformed_percent = 10;
    /// The bytes of arguments the dynamic values (arrays, bytes, string)
    /// may add, at most: past them, they are empty.
    std::size_t budget = 16 << 10;
};

/// A typed call: its calldata and how it was malformed.
struct AbiCall
{
    Bytes calldata;  ///< the selector, then the arguments
    Malformation malformation = Malformation::none;
};

/// The call of a function whose parameters are `params` (a tuple): its
/// selector, then values of their types drawn from the world's seed, the
/// selector and the variant (variant 0: the plainest values: small numbers,
/// the actors, short arrays), malformed in config.malformed_percent of the
/// calls.
AbiCall abi_call(std::uint32_t selector, const AbiType& params, unsigned variant,
    const SeededWorld& world, const AbiConfig& config = {});

/// CallGenerator's Encoder of typed arguments (set_encoder): abi_call()
/// with the parameters the signature database gives a selector; nullopt for
/// a selector it doesn't know (or an event's, or types too large to
/// encode): the generator's untyped words then. Copyable, thread-safe; the
/// database must outlive it.
class AbiEncoder
{
public:
    explicit AbiEncoder(const pan::sigdb::Database& db, AbiConfig config = {});

    /// The parameters of a selector's function (a tuple), or nullopt.
    std::optional<AbiType> params(std::uint32_t selector) const;
    bool knows(std::uint32_t selector) const { return params(selector).has_value(); }

    std::optional<Bytes> operator()(std::uint32_t selector, unsigned variant, const SeededWorld& world) const;

    const AbiConfig& config() const noexcept { return config_; }

private:
    const pan::sigdb::Database* db_;
    AbiConfig config_;
};
}  // namespace validate
