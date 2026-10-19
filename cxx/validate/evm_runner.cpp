// The EVM side: evmone with a host answering from a Session.
#include "evm_runner.hpp"

#include <evmc/evmc.hpp>
#include <evmone/baseline.hpp>
#include <evmone/vm.hpp>

#include <algorithm>
#include <cstring>
#include <set>

namespace validate
{
namespace
{
Word word_of(const evmc::bytes32& b) noexcept
{
    return intx::be::load<Word>(b);
}

Word word_of(const evmc::address& a) noexcept
{
    return intx::be::load<Word>(a);
}

evmc::bytes32 bytes32_of(const Word& w) noexcept
{
    return intx::be::store<evmc::bytes32>(w);
}

evmc::address address_of(const Word& w) noexcept
{
    return intx::be::trunc<evmc::address>(w);
}

/// The evmc host of one call: every question to the Session.
class SessionHost final : public evmc::Host
{
public:
    explicit SessionHost(Session& session) : s_{session}
    {
        for (const auto& h : s_.block().blob_hashes)
            blob_hashes_.push_back(bytes32_of(h));
        // warm from the start: the transaction's sender and recipient, the precompiles
        accessed_accounts_.insert(s_.context().caller);
        accessed_accounts_.insert(s_.context().origin);
        accessed_accounts_.insert(s_.address());
        for (unsigned a = 1; a <= 0x11; ++a)
            accessed_accounts_.insert(a);
        accessed_accounts_.insert(0x100);
    }

    bool account_exists(const evmc::address& addr) const noexcept override
    {
        return s_.account_exists(word_of(addr));
    }

    evmc::bytes32 get_storage(const evmc::address&, const evmc::bytes32& key) const noexcept override
    {
        return bytes32_of(s_.sload(word_of(key)));
    }

    evmc_storage_status set_storage(const evmc::address&, const evmc::bytes32& key,
        const evmc::bytes32& value) noexcept override
    {
        s_.sstore(word_of(key), word_of(value));
        return EVMC_STORAGE_ASSIGNED;  // the gas only
    }

    evmc::uint256be get_balance(const evmc::address& addr) const noexcept override
    {
        return bytes32_of(s_.balance(word_of(addr)));
    }

    uint64_t get_nonce(const evmc::address& addr) const noexcept override
    {
        return s_.nonce(word_of(addr));
    }

    size_t get_code_size(const evmc::address& addr) const noexcept override
    {
        return static_cast<size_t>(s_.code_size(word_of(addr)));
    }

    evmc::bytes32 get_code_hash(const evmc::address& addr) const noexcept override
    {
        return bytes32_of(s_.code_hash(word_of(addr)));
    }

    size_t copy_code(const evmc::address& addr, size_t code_offset, uint8_t* buffer_data,
        size_t buffer_size) const noexcept override
    {
        const auto code = s_.code_of(word_of(addr));
        if (code_offset >= code.size())
            return 0;
        const auto n = std::min(buffer_size, code.size() - code_offset);
        std::memcpy(buffer_data, code.data() + code_offset, n);
        return n;
    }

    bool selfdestruct(const evmc::address&, const evmc::address& beneficiary) noexcept override
    {
        s_.selfdestruct(word_of(beneficiary));
        return true;  // the gas refunds only
    }

    evmc::Result call(const evmc_message& msg) noexcept override
    {
        const BytesView input{msg.input_data, msg.input_size};
        // the callee uses no gas: all of it comes back (and the state gas)
        const evmc::StateGas state_gas{msg.state_gas, 0};
        if (msg.kind == EVMC_CREATE || msg.kind == EVMC_CREATE2)
        {
            const auto kind = msg.kind == EVMC_CREATE ? CreateKind::create : CreateKind::create2;
            const auto r = s_.create_at(kind, word_of(msg.recipient), word_of(msg.value), input);
            return evmc::Result{r.success ? EVMC_SUCCESS : EVMC_REVERT, msg.gas, 0,
                r.output.data(), r.output.size(), state_gas};
        }
        CallResult r;
        switch (msg.kind)
        {
        case EVMC_CALL:
            // our call is not static: only STATICCALL makes a static one
            r = s_.call((msg.flags & EVMC_STATIC) != 0 ? CallKind::staticcall : CallKind::call,
                word_of(msg.recipient), word_of(msg.value), input);
            break;
        case EVMC_DELEGATECALL:
            r = s_.call(CallKind::delegatecall, word_of(msg.code_address), 0, input);
            break;
        case EVMC_CALLCODE:
            r = s_.call(CallKind::callcode, word_of(msg.code_address), word_of(msg.value), input);
            break;
        default:
            return evmc::Result{EVMC_INTERNAL_ERROR, 0, 0, state_gas};
        }
        return evmc::Result{r.success ? EVMC_SUCCESS : EVMC_REVERT, msg.gas, 0, r.output.data(),
            r.output.size(), state_gas};
    }

    evmc_tx_context get_tx_context() const noexcept override
    {
        const auto& b = s_.block();
        const auto& c = s_.context();
        evmc_tx_context t{};
        t.tx_gas_price = bytes32_of(c.gas_price);
        t.tx_origin = address_of(c.origin);
        t.block_coinbase = address_of(b.coinbase);
        t.block_number = static_cast<int64_t>(b.number);
        t.block_timestamp = static_cast<int64_t>(b.timestamp);
        t.block_gas_limit = static_cast<int64_t>(b.gas_limit);
        t.block_prev_randao = bytes32_of(b.prevrandao);
        t.chain_id = bytes32_of(b.chain_id);
        t.block_base_fee = bytes32_of(b.base_fee);
        t.blob_base_fee = bytes32_of(b.blob_base_fee);
        t.blob_hashes = blob_hashes_.data();
        t.blob_hashes_count = blob_hashes_.size();
        return t;
    }

