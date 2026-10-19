// Lot 12: the driver - the pipeline's stages, the jobs and their waves, the
// problems, the limits, the outputs' determinism at any thread count.
#include <doctest/doctest.h>

#include <filesystem>
#include <format>
#include <fstream>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <vector>

#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/dump.hpp"
#include "core/errors.hpp"
#include "core/platform.hpp"
#include "driver/pipeline.hpp"
#include "hex.hpp"

using namespace pan;
using driver::ContractResult;
using driver::Stage;

namespace {

// a context of its own for a test, on the calling thread
struct Fixture {
    Budget budget{Budget::Limits{}};
    std::unique_ptr<Context> ctx;
    std::optional<ContextScope> scope;
    explicit Fixture(Budget::Limits l = {}) : budget(l)
    {
        init();
        budget.attach_thread();
        ctx = Context::create(budget);
        scope.emplace(*ctx);
    }
    ~Fixture()
    {
        scope.reset();
        ctx.reset();
        budget.detach_thread();
    }
};

std::vector<u8> bytes_of(std::string_view hex)
{
    auto b = hex::decode(hex);
    REQUIRE(b.has_value());
    return *b;
}

// the repository's tests/ (the corpus, the synthetic contracts)
std::optional<std::filesystem::path> tests_dir()
{
    for (const std::filesystem::path& p :
         {std::filesystem::path("../tests"), std::filesystem::path(__FILE__).parent_path() / "../../tests"}) {
        std::error_code e;
        if (std::filesystem::is_directory(p / "corpus", e))
            return p;
    }
    return std::nullopt;
}

std::optional<std::vector<u8>> contract(std::string_view rel)
{
    const auto dir = tests_dir();
    if (!dir)
        return std::nullopt;
    std::ifstream in(*dir / rel, std::ios::binary);
    if (!in)
        return std::nullopt;
    std::stringstream s;
    s << in.rdbuf();
    auto b = hex::decode(s.str());
    if (!b)
        return std::nullopt;
    return *b;
}

// the log quiet for a test (the driver's INFO lines), as it was after
struct QuietLog {
    int saved = log_level();
    QuietLog() { set_log_level(log_critical); }
    ~QuietLog() { set_log_level(saved); }
};

// stor0 = cd[0]; stor0 = 1 (no dispatcher: the fallback alone)
constexpr std::string_view TINY = "6000356000556001600055";

// what an observer is handed
struct Seen final : driver::StageObserver {
    std::vector<Stage> stages;
    std::vector<usize> functions, internals;
    std::vector<std::string> dumps;
    void stage(Stage s, std::span<const FunctionInfo> fs, std::span<const FunctionInfo> is) override
    {
        stages.push_back(s);
        functions.push_back(fs.size());
        internals.push_back(is.size());
        std::string d;
        for (const FunctionInfo& f : fs)
            d += dump(f.trace) + "\n";
        for (const FunctionInfo& f : is)
            d += dump(f.trace) + "\n";
        dumps.push_back(std::move(d));
    }
};

std::string dump_result(const ContractResult& r)
{
    std::string d;
    for (unsigned s = 0; s < driver::STAGE_COUNT; ++s) {
        if (!r.kept[s])
            continue;
        for (const FunctionInfo& f : r.functions[s])
            d += std::to_string(s) + " " + dump(f.trace) + (f.problem ? " problem\n" : "\n");
        for (const FunctionInfo& f : r.internals[s])
            d += std::to_string(s) + " i" + std::to_string(f.entry_pc) + " " + dump(f.trace) + "\n";
    }
    for (const driver::Problem& p : r.problems)
        d += "problem " + std::to_string(p.index) + " " + p.message + "\n";
    return d;
}

}  // namespace


