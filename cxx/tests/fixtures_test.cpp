// Code that isn't solc's high-level output (DESIGN.md, "Nothing assumed of
// the compiler"): the fixtures of tests/fixtures (compile.sh: Yul objects;
// Vyper contracts by 0.3.7, 0.3.10, 0.4.0 and 0.4.3) and hand-assembled
// code, decompiled by the pipeline - every stage's traces run by the trace
// machine and the printed text by its interpreter against evmone (the checks
// of stagecheck and text_check: the planned calls in a sequence on the empty
// world and on a random one): no difference, no bug, calls the same.
#include "validate/calls.hpp"
#include "validate/stage_check.hpp"
#include "validate/text_interp.hpp"
#include "validate/text_parser.hpp"

#include "core/context.hpp"
#include "core/dump.hpp"
#include "decompile.hpp"
#include "driver/pipeline.hpp"
#include "output/output.hpp"
#include "validate_test_util.hpp"

#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>
#include <vector>

#ifndef PAN_FIXTURES
#define PAN_FIXTURES "tests/fixtures"
#endif

using namespace validate;

namespace
{
/// The log quiet for a test (the driver's INFO lines), as it was after
struct QuietLog
{
    int saved = pan::log_level();
    QuietLog() { pan::set_log_level(pan::log_critical); }
    ~QuietLog() { pan::set_log_level(saved); }
};

std::filesystem::path fixtures_dir()
{
    if (const char* e = std::getenv("PANORAMIX_FIXTURES"); e != nullptr && *e != 0)
        return e;
    return PAN_FIXTURES;
}

/// The .hex files of the fixtures, in order.
std::vector<std::filesystem::path> fixtures()
{
    std::vector<std::filesystem::path> out;
    std::error_code ec;
    for (const auto& e : std::filesystem::recursive_directory_iterator(fixtures_dir(), ec))
        if (e.is_regular_file() && e.path().extension() == ".hex")
            out.push_back(e.path());
    std::ranges::sort(out);
    return out;
}

std::optional<Bytes> read_hex(const std::filesystem::path& path)
{
    std::ifstream in{path, std::ios::binary};
    if (!in)
        return std::nullopt;
    std::ostringstream text;
    text << in.rdbuf();
    return parse_hex(text.str());
}

/// A function of the dispatcher and where its params are (the calldata
/// offsets of their head words: text_check's side information).
struct Placed
{
    std::optional<std::uint32_t> selector;  ///< none: the fallback
    std::vector<text::ParamPlace> places;
};

/// What the pipeline made of a contract beside the stages' traces: its
/// text (no color, no signature database) and its functions' params.
struct Made
{
    std::string text;
    std::vector<Placed> functions;
};

void keep_made(const pan::driver::ContractResult& r, Made& made)
{
    pan::output::PrintOptions po;
    po.color = false;
    made.text = pan::output::print_contract(r, po);
    made.functions.clear();
    for (const auto& f : r.final_functions())
    {
        if (f.kind == pan::FunctionInfo::Kind::Internal)
            continue;
        Placed p;
        if (f.kind == pan::FunctionInfo::Kind::Selector)
            p.selector = f.selector;
        for (const auto& param : f.params)
            p.places.push_back({param.calldata_offset, std::nullopt});
        made.functions.push_back(std::move(p));
    }
}

/// stagecheck's pipeline (lot 12's run_until, every stage kept), the text
/// and the params kept.
void pipeline(Decompiled& c, Stage upto, pan::Budget& budget, Made& made)
{
    pan::driver::PipelineOptions o;
    o.threads = 1;
    o.keep = pan::driver::KEEP_ALL;
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
    keep_made(r, made);
}

/// The text parsed, its params placed as the pipeline found them.
text::Program program_of(const Made& made)
{
    text::Program program = text::parse(made.text);
    for (const auto& f : made.functions)
        text::place_params(program, f.selector, f.places);
    return program;
}

/// text_check's counts of the calls of a text.
struct TextTally
{
    unsigned long calls = 0, same = 0, different = 0, inconclusive = 0;
    std::string first;  ///< the first difference
};

/// One call by evmone and by the text's interpreter (each from its state:
/// the text's set to evmone's after a difference, as text_check does).
void text_call(TextTally& t, EvmRunner& runner, text::Interpreter& interp, State& evm_state, State& text_state,
    const CallContext& call)
{
    const Effects evm = runner.run(evm_state, call);
    const Effects mine = interp.run(text_state, call);
    const auto c = compare(evm, mine);
    ++t.calls;
    if (c.verdict != Verdict::same)
        text_state = evm_state;
    if (evm.end.inconclusive() || mine.end.inconclusive())
        ++t.inconclusive;
    else if (c.verdict == Verdict::same)
        ++t.same;
    else
    {
        ++t.different;
        if (t.first.empty())
            t.first = "calldata " + hex(call.calldata) + ": " + c.message + "\nevm:\n" + to_string(evm)
                      + "text:\n" + to_string(mine);
    }
}

/// text_check's run of a text: the planned calls in a sequence.
TextTally run_text(const Bytes& code, const text::Program& program, bool random, std::uint64_t seed)
{
    TextTally t;
    const SeededWorld world{WorldConfig{.seed = seed, .random = random}};
    const CallGenerator gen{world, code};
    EvmRunner runner{code};
    text::Interpreter interp{program};
    State evm_state{world, world.contract_address(), code};
    State text_state{world, world.contract_address(), code};
    for (const auto& planned : gen.calls())
        text_call(t, runner, interp, evm_state, text_state, planned.context);
    return t;
}

std::string examples(const StageResult& s)
{
    std::string out;
    for (const auto& e : s.examples)
        out += category_name(e.category) + std::string{" "} + e.call + ": " + e.message + "\n  at " + e.where
               + "\n  evm:\n" + e.expected + "  machine:\n" + e.actual + "\n";
    return out;
}

/// A World with a slot's value set (a length), the rest the random world's.
class SlotWorld final : public World
{
public:
    SlotWorld(std::uint64_t seed, Word slot, Word value)
      : base_{WorldConfig{.seed = seed, .random = true}}, slot_{slot}, value_{value}
    {
    }

