// stagecheck: the validation of the decompiler's stages by execution (lot
// 11, AGENTS.md rule 5): each contract decompiled up to a stage, its calls
// run by evmone and by the trace machine on every stage's trace against the
// same worlds, the effects compared - per contract, and over a corpus: the
// counts by stage, by category of difference, and the first stage that
// diverges (stage_check.hpp).
#include "scan.hpp"
#include "stage_check.hpp"

#include "core/budget.hpp"
#include "core/errors.hpp"
#include "core/jobs.hpp"
#include "core/platform.hpp"
#include "driver/pipeline.hpp"
#include "sigdb.hpp"

#include <algorithm>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

namespace
{
using namespace validate;

constexpr char usage[] =
    R"(usage: stagecheck [options] CONTRACT.hex...
       stagecheck [options] --corpus LIST
Decompiles each contract up to a stage, runs its calls (the selectors found
in its dispatcher, typed by the signature database, and the fallback's) in
evmone and in the trace machine on each stage's trace, and compares their
effects: a sequence of calls on the empty world, each call alone on a random
world. Prints per contract the calls the same, different (by category),
inconclusive (by reason) and the traces' bugs, with examples; then the
totals and the first stage that diverges.
  --stage S         the last stage checked: raw (the default), whiles,
                    simplified, analysed, folded
  --corpus LIST     the contracts of LIST (a file of .hex paths, one per line)
  --limit N         the first N contracts of the corpus only
  --seed N          the worlds' seed (0)
  --seeds N         the random worlds (seed, seed + 1...: 1)
  --empty           the empty world's sequence only
  --random          the random world's calls only
  --per-selector N  the calls per selector (4)
  --sigdb FILE      the signature database (pancxx's: $PANORAMIX_SIGDB, else
                    the cache's) for typed arguments
  --untyped         random words for every selector
  -j, --jobs N      the contracts checked at once (1)
  --show N          the examples shown per stage of a contract (3)
  --quiet           a line per contract and the totals, no examples
  --timeout S       the time limit of a contract, in seconds (900; 0: none)
  --steps N         the trace machine's steps per call (4000000)
  --gas N           evmone's gas per call (100000000)
  --function SEL    the calls of that selector only (0x... or decimal)
Exit status: 0 when no stage differs, 2 when one does, 1 on an error.
)";

struct Options
{
    CheckConfig check;
    bool world_given = false;
    std::string corpus;
    std::vector<std::string> files;
    unsigned jobs = 1;
    unsigned long limit = 0;
    unsigned show = 3;
    bool quiet = false;
    std::string sigdb;
    bool untyped = false;
};

/// The decompiler's pipeline (lot 12's driver::run_until): one run makes
/// every stage up to `upto` the build has (driver::stage_available) - the
/// functions the dispatcher reaches, each on a context of its own (lot 5's
/// VM, lot 6's whiles, lot 7's simplifier...), the recursive internal
/// functions in waves - and keeps each stage's traces, imported into the
/// check's context. A function that fails at a stage has no trace there
/// (problem set); its earlier stages are checked.
void pipeline(Decompiled& c, Stage upto, pan::Budget& budget, const pan::sigdb::Database* db)
{
    pan::driver::PipelineOptions o;
    o.threads = 1;  // (the contracts are checked in parallel)
    o.keep = pan::driver::KEEP_ALL;
    o.db = db;
    o.function_memory = budget.limits().memory;
    const auto r = pan::driver::run_until(c.code, static_cast<pan::driver::Stage>(upto), o);
    for (unsigned s = 0; s < stage_count; ++s)
        if (r.kept[s])
        {
            c.functions[s] = r.functions[s];
            c.internals[s] = r.internals[s];
            c.made[s] = true;
        }
    c.storage = r.storage;
    c.safemath = r.safemath;
}

std::optional<Bytes> read_hex_file(const std::string& path)
{
    std::ifstream in{path, std::ios::binary};
    if (!in)
        return std::nullopt;
    std::ostringstream text;
    text << in.rdbuf();
    return parse_hex(text.str());
}

/// A contract's check, made into text.
struct Done
{
    bool readable = true;
    StageReport report;
    std::string text;
};

std::string indent(const std::string& s, const char* prefix)
{
    std::string out;
    std::size_t start = 0;
    while (start < s.size())
    {
        auto end = s.find('\n', start);
        if (end == std::string::npos)
            end = s.size();
        out += prefix + s.substr(start, end - start) + "\n";
        start = end + 1;
    }
    return out;
}

std::string render(const std::string& path, const Done& d, const Options& o)
{
    if (!d.readable)
        return path + ": not a file of hex\n";
    std::string s = path + ": " + summary(d.report);
    if (d.report.first_divergent)
        s += std::string{" | first divergent: "} + stage_name(*d.report.first_divergent);
    s += "\n";
    if (o.quiet)
        return s;
    for (unsigned i = 0; i < stage_count; ++i)
    {
        const auto& r = d.report.stages[i];
        unsigned shown = 0;
        for (const auto& x : r.examples)
        {
            if (shown++ >= o.show)
                break;
            s += std::string{"  "} + stage_name(static_cast<Stage>(i)) + " " + category_name(x.category) + ": " +
                 x.call + "\n";
            s += "    " + x.message + "\n";
            if (!x.where.empty())
                s += "    at " + x.where + "\n";
            if (!x.expected.empty())
                s += "    evm:\n" + indent(x.expected, "      ");
            if (!x.actual.empty())
                s += "    machine:\n" + indent(x.actual, "      ");
        }
        shown = 0;
        for (const auto& x : r.inconclusive_examples)
        {
            if (shown++ >= o.show)
                break;
            s += std::string{"  "} + stage_name(static_cast<Stage>(i)) + " inconclusive: " + x.call + "\n";
            s += "    " + x.message + "\n";
            if (!x.where.empty())
                s += "    at " + x.where + "\n";
        }
    }
    return s;
}

/// The totals of a corpus.
struct Totals
{
    unsigned contracts = 0, unreadable = 0, failed = 0, stopped = 0;
    std::array<StageResult, stage_count> stages{};
    std::array<unsigned, stage_count> ran{}, clean{}, first{};

    void add(const Done& d)
    {
        ++contracts;
        if (!d.readable)
        {
            ++unreadable;
            return;
        }
        const auto& rep = d.report;
        if (!rep.ran)
        {
            ++failed;
            return;
        }
        if (!rep.failure.empty())
            ++stopped;
        for (unsigned i = 0; i < stage_count; ++i)
        {
            const auto& r = rep.stages[i];
            if (!r.ran)
                continue;
            ++ran[i];
            auto& t = stages[i];
            t.same += r.same;
            t.different += r.different;
            t.inconclusive += r.inconclusive;
            t.bugs += r.bugs;
            t.unsized += r.unsized;
            for (unsigned e = 0; e < t.same_by_end.size(); ++e)
                t.same_by_end[e] += r.same_by_end[e];
            for (unsigned c = 0; c < category_count; ++c)
                t.by_category[c] += r.by_category[c];
            for (unsigned w = 0; w < why_count; ++w)
                t.by_why[w] += r.by_why[w];
            clean[i] += r.different + r.bugs == 0;
        }
        if (rep.first_divergent)
            ++first[static_cast<unsigned>(*rep.first_divergent)];
    }

    std::string str() const
    {
        std::string s = std::to_string(contracts) + " contracts";
        if (unreadable != 0)
            s += ", " + std::to_string(unreadable) + " unreadable";
        s += ", " + std::to_string(failed) + " not decompiled, " + std::to_string(stopped) + " stopped (a limit)\n";
        for (unsigned i = 0; i < stage_count; ++i)
        {
            if (ran[i] == 0)
                continue;
            const auto& t = stages[i];
            const auto calls = t.same + t.different + t.inconclusive + t.bugs;
            s += std::string{"stage "} + stage_name(static_cast<Stage>(i)) + ": " + std::to_string(ran[i]) +
                 " contracts, " + std::to_string(clean[i]) + " with no difference; calls " + std::to_string(calls) +
                 ": same " + std::to_string(t.same) + " (stop " + std::to_string(t.same_by_end[0]) + " return " +
                 std::to_string(t.same_by_end[1]) + " revert " + std::to_string(t.same_by_end[2]) + " invalid " +
                 std::to_string(t.same_by_end[3]) + "), different " + std::to_string(t.different) + " (";
            for (unsigned c = 0; c < static_cast<unsigned>(Category::bug); ++c)
                s += std::string{c ? " " : ""} + category_name(static_cast<Category>(c)) + " " +
                     std::to_string(t.by_category[c]);
            s += "), bugs " + std::to_string(t.bugs) + ", unsized " + std::to_string(t.unsized) +
                 ", inconclusive " + std::to_string(t.inconclusive) + " (";
            for (unsigned w = 0; w < why_count; ++w)
                s += std::string{w ? " " : ""} + why_name(static_cast<Why>(w)) + " " + std::to_string(t.by_why[w]);
            s += ")\n";
        }
        s += "first divergent stage:";
        for (unsigned i = 0; i < stage_count; ++i)
            if (ran[i] != 0)
                s += std::string{" "} + stage_name(static_cast<Stage>(i)) + " " + std::to_string(first[i]);
        return s + "\n";
    }

    bool diverged() const
    {
        for (unsigned i = 0; i < stage_count; ++i)
            if (stages[i].different + stages[i].bugs != 0)
                return true;
        return false;
    }
};
}  // namespace

int main(int argc, char** argv)
{
    // the decompiler's log: its warnings and errors only (its INFO lines,
    // a few per function, would drown the report), unless PANORAMIX_LOG says
    if (!std::getenv("PANORAMIX_LOG"))
        pan::set_log_level(pan::log_warning);
    Options o;
    o.check.timeout_ns = 900 * pan::limits::SEC;
    for (int i = 1; i < argc; ++i)
    {
        const std::string_view a = argv[i];
        const auto value = [&]() -> std::optional<std::string_view> {
            if (i + 1 >= argc)
                return std::nullopt;
            return std::string_view{argv[++i]};
        };
        const auto number = [&]() -> std::optional<std::uint64_t> {
            const auto v = value();
            if (!v)
                return std::nullopt;
            const auto n = parse_number(*v);
            if (!n || *n >> 63 != 0)
                return std::nullopt;
            return static_cast<std::uint64_t>(*n);
        };
        std::optional<std::uint64_t> n;
        switch (stagecheck_option(a))
        {
        case StagecheckOption::none:
            if (a.starts_with("-") && a.size() > 1)
            {
                std::cerr << "stagecheck: unknown option " << a << "\n" << usage;
                return 1;
            }
            o.files.emplace_back(a);
            continue;
        case StagecheckOption::stage:
            if (const auto v = value())
                if (const auto s = parse_stage(*v))
                {
                    o.check.upto = *s;
                    continue;
                }
            break;
        case StagecheckOption::corpus:
            if (const auto v = value())
            {
                o.corpus = *v;
                continue;
            }
            break;
        case StagecheckOption::seed:
            if (!(n = number()))
                break;
            o.check.seed = *n;
            continue;
        case StagecheckOption::empty:
            o.check.empty_world = true;
            o.check.random_world = o.world_given && o.check.random_world;
            o.world_given = true;
            continue;
        case StagecheckOption::random:
            o.check.random_world = true;
            o.check.empty_world = o.world_given && o.check.empty_world;
            o.world_given = true;
            continue;
        case StagecheckOption::per_selector:
            if (!(n = number()) || *n > 1000)
                break;
            o.check.calls.per_selector = static_cast<unsigned>(*n);
            continue;
        case StagecheckOption::sigdb:
            if (const auto v = value())
            {
                o.sigdb = *v;
                continue;
            }
            break;
        case StagecheckOption::untyped:
            o.untyped = true;
            continue;
        case StagecheckOption::jobs:
            if (!(n = number()) || *n == 0 || *n > pan::limits::MAX_THREADS)
                break;
            o.jobs = static_cast<unsigned>(*n);
            continue;
        case StagecheckOption::limit:
            if (!(n = number()))
                break;
            o.limit = *n;
            continue;
        case StagecheckOption::show:
            if (!(n = number()) || *n > 1000)
                break;
            o.show = static_cast<unsigned>(*n);
            o.check.keep = std::max(o.check.keep, o.show);
            continue;
        case StagecheckOption::quiet:
            o.quiet = true;
            continue;
        case StagecheckOption::timeout:
            if (!(n = number()) || *n > 1'000'000)
                break;
            o.check.timeout_ns = static_cast<std::int64_t>(*n) * pan::limits::SEC;
            continue;
        case StagecheckOption::steps:
            if (!(n = number()) || *n == 0 || *n > 0xffffffffu)
                break;
            o.check.machine.steps = static_cast<std::uint32_t>(*n);
            continue;
        case StagecheckOption::gas:
            if (!(n = number()) || *n == 0)
                break;
            o.check.evm.gas = static_cast<std::int64_t>(*n);
            continue;
        case StagecheckOption::function:
            if (!(n = number()) || *n > 0xffffffffu)
                break;
            o.check.only = static_cast<std::uint32_t>(*n);
            continue;
        case StagecheckOption::seeds:
            if (!(n = number()) || *n == 0 || *n > 1000)
                break;
            o.check.random_seeds = static_cast<unsigned>(*n);
            continue;
        case StagecheckOption::help:
            std::cout << usage;
            return 0;
        }
        std::cerr << "stagecheck: " << a << ": a value is missing or wrong\n" << usage;
        return 1;
    }

    // the typed arguments
    std::unique_ptr<pan::sigdb::Database> owned;
    const pan::sigdb::Database* db = nullptr;
    if (!o.sigdb.empty())
    {
        try
        {
            owned = pan::sigdb::Database::open(o.sigdb);
        }
        catch (const pan::sigdb::Error& e)
        {
            std::cerr << "stagecheck: " << o.sigdb << ": " << e.what() << "\n";
            return 1;
        }
        db = owned.get();
    }
    else
        db = pan::sigdb::get();
    if (!o.untyped)
        o.check.db = db;

    // the contracts
    std::vector<std::string> paths = o.files;
    if (!o.corpus.empty())
    {
        std::ifstream list{o.corpus};
        if (!list)
        {
            std::cerr << "stagecheck: " << o.corpus << ": can't read\n";
            return 1;
        }
        std::string path;
        while (std::getline(list, path))
            if (!path.empty())
                paths.push_back(path);
    }
    if (o.limit != 0 && paths.size() > o.limit)
        paths.resize(o.limit);
    if (paths.empty())
    {
        std::cerr << usage;
        return 1;
    }
    for (unsigned s = 0; s <= static_cast<unsigned>(o.check.upto); ++s)
        if (!pan::driver::stage_available(static_cast<pan::driver::Stage>(s)))
            std::cout << "(the " << stage_name(static_cast<Stage>(s)) << " stage isn't in this build: not checked)\n";
    std::cout << "stagecheck: " << paths.size() << " contracts, seed " << o.check.seed << ", "
              << (o.check.db != nullptr ? "typed" : "untyped") << " calldata, "
              << (o.check.empty_world ? (o.check.random_world ? "empty and random worlds" : "the empty world") :
                                        "the random world")
              << std::endl;

    // each contract on a worker (64 MiB stacks), the results printed in order
    std::vector<Done> done(paths.size());
    std::vector<char> finished(paths.size(), 0);
    std::mutex lock;
    std::size_t next = 0;
    Totals totals;
    const auto job = [&](std::size_t i) {
        Done d;
        try
        {
            if (const auto code = read_hex_file(paths[i]))
                d.report = check_contract(*code, o.check, [&](Decompiled& c, Stage upto, pan::Budget& b) {
                    pipeline(c, upto, b, db);
                });
            else
                d.readable = false;
        }
        catch (const std::exception& e)
        {
            d.report.failure = std::string{"the check failed: "} + e.what();
        }
        d.text = render(paths[i], d, o);
        std::lock_guard<std::mutex> g{lock};
        done[i] = std::move(d);
        finished[i] = 1;
        while (next < done.size() && finished[next])
        {
            std::cout << done[next].text << std::flush;
            totals.add(done[next]);
            done[next].text.clear();
            done[next].report.stages = {};
            ++next;
        }
    };
    std::exception_ptr failure;
    auto runner = pan::platform::spawn(
        [&] {
            try
            {
                pan::parallel_for(paths.size(), o.jobs, job);
            }
            catch (...)
            {
                failure = std::current_exception();
            }
        },
        pan::limits::WORKER_STACK);
    runner.join();
    if (failure)
    {
        try
        {
            std::rethrow_exception(failure);
        }
        catch (const std::exception& e)
        {
            std::cerr << "stagecheck: " << e.what() << "\n";
        }
        return 1;
    }
    std::cout << totals.str();
    return totals.diverged() ? 2 : 0;
}
