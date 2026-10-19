// The validation of the stages by execution (stage_check.hpp).
#include "stage_check.hpp"

#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/dump.hpp"
#include "core/errors.hpp"
#include "core/platform.hpp"
#include "core/watchdog.hpp"

#include <algorithm>
#include <cstdio>
#include <memory>
#include <optional>

namespace validate
{
// ---------------------------------------------------------------- words

pan::Word256 to_word256(const Word& w) noexcept
{
    return pan::Word256{{w[0], w[1], w[2], w[3]}};
}

Word to_word(const pan::Word256& w) noexcept
{
    return Word{w.limb[0], w.limb[1], w.limb[2], w.limb[3]};
}

// ---------------------------------------------------------------- the host

SessionHost::SessionHost(Session& session) : session_{&session}
{
    const auto& c = session.context();
    const auto& b = session.block();
    env_.address = to_word256(session.address());
    env_.caller = to_word256(c.caller);
    env_.origin = to_word256(c.origin);
    env_.callvalue = to_word256(c.value);
    env_.gasprice = to_word256(c.gas_price);
    env_.gas = pan::Word256::of(static_cast<std::uint64_t>(fixed_gas));
    env_.coinbase = to_word256(b.coinbase);
    env_.timestamp = to_word256(b.timestamp);
    env_.number = to_word256(b.number);
    env_.prevrandao = to_word256(b.prevrandao);
    env_.gaslimit = to_word256(b.gas_limit);
    env_.chainid = to_word256(b.chain_id);
    env_.basefee = to_word256(b.base_fee);
    env_.blobbasefee = to_word256(b.blob_base_fee);
    env_.calldata = c.calldata;
    env_.code = session.code();
}

const pan::exec::CallEnv& SessionHost::env()
{
    return env_;
}

pan::Word256 SessionHost::sload(const pan::Word256& slot)
{
    return to_word256(session_->sload(to_word(slot)));
}

void SessionHost::sstore(const pan::Word256& slot, const pan::Word256& value)
{
    session_->sstore(to_word(slot), to_word(value));
}

pan::Word256 SessionHost::tload(const pan::Word256& key)
{
    return to_word256(session_->tload(to_word(key)));
}

void SessionHost::tstore(const pan::Word256& key, const pan::Word256& value)
{
    session_->tstore(to_word(key), to_word(value));
}

pan::Word256 SessionHost::balance(const pan::Word256& account)
{
    return to_word256(session_->balance(to_word(account)));
}

// (the contract's own account too: the State answers with its code, as to evmone)
pan::Word256 SessionHost::code_size(const pan::Word256& account)
{
    return to_word256(session_->code_size(to_word(account)));
}

pan::Word256 SessionHost::code_hash(const pan::Word256& account)
{
    return to_word256(session_->code_hash(to_word(account)));
}

std::vector<std::uint8_t> SessionHost::code_of(const pan::Word256& account)
{
    return session_->code_of(to_word(account));
}

pan::Word256 SessionHost::block_hash(const pan::Word256& number)
{
    return to_word256(session_->block_hash(to_word(number)));
}

pan::Word256 SessionHost::blob_hash(const pan::Word256& index)
{
    return to_word256(session_->blob_hash(to_word(index)));
}

void SessionHost::log(std::span<const pan::Word256> topics, std::span<const std::uint8_t> data)
{
    Word words[4];
    const auto n = std::min<std::size_t>(topics.size(), 4);
    for (std::size_t i = 0; i < n; ++i)
        words[i] = to_word(topics[i]);
    session_->log(std::span<const Word>(words, n), data);
}

pan::exec::CallResult SessionHost::call(pan::exec::CallKind kind, const pan::Word256& target,
    const pan::Word256& value, std::span<const std::uint8_t> input)
{
    CallKind k = CallKind::call;
    switch (kind)
    {
    case pan::exec::CallKind::Call:
        k = CallKind::call;
        break;
    case pan::exec::CallKind::StaticCall:
        k = CallKind::staticcall;
        break;
    case pan::exec::CallKind::DelegateCall:
        k = CallKind::delegatecall;
        break;
    case pan::exec::CallKind::CallCode:
        k = CallKind::callcode;
        break;
    }
    auto r = session_->call(k, to_word(target), to_word(value), input);
    return {r.success, std::move(r.output)};
}

pan::exec::CreateResult SessionHost::create(pan::exec::CreateKind kind, const pan::Word256& value,
    std::span<const std::uint8_t> init_code, const pan::Word256& salt)
{
    const auto k = kind == pan::exec::CreateKind::Create ? CreateKind::create : CreateKind::create2;
    auto r = session_->create(k, to_word(value), init_code, to_word(salt));
    return {r.success, to_word256(r.address), std::move(r.output)};
}

void SessionHost::selfdestruct(const pan::Word256& beneficiary)
{
    session_->selfdestruct(to_word(beneficiary));
}

End to_end(const pan::exec::Outcome& o)
{
    using pan::exec::Status;
    switch (o.status)
    {
    case Status::Stop:
        return End::stop();
    case Status::Return:
        return End::returned(o.data);
    case Status::Revert:
        return End::reverted(o.data);
    case Status::Invalid: {
        auto fault = Fault::other;
        switch (static_cast<pan::InvalidReason>(o.reason))
        {
        case pan::InvalidReason::OPCODE:
            fault = Fault::invalid_instruction;
            break;
        case pan::InvalidReason::ASSERT_FAIL:
            fault = Fault::invalid_instruction;
            break;
        case pan::InvalidReason::JUMP:
        case pan::InvalidReason::JUMPDEST:
            fault = Fault::bad_jump;
            break;
        case pan::InvalidReason::STACK_UNDERFLOW:
            fault = Fault::stack_underflow;
            break;
        case pan::InvalidReason::RETURNDATACOPY:
            fault = Fault::memory_access;
            break;
        case pan::InvalidReason::STACK_OVERFLOW:
            fault = Fault::stack_overflow;
            break;
        }
        return End::invalid(fault);
    }
    case Status::Exhausted:
        return End::exhausted(o.note);
    case Status::Undefined:
        return End::unsupported("undefined: " + o.note);
    case Status::Unsupported:
        return End::unsupported(o.note);
    case Status::Bug:
        return End::error("the trace's bug: " + o.note);
    }
    return End::error("?");
}

Effects run_machine(pan::exec::Machine& machine, Session& session, std::optional<std::uint32_t> selector_hint,
    pan::exec::Outcome* outcome)
{
    SessionHost host{session};
    auto o = machine.call(host, selector_hint);
    auto effects = session.finish(to_end(o));
    if (outcome != nullptr)
        *outcome = std::move(o);
    return effects;
}

// ---------------------------------------------------------------- names

const char* stage_name(Stage stage) noexcept
{
    switch (stage)
    {
    case Stage::raw:
        return "raw";
    case Stage::whiles:
        return "whiles";
    case Stage::simplified:
        return "simplified";
    case Stage::analysed:
        return "analysed";
    case Stage::folded:
        return "folded";
    }
    return "?";
}

const char* category_name(Category c) noexcept
{
    switch (c)
    {
    case Category::end_status:
        return "end";
    case Category::end_data:
        return "data";
    case Category::events:
        return "events";
    case Category::storage:
        return "storage";
    case Category::bug:
        return "bug";
    case Category::unsized:
        return "unsized";
    }
    return "?";
}

const char* why_name(Why w) noexcept
{
    switch (w)
    {
    case Why::evm:
        return "evm";
    case Why::exhausted:
        return "exhausted";
    case Why::undefined:
        return "undefined";
    case Why::unsupported:
        return "unsupported";
    }
    return "?";
}

Decompiled::Decompiled(BytesView c) : code(c.begin(), c.end()), map(pan::analyse(code))
{
    shared.code = code;
    shared.map = &map;
    shared.free_memory_pointer = map.fmp;
    if (const auto md = pan::metadata(code))
        shared.lang = md->lang;
}

namespace
{
// ---------------------------------------------------------------- the calls

std::string call_description(bool random, std::uint64_t seed, std::size_t i, const PlannedCall& c)
{
    char buf[64];
    std::string s = std::string{random ? "random" : "empty"} + " world " + std::to_string(seed) + ", call ";
    s += std::to_string(i);
    if (c.selector)
    {
        std::snprintf(buf, sizeof buf, " 0x%08x/%u", *c.selector, c.variant);
        s += buf;
    }
    else
        s += " fallback/" + std::to_string(c.variant);
    s += " from " + hex(c.context.caller);
    if (c.context.value != 0)
        s += " value " + hex(c.context.value);
    return s + " calldata " + hex(c.context.calldata);
}

std::string where(const pan::exec::Outcome& o)
{
    if (o.line.nil())
        return {};
    std::string s = pan::dump(o.line);
    if (s.size() > 400)
        s = s.substr(0, 400) + "...";
    if (const auto pc = pan::cx().pcs.pc_of(o.line))
        s += " (pc " + std::to_string(*pc) + ")";
    return s;
}

/// The part of the effects that differs first, in compare()'s order.
Category classify(const Effects& expected, const Effects& actual, const CompareOptions& options)
{
    const auto status = [](const End& e) {
        return e.status == Status::return_ && e.data.empty() ? Status::stop : e.status;
    };
    if (status(expected.end) != status(actual.end) || (options.faults && expected.end.fault != actual.end.fault))
        return Category::end_status;
    if (expected.end.data != actual.end.data)
        return Category::end_data;
    Effects e{expected.events, expected.end, {}};
    Effects a{actual.events, actual.end, {}};
    if (compare(e, a, options).verdict == Verdict::different)
        return Category::events;
    return Category::storage;
}

struct Checker
{
    const CheckConfig& config;
    Decompiled& contract;
    StageReport& report;
    EvmRunner runner;
    std::array<std::unique_ptr<pan::exec::Machine>, stage_count> machines;
    std::uint64_t world_seed = 0;

