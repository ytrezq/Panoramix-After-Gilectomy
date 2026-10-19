// The validation of the stages by execution (AGENTS.md rule 5; lot 11): for
// a contract, the decompiler's pipeline up to each stage, then the planned
// calls (CallGenerator, typed by AbiEncoder when a signature database is
// given) run by evmone and by the trace machine (src/exec/machine.hpp) on
// each stage's trace, against the same world, their effects compared
// (effects.hpp: compare()) - sequences of calls on the empty world (the
// state carried, each call of the machine started from the state evmone's
// previous calls left), isolated calls on a random world. Per stage: the
// calls the same, different (by category), inconclusive (by reason) and the
// machine's bugs (a trace that breaks the IR's rules); the first stage that
// diverges. Deterministic: a function of the code, the seed and the options.
//
//   SessionHost     pan::exec::Host over a Session: where the trace machine
//                   meets the world (Word256 <-> Word, at this boundary only)
//   run_machine     one call by the machine: the Session's Effects
//   check_contract  the whole check of one contract (its own Budget, Context
//                   and watchdog, on the calling thread)
//
// The pipeline is a parameter (Pipeline): stagecheck's is lot 5's discover /
// run_function (Stage::raw, with the waves of the recursive internal
// functions) until lot 12's run_until lands; the tests give hand-made
// stages.
#pragma once

#include "abi_encode.hpp"
#include "calls.hpp"
#include "effects.hpp"
#include "evm_runner.hpp"
#include "session.hpp"
#include "world.hpp"

#include "core/budget.hpp"
#include "evm/decoder.hpp"
#include "exec/machine.hpp"