TEST_CASE("driver: the stages of a contract, one run")
{
    QuietLog quiet;
    Fixture fx;
    const auto code = bytes_of(TINY);
    Seen seen;
    driver::PipelineOptions o;
    o.upto = Stage::Folded;  // (at most what there is)
    o.observer = &seen;
    const ContractResult r = driver::run_pipeline(code, o);
    CHECK(r.has_code);
    CHECK(r.problems.empty());
    CHECK(r.last == driver::last_available());
    for (unsigned s = 0; s <= driver::stage_index(r.last); ++s) {
        CHECK(r.made[s]);
        CHECK(r.kept[s]);
        REQUIRE(r.functions[s].size() == 1);
        CHECK(r.functions[s][0].kind == FunctionInfo::Kind::Fallback);
        CHECK(r.functions[s][0].trace.is_trace());
        CHECK(!r.functions[s][0].problem);
        CHECK(r.internals[s].empty());
    }
    for (unsigned s = driver::stage_index(r.last) + 1; s < driver::STAGE_COUNT; ++s) {
        CHECK(!r.made[s]);
        CHECK(!driver::stage_available(Stage(s)));
    }
    // the observer: each stage once, in order, the whole contract
    REQUIRE(seen.stages.size() == driver::stage_index(r.last) + 1);
    for (usize k = 0; k < seen.stages.size(); ++k) {
        CHECK(seen.stages[k] == Stage(k));
        CHECK(seen.functions[k] == 1);
        CHECK(seen.internals[k] == 0);
    }
    // run_until stops where asked; keep drops the others
    driver::PipelineOptions raw;
    raw.keep = driver::keep_bit(Stage::Raw);
    const ContractResult r0 = driver::run_until(code, Stage::Raw, raw);
    CHECK(r0.last == Stage::Raw);
    CHECK(r0.made[0]);
    CHECK(!r0.made[1]);
    REQUIRE(r0.functions[0].size() == 1);
    CHECK(r0.functions[0][0].trace == r.functions[0][0].trace);
    CHECK(r0.functions[0][0].trace.is_trace());
}

TEST_CASE("driver: names, as python's get_func_name")
{
    QuietLog quiet;
    FunctionInfo f;
    f.kind = FunctionInfo::Kind::Selector;
    f.selector = 0xa9059cbb;
    CHECK(driver::function_name(nullptr, f) == "unknowna9059cbb(?)");
    f.selector = 0x12;
    CHECK(driver::function_name(nullptr, f) == "unknown00000012(?)");
    f.kind = FunctionInfo::Kind::Fallback;
    CHECK(driver::function_name(nullptr, f) == "_fallback(?)");
    f.kind = FunctionInfo::Kind::Internal;
    f.entry_pc = 0x13b;
    CHECK(driver::function_name(nullptr, f) == "internal_0x13b");
}

TEST_CASE("driver: decompile - the text, no code, the JSON")
{
    QuietLog quiet;
    DecompileOptions o;
    o.color = false;
    o.json = true;
    o.asm_lines = true;
    const auto code = bytes_of(TINY);
    const Decompilation d = driver::decompile(code, o);
    CHECK(d.text.starts_with("# Palkeoramix decompiler. \n\n"));
    CHECK(d.text.find("def _fallback(?):") != std::string::npos);
    CHECK(d.text.find('\033') == std::string::npos);
    CHECK(d.json.starts_with("{\"problems\": {}"));
    CHECK(!d.asm_lines.empty());
    CHECK(d.asm_lines[0] == "0x0, push1, 0x0");
    CHECK(d.explain.empty());
    o.color = true;
    CHECK(driver::decompile(code, o).text.find("\033[38;5;8m# Palkeoramix decompiler. ") == 0);
    // no code
    o.color = false;
    const Decompilation none = driver::decompile({}, o);
    CHECK(none.text == "# No code found for this contract.");
    CHECK(none.json == "{}");
    CHECK(none.asm_lines.empty());
    o.color = true;
    CHECK(driver::decompile({}, o).text == "\033[38;5;8m# No code found for this contract.\033[0m");
}

