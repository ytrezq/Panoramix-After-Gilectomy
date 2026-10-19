// evmrun: a runtime bytecode run by evmone against a deterministic world, the
// effects of its calls printed readably; or a whole corpus run, counted.
#include "calls.hpp"
#include "effects.hpp"
#include "evm_runner.hpp"
#include "scan.hpp"
#include "session.hpp"
#include "world.hpp"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

namespace
{
using namespace validate;

constexpr char usage[] =
    R"(usage: evmrun [options] CONTRACT.hex [CALLDATA...]
       evmrun [options] --corpus LIST
Runs a runtime bytecode in evmone (Osaka) against a deterministic world and
prints the effects of each call: the calls given (CALLDATA in hex), or calls
generated from the selectors found in the code, and the fallback's.
  --seed N          the world's seed (0)
  --empty           the empty world: storage zero, no other contract
  --random          the random world (the default; --corpus: both)
  --per-selector N  the generated calls per selector (4)
  --gas N           the gas budget of a call (100000000)
  --caller ADDR     the caller of the given calls (the world's first actor)
  --value N         the value of the given calls (0)
  --each            every call from the world's state (default: a sequence,
                    the state carried from one call to the next)
  --selectors       print the selectors found, nothing else
  --quiet           the summary only
  --corpus LIST     every contract of LIST (a file of .hex paths, one per
                    line): its calls counted, per contract and in total
  --compare         run every sequence twice, compare the effects (the
                    harness's determinism, compare()'s self-check)
)";

struct Options
{
    WorldConfig world;
    bool world_given = false;
    CallConfig calls;
    RunOptions run;
    std::optional<Word> caller;
    Word value;
    bool each = false;
    bool selectors = false;
    bool quiet = false;
    bool compare = false;
    std::string corpus;
    std::vector<std::string> args;
};

std::optional<Bytes> read_hex_file(const std::string& path)
{
    std::ifstream in{path, std::ios::binary};
    if (!in)
        return std::nullopt;
    std::ostringstream text;
    text << in.rdbuf();
    return parse_hex(text.str());
}

/// The counts of a run.
struct Tally
{
    unsigned long calls = 0, stops = 0, returns = 0, reverts = 0, invalids = 0, exhausted = 0,
                  errors = 0, events = 0, mismatches = 0;
    double seconds = 0;
    std::vector<float> times;  ///< of every call, in microseconds (--corpus)

    void add(const Effects& e)
    {
        ++calls;
        events += e.events.size();
        switch (e.end.status)
        {
        case Status::stop:
            ++stops;
            break;
        case Status::return_:
            ++returns;
            break;
        case Status::revert:
            ++reverts;
            break;
        case Status::invalid:
            ++invalids;
            break;
        case Status::exhausted:
            ++exhausted;
            break;
        default:
            ++errors;
            break;
        }
    }

    void add(const Tally& t)
    {
        calls += t.calls;
        stops += t.stops;
        returns += t.returns;
        reverts += t.reverts;
        invalids += t.invalids;
        exhausted += t.exhausted;
        errors += t.errors;
        events += t.events;
        mismatches += t.mismatches;
        seconds += t.seconds;
        times.insert(times.end(), t.times.begin(), t.times.end());
    }

    /// The distribution of the times of the calls.
    std::string distribution()
    {
        if (times.empty())
            return {};
        std::ranges::sort(times);
        const auto at = [&](double q) {
            return times[std::min(times.size() - 1, static_cast<std::size_t>(q * static_cast<double>(times.size())))];
        };
        char buf[160];
        std::snprintf(buf, sizeof buf, "us/call: median %.1f, p90 %.1f, p99 %.1f, p99.9 %.1f, max %.0f",
            at(0.5), at(0.9), at(0.99), at(0.999), times.back());
        return buf;
    }

    std::string str() const
    {
        char buf[256];
        std::snprintf(buf, sizeof buf,
            "calls %lu: stop %lu return %lu revert %lu invalid %lu exhausted %lu error %lu, "
            "events %lu, %.1f us/call",
            calls, stops, returns, reverts, invalids, exhausted, errors, events,
            calls != 0 ? 1e6 * seconds / static_cast<double>(calls) : 0.0);
        std::string s = buf;
        if (mismatches != 0)
            s += ", MISMATCHES " + std::to_string(mismatches);
        return s;
    }
};