#include <array>
#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace validate
{
pan::Word256 to_word256(const Word& w) noexcept;
Word to_word(const pan::Word256& w) noexcept;

/// The trace machine's host: every read and effect through the Session (the
/// EVM's rules applied there, as for evmone).
class SessionHost final : public pan::exec::Host
{
public:
    explicit SessionHost(Session& session);

    const pan::exec::CallEnv& env() override;
    pan::Word256 sload(const pan::Word256& slot) override;
    void sstore(const pan::Word256& slot, const pan::Word256& value) override;
    pan::Word256 tload(const pan::Word256& key) override;
    void tstore(const pan::Word256& key, const pan::Word256& value) override;
    pan::Word256 balance(const pan::Word256& account) override;
    pan::Word256 code_size(const pan::Word256& account) override;
    pan::Word256 code_hash(const pan::Word256& account) override;
    std::vector<std::uint8_t> code_of(const pan::Word256& account) override;
    pan::Word256 block_hash(const pan::Word256& number) override;
    pan::Word256 blob_hash(const pan::Word256& index) override;
    void log(std::span<const pan::Word256> topics, std::span<const std::uint8_t> data) override;
    pan::exec::CallResult call(pan::exec::CallKind kind, const pan::Word256& target, const pan::Word256& value,
        std::span<const std::uint8_t> input) override;
    pan::exec::CreateResult create(pan::exec::CreateKind kind, const pan::Word256& value,
        std::span<const std::uint8_t> init_code, const pan::Word256& salt) override;
    void selfdestruct(const pan::Word256& beneficiary) override;

private:
    Session* session_;
    pan::exec::CallEnv env_;
};

/// The machine's end as the harness has it: Exhausted exhausted, Undefined
/// and Unsupported unsupported, Bug error (all three inconclusive for
/// compare(): the driver counts the bugs apart).
End to_end(const pan::exec::Outcome& outcome);

/// One call run by the machine against the session, which it finishes; its
/// outcome in *outcome when asked.
Effects run_machine(pan::exec::Machine& machine, Session& session,
    std::optional<std::uint32_t> selector_hint = {}, pan::exec::Outcome* outcome = nullptr);

/// The stages whose traces are run (lot 12's pipeline Stage when it lands).
enum class Stage : std::uint8_t
{
    raw,         ///< the VM's trace: LABEL / GOTO (M1)
    whiles,      ///< WHILE / CONTINUE (M2)
    simplified,  ///< (M2)
    analysed,    ///< params, payable, storage forms (M3)
    folded,      ///< the ast: LAND LOR REQUIRE SAFEMATH (M3)
};
inline constexpr unsigned stage_count = 5;
const char* stage_name(Stage stage) noexcept;

/// What a difference is, in compare()'s order (the first part that differs).
enum class Category : std::uint8_t
{
    end_status,  ///< another end (return / revert / stop / invalid)
    end_data,    ///< the same end, other data
    events,      ///< logs, calls, creations, selfdestructs
    storage,     ///< the storage written
    bug,         ///< the machine found the trace breaking the IR's rules
    unsized,     ///< (not a difference) a byte element without SIZED: its width guessed
};
inline constexpr unsigned category_count = 6;
const char* category_name(Category c) noexcept;

/// Why a call was inconclusive.
enum class Why : std::uint8_t
{
    evm,          ///< evmone's side (out of gas...)
    exhausted,    ///< the machine's limits
    undefined,    ///< an UNDEFINED line (the decompiler gave up on that path)
    unsupported,  ///< the machine can't (no function, a failed one, a missing table)
};
inline constexpr unsigned why_count = 4;
const char* why_name(Why w) noexcept;

struct CheckConfig
{
    Stage upto = Stage::raw;
    std::uint64_t seed = 0;
    bool empty_world = true;   ///< the calls in a sequence on the empty world
    bool random_world = true;  ///< each call alone on the random world
    CallConfig calls{};
    RunOptions evm{};
    pan::exec::MachineLimits machine{};
    CompareOptions compare{};
    const pan::sigdb::Database* db = nullptr;  ///< typed calldata for the selectors it knows
    AbiConfig abi{};
    std::size_t memory = std::size_t{2} << 30;  ///< the contract's memory limit (0: none)
    std::int64_t timeout_ns = 0;                ///< the contract's time limit (0: none)
    unsigned keep = 3;                          ///< the examples kept per stage
};

/// A call that differed (or a bug), for the report.
struct Example
{
    Category category = Category::bug;
    std::string call;      ///< which: the world, the selector/variant, caller, value, calldata
    std::string message;   ///< compare()'s, or the bug's
    std::string where;     ///< the machine's line where it ended (dump) and its pc
    std::string expected;  ///< evmone's effects
    std::string actual;    ///< the machine's
};

struct StageResult
{
    bool ran = false;  ///< the stage's traces were made
    unsigned long same = 0, different = 0, inconclusive = 0, bugs = 0;
    /// the calls whose run met a byte element without SIZED (whatever their
    /// verdict): the stage's bug to report, not a difference
    unsigned long unsized = 0;
    /// the calls the same, by how they ended: stop, return, revert, invalid
    std::array<unsigned long, 4> same_by_end{};
    std::array<unsigned long, category_count> by_category{};  ///< different, bugs, unsized
    std::array<unsigned long, why_count> by_why{};            ///< inconclusive
    std::vector<Example> examples;
    /// calls the machine left inconclusive (exhausted, undefined, unsupported) and evmone didn't
    std::vector<Example> inconclusive_examples;
};

/// The check of one contract.
struct StageReport
{
    bool ran = false;     ///< the pipeline ran (else: failure)
    std::string failure;  ///< why it didn't (the decompiler's error, a limit)
    unsigned functions = 0, internals = 0, problems = 0;  ///< problems: functions that failed
    unsigned long calls = 0;                               ///< planned, per world
    std::array<StageResult, stage_count> stages{};
    std::optional<Stage> first_divergent;  ///< the first stage with a difference or a bug
};

/// A contract decompiled up to some stage: what the machines run. Its
/// Values are on the check's context (the current one when the pipeline
/// runs).
struct Decompiled
{
    Bytes code;
    pan::CodeMap map;            ///< lot 1's analysis of the code
    pan::ContractShared shared;  ///< code, map, lang (the metadata's), fmp
    std::array<std::vector<pan::FunctionInfo>, stage_count> functions;  ///< per stage: selectors, fallback
    std::array<std::vector<pan::FunctionInfo>, stage_count> internals;  ///< per stage: internal functions
    std::array<bool, stage_count> made{};                              ///< the stages made

    explicit Decompiled(BytesView code);
    Decompiled(const Decompiled&) = delete;
    Decompiled& operator=(const Decompiled&) = delete;
};

/// Makes the stages up to `upto` (those it can) on the current context,
/// within the budget; throws the decompiler's errors (pan::Error) when the
/// contract can't be decompiled.
using Pipeline = std::function<void(Decompiled& contract, Stage upto, pan::Budget& budget)>;

StageReport check_contract(BytesView code, const CheckConfig& config, const Pipeline& pipeline);

/// One line: a contract's counts per stage that ran.
std::string summary(const StageReport& report);

/// stagecheck's options and the stages' names (stage_check.rl, Ragel).
enum class StagecheckOption : std::uint8_t
{
    none,  ///< not an option
    stage,
    corpus,
    seed,
    empty,
    random,
    per_selector,
    sigdb,
    untyped,
    jobs,
    limit,
    show,
    quiet,
    timeout,
    steps,
    gas,
    help,
};
StagecheckOption stagecheck_option(std::string_view arg);
std::optional<Stage> parse_stage(std::string_view name);
}  // namespace validate