TEST_CASE("driver: --explain and --verbose")
{
    QuietLog quiet;
    DecompileOptions o;
    o.color = false;
    o.explain = true;
    const auto code = bytes_of(TINY);
    const Decompilation d = driver::decompile(code, o);
    CHECK(d.explain.starts_with("\n Initial decompiled trace: \n\n"));
    CHECK(d.explain.find(" Without assembly: ") != std::string::npos);
    // (the ASM lines dropped after the first trace explained)
    CHECK(d.text.find("(asm ") == std::string::npos);
    o.explain = false;
    o.verbose = true;
    const Decompilation v = driver::decompile(code, o);
    CHECK(v.text.find("(asm ") != std::string::npos);
    CHECK(v.explain.empty());
}

TEST_CASE("driver: only_function")
{
    QuietLog quiet;
    const auto code = contract("corpus/WETH.hex");
    if (!code) {
        MESSAGE("no tests/corpus/WETH.hex");
        return;
    }
    Fixture fx;
    driver::PipelineOptions o;
    o.db = nullptr;
    o.upto = Stage::Raw;
    const ContractResult all = driver::run_pipeline(*code, o);
    CHECK(all.functions[0].size() == 12);  // (WETH's 11 selectors and its fallback)
    o.only_function = "unknowna9059cbb";
    const ContractResult one = driver::run_pipeline(*code, o);
    REQUIRE(one.functions[0].size() == 1);
    CHECK(one.functions[0][0].selector == 0xa9059cbb);
    o.only_function = "_fallback";
    const ContractResult fb = driver::run_pipeline(*code, o);
    REQUIRE(fb.functions[0].size() == 1);
    CHECK(fb.functions[0][0].kind == FunctionInfo::Kind::Fallback);
    o.only_function = "nothing";
    CHECK(driver::run_pipeline(*code, o).functions[0].empty());
}

TEST_CASE("driver: the waves of recursive internal functions")
{
    QuietLog quiet;
    const auto code = contract("synthetic/recursion_0.hex");
    if (!code) {
        MESSAGE("no tests/synthetic/recursion_0.hex");
        return;
    }
    Fixture fx;
    driver::PipelineOptions o;
    o.db = nullptr;
    const ContractResult r = driver::run_pipeline(*code, o);
    const auto& ints = r.final_internals();
    REQUIRE(!ints.empty());
    REQUIRE(ints.size() == r.internal_entries.size());
    for (usize k = 0; k < ints.size(); ++k) {
        CHECK(ints[k].kind == FunctionInfo::Kind::Internal);
        CHECK(ints[k].entry_pc == r.internal_entries[k].entry);
        CHECK(ints[k].params.size() == r.internal_entries[k].nargs);
        if (k)
            CHECK(r.internal_entries[k - 1].entry < r.internal_entries[k].entry);
    }
    // (the asm's: internal_0x13b, 0x18a, 0x1e1)
    bool fib = false;
    for (const auto& e : r.internal_entries)
        fib |= e.entry == 0x13b && e.nargs == 1;
    CHECK(fib);
    // an INTERNAL line of every internal function in some trace
    DecompileOptions d;
    d.color = false;
    const Decompilation text = driver::decompile(*code, d);
    CHECK(text.text.find("#  Internal functions") != std::string::npos);
    CHECK(text.text.find("def internal_0x13b(_param1): # recursive, a call takes 3 of the 1024 words of the stack") !=
          std::string::npos);
}