std::string call_header(std::size_t i, const PlannedCall& c)
{
    std::string s = "call " + std::to_string(i);
    if (c.selector)
    {
        char sel[16];
        std::snprintf(sel, sizeof sel, "0x%08x", *c.selector);
        s += " " + std::string{sel} + "/" + std::to_string(c.variant);
    }
    else
        s += " fallback/" + std::to_string(c.variant);
    s += " from " + hex(c.context.caller);
    if (c.context.value != 0)
        s += " value " + hex(c.context.value);
    return s + " calldata " + hex(c.context.calldata);
}

/// The calls of one contract, run (a sequence, or each one from the world).
Tally run_calls(EvmRunner& runner, const SeededWorld& world, const Word& address, const Bytes& code,
    const std::vector<PlannedCall>& calls, const Options& o, bool print)
{
    Tally t;
    State sequence{world, address, code};
    std::vector<Effects> first;
    const auto start = std::chrono::steady_clock::now();
    for (std::size_t i = 0; i < calls.size(); ++i)
    {
        State single{world, address, code};
        const auto call_start = std::chrono::steady_clock::now();
        auto effects = runner.run(o.each ? single : sequence, calls[i].context);
        t.times.push_back(static_cast<float>(
            std::chrono::duration<double, std::micro>(std::chrono::steady_clock::now() - call_start).count()));
        t.add(effects);
        if (print)
            std::cout << call_header(i, calls[i]) << "\n" << to_string(effects) << "\n";
        if (o.compare)
            first.push_back(std::move(effects));
    }
    t.seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
    if (o.compare)
    {
        // the same calls again, from a new state: the same effects
        State again{world, address, code};
        for (std::size_t i = 0; i < calls.size(); ++i)
        {
            State single{world, address, code};
            const auto effects = runner.run(o.each ? single : again, calls[i].context);
            const auto c = validate::compare(first[i], effects);
            if (c.verdict == Verdict::different ||
                (c.verdict == Verdict::inconclusive && !first[i].end.inconclusive()))
            {
                ++t.mismatches;
                std::cout << "MISMATCH " << call_header(i, calls[i]) << ": " << c.message << "\n";
            }
        }
    }
    return t;
}

int run_contract(const std::string& path, const Options& o)
{
    const auto code = read_hex_file(path);
    if (!code)
    {
        std::cerr << "evmrun: " << path << ": not a file of hex\n";
        return 1;
    }
    const SeededWorld world{o.world};
    CallGenerator gen{world, *code, o.calls};
    if (o.selectors)
    {
        for (const auto s : gen.selectors())
            std::printf("0x%08x\n", s);
        return 0;
    }
    std::vector<PlannedCall> calls;
    if (o.args.empty())
        calls = gen.calls();
    else
        for (const auto& a : o.args)
        {
            const auto data = parse_hex(a);
            if (!data)
            {
                std::cerr << "evmrun: " << a << ": not hex calldata\n";
                return 1;
            }
            PlannedCall c;
            c.context.caller = o.caller ? *o.caller : world.actors().front();
            c.context.origin = c.context.caller;
            c.context.value = o.value;
            c.context.gas_price = world.block().base_fee + 1'000'000'000;
            c.context.calldata = *data;
            if (data->size() >= 4)
                c.selector = static_cast<std::uint32_t>(load_word(*data, 0) >> 224);
            calls.push_back(std::move(c));
        }
    EvmRunner runner{*code, o.run};
    const auto t = run_calls(runner, world, world.contract_address(), *code, calls, o, !o.quiet);
    std::cout << path << ": " << (o.world.random ? "random" : "empty") << " world, "
              << gen.selectors().size() << " selectors, " << t.str() << "\n";
    return t.mismatches != 0 ? 2 : 0;
}

