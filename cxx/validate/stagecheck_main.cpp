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
#include "sigdb.hpp"
#include "vm/vm.hpp"

#include <algorithm>
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

/// The pipeline until lot 12's run_until: lot 5's raw traces - the functions
/// the dispatcher reaches (discover), each one's trace (run_function), and
/// the recursive internal functions found, in waves (each wave runs every
/// function again with the internals known so far).
void raw_pipeline(Decompiled& c, Stage, pan::Budget& budget)
{
    constexpr unsigned max_waves = 8;
    auto& fns = c.functions[0];
    auto& internals = c.internals[0];
    fns = pan::vm::discover(c.shared, budget);
    std::vector<pan::vm::InternalEntry> known;
    for (unsigned wave = 0; wave < max_waves; ++wave)
    {
        std::vector<pan::vm::InternalEntry> found;
        const auto run = [&](pan::FunctionInfo& f) {
            pan::vm::VmOptions opts;
            opts.known_internals = &known;
            try
            {
                auto r = pan::vm::run_function(c.shared, f, opts);
                f.trace = r.trace;
                f.calls = std::move(r.calls);
                f.loops = std::move(r.loops);
                f.problem.reset();
                for (const auto& e : r.found_internals)
                    if (std::find(known.begin(), known.end(), e) == known.end() &&
                        std::find(found.begin(), found.end(), e) == found.end())
                        found.push_back(e);
            }
            catch (const pan::Error&)
            {
                f.trace = pan::Value{};
                f.problem = 0;
            }
        };
        for (auto& f : fns)
            run(f);
        for (auto& f : internals)
            run(f);
        if (found.empty())
            break;
        for (const auto& e : found)
        {
            known.push_back(e);
            pan::FunctionInfo f;
            f.kind = pan::FunctionInfo::Kind::Internal;
            f.entry_pc = e.entry;
            f.params.resize(e.nargs);
            internals.push_back(std::move(f));
        }
    }
    c.made[static_cast<unsigned>(Stage::raw)] = true;
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
    if (o.check.upto > Stage::raw)
        std::cout << "(the stages past raw need lot 12's pipeline: only raw is checked for now)\n";
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
                d.report = check_contract(*code, o.check, raw_pipeline);
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