TEST_CASE("driver: problems - a function's memory limit, the loader's fallback")
{
    QuietLog quiet;
    Fixture fx;
    const auto code = bytes_of(TINY);
    driver::PipelineOptions o;
    o.function_memory = usize{1} << 20;  // (less than an arena's chunk: nothing fits)
    const ContractResult r = driver::run_pipeline(code, o);
    REQUIRE(r.functions[0].size() == 1);
    CHECK(r.functions[0][0].kind == FunctionInfo::Kind::Fallback);
    REQUIRE(r.problems.size() == 1);
    CHECK(!r.problems[0].internal);
    CHECK(r.problems[0].index == 0);
    CHECK(r.problems[0].message.find("memory limit") != std::string::npos);
    for (unsigned s = 0; s <= driver::stage_index(r.last); ++s) {
        REQUIRE(r.functions[s].size() == 1);
        CHECK(r.functions[s][0].trace.nil());
        CHECK(r.functions[s][0].problem == 0u);
    }
}

TEST_CASE("driver: a caller's deadline past - the functions stop, then the run")
{
    QuietLog quiet;
    init();
    Fixture fx(Budget::Limits{.deadline_ns = platform::monotonic_ns() - 1});
    const auto code = bytes_of(TINY);
    driver::PipelineOptions o;
    CHECK_THROWS_AS(driver::run_pipeline(code, o), Timeout);
}

TEST_CASE("driver: the same text and JSON at 1, 2 and 8 threads")
{
    QuietLog quiet;
    const char* names[] = {"corpus/WETH.hex", "corpus/Multicall3.hex", "corpus/USDC_proxy.hex",
                           "synthetic/recursion_0.hex", "synthetic/recursion2_0.hex", "synthetic/fuzz_2_11.hex"};
    unsigned tested = 0;
    for (const char* name : names) {
        const auto code = contract(name);
        if (!code)
            continue;
        ++tested;
        std::optional<Decompilation> first;
        for (const usize threads : {usize{1}, usize{2}, usize{8}}) {
            DecompileOptions o;
            o.threads = threads;
            o.color = false;
            o.json = true;
            Decompilation d = driver::decompile(*code, o);
            if (!first) {
                CHECK(d.text.find("# Palkeoramix decompiler.") == 0);
                first = std::move(d);
                continue;
            }
            INFO(name, " at ", threads, " threads");
            CHECK(d.text == first->text);
            CHECK(d.json == first->json);
        }
        // the pipeline's traces too, every stage
        std::string at1;
        for (const usize threads : {usize{1}, usize{8}}) {
            Fixture fx;
            driver::PipelineOptions o;
            o.threads = threads;
            o.db = nullptr;
            const std::string d = dump_result(driver::run_pipeline(*code, o));
            if (threads == 1)
                at1 = d;
            else
                CHECK(d == at1);
        }
    }
    if (!tested)
        MESSAGE("no contracts of tests/corpus or tests/synthetic");
}

TEST_CASE("driver: thread counts past the cap")
{
    QuietLog quiet;
    DecompileOptions o;
    o.color = false;
    o.threads = usize{1} << 62;
    const auto code = bytes_of("6000356000556001600055");
    CHECK(driver::decompile(code, o).text.find("def _fallback(?):") != std::string::npos);
}

TEST_CASE("driver: hostile inputs - a 20000-deep expression, 2000 nested ifs, no instruction but a cut push")
{
    QuietLog quiet;
    // cd[cd[cd[...]]]: an expression 20000 deep (the asm's robustness.sh)
    std::string chain = "600435";
    for (int i = 0; i < 20000; ++i)
        chain += "35";
    chain += "60005500";
    // require(!cd[4 + 32 i]) 2000 times: a path 2000 jumps deep
    std::string ifs = "6080604052";
    usize size = 5;
    for (int i = 0; i < 2000; ++i) {
        ifs += std::format("62{:06x}351562{:06x}57fe5b", 4 + 32 * i, size + 12);
        size += 13;
    }
    ifs += "00";
    for (const std::string& hex : {chain, ifs, std::string("60"), std::string("fe")}) {
        DecompileOptions o;
        o.color = false;
        o.threads = 2;
        const auto code = bytes_of(hex);
        const Decompilation d = driver::decompile(code, o);
        CHECK(d.text.starts_with("# Palkeoramix decompiler. "));
    }
}
