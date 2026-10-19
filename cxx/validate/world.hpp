// The world of the validation by execution (AGENTS.md rule 5): everything a
// contract can read, shared by both sides of the comparison - evmone running
// the bytecode (evm_runner.hpp) and the interpreters of the decompiled result
// - so that, given the same calls, both see exactly the same answers.
//
//   World        the state before the calls, an abstract interface: every
//                answer is a pure function of its key, never of the order
//                of the reads.
//   SeededWorld  its deterministic pseudo-random implementation: every value
//                is keccak(seed, kind, key) made into a word; two modes,
//                empty (storage zero, no other contract) and random.
//   State        the world plus what the calls of a sequence changed
//                (storage, balances, nonces, created accounts), carried
//                from one call to the next.
//   Session      (session.hpp) one call executed against a State: answers
//                the reads, applies the EVM's rules to the external calls,
//                records the Effects (effects.hpp).
//
// Every EVM value is a Word (intx::uint256), addresses too (below 2^160).
// Nothing here depends on gas: external calls are never executed (their
// results come from the World), GAS gives `fixed_gas`.
#pragma once

#include <intx/intx.hpp>

#include <array>
#include <cstddef>
#include <cstdint>
#include <map>
#include <set>
#include <span>
#include <vector>

namespace validate
{
using Word = intx::uint256;
using Bytes = std::vector<std::uint8_t>;
using BytesView = std::span<const std::uint8_t>;

inline constexpr Word address_mask = (Word{1} << 160) - 1;

constexpr Word to_address(const Word& w) noexcept
{
    return w & address_mask;
}

/// What GAS (gasleft()) gives, on both sides: gas never matters. (evmone is
/// patched for it: EVMONE_FIXED_GAS in validate/Makefile.inc, the same value.)
inline constexpr std::int64_t fixed_gas = 30'000'000;

/// keccak-256 (KECCAK256's) of bytes, as a word.
Word keccak256(BytesView data) noexcept;
/// The 32 bytes of a word, big-endian (the EVM's memory order).
std::array<std::uint8_t, 32> to_bytes(const Word& w) noexcept;
/// The word of the 32 bytes of `data` at `offset`, big-endian, zero past its
/// end (CALLDATALOAD's rule).
Word load_word(BytesView data, const Word& offset) noexcept;
/// Appends the 32 bytes of a word.
void append_word(Bytes& out, const Word& w);

/// The address CREATE makes: keccak(rlp([sender, nonce]))[12:].
Word create_address(const Word& sender, std::uint64_t nonce) noexcept;
/// The address CREATE2 makes: keccak(0xff ++ sender ++ salt ++ keccak(init_code))[12:].
Word create2_address(const Word& sender, const Word& salt, BytesView init_code) noexcept;

/// The precompiled contracts of the revision (Osaka): 0x01..0x11 and 0x100.
bool is_precompile(const Word& address) noexcept;

enum class CallKind : std::uint8_t
{
    call,
    staticcall,
    delegatecall,
    callcode,
};

enum class CreateKind : std::uint8_t
{
    create,
    create2,
};

/// The block of a call. number, timestamp and gas_limit are below 2^63.
struct BlockContext
{
    Word number{};                    ///< NUMBER
    Word timestamp{};                 ///< TIMESTAMP
    Word coinbase{};                  ///< COINBASE
    Word prevrandao{};                ///< PREVRANDAO (DIFFICULTY)
    Word gas_limit{};                 ///< GASLIMIT
    Word chain_id{};                  ///< CHAINID
    Word base_fee{};                  ///< BASEFEE
    Word blob_base_fee{};             ///< BLOBBASEFEE
    std::vector<Word> blob_hashes{};  ///< BLOBHASH(i), zero past the end
};

/// The inputs of one call of the contract (its address is the State's).
struct CallContext
{
    Word caller{};     ///< CALLER
    Word origin{};     ///< ORIGIN
    Word value{};      ///< CALLVALUE
    Word gas_price{};  ///< GASPRICE
    Bytes calldata{};  ///< CALLDATALOAD, CALLDATASIZE, CALLDATACOPY
};

/// What an external call gives back (or a creation: output = its revert data).
struct CallResult
{
    bool success = false;
    Bytes output{};  ///< the return data (RETURNDATASIZE, RETURNDATACOPY)

    friend bool operator==(const CallResult&, const CallResult&) = default;
};

/// What a creation gives back: the new address (0 when it failed) and the
/// return data (empty when it succeeded, the revert data when it failed).
struct CreateResult
{
    bool success = false;
    Word address{};
    Bytes output{};

    friend bool operator==(const CreateResult&, const CreateResult&) = default;
};

/// Everything a contract can read of the world before the calls: pure
/// functions (the same key, the same answer, whatever was asked before).
/// Thread-safe: the methods are const and keep no state.
class World
{
public:
    virtual ~World() = default;

