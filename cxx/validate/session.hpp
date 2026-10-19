// One call of the contract executed against a State: the single place where
// both sides of the comparison read the world and make their effects, so
// that the EVM's rules apply the same way to both. evmone's host
// (evm_runner.cpp) and the interpreters of the decompiled result call it for
// every instruction that touches the world:
//
//   SLOAD sload  SSTORE sstore  TLOAD tload  TSTORE tstore  BALANCE balance
//   SELFBALANCE balance(address())  EXTCODESIZE code_size  EXTCODEHASH
//   code_hash  EXTCODECOPY code_of  BLOCKHASH block_hash  BLOBHASH blob_hash
//   LOGn log  CALL/STATICCALL/DELEGATECALL/CALLCODE call  CREATE/CREATE2
//   create  SELFDESTRUCT selfdestruct (then finish(End::stop()))
//   ADDRESS address()  CODESIZE/CODECOPY code()  CALLER ORIGIN CALLVALUE
//   GASPRICE CALLDATA* context()  NUMBER TIMESTAMP COINBASE PREVRANDAO
//   GASLIMIT CHAINID BASEFEE BLOBBASEFEE block()  GAS fixed_gas
//
// and ends with finish(end), which commits the call's changes to the State
// when it succeeded (stop, return) and drops them otherwise.
//
// The EVM's rules applied here: the call's value is credited to the contract
// before its code runs; a CALL/CALLCODE (or a creation) with a value above
// the contract's balance fails without reaching the world (a "light
// failure": success 0, no data, no event); a call to an account without
// code succeeds with no data; the precompiles are computed (not the world's);
// value transfers move balances; CREATE's address comes from the contract's
// nonce, which every creation that reaches the world increments; a created
// account's code is one STOP (its init code never runs); SELFDESTRUCT moves
// the balance (EIP-6780: the code stays). Not modeled: the caller paying the
// value or the gas, address collisions of the creations, re-entrance.
//
// Limits: at most `max_events` events (a memory limit), past it the end is
// `exhausted`.
#pragma once

#include "effects.hpp"
#include "world.hpp"

#include <map>
#include <set>
#include <span>
#include <vector>

namespace validate
{
class Session
{
public:
    Session(State& state, CallContext context);
    Session(const Session&) = delete;
    Session& operator=(const Session&) = delete;

    const State& state() const noexcept { return *state_; }
    const CallContext& context() const noexcept { return context_; }
    const BlockContext& block() const noexcept { return state_->block; }
    const Word& address() const noexcept { return state_->address(); }  ///< ADDRESS
    BytesView code() const noexcept { return state_->code(); }          ///< CODESIZE, CODECOPY

    // The reads: the call's own changes first, then the State's, then the World's.
    Word sload(const Word& slot) const;
    Word tload(const Word& slot) const;
    Word balance(const Word& account) const;  ///< the contract's includes the call's value
    std::uint64_t nonce(const Word& account) const;
    bool account_exists(const Word& account) const;  ///< has code, balance or nonce
    Word code_size(const Word& account) const;
    Word code_hash(const Word& account) const;  ///< 0 for an account that doesn't exist
    Bytes code_of(const Word& account) const;
    Word block_hash(const Word& number) const;  ///< 0 outside the 256 blocks before block().number
    Word blob_hash(const Word& index) const;    ///< 0 past the end

    // The changes, recorded in the effects.
    void sstore(const Word& slot, const Word& value);
    void tstore(const Word& slot, const Word& value);
    void log(std::span<const Word> topics, BytesView data);
    /// An external call. value: ignored (0) for staticcall and delegatecall.
    CallResult call(CallKind kind, const Word& target, const Word& value, BytesView input);
    /// A creation: its address computed here (salt: CREATE2's).
    CreateResult create(CreateKind kind, const Word& value, BytesView init_code, const Word& salt = 0);
    /// A creation whose address the VM computed (evmone: from nonce(address())
    /// or the salt), the light failures checked already.
    CreateResult create_at(CreateKind kind, const Word& address, const Word& value, BytesView init_code);
    void selfdestruct(const Word& beneficiary);

    const std::vector<Event>& events() const noexcept { return events_; }

    /// The events a call may make (a memory limit): past it they're not
    /// recorded, and the call ends `exhausted`.
    std::size_t max_events = 100'000;

    /// The end of the call; its effects. The Session is spent after it.
    Effects finish(End end);

private:
    void transfer(const Word& from, const Word& to, const Word& value);
    void record(Event e);

    State* state_;
    CallContext context_;
    std::map<Word, Word> storage_;          // the slots written by the call
    std::map<Word, Word> transient_;
    std::map<Word, Word> balances_;         // the balances changed by the call
    std::map<Word, std::uint64_t> nonces_;  // the nonces changed by the call
    std::set<Word> created_;
    std::vector<Event> events_;
    bool too_many_events_ = false;
    bool finished_ = false;
};

/// A precompile's result, computed: 0x01 ecrecover, 0x02 sha256, 0x03
/// ripemd160, 0x04 identity, 0x05 modexp, 0x06-0x08 bn254 add, mul,
/// pairing, 0x09 blake2f, 0x100 p256verify; the others (0x0a point
/// evaluation, 0x0b-0x11 BLS12-381) fail. Never out of gas.
CallResult run_precompile(const Word& address, BytesView input);
}  // namespace validate