    Word storage(const Word& account, const Word& slot) const override
    {
        return slot == slot_ ? value_ : base_.storage(account, slot);
    }
    Word balance(const Word& account) const override { return base_.balance(account); }
    std::uint64_t nonce(const Word& account) const override { return base_.nonce(account); }
    Bytes code(const Word& account) const override { return base_.code(account); }
    Word block_hash(const Word& number) const override { return base_.block_hash(number); }
    BlockContext block() const override { return base_.block(); }
    CallResult call(CallKind kind, const Word& target, const Word& value, BytesView input) const override
    {
        return base_.call(kind, target, value, input);
    }
    CallResult create(CreateKind kind, const Word& address, const Word& value, BytesView init_code) const override
    {
        return base_.create(kind, address, value, init_code);
    }

    const SeededWorld& base() const noexcept { return base_; }

private:
    SeededWorld base_;
    Word slot_, value_;
};

bool has_op(pan::Value v, pan::Op op)
{
    if (!(v.is_expr() || v.is_list()))
        return false;
    if (v.is(op))
        return true;
    for (pan::Value a : v.children())
        if (has_op(a, op))
            return true;
    return false;
}
}  // namespace

TEST_CASE("fixtures: code that isn't solc's - every stage and the text run as evmone runs the code")
{
    const QuietLog quiet;
    const auto files = fixtures();
    INFO("the fixtures' directory: ", fixtures_dir().string(), " (PANORAMIX_FIXTURES)");
    REQUIRE(files.size() >= 13);  // 5 Yul objects, 8 Vyper builds
    for (const auto& path : files)
    {
        INFO("fixture ", path.string());
        const auto code = read_hex(path);
        REQUIRE(code.has_value());
        REQUIRE(!code->empty());
        CheckConfig config;
        config.upto = Stage::folded;
        Made made;
        const auto report = check_contract(*code, config, [&](Decompiled& c, Stage upto, pan::Budget& budget) {
            pipeline(c, upto, budget, made);
        });
        INFO(report.failure);
        REQUIRE(report.ran);
        CHECK(report.problems == 0);
        for (unsigned s = 0; s < stage_count; ++s)
        {
            const StageResult& st = report.stages[s];
            INFO("stage ", stage_name(static_cast<Stage>(s)), ": ", summary(report), "\n", examples(st));
            CHECK(st.ran);
            CHECK(st.different == 0);
            CHECK(st.bugs == 0);
            CHECK(st.unsized == 0);
            CHECK(st.same > 0);
        }
        const text::Program program = program_of(made);
        INFO("text:\n", made.text);
        for (const auto& e : program.errors)
            MESSAGE(e);
        CHECK(program.errors.empty());
        for (const bool random : {false, true})
        {
            const TextTally t = run_text(*code, program, random, 0);
            INFO((random ? "random" : "empty"), " world: ", t.calls, " calls, ", t.same, " same, ", t.different,
                " different, ", t.inconclusive, " inconclusive\n", t.first);
            CHECK(t.different == 0);
            CHECK(t.same > 0);
            CHECK(t.same + t.inconclusive == t.calls);
        }
    }
}

