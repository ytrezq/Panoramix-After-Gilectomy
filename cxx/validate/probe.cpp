// The selectors a dispatcher compares the calldata's with, found by running
// it (calls.hpp: probe_selectors): calls of a probe selector through evmone,
// with a tracer that records the constants the probe meets in the
// comparisons. It finds what no pattern of the code does: the optimizer's
// comparisons of left-aligned selectors (PUSH4 v PUSH1 0xe1 SHL ... ADD),
// vyper's table-driven dispatchers (the selectors in a data section, read
// with CODECOPY), solc's binary searches (the pivots are selectors too).
#include "calls.hpp"
#include "session.hpp"

#include <evmc/evmc.hpp>
#include <evmone/baseline.hpp>
#include <evmone/execution_state.hpp>
#include <evmone/tracing.hpp>
#include <evmone/vm.hpp>

#include <deque>
#include <set>

namespace validate
{
namespace
{
constexpr Word low224 = (Word{1} << 224) - 1;

class ProbeTracer final : public evmone::Tracer
{
public:
    ProbeTracer(std::uint32_t probe, const Word& caller, ProbeResult& found)
      : right_{probe}, left_{Word{probe} << 224}, caller_{caller}, probe_{probe}, found_{found}
    {}

private:
    void on_execution_start(evmc_revision, const evmc_message&, evmone::bytes_view code) noexcept override
    {
        code_ = code;
    }

    void on_instruction_start(uint32_t pc, const intx::uint256* top, int height, int64_t,
        const evmone::ExecutionState&) noexcept override
    {
        if (height < 2 || pc >= code_.size())
            return;
        switch (const auto op = code_[pc])
        {
        case 0x01:  // ADD: x + c == 0
        case 0x03:  // SUB
        case 0x10:  // LT, GT, SLT, SGT: the pivots of the binary searches
        case 0x11:
        case 0x12:
        case 0x13:
        case 0x14:  // EQ
        case 0x18:  // XOR
            consider(top[0], top[-1], op);
            consider(top[-1], top[0], op);
            // the addresses the caller is compared with: owners, admins
            if (op != 0x10 && op != 0x11 && op != 0x12 && op != 0x13 && op != 0x01)
            {
                caller(top[0], top[-1]);
                caller(top[-1], top[0]);
            }
            break;
        default:
            break;
        }
    }

    void on_execution_end(const evmc_result&) noexcept override {}

    void consider(const Word& mine, const Word& other, std::uint8_t op) noexcept
    {
        const auto o = op == 0x01 ? Word{0} - other : other;
        if (mine == right_ && o >> 32 == 0)
            add(static_cast<std::uint32_t>(o));
        else if (mine == left_ && (o & low224) == 0)
            add(static_cast<std::uint32_t>(o >> 224));
    }

    void add(std::uint32_t s) noexcept
    {
        if (s != probe_ && std::ranges::find(found_.selectors, s) == found_.selectors.end())
            found_.selectors.push_back(s);
    }

    void caller(const Word& mine, const Word& other) noexcept
    {
        if (mine == caller_ && other != caller_ && other <= address_mask &&
            std::ranges::find(found_.callers, other) == found_.callers.end())
            found_.callers.push_back(other);
    }