    Checker(const CheckConfig& cfg, Decompiled& c, StageReport& r) : config{cfg}, contract{c}, report{r}, runner{c.code, cfg.evm}
    {
        for (unsigned s = 0; s < stage_count; ++s)
        {
            if (!contract.made[s])
                continue;
            pan::exec::Program p;
            p.functions = contract.functions[s];
            p.internals = contract.internals[s];
            p.shared = &contract.shared;
            p.layout = contract.storage.get();
            p.safemath = contract.safemath.get();
            machines[s] = std::make_unique<pan::exec::Machine>(p, config.machine);
            report.stages[s].ran = true;
        }
    }

    void keep(StageResult& r, Category category, bool random, std::size_t i, const PlannedCall& call,
        std::string message, const pan::exec::Outcome& o, const Effects& expected, const Effects& actual)
    {
        if (r.examples.size() >= config.keep)
            return;
        Example x;
        x.category = category;
        x.call = call_description(random, world_seed, i, call);
        x.message = std::move(message);
        x.where = where(o);
        x.expected = to_string(expected);
        x.actual = to_string(actual);
        r.examples.push_back(std::move(x));
    }

    void tally(unsigned s, bool random, std::size_t i, const PlannedCall& call, const Effects& expected,
        const Effects& actual, const pan::exec::Outcome& o)
    {
        auto& r = report.stages[s];
        using pan::exec::Status;
        if (o.unsized != 0)
        {
            ++r.unsized;
            ++r.by_category[static_cast<unsigned>(Category::unsized)];
            if (r.examples.size() < config.keep)
            {
                Example x;
                x.category = Category::unsized;
                x.call = call_description(random, world_seed, i, call);
                x.message = std::to_string(o.unsized) + " byte element(s) without SIZED, the first: " +
                            pan::dump(o.unsized_element);
                pan::exec::Outcome at;
                at.line = o.unsized_line;
                x.where = where(at);
                r.examples.push_back(std::move(x));
            }
        }
        if (o.status == Status::Bug)
        {
            ++r.bugs;
            ++r.by_category[static_cast<unsigned>(Category::bug)];
            keep(r, Category::bug, random, i, call, o.note, o, expected, actual);
            return;
        }
        const auto c = compare(expected, actual, config.compare);
        switch (c.verdict)
        {
        case Verdict::same:
            ++r.same;
            switch (expected.end.status)
            {
            case validate::Status::stop:
                ++r.same_by_end[0];
                break;
            case validate::Status::return_:
                ++r.same_by_end[expected.end.data.empty() ? 0 : 1];
                break;
            case validate::Status::revert:
                ++r.same_by_end[2];
                break;
            default:
                ++r.same_by_end[3];
                break;
            }
            return;
        case Verdict::inconclusive: {
            ++r.inconclusive;
            auto why = Why::evm;
            if (!expected.end.inconclusive())
            {
                why = o.status == Status::Exhausted ? Why::exhausted :
                      o.status == Status::Undefined ? Why::undefined :
                                                      Why::unsupported;
                if (r.inconclusive_examples.size() < config.keep)
                {
                    Example x;
                    x.call = call_description(random, world_seed, i, call);
                    x.message = std::string{why_name(why)} + ": " + o.note;
                    x.where = where(o);
                    x.expected = to_string(expected);
                    r.inconclusive_examples.push_back(std::move(x));
                }
            }
            ++r.by_why[static_cast<unsigned>(why)];
            return;
        }
        case Verdict::different: {
            ++r.different;
            const auto cat = classify(expected, actual, config.compare);
            ++r.by_category[static_cast<unsigned>(cat)];
            keep(r, cat, random, i, call, c.message, o, expected, actual);
            return;
        }
        }
    }