TEST_CASE("fixtures: a copy loop of the storage's words to memory is one line")
{
    // Vyper's string read: slot 0 the length L, its n = (L + 31) / 32 words
    // in the slots from 1 on, copied word by word after the 2 words of the
    // ABI's head - return(0, 64 + 32 n):
    //   mem[32] = L; mem[0] = 32; n = (L + 31) >> 5
    //   i = 0; while i < n: mem[64 + 32 i] = sload(1 + i); i += 1
    const Bytes code = *parse_hex("6000" "54" "80" "6020" "52" "6020" "6000" "52" "601f" "01" "6005" "1c" "6000"
                                  "5b" "81" "81" "10" "15" "602f" "57" "80" "6001" "01" "54" "81" "6005" "1b"
                                  "6040" "01" "52" "6001" "01" "6014" "56"
                                  "5b" "50" "6005" "1b" "6040" "01" "6000" "f3");
    const QuietLog quiet;
    pan::init();
    pan::Budget budget{pan::Budget::Limits{}};
    budget.attach_thread();
    {
        Decompiled contract{code};
        auto ctx = pan::Context::create(budget, &contract.shared);
        pan::ContextScope scope{*ctx};
        Made made;
        pipeline(contract, Stage::folded, budget, made);
        for (unsigned s = 0; s < stage_count; ++s)
            REQUIRE(contract.made[s]);
        // the loop is one line: no WHILE, the storage's words
        const auto& last = contract.functions[stage_count - 1];
        REQUIRE(last.size() == 1);
        INFO("folded: ", pan::dump_trace(last[0].trace), "\ntext:\n", made.text);
        CHECK(!has_op(last[0].trace, pan::Op::WHILE));
        CHECK(has_op(last[0].trace, pan::Op::STORAGE_RANGE));
        CHECK(made.text.find("while") == std::string::npos);
        // (the length's word and the words after it, consecutive slots: one
        // part - return 32, stor[0 len (stor0 + 31) / 32 + 1])
        CHECK(made.text.find("stor[0 len ") != std::string::npos);
        const text::Program program = program_of(made);
        for (const auto& e : program.errors)
            MESSAGE(e);
        CHECK(program.errors.empty());
        text::Interpreter interp{program};
        // every stage and the text, as evmone, for lengths of every kind
        for (const unsigned length : {0u, 1u, 31u, 32u, 33u, 64u, 100u, 1000u})
            for (const std::uint64_t seed : {1u, 2u})
            {
                const SlotWorld world{seed, 0, length};
                const CallContext call{world.base().actors()[0], world.base().actors()[0], 0, 1, Bytes{}};
                EvmRunner runner{code};
                State evm_state{world, world.base().contract_address(), code};
                const Effects expected = runner.run(evm_state, call);
                INFO("length ", length, ", seed ", seed, "\nevm:\n", to_string(expected));
                REQUIRE(expected.end.status == Status::return_);
                CHECK(expected.end.data.size() == 64 + 32 * ((length + 31) / 32));
                for (unsigned s = 0; s < stage_count; ++s)
                {
                    pan::exec::Program p;
                    p.functions = contract.functions[s];
                    p.internals = contract.internals[s];
                    p.shared = &contract.shared;
                    p.layout = contract.storage.get();
                    p.safemath = contract.safemath.get();
                    State state{world, world.base().contract_address(), code};
                    Session session{state, call};
                    pan::exec::Machine m{p};
                    pan::exec::Outcome out;
                    const Effects actual = run_machine(m, session, std::nullopt, &out);
                    INFO("stage ", stage_name(static_cast<Stage>(s)), ", machine (",
                        pan::exec::status_name(out.status), " ", out.note, "):\n", to_string(actual));
                    CHECK(compare(expected, actual).verdict == Verdict::same);
                }
                State text_state{world, world.base().contract_address(), code};
                const Effects mine = interp.run(text_state, call);
                INFO("text:\n", to_string(mine));
                CHECK(compare(expected, mine).verdict == Verdict::same);
            }
    }
    budget.detach_thread();
}