int run_corpus(const Options& o)
{
    std::ifstream list{o.corpus};
    if (!list)
    {
        std::cerr << "evmrun: " << o.corpus << ": can't read\n";
        return 1;
    }
    std::vector<bool> modes;
    if (o.world_given)
        modes.push_back(o.world.random);
    else
        modes = {false, true};
    Tally total[2];
    unsigned contracts = 0, unreadable = 0;
    double slowest = 0, generation = 0;
    std::string slowest_name;
    std::string path;
    while (std::getline(list, path))
    {
        if (path.empty())
            continue;
        const auto code = read_hex_file(path);
        if (!code)
        {
            ++unreadable;
            std::cout << path << ": not a file of hex\n";
            continue;
        }
        ++contracts;
        EvmRunner runner{*code, o.run};
        std::string line = path;
        for (const bool random : modes)
        {
            auto config = o.world;
            config.random = random;
            const SeededWorld world{config};
            const auto gen_start = std::chrono::steady_clock::now();
            const CallGenerator gen{world, *code, o.calls};
            const auto planned = gen.calls();
            generation += std::chrono::duration<double>(std::chrono::steady_clock::now() - gen_start).count();
            const auto t = run_calls(runner, world, world.contract_address(), *code, planned, o, false);
            if (t.seconds > slowest)
            {
                slowest = t.seconds;
                slowest_name = path;
            }
            line += std::string{random ? " | random: " : " | empty: "} + std::to_string(gen.selectors().size()) +
                    " selectors, " + t.str();
            total[random].add(t);
        }
        if (!o.quiet)
            std::cout << line << std::endl;
    }
    std::cout << contracts << " contracts";
    if (unreadable != 0)
        std::cout << " (" << unreadable << " unreadable)";
    std::cout << "\n";
    for (const bool random : modes)
        std::cout << (random ? "random world: " : "empty world:  ") << total[random].str() << "\n  "
                  << total[random].distribution() << "\n";
    std::cout << "slowest contract: " << slowest_name << " (" << slowest << " s)\n";
    std::cout << "the calls' generation (selectors found, probed): " << generation << " s\n";
    return (total[0].mismatches + total[1].mismatches) != 0 ? 2 : 0;
}
}  // namespace

int main(int argc, char** argv)
{
    Options o;
    for (int i = 1; i < argc; ++i)
    {
        const std::string_view a = argv[i];
        const auto value = [&]() -> std::optional<std::string_view> {
            if (i + 1 >= argc)
                return std::nullopt;
            return std::string_view{argv[++i]};
        };
        const auto number = [&]() -> std::optional<Word> {
            const auto v = value();
            return v ? parse_number(*v) : std::nullopt;
        };
        std::optional<Word> n;
        switch (evmrun_option(a))
        {
        case EvmrunOption::none:
            if (a.starts_with("-") && a.size() > 1)
            {
                std::cerr << "evmrun: unknown option " << a << "\n" << usage;
                return 1;
            }
            o.args.emplace_back(a);
            continue;
        case EvmrunOption::seed:
            if (!(n = number()) || *n >> 64 != 0)
                break;
            o.world.seed = static_cast<std::uint64_t>(*n);
            continue;
        case EvmrunOption::empty:
            o.world.random = false;
            o.world_given = true;
            continue;
        case EvmrunOption::random:
            o.world.random = true;
            o.world_given = true;
            continue;
        case EvmrunOption::per_selector:
            if (!(n = number()) || *n > 1000)
                break;
            o.calls.per_selector = static_cast<unsigned>(*n);
            continue;
        case EvmrunOption::gas:
            if (!(n = number()) || *n > Word{std::numeric_limits<std::int64_t>::max()})
                break;
            o.run.gas = static_cast<std::int64_t>(*n);
            continue;
        case EvmrunOption::caller:
            if (!(n = number()) || *n > address_mask)
                break;
            o.caller = *n;
            continue;
        case EvmrunOption::value:
            if (!(n = number()))
                break;
            o.value = *n;
            continue;
        case EvmrunOption::selectors:
            o.selectors = true;
            continue;
        case EvmrunOption::quiet:
            o.quiet = true;
            continue;
        case EvmrunOption::corpus:
            if (const auto v = value())
            {
                o.corpus = *v;
                continue;
            }
            break;
        case EvmrunOption::each:
            o.each = true;
            continue;
        case EvmrunOption::compare:
            o.compare = true;
            continue;
        case EvmrunOption::help:
            std::cout << usage;
            return 0;
        }
        std::cerr << "evmrun: " << a << ": a value is missing or wrong\n" << usage;
        return 1;
    }
    if (!o.corpus.empty())
        return run_corpus(o);
    if (o.args.empty())
    {
        std::cerr << usage;
        return 1;
    }
    const auto path = o.args.front();
    o.args.erase(o.args.begin());
    return run_contract(path, o);
}