    evmc::bytes32 get_block_hash(int64_t block_number) const noexcept override
    {
        return bytes32_of(s_.block_hash(static_cast<std::uint64_t>(block_number)));
    }

    void emit_log(const evmc::address&, const uint8_t* data, size_t data_size,
        const evmc::bytes32 topics[], size_t num_topics) noexcept override
    {
        Word t[4];
        for (size_t i = 0; i < num_topics; ++i)
            t[i] = word_of(topics[i]);
        s_.log(std::span{t, num_topics}, BytesView{data, data_size});
    }

    // EIP-2929's accesses, cold the first time (the gas only: the budget of
    // a loop of SLOADs is the real one)
    evmc_access_status access_account(const evmc::address& addr) noexcept override
    {
        return accessed_accounts_.insert(word_of(addr)).second ? EVMC_ACCESS_COLD : EVMC_ACCESS_WARM;
    }

    evmc_access_status access_storage(const evmc::address&, const evmc::bytes32& key) noexcept override
    {
        return accessed_slots_.insert(word_of(key)).second ? EVMC_ACCESS_COLD : EVMC_ACCESS_WARM;
    }

    evmc::bytes32 get_transient_storage(const evmc::address&, const evmc::bytes32& key) const noexcept override
    {
        return bytes32_of(s_.tload(word_of(key)));
    }

    void set_transient_storage(const evmc::address&, const evmc::bytes32& key,
        const evmc::bytes32& value) noexcept override
    {
        s_.tstore(word_of(key), word_of(value));
    }

private:
    Session& s_;
    std::vector<evmc::bytes32> blob_hashes_;
    std::set<Word> accessed_accounts_;
    std::set<Word> accessed_slots_;
};

End end_of(const evmc::Result& r)
{
    const Bytes data(r.output_data, r.output_data + r.output_size);
    switch (r.status_code)
    {
    case EVMC_SUCCESS:
        return data.empty() ? End::stop() : End::returned(data);
    case EVMC_REVERT:
        return End::reverted(data);
    case EVMC_OUT_OF_GAS:
        return End::exhausted("out of gas (or a memory offset >= 2^32)");
    case EVMC_INVALID_INSTRUCTION:
        return End::invalid(Fault::invalid_instruction);
    case EVMC_UNDEFINED_INSTRUCTION:
        return End::invalid(Fault::undefined_instruction);
    case EVMC_STACK_OVERFLOW:
        return End::invalid(Fault::stack_overflow);
    case EVMC_STACK_UNDERFLOW:
        return End::invalid(Fault::stack_underflow);
    case EVMC_BAD_JUMP_DESTINATION:
        return End::invalid(Fault::bad_jump);
    case EVMC_STATIC_MODE_VIOLATION:
        return End::invalid(Fault::static_violation);
    case EVMC_INVALID_MEMORY_ACCESS:
        return End::invalid(Fault::memory_access);
    case EVMC_FAILURE:
        return End::invalid(Fault::other);
    case EVMC_OUT_OF_MEMORY:
        return End::exhausted("out of memory");
    default:
        return End::error("evmone status " + std::to_string(static_cast<int>(r.status_code)));
    }
}
}  // namespace

struct EvmRunner::Impl
{
    Bytes code;
    RunOptions options;
    evmone::VM vm;
    evmone::baseline::CodeAnalysis analysis;

    Impl(Bytes c, RunOptions o)
      : code{std::move(c)}, options{o}, analysis{evmone::baseline::analyze({code.data(), code.size()})}
    {}
};

EvmRunner::EvmRunner(Bytes code, RunOptions options)
  : impl_{std::make_unique<Impl>(std::move(code), options)}
{}

EvmRunner::~EvmRunner() = default;
EvmRunner::EvmRunner(EvmRunner&&) noexcept = default;
EvmRunner& EvmRunner::operator=(EvmRunner&&) noexcept = default;

const Bytes& EvmRunner::code() const noexcept
{
    return impl_->code;
}

RunOptions& EvmRunner::options() noexcept
{
    return impl_->options;
}

Effects EvmRunner::run(Session& session)
{
    SessionHost host{session};
    const auto& context = session.context();
    evmc_message msg{};
    msg.kind = EVMC_CALL;
    msg.depth = 0;
    msg.gas = impl_->options.gas;
    msg.recipient = address_of(session.address());
    msg.sender = address_of(context.caller);
    msg.input_data = context.calldata.data();
    msg.input_size = context.calldata.size();
    msg.value = bytes32_of(context.value);
    msg.code_address = msg.recipient;
    msg.code = impl_->code.data();
    msg.code_size = impl_->code.size();
    const evmc::Result result{evmone::baseline::execute(impl_->vm, evmc::Host::get_interface(),
        host.to_context(), EVMC_OSAKA, msg, impl_->analysis)};
    return session.finish(end_of(result));
}

Effects EvmRunner::run(State& state, const CallContext& call)
{
    Session session{state, call};
    return run(session);
}

std::vector<Effects> EvmRunner::run(State& state, std::span<const CallContext> calls)
{
    std::vector<Effects> out;
    out.reserve(calls.size());
    for (const auto& c : calls)
        out.push_back(run(state, c));
    return out;
}
}  // namespace validate