    Word right_, left_, caller_;
    std::uint32_t probe_;
    ProbeResult& found_;
    evmone::bytes_view code_;
};

/// A host for the probes: the world's answers through a Session, nothing kept.
class ProbeHost final : public evmc::Host
{
public:
    explicit ProbeHost(Session& s) : s_{s} {}
    bool account_exists(const evmc::address&) const noexcept override { return true; }
    evmc::bytes32 get_storage(const evmc::address&, const evmc::bytes32& key) const noexcept override
    {
        return intx::be::store<evmc::bytes32>(s_.sload(intx::be::load<Word>(key)));
    }
    evmc_storage_status set_storage(const evmc::address&, const evmc::bytes32&, const evmc::bytes32&) noexcept override
    {
        return EVMC_STORAGE_ASSIGNED;
    }
    evmc::uint256be get_balance(const evmc::address&) const noexcept override { return {}; }
    uint64_t get_nonce(const evmc::address&) const noexcept override { return 1; }
    size_t get_code_size(const evmc::address&) const noexcept override { return 1; }
    evmc::bytes32 get_code_hash(const evmc::address&) const noexcept override { return {}; }
    size_t copy_code(const evmc::address&, size_t, uint8_t*, size_t) const noexcept override { return 0; }
    bool selfdestruct(const evmc::address&, const evmc::address&) noexcept override { return true; }
    evmc::Result call(const evmc_message& msg) noexcept override
    {
        return evmc::Result{EVMC_SUCCESS, msg.gas, 0, evmc::StateGas{msg.state_gas, 0}};
    }
    evmc_tx_context get_tx_context() const noexcept override
    {
        evmc_tx_context t{};
        t.block_number = 21'000'000;
        t.block_timestamp = 1'750'000'000;
        t.block_gas_limit = 30'000'000;
        return t;
    }
    evmc::bytes32 get_block_hash(int64_t) const noexcept override { return {}; }
    void emit_log(const evmc::address&, const uint8_t*, size_t, const evmc::bytes32[], size_t) noexcept override {}
    evmc_access_status access_account(const evmc::address&) noexcept override { return EVMC_ACCESS_WARM; }
    evmc_access_status access_storage(const evmc::address&, const evmc::bytes32&) noexcept override
    {
        return EVMC_ACCESS_WARM;
    }
    evmc::bytes32 get_transient_storage(const evmc::address&, const evmc::bytes32&) const noexcept override
    {
        return {};
    }
    void set_transient_storage(const evmc::address&, const evmc::bytes32&, const evmc::bytes32&) noexcept override {}

private:
    Session& s_;
};
}  // namespace

ProbeResult probe_selectors(BytesView code, const SeededWorld& world, const ProbeConfig& config)
{
    ProbeResult found;
    if (code.empty() || world.actors().empty())
        return found;
    evmone::VM vm;
    const auto analysis = evmone::baseline::analyze({code.data(), code.size()});
    State state{world, world.contract_address(), Bytes(code.begin(), code.end())};

    unsigned runs = 0;
    std::set<std::pair<Word, std::uint32_t>> probed;
    const auto run = [&](const Word& caller, std::uint32_t probe) {
        if (runs >= config.max_runs || !probed.emplace(caller, probe).second)
            return;
        ++runs;
        Bytes calldata{static_cast<std::uint8_t>(probe >> 24), static_cast<std::uint8_t>(probe >> 16),
            static_cast<std::uint8_t>(probe >> 8), static_cast<std::uint8_t>(probe)};
        calldata.resize(4 + 32 * 4);
        Session session{state, {.caller = caller, .origin = caller, .calldata = calldata}};
        ProbeHost host{session};
        vm.remove_tracers();
        vm.add_tracer(std::make_unique<ProbeTracer>(probe, caller, found));
        evmc_message msg{};
        msg.kind = EVMC_CALL;
        msg.gas = config.gas;
        msg.recipient = intx::be::trunc<evmc::address>(state.address());
        msg.sender = intx::be::trunc<evmc::address>(caller);
        msg.input_data = calldata.data();
        msg.input_size = calldata.size();
        msg.code_address = msg.recipient;
        const evmc::Result r{evmone::baseline::execute(
            vm, evmc::Host::get_interface(), host.to_context(), EVMC_OSAKA, msg, analysis)};
        (void)session.finish(End::stop());  // nothing is kept: the probe's State isn't reused
    };

    // as the first actor, then as the addresses the caller was compared
    // with: random probes (the slots of the tables), each followed by the
    // selectors found (the other branches of the binary searches), until
    // `patience` of them in a row find nothing
    std::vector<Word> callers{world.actors().front()};
    for (std::size_t c = 0; c < callers.size() && c <= config.max_callers; ++c)
    {
        std::size_t next = 0;
        unsigned idle = 0;
        for (unsigned i = 0; i < config.random_probes && runs < config.max_runs; ++i)
        {
            const auto before = found.selectors.size();
            run(callers[c], static_cast<std::uint32_t>(world.hash(0x90, to_bytes(i))));
            while (next < found.selectors.size() && runs < config.max_runs)
                run(callers[c], found.selectors[next++]);
            idle = found.selectors.size() == before ? idle + 1 : 0;
            if (idle >= config.patience)
                break;
        }
        for (const auto& a : found.callers)
            if (std::ranges::find(callers, a) == callers.end())
                callers.push_back(a);
    }
    return found;
}
}  // namespace validate
