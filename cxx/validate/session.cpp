// One call of the contract executed against a State (session.hpp).
#include "session.hpp"

#include <limits>

namespace validate
{
Session::Session(State& state, CallContext context) : state_{&state}, context_{std::move(context)}
{
    context_.caller = to_address(context_.caller);
    context_.origin = to_address(context_.origin);
    // the call's value is the contract's before its code runs (the caller's
    // balance is not debited: the transaction is assumed valid)
    if (context_.value != 0)
        balances_[address()] = state_->balance(address()) + context_.value;
}

Word Session::sload(const Word& slot) const
{
    if (const auto it = storage_.find(slot); it != storage_.end())
        return it->second;
    return state_->storage(slot);
}

Word Session::tload(const Word& slot) const
{
    if (const auto it = transient_.find(slot); it != transient_.end())
        return it->second;
    return 0;
}

Word Session::balance(const Word& account) const
{
    const auto a = to_address(account);
    if (const auto it = balances_.find(a); it != balances_.end())
        return it->second;
    return state_->balance(a);
}

std::uint64_t Session::nonce(const Word& account) const
{
    const auto a = to_address(account);
    if (const auto it = nonces_.find(a); it != nonces_.end())
        return it->second;
    return state_->nonce(a);
}

Bytes Session::code_of(const Word& account) const
{
    const auto a = to_address(account);
    if (created_.contains(a))
        return Bytes{State::created_code};
    return state_->code_of(a);
}

bool Session::account_exists(const Word& account) const
{
    return !code_of(account).empty() || balance(account) != 0 || nonce(account) != 0;
}

Word Session::code_size(const Word& account) const
{
    return code_of(account).size();
}

Word Session::code_hash(const Word& account) const
{
    if (!account_exists(account))
        return 0;
    return keccak256(code_of(account));
}

Word Session::block_hash(const Word& number) const
{
    const auto& current = block().number;
    if (number >= current || number + 256 < current)
        return 0;
    return state_->world().block_hash(number);
}

Word Session::blob_hash(const Word& index) const
{
    const auto& hashes = block().blob_hashes;
    if (index >= hashes.size())
        return 0;
    return hashes[static_cast<std::size_t>(index)];
}

void Session::record(Event e)
{
    if (events_.size() < max_events)
        events_.push_back(std::move(e));
    else
        too_many_events_ = true;
}

void Session::sstore(const Word& slot, const Word& value)
{
    storage_[slot] = value;
    record(StorageWrite{slot, value});
}

void Session::tstore(const Word& slot, const Word& value)
{
    transient_[slot] = value;
    record(TransientWrite{slot, value});
}

void Session::log(std::span<const Word> topics, BytesView data)
{
    record(Log{{topics.begin(), topics.end()}, Bytes(data.begin(), data.end())});
}

void Session::transfer(const Word& from, const Word& to, const Word& value)
{
    if (value == 0 || from == to)
        return;
    const auto from_balance = balance(from);
    const auto to_balance = balance(to);
    balances_[from] = from_balance - value;
    balances_[to] = to_balance + value;
}

CallResult Session::call(CallKind kind, const Word& target, const Word& value, BytesView input)
{
    const auto to = to_address(target);
    const auto with_value = kind == CallKind::call || kind == CallKind::callcode;
    const Word v = with_value ? value : Word{0};
    // the light failure: not enough balance for the value (evmone's check
    // before it asks the host: no event)
    if (v != 0 && v > balance(address()))
        return {};

    ExternalCall event{kind, to, v, Bytes(input.begin(), input.end()), false, {}};
    if (is_precompile(to))
    {
        event.precompile = true;
        event.result = run_precompile(to, input);
    }
    else if (code_of(to).empty())
        event.result = {true, {}};  // nothing runs: success, no data
    else
        event.result = state_->world().call(kind, to, v, input);
    if (event.result.success && kind == CallKind::call)
        transfer(address(), to, v);
    auto result = event.result;
    record(std::move(event));
    return result;
}

CreateResult Session::create(CreateKind kind, const Word& value, BytesView init_code, const Word& salt)
{
    // the light failures: not enough balance, the nonce at its maximum (EIP-2681)
    if (value != 0 && value > balance(address()))
        return {};
    const auto n = nonce(address());
    if (n == std::numeric_limits<std::uint64_t>::max())
        return {};
    const auto new_address = kind == CreateKind::create ? create_address(address(), n) :
                                                          create2_address(address(), salt, init_code);
    auto result = create_at(kind, new_address, value, init_code);
    if (kind == CreateKind::create2 && !events_.empty())
        if (auto* c = std::get_if<Creation>(&events_.back()); c && c->address == new_address)
            c->salt = salt;
    return result;
}

CreateResult Session::create_at(CreateKind kind, const Word& address_, const Word& value,
    BytesView init_code)
{
    const auto a = to_address(address_);
    nonces_[address()] = nonce(address()) + 1;
    const auto r = state_->world().create(kind, a, value, init_code);
    if (r.success)
    {
        created_.insert(a);
        transfer(address(), a, value);
    }
    record(Creation{kind, value, Bytes(init_code.begin(), init_code.end()),
        std::nullopt, a, r});
    if (!r.success)
        return {false, 0, r.output};
    return {true, a, {}};
}

void Session::selfdestruct(const Word& beneficiary)
{
    const auto b = to_address(beneficiary);
    transfer(address(), b, balance(address()));
    record(SelfDestruct{b});
}

Effects Session::finish(End end)
{
    Effects effects{std::move(events_), std::move(end), {}};
    events_.clear();
    if (finished_)
    {
        effects.end = End::error("Session::finish called twice");
        return effects;
    }
    finished_ = true;
    if (too_many_events_)
        effects.end = End::exhausted("more than " + std::to_string(max_events) + " events");
    if (!effects.end.success())
        return effects;

    // commit: the slots whose value changed make the diff
    for (const auto& [slot, value] : storage_)
    {
        if (value != state_->storage(slot))
            effects.storage_diff.emplace(slot, value);
    }
    for (const auto& [slot, value] : storage_)
        state_->storage_[slot] = value;
    for (const auto& [account, value] : balances_)
        state_->balances_[account] = value;
    for (const auto& [account, value] : nonces_)
        state_->nonces_[account] = value;
    state_->created_.insert(created_.begin(), created_.end());
    return effects;
}
}  // namespace validate
