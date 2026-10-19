// text_check: the decompiled texts parsed (text_parser.hpp), and run
// (text_interp.hpp) against evmone on the same calls: how faithful a text
// is to its bytecode.
//
//   text_check parse FILE...      parses the texts, prints their errors
//   text_check run [options] HEX TEXT
//   text_check run [options] --corpus LIST --texts DIR
//                                 each contract of LIST (.hex paths) with its
//                                 text DIR/NAME.txt: the calls of the
//                                 CallGenerator, on evmone and on the text
#include "validate/calls.hpp"
#include "validate/effects.hpp"
#include "validate/evm_runner.hpp"
#include "validate/scan.hpp"
#include "validate/session.hpp"
#include "validate/text_check.hpp"
#include "validate/text_interp.hpp"
#include "validate/text_parser.hpp"
#include "validate/world.hpp"

#include "sigdb.hpp"

#include <array>
#include <chrono>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <algorithm>
#include <map>
#include <memory>
#include <ranges>
#include <span>
#include <sstream>
#include <string>
#include <vector>

namespace
{
using namespace validate;
using namespace validate::text;

constexpr char usage[] =
    R"(usage: text_check parse FILE...
       text_check run [options] CONTRACT.hex CONTRACT.txt
       text_check run [options] --corpus LIST --texts DIR
Parses decompiled texts; runs them against evmone on the same calls (the
CallGenerator's, against the same SeededWorld) and compares the effects.
  --seed N          the world's seed (0)
  --empty           the empty world (default: both worlds)
  --random          the random world
  --per-selector N  the generated calls per selector (4)
  --params DIR      side information: DIR/NAME.txt, lines 0xSELECTOR OFFSET[:TYPE]...
                    (_fallback OFFSET[:TYPE]...): where an unknown function's, the
                    fallback's params are, which the text doesn't say (without it:
                    at consecutive places, and their calls are counted apart)
  --each            each call from the world's state (default: a sequence)
  --sigdb FILE      the signature database (the names of a struct param's members)
  --call N          the call N only, its effects (with --each: from the world's state)
  --trace           the lines of the text the calls run, the values they set
  --verbose         every call's effects, both sides (one contract)
  --quiet           the totals only
)";

/// The names of a param's components (a tuple's fields, through its arrays):
/// the signature database's, python's _param<i + 1> for those it hasn't.
NameTree name_tree(std::string_view name, pan::sigdb::Type type, unsigned index)
{
    using pan::sigdb::TypeKind;
    NameTree n;
    n.name = name.empty() ? "_param" + std::to_string(index + 1) : std::string(name);
    for (;;)
    {
        const auto k = type.kind();
        if (k != TypeKind::array && k != TypeKind::static_array && k != TypeKind::storage
            && k != TypeKind::memory && k != TypeKind::calldata)
            break;
        type = type.element();
    }
    if (type.kind() == TypeKind::tuple)
    {
        unsigned i = 0;
        for (const auto field : type.fields())
            n.components.push_back(name_tree(field.name(), field.type(), i++));
    }
    return n;
}

ParamNames param_names(const pan::sigdb::Database& db)
{
    return [&db](std::uint32_t selector) -> std::optional<std::vector<NameTree>> {
        const auto entry = db.function(selector);
        if (!entry)
            return std::nullopt;
        std::vector<NameTree> out;
        unsigned i = 0;
        for (const auto field : entry->params())
            out.push_back(name_tree(field.name(), field.type(), i++));
        return out;
    };
}

std::optional<std::string> read_file(const std::string& path)
{
    std::ifstream in{path, std::ios::binary};
    if (!in)
        return std::nullopt;
    std::ostringstream s;
    s << in.rdbuf();
    return s.str();
}

int parse_files(int argc, char** argv, int first)
{
    unsigned files = 0, bad = 0, errors = 0;
    std::size_t functions = 0, statements = 0;
    const auto start = std::chrono::steady_clock::now();
    for (int i = first; i < argc; ++i)
    {
        const auto text = read_file(argv[i]);
        if (!text)
        {
            std::cerr << argv[i] << ": can't read\n";
            ++bad;
            continue;
        }
        const Program p = parse(*text);
        ++files;
        functions += p.functions.size();
        statements += p.stmts.size();
        if (!p.errors.empty())
        {
            ++bad;
            errors += static_cast<unsigned>(p.errors.size());
            for (const auto& e : p.errors)
                std::cout << argv[i] << ": " << e << "\n";
        }
    }
    const double s = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
    std::cout << files << " texts parsed in " << s << " s: " << functions << " functions, " << statements
              << " statements; " << bad << " with errors (" << errors << " lines)\n";
    return bad != 0 ? 1 : 0;
}

struct Options
{
    WorldConfig world;
    bool world_given = false;
    CallConfig calls;
    bool each = false;
    bool verbose = false;
    std::optional<std::size_t> only;  // --call N: that call only (and --trace its statements)
    bool trace = false;
    bool quiet = false;
    std::string corpus;
    std::string texts;
    std::string params;  // a directory of NAME.txt: the params' positions
    std::string sigdb;   // the signature database: the names of the struct params' members
    const pan::sigdb::Database* db = nullptr;
    std::vector<std::string> args;
};

struct Counts
{
    unsigned long calls = 0, same = 0, different = 0, unsupported = 0, exhausted = 0, evm_inconclusive = 0;
    unsigned long same_success = 0, same_events = 0;  // the same calls that succeeded, that had events

    void add(const Counts& c)
    {
        calls += c.calls;
        same += c.same;
        same_success += c.same_success;
        same_events += c.same_events;
        different += c.different;
        unsupported += c.unsupported;
        exhausted += c.exhausted;
        evm_inconclusive += c.evm_inconclusive;
    }

    std::string str() const
    {
        char buf[256];
        std::snprintf(buf, sizeof buf,
            "calls %lu: same %lu (%lu succeeded, %lu with events), different %lu, unsupported %lu, exhausted %lu, "
            "evm inconclusive %lu",
            calls, same, same_success, same_events, different, unsupported, exhausted, evm_inconclusive);
        return buf;
    }
};

struct Tally
{
    Counts exact;    // the calls of functions whose params' places the text, or side information, says
    Counts guessed;  // the others' (an unknown function's, the fallback's): consecutive places
    unsigned contracts = 0, unparsed_contracts = 0, all_same = 0;
    std::array<std::uint64_t, static_cast<std::size_t>(Unsupported::count)> reasons{};
    std::map<std::string, unsigned long> differences;  // the first words of the messages

    void add(const Tally& t)
    {
        exact.add(t.exact);
        guessed.add(t.guessed);
        contracts += t.contracts;
        unparsed_contracts += t.unparsed_contracts;
        all_same += t.all_same;
        for (std::size_t i = 0; i < reasons.size(); ++i)
            reasons[i] += t.reasons[i];
        for (const auto& [k, n] : t.differences)
            differences[k] += n;
    }

    bool all_agree() const
    {
        return exact.different + exact.unsupported + exact.exhausted + guessed.different + guessed.unsupported
                   + guessed.exhausted
               == 0;
    }

    std::string str() const
    {
        return exact.str() + (guessed.calls != 0 ? " + guessed params' places: " + guessed.str() : "");
    }
};

/// Whether a function's params are at places guessed: the text doesn't say
/// where, and no side information did (place_params).
bool guessed_places(const Function& f)
{
    return f.places_unknown && !f.placed && !f.params.empty();
}

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
    if (c.context.value != 0)
        s += " value " + hex(c.context.value);
    return s + " calldata " + hex(c.context.calldata);
}

/// The kind of a difference: the start of compare()'s message.
std::string difference_kind(const std::string& message)
{
    const auto colon = message.find(':');
    return colon == std::string::npos ? message.substr(0, 40) : message.substr(0, colon);
}

Tally run_contract(const Bytes& code, const Program& program, const Options& o, bool random,
    std::string* first_difference)
{
    Tally t;
    auto config = o.world;
    config.random = random;
    const SeededWorld world{config};
    const CallGenerator gen{world, code, o.calls};
    const auto planned = gen.calls();
    EvmRunner runner{code};
    Interpreter interp{program};
    if (o.db != nullptr)
        interp.set_param_names(param_names(*o.db));
    State evm_state{world, world.contract_address(), code};
    State text_state{world, world.contract_address(), code};
    if (o.trace)
        interp.set_trace([](std::uint32_t line, const Word* value) {
            if (value == nullptr)
                std::cout << "  line " << line << "\n";
            else
                std::cout << "    = " << hex(*value) << "\n";
        });
    for (std::size_t i = 0; i < planned.size(); ++i)
    {
        if (o.only && *o.only != i)
            continue;
        const auto& call = planned[i].context;
        State evm_single{world, world.contract_address(), code};
        State text_single{world, world.contract_address(), code};
        const Effects evm = runner.run(o.each ? evm_single : evm_state, call);
        const Effects mine = interp.run(o.each ? text_single : text_state, call);
        const auto fn = interp.function_for(call.calldata);
        const bool guessed = fn && guessed_places(program.functions[*fn]);
        Counts& n = guessed ? t.guessed : t.exact;
        ++n.calls;
        const auto c = compare(evm, mine);
        if (!o.each && c.verdict != Verdict::same)
        {
            // the sequence goes on from the same state on both sides: no
            // difference (an inconclusive call) passed on to the next calls
            text_state = evm_state;
        }
        if (o.verbose)
            std::cout << call_header(i, planned[i]) << (guessed ? " (guessed params' places)" : "") << "\n  evm:  "
                      << to_string(evm.end) << "\n  text: " << to_string(mine.end) << "\n  "
                      << (c.verdict == Verdict::same ? "same" : c.message) << "\n";
        if (evm.end.inconclusive())
            ++n.evm_inconclusive;
        else if (mine.end.status == Status::unsupported || mine.end.status == Status::error)
            ++n.unsupported;
        else if (mine.end.status == Status::exhausted)
            ++n.exhausted;
        else if (c.verdict == Verdict::same)
        {
            ++n.same;
            n.same_success += evm.end.success() ? 1 : 0;
            n.same_events += evm.events.empty() ? 0 : 1;
        }
        else
        {
            ++n.different;
            ++t.differences[difference_kind(c.message)];
            if (first_difference != nullptr && first_difference->empty())
                *first_difference = call_header(i, planned[i]) + (guessed ? " (guessed params' places)" : "") + ": "
                                    + c.message;
        }
    }
    t.reasons = interp.unsupported();
    return t;
}

int run(const Options& o)
{
    std::vector<std::pair<std::string, std::string>> pairs;  // hex, text
    if (!o.corpus.empty())
    {
        std::ifstream list{o.corpus};
        if (!list)
        {
            std::cerr << "text_check: " << o.corpus << ": can't read\n";
            return 1;
        }
        std::string path;
        while (std::getline(list, path))
            if (!path.empty())
                pairs.emplace_back(path, o.texts + "/" + std::filesystem::path(path).stem().string() + ".txt");
    }
    else if (o.args.size() == 2)
        pairs.emplace_back(o.args[0], o.args[1]);
    else
    {
        std::cerr << usage;
        return 1;
    }
    std::vector<bool> modes;
    if (o.world_given)
        modes.push_back(o.world.random);
    else
        modes = {false, true};
    Tally total[2];
    for (const auto& [hex_path, text_path] : pairs)
    {
        const auto hex_text = read_file(hex_path);
        const auto code = hex_text ? parse_hex(*hex_text) : std::nullopt;
        const auto text = read_file(text_path);
        if (!code || !text)
        {
            std::cout << hex_path << ": can't read it or its text\n";
            continue;
        }
        Program program = parse(*text);
        std::string line = hex_path;
        if (!program.errors.empty())
            line += " (" + std::to_string(program.errors.size()) + " lines unparsed)";
        if (!o.params.empty())
        {
            // the side information: where the params the text doesn't place
            // are (an unknown function's, the fallback's), their types
            const auto file = read_file(o.params + "/" + std::filesystem::path(hex_path).stem().string() + ".txt");
            const auto side = file ? parse_side_info(*file) : std::nullopt;
            unsigned moved = 0;
            if (side)
                for (const auto& s : *side)
                {
                    std::vector<ParamPlace> places;
                    for (const auto& sp : s.places)
                        places.push_back({sp.offset, sp.type.empty() ? std::nullopt : parse_type(sp.type)});
                    std::vector<std::uint32_t> before;
                    for (const auto& f : program.functions)
                        if (s.selector ? f.kind == Function::regular && f.selector == *s.selector
                                       : f.kind == Function::fallback)
                            for (const auto& p : f.params)
                                before.push_back(p.position);
                    if (place_params(program, s.selector, places)
                        && !std::ranges::equal(before, s.places | std::views::take(before.size())
                                                           | std::views::transform(&SidePlace::offset)))
                        ++moved;
                }
            else
                line += " (no side information)";
            if (moved != 0)
                line += " (" + std::to_string(moved) + " functions' params moved)";
        }
        if (const auto n = std::ranges::count_if(program.functions, guessed_places); n != 0)
            line += " (" + std::to_string(n) + " functions' params at guessed places)";
        for (const bool random : modes)
        {
            std::string first;
            Tally t = run_contract(*code, program, o, random, &first);
            t.contracts = 1;
            t.unparsed_contracts = program.errors.empty() ? 0 : 1;
            t.all_same = t.all_agree() ? 1 : 0;
            line += std::string(random ? " | random: " : " | empty: ") + t.str();
            if (!first.empty())
                line += "\n    first difference: " + first;
            total[random].add(t);
        }
        if (!o.quiet)
            std::cout << line << std::endl;
    }
    for (const bool random : modes)
    {
        const Tally& t = total[random];
        std::cout << (random ? "random world: " : "empty world:  ") << t.contracts << " contracts ("
                  << t.unparsed_contracts << " with unparsed lines, " << t.all_same << " all same), "
                  << t.exact.str() << "\n";
        if (t.guessed.calls != 0)
            std::cout << "    apart, the calls of the functions whose params' places are guessed (no side "
                         "information): "
                      << t.guessed.str() << "\n";
        for (std::size_t i = 0; i < t.reasons.size(); ++i)
            if (t.reasons[i] != 0)
                std::cout << "    unsupported: " << to_string(static_cast<Unsupported>(i)) << ": " << t.reasons[i]
                          << "\n";
        for (const auto& [k, n] : t.differences)
            std::cout << "    different: " << k << ": " << n << "\n";
    }
    return 0;
}
}  // namespace

int main(int argc, char** argv)
{
    if (argc < 2)
    {
        std::cerr << usage;
        return 1;
    }
    switch (check_word(argv[1]))
    {
    case CheckWord::parse:
        return parse_files(argc, argv, 2);
    case CheckWord::run:
        break;
    default:
        std::cerr << usage;
        return 1;
    }
    Options o;
    for (int i = 2; i < argc; ++i)
    {
        const std::string_view a = argv[i];
        const auto value = [&]() -> std::string_view { return i + 1 < argc ? argv[++i] : ""; };
        switch (check_word(a))
        {
        case CheckWord::seed:
        {
            const auto n = parse_number(value());
            if (!n || *n >> 64 != 0)
                return std::cerr << usage, 1;
            o.world.seed = static_cast<std::uint64_t>(*n);
            break;
        }
        case CheckWord::empty:
            o.world.random = false;
            o.world_given = true;
            break;
        case CheckWord::random:
            o.world.random = true;
            o.world_given = true;
            break;
        case CheckWord::per_selector:
        {
            const auto n = parse_number(value());
            if (!n || *n > 1000)
                return std::cerr << usage, 1;
            o.calls.per_selector = static_cast<unsigned>(*n);
            break;
        }
        case CheckWord::each:
            o.each = true;
            break;
        case CheckWord::verbose:
            o.verbose = true;
            break;
        case CheckWord::quiet:
            o.quiet = true;
            break;
        case CheckWord::corpus:
            o.corpus = value();
            break;
        case CheckWord::texts:
            o.texts = value();
            break;
        case CheckWord::params:
            o.params = value();
            break;
        case CheckWord::call:
        {
            const auto n = parse_number(value());
            if (!n || *n > 1000000)
                return std::cerr << usage, 1;
            o.only = static_cast<std::size_t>(*n);
            o.verbose = true;
            break;
        }
        case CheckWord::trace:
            o.trace = true;
            break;
        case CheckWord::sigdb:
            o.sigdb = value();
            break;
        case CheckWord::none:
            o.args.emplace_back(a);
            break;
        case CheckWord::unknown:
            std::cerr << "text_check: unknown option " << a << "\n" << usage;
            return 1;
        default:
            std::cerr << usage;
            return 1;
        }
    }
    std::unique_ptr<pan::sigdb::Database> db;
    if (!o.sigdb.empty())
    {
        try
        {
            db = pan::sigdb::Database::open(o.sigdb);
        }
        catch (const std::exception& e)
        {
            std::cerr << "text_check: " << o.sigdb << ": " << e.what() << "\n";
            return 1;
        }
        o.db = db.get();
    }
    return run(o);
}