    void run_world(bool random, std::uint64_t seed)
    {
        world_seed = seed;
        WorldConfig wc;
        wc.seed = seed;
        wc.random = random;
        const SeededWorld world{wc};
        CallGenerator gen{world, contract.code, config.calls};
        if (config.db != nullptr)
            gen.set_encoder(AbiEncoder{*config.db, config.abi});
        const auto calls = gen.calls();
        report.calls = std::max<unsigned long>(report.calls, calls.size());
        const auto& address = world.contract_address();
        State sequence{world, address, contract.code};
        for (std::size_t i = 0; i < calls.size(); ++i)
        {
            pan::poll();
            const auto& call = calls[i];
            if (config.only && call.selector != config.only)
                continue;
            std::optional<State> fresh;
            if (random)
                fresh.emplace(world, address, contract.code);
            State& evm_state = random ? *fresh : sequence;
            const State before = evm_state;
            const auto expected = runner.run(evm_state, call.context);
            for (unsigned s = 0; s < stage_count; ++s)
            {
                if (!machines[s])
                    continue;
                State state = before;
                Session session{state, call.context};
                pan::exec::Outcome o;
                const auto actual = run_machine(*machines[s], session, call.selector, &o);
                tally(s, random, i, call, expected, actual, o);
            }
        }
    }
};
}  // namespace

StageReport check_contract(BytesView code, const CheckConfig& config, const Pipeline& pipeline)
{
    StageReport report;
    pan::init();
    const auto start = pan::platform::monotonic_ns();
    const std::int64_t deadline = config.timeout_ns > 0 ? start + config.timeout_ns : 0;
    pan::Budget budget{pan::Budget::Limits{.memory = config.memory, .deadline_ns = deadline}};
    budget.attach_thread();
    struct Detach
    {
        pan::Budget& b;
        ~Detach() { b.detach_thread(); }
    } detach{budget};
    std::optional<pan::Watchdog::Watch> watch;
    if (deadline != 0)
        watch.emplace(budget, deadline);
    try
    {
        Decompiled contract{code};
        auto ctx = pan::Context::create(budget, &contract.shared);
        pan::ContextScope scope{*ctx};
        try
        {
            pipeline(contract, config.upto, budget);
            report.ran = true;
        }
        catch (const pan::Error& e)
        {
            report.failure = std::string{"the decompilation failed: "} + e.what();
            report.decompile_ns = pan::platform::monotonic_ns() - start;
            return report;
        }
        const auto decompiled = pan::platform::monotonic_ns();
        report.decompile_ns = decompiled - start;
        struct Clock
        {
            StageReport& r;
            std::int64_t from;
            ~Clock() { r.check_ns = pan::platform::monotonic_ns() - from; }
        } clock{report, decompiled};
        // the counts of the first stage made
        for (unsigned s = 0; s < stage_count; ++s)
        {
            if (!contract.made[s])
                continue;
            report.functions = static_cast<unsigned>(contract.functions[s].size());
            report.internals = static_cast<unsigned>(contract.internals[s].size());
            for (const auto& f : contract.functions[s])
                report.problems += f.problem.has_value();
            for (const auto& f : contract.internals[s])
                report.problems += f.problem.has_value();
            break;
        }
        Checker checker{config, contract, report};
        if (config.empty_world)
            checker.run_world(false, config.seed);
        if (config.random_world)
            for (unsigned k = 0; k < std::max(config.random_seeds, 1u); ++k)
                checker.run_world(true, config.seed + k);
        for (unsigned s = 0; s < stage_count; ++s)
            if (report.stages[s].different + report.stages[s].bugs != 0)
            {
                report.first_divergent = static_cast<Stage>(s);
                break;
            }
    }
    catch (const pan::Timeout&)
    {
        if (!report.ran)
            report.decompile_ns = pan::platform::monotonic_ns() - start;
        report.failure = "the time limit";
    }
    catch (const pan::Abort& e)
    {
        report.failure = e.what();
    }
    catch (const pan::Error& e)
    {
        report.failure = e.what();
    }
    catch (const std::bad_alloc&)
    {
        report.failure = "out of memory";
    }
    return report;
}

std::string summary(const StageReport& report)
{
    if (!report.failure.empty() && !report.ran)
        return "FAILED: " + report.failure + " (after " + std::to_string(report.decompile_ns / 1'000'000) + " ms)";
    std::string s = std::to_string(report.functions) + " functions";
    if (report.internals != 0)
        s += " + " + std::to_string(report.internals) + " internal";
    if (report.problems != 0)
        s += " (" + std::to_string(report.problems) + " failed)";
    s += ", " + std::to_string(report.calls) + " calls";
    for (unsigned i = 0; i < stage_count; ++i)
    {
        const auto& r = report.stages[i];
        if (!r.ran)
            continue;
        s += std::string{" | "} + stage_name(static_cast<Stage>(i)) + ": same " + std::to_string(r.same) + " (stop " +
             std::to_string(r.same_by_end[0]) + " return " + std::to_string(r.same_by_end[1]) + " revert " +
             std::to_string(r.same_by_end[2]) + " invalid " + std::to_string(r.same_by_end[3]) + ")";
        if (r.different != 0)
        {
            s += ", DIFFERENT " + std::to_string(r.different) + " (";
            bool first = true;
            for (unsigned c = 0; c < category_count; ++c)
                if (c < static_cast<unsigned>(Category::bug) && r.by_category[c] != 0)
                {
                    s += (first ? "" : " ") + std::string{category_name(static_cast<Category>(c))} + " " +
                         std::to_string(r.by_category[c]);
                    first = false;
                }
            s += ")";
        }
        if (r.bugs != 0)
            s += ", BUGS " + std::to_string(r.bugs);
        if (r.unsized != 0)
            s += ", UNSIZED " + std::to_string(r.unsized);
        if (r.inconclusive != 0)
        {
            s += ", inconclusive " + std::to_string(r.inconclusive) + " (";
            bool first = true;
            for (unsigned w = 0; w < why_count; ++w)
                if (r.by_why[w] != 0)
                {
                    s += (first ? "" : " ") + std::string{why_name(static_cast<Why>(w))} + " " +
                         std::to_string(r.by_why[w]);
                    first = false;
                }
            s += ")";
        }
    }
    if (!report.failure.empty())
        s += " | stopped: " + report.failure;
    s += " | " + std::to_string(report.decompile_ns / 1'000'000) + " + " + std::to_string(report.check_ns / 1'000'000) +
         " ms";
    return s;
}
}  // namespace validate
