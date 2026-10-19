// The effects of a call, the ordered record both sides of the comparison
// make (evmone's through evm_runner.hpp, the interpreters' through
// session.hpp), and their comparison.
//
// Gas is never part of them: not the gas of the external calls, not the gas
// left. What still depends on gas: the budget an execution has (evmone's gas,
// the interpreters' steps and memory) - running out of it is the end
// `exhausted`, which makes the comparison inconclusive, never different.
// evmone reports memory offsets/sizes of 2^32 and more as out of gas:
// exhausted too.
#pragma once

#include "world.hpp"

#include <map>
#include <optional>
#include <string>
#include <variant>
#include <vector>

namespace validate
{
/// SSTORE (of the contract's storage).
struct StorageWrite
{
    Word slot;
    Word value;
    friend bool operator==(const StorageWrite&, const StorageWrite&) = default;
};

/// TSTORE (EIP-1153: zero at the start of every call, never carried over).
struct TransientWrite
{
    Word slot;
    Word value;
    friend bool operator==(const TransientWrite&, const TransientWrite&) = default;
};

/// LOG0..LOG4 (of the contract).
struct Log
{
    std::vector<Word> topics;
    Bytes data;
    friend bool operator==(const Log&, const Log&) = default;
};

/// CALL, STATICCALL, DELEGATECALL, CALLCODE that reached the world (not the
/// light failures: a value above the balance). No gas. value: 0 for
/// staticcall and delegatecall. The result is the world's answer (a function
/// of the rest), recorded for the display, never compared.
struct ExternalCall
{
    CallKind kind = CallKind::call;
    Word target;
    Word value;
    Bytes input;
    bool precompile = false;  ///< target 0x01..0x11, 0x100: computed, not the world's
    CallResult result;
    friend bool operator==(const ExternalCall&, const ExternalCall&) = default;
};

/// CREATE, CREATE2 that reached the world. The address is what's compared:
/// it is a function of the salt and the init code for CREATE2 (evmone never
/// tells the salt: salt is filled by the interpreters only, for the display).
struct Creation
{
    CreateKind kind = CreateKind::create;
    Word value;
    Bytes init_code;
    std::optional<Word> salt;
    Word address;
    CallResult result;
    friend bool operator==(const Creation&, const Creation&) = default;
};

/// SELFDESTRUCT: the balance goes to the beneficiary (EIP-6780: the code
/// stays); the call ends with `stop`.
struct SelfDestruct
{
    Word beneficiary;
    friend bool operator==(const SelfDestruct&, const SelfDestruct&) = default;
};

using Event = std::variant<StorageWrite, TransientWrite, Log, ExternalCall, Creation, SelfDestruct>;

/// How a call ended.
enum class Status : std::uint8_t
{
    stop,         ///< STOP, the end of the code, SELFDESTRUCT (= return_ of no data)
    return_,      ///< RETURN(data)
    revert,       ///< REVERT(data)
    invalid,      ///< an exceptional halt: no data, nothing persists (see Fault)
    exhausted,    ///< the gas, steps, memory or time ran out: inconclusive
    unsupported,  ///< the side cannot execute the call exactly: inconclusive
    error,        ///< the harness failed: inconclusive
};

/// Why a call ended `invalid` (displayed; compared only on request).
enum class Fault : std::uint8_t
{
    none,
    invalid_instruction,    ///< INVALID (0xfe)
    undefined_instruction,  ///< an opcode the revision doesn't define
    bad_jump,               ///< JUMP/JUMPI to something else than a JUMPDEST
    stack_underflow,
    stack_overflow,
    static_violation,       ///< a state change in a static call
    memory_access,          ///< RETURNDATACOPY past the end of the return data
    other,
};

struct End
{
    Status status = Status::error;
    Fault fault = Fault::none;
    Bytes data;        ///< the data of RETURN / REVERT
    std::string note;  ///< why exhausted / unsupported / error (free text, not compared)

    static End stop() { return {Status::stop, Fault::none, {}, {}}; }
    static End returned(Bytes data) { return {Status::return_, Fault::none, std::move(data), {}}; }
    static End reverted(Bytes data) { return {Status::revert, Fault::none, std::move(data), {}}; }
    static End invalid(Fault fault) { return {Status::invalid, fault, {}, {}}; }
    static End exhausted(std::string note = {}) { return {Status::exhausted, Fault::none, {}, std::move(note)}; }
    static End unsupported(std::string note) { return {Status::unsupported, Fault::none, {}, std::move(note)}; }
    static End error(std::string note) { return {Status::error, Fault::none, {}, std::move(note)}; }

    /// stop or return: the call's changes persist.
    bool success() const noexcept { return status == Status::stop || status == Status::return_; }
    /// exhausted, unsupported or error: nothing can be concluded.
    bool inconclusive() const noexcept { return status >= Status::exhausted; }
};

/// The record of one call.
struct Effects
{
    std::vector<Event> events;  ///< in the order of the call, failed or not
    End end;
    /// The contract's slots whose value at the end differs from the one at
    /// the start, with their final values: empty when the call failed.
    std::map<Word, Word> storage_diff;
};

struct CompareOptions
{
    /// Compare the order of the storage writes among the other events (by
    /// default only the final storage diff is compared, and the order of the
    /// logs, calls, creations and selfdestructs among themselves).
    bool write_order = false;
    bool transient = false;      ///< compare the TSTOREs (in order)
    bool precompiles = false;    ///< compare the calls to precompiles
    bool failed_events = false;  ///< compare the events of a call that failed too
    bool faults = false;         ///< compare why the `invalid` ends happened
};

enum class Verdict : std::uint8_t
{
    same,
    different,
    inconclusive,  ///< one side exhausted, unsupported or error
};

struct Comparison
{
    Verdict verdict = Verdict::same;
    std::string message;  ///< the first difference, readable (or why inconclusive)
};

/// Compares the effects of the same call on both sides: `expected` is
/// evmone's, `actual` the decompiled result's.
Comparison compare(const Effects& expected, const Effects& actual, const CompareOptions& options = {});

/// Readable forms (hex: 0x-prefixed, lowercase; words without leading zeros).
std::string hex(BytesView bytes);
std::string hex(const Word& word);
std::string to_string(CallKind kind);
std::string to_string(CreateKind kind);
std::string to_string(Status status);
std::string to_string(Fault fault);
std::string to_string(const Event& event);
std::string to_string(const End& end);
std::string to_string(const Effects& effects);  ///< one line per event, then the end, then the diff
}  // namespace validate