    /// A storage slot of an account, before any write.
    virtual Word storage(const Word& account, const Word& slot) const = 0;
    /// The balance of an account (the contract's before its first call).
    virtual Word balance(const Word& account) const = 0;
    virtual std::uint64_t nonce(const Word& account) const = 0;
    /// The code of an account other than the contract under test (EXTCODE*);
    /// never starts with 0xef (no EIP-7702 delegation).
    virtual Bytes code(const Word& account) const = 0;
    /// The hash of a block (asked for the 256 blocks before block().number only).
    virtual Word block_hash(const Word& number) const = 0;
    /// The block of the calls.
    virtual BlockContext block() const = 0;
    /// The result of an external call to an account with code, other than a
    /// precompile: a function of its kind, target, value and input only (no
    /// gas, no order, no re-entrance). value is 0 for staticcall and
    /// delegatecall.
    virtual CallResult call(CallKind kind, const Word& target, const Word& value,
        BytesView input) const = 0;
    /// Whether a creation at `address` succeeds (its init code is never run),
    /// and its revert data when it fails.
    virtual CallResult create(CreateKind kind, const Word& address, const Word& value,
        BytesView init_code) const = 0;
};

/// The weights of the kinds of words the random world makes (each one the
/// fraction weight / sum of the weights).
struct WordMix
{
    unsigned zero = 30;     ///< 0
    unsigned one = 10;      ///< 1
    unsigned small = 20;    ///< 2..63: lengths, counts, enums, indices
    unsigned address = 25;  ///< an address: an actor, the contract, or any
    unsigned large = 10;    ///< any 256-bit word
    unsigned max = 5;       ///< 2^256 - 1
};

struct WorldConfig
{
    std::uint64_t seed = 0;
    /// false: the empty world - storage zero, the other accounts empty (no
    /// code, no balance), so the calls to them succeed with no data.
    bool random = true;
    WordMix mix{};
    unsigned contracts_percent = 75;  ///< of the other accounts with code (random world)
    unsigned call_success_percent = 85;
    unsigned create_success_percent = 90;
    unsigned actors = 4;  ///< the addresses that make the calls (the first: the default caller)
};

/// The deterministic pseudo-random world: every value is a function of
/// (seed, kind, key), keccak of their encoding made into a word of the mix.
class SeededWorld final : public World
{
public:
    explicit SeededWorld(const WorldConfig& config = {});

    Word storage(const Word& account, const Word& slot) const override;
    Word balance(const Word& account) const override;
    std::uint64_t nonce(const Word& account) const override;
    Bytes code(const Word& account) const override;
    Word block_hash(const Word& number) const override;
    BlockContext block() const override;
    CallResult call(CallKind kind, const Word& target, const Word& value,
        BytesView input) const override;
    CallResult create(CreateKind kind, const Word& address, const Word& value,
        BytesView init_code) const override;

    const WorldConfig& config() const noexcept { return config_; }
    /// The address of the contract under test (a suggestion: State takes any).
    const Word& contract_address() const noexcept { return contract_; }
    /// The accounts that make the calls (EOAs), also the addresses the
    /// world's words and the calldata generator pick, so that the
    /// msg.sender == owner kinds of branches go both ways.
    std::span<const Word> actors() const noexcept { return actors_; }
    /// A word of the mix, a function of (seed, kind, key): for the other
    /// pseudo-random needs (the calldata generator...). kind: any tag of the
    /// caller's, the world's own are below 0x80.
    Word word(std::uint8_t kind, BytesView key) const;
    /// A pseudo-random word (uniform), a function of (seed, kind, key).
    Word hash(std::uint8_t kind, BytesView key) const;

private:
    Word mixed(const Word& random) const;

    WorldConfig config_;
    Word contract_;
    std::vector<Word> actors_;
};

/// The world plus what the calls of a sequence changed, carried from one call
/// to the next (a Session commits its changes when its call succeeds).
class State
{
public:
    /// `address`: the contract under test (ADDRESS), `code` its runtime code.
    State(const World& world, const Word& address, Bytes code);

    const World& world() const noexcept { return *world_; }
    const Word& address() const noexcept { return address_; }
    BytesView code() const noexcept { return code_; }

    /// The block of the next calls (World::block() at first: free to change
    /// between the calls).
    BlockContext block;

    /// The values the next call starts from.
    Word storage(const Word& slot) const;  ///< the contract's
    Word balance(const Word& account) const;
    std::uint64_t nonce(const Word& account) const;
    /// The code of an account: the contract's own, a created account's
    /// (`created_code`), or the World's.
    Bytes code_of(const Word& account) const;
    bool created(const Word& account) const { return created_.contains(account); }

    /// The contract's slots written so far, with their current values.
    const std::map<Word, Word>& written_storage() const noexcept { return storage_; }

    /// The code of the accounts created in the sequence (their init code is
    /// never run): one STOP.
    static constexpr std::uint8_t created_code = 0x00;

private:
    friend class Session;

    const World* world_;
    Word address_;
    Bytes code_;
    std::map<Word, Word> storage_;          // the contract's written slots
    std::map<Word, Word> balances_;         // the balances changed
    std::map<Word, std::uint64_t> nonces_;  // the nonces changed
    std::set<Word> created_;                // the accounts created
};
}  // namespace validate
