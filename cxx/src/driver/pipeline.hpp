// The driver (lot 12; python decompiler.py and contract.py's postprocess,
// asm decompiler.s, par.s, rt_watch.s): a contract decompiled as a pipeline
// of stages, its functions on threads, within the limits of rule 8.
//
//  1. lot 1's analysis of the code; lot 5's discovery of the functions (the
//     VM on the dispatcher) on a context of its own: half of a function's
//     memory limit, the deadline scaled(60 s) + scaled(180 s). A discovery
//     that fails (its limits included: "finding the functions took more than
//     4 minutes") logs "Loader issue: ..." and leaves the fallback alone, at 0.
//  2. a job per function (only_function: those whose name starts with it),
//     min(threads, jobs) at once: each on its own Context and Budget (a
//     function's memory limit: PANORAMIX_MAX_MEMORY, else the machine's
//     memory shared by the threads), watched to its deadline (scaled(180 s):
//     "the function took more than 3 minutes"): lot 5's VM -> lot 6's whiles
//     -> lot 7's simplifier -> lot 8's traits. A function that fails is a
//     problem (its message kept), the others go on; std::bad_alloc is the
//     job's MemoryLimit. Its result is imported into the contract's context
//     as soon as it is done, and its context freed.
//  3. waves: the recursive internal functions the VMs of the functions made
//     found (python's `internal`), decompiled apart - those the functions
//     call, then those they call, by entry.
//  4. the contract phase, on the contract's context: lot 9's storage, lot
//     10's folds and texts (a context per function, on threads), lot 8's
//     SafeMath, the JSON - its deadline scaled(180 s) ("the post-processing
//     and the text took more than 3 minutes": the decompilation fails).
// The results are placed by job order: the same at any thread count.
//
// Every stage is written (stage_available is true for all, last_available
// is Folded); the two hooks stay for a build that leaves a stage out.
#pragma once

#include <array>
#include <memory>
#include <span>
#include <string>
#include <vector>

#include "core/base.hpp"
#include "core/contract.hpp"
#include "core/value.hpp"
#include "decompile.hpp"
#include "vm/vm.hpp"

namespace pan {
// the contract-wide results of lots 8 and 9, declared in their headers
struct StorageLayout;  // lot 9: the storage variables, their slots and types
struct SafeMathTable;  // lot 8: the functions of the contract's SafeMath
}  // namespace pan

namespace pan::driver {

// The stages a function goes through (lot 11's stage checks run each one's traces).
enum class Stage : u8 {
    Raw,         // lot 5's VM: LABEL / GOTO
    Whiles,      // lot 6: WHILE / CONTINUE
    Simplified,  // lot 7 (python's orig_trace)
    Analysed,    // lot 8's traits (payable...), lot 9's storage forms (python's func.trace)
    Folded,      // lot 10's ast: LAND LOR REQUIRE SAFEMATH (python's func.ast)
};
inline constexpr unsigned STAGE_COUNT = 5;
constexpr unsigned stage_index(Stage s) noexcept { return unsigned(s); }

// Whether this build makes the stage (its lot is in): the stages past the
// last one available are not made, whatever is asked.
bool stage_available(Stage s) noexcept;
// the last stage available
Stage last_available() noexcept;

// PipelineOptions::keep: the stages whose traces ContractResult keeps (a bit per Stage)
inline constexpr u32 keep_bit(Stage s) noexcept { return u32(1) << stage_index(s); }
inline constexpr u32 KEEP_ALL = (u32(1) << STAGE_COUNT) - 1;
// what the outputs read: python's orig_trace (--repr), trace (JSON), ast (text)
inline constexpr u32 KEEP_OUTPUT = keep_bit(Stage::Simplified) | keep_bit(Stage::Analysed) | keep_bit(Stage::Folded);

// A function that failed (python's problems, in the order of the jobs).
struct Problem {
    bool internal = false;      // ContractResult::internals[index], else functions[index]
    u32 index = 0;
    Stage stage = Stage::Raw;   // the stage it failed at (it has the traces of those before)
    std::string message;        // why: the error's ("the function took more than 3 minutes"...)
};

// What the stages made of a contract: what the printer (lot 10) and the
// stage checks (lot 11) read. Its Values are on the context that was the
// current one when it was made (run_pipeline's caller's).
struct ContractResult {
    // false: the code has no instruction (python: "# No code found for this contract.")
    bool has_code = true;
    Lang lang = Lang::Unknown;  // the metadata's (lot 9 may tell it better)
    // The traces of each stage kept (made[s] && kept[s]): the same functions,
    // in the same order, at every stage -
    //  functions: the dispatcher's, in its order (the selectors, then the
    //    fallback), those PipelineOptions::only_function keeps;
    //  internals: the recursive internal functions decompiled apart, by entry
    //    (python's Contract.internal).
    // A function that failed at a stage has, at that stage and after it,
    // problem set (an index into problems) and no trace (NIL).
    std::array<std::vector<FunctionInfo>, STAGE_COUNT> functions;
    std::array<std::vector<FunctionInfo>, STAGE_COUNT> internals;
    std::array<bool, STAGE_COUNT> made{};  // the stage ran (for every function that got there)
    std::array<bool, STAGE_COUNT> kept{};  // ... and its traces are here
    Stage last = Stage::Raw;               // the last stage made
    // internals[s][i]'s record: entry, words of arguments and results, frame
    std::vector<vm::InternalEntry> internal_entries;
    std::vector<Problem> problems;
    std::shared_ptr<const StorageLayout> storage;   // lot 9's (null: not analysed, the accesses raw)
    std::shared_ptr<const SafeMathTable> safemath;  // lot 8's (null: none)

    // the last stage's functions and internals (python's Contract.functions,
    // .internal: the failed ones with problem set)
    const std::vector<FunctionInfo>& final_functions() const { return functions[stage_index(last)]; }
    const std::vector<FunctionInfo>& final_internals() const { return internals[stage_index(last)]; }
};

// One run of the pipeline hands each stage's traces to an observer (the
// stage checks): every function and internal function as the stage left
// them, in ContractResult's order, on the caller's context - once per stage
// made, in the order of the stages, when the whole contract went through it
// (all the waves; Analysed and Folded after the contract phase). The spans
// live for the call.
class StageObserver {
public:
    virtual void stage(Stage stage, std::span<const FunctionInfo> functions, std::span<const FunctionInfo> internals) = 0;

protected:
    ~StageObserver() = default;
};

struct PipelineOptions {
    Stage upto = Stage::Folded;  // the last stage made (at most last_available())
    // the functions decompiled at once: 0 for one per CPU (at most
    // limits::MAX_THREADS); the results are the same at any count
    usize threads = 1;
    // python's only_func_name: only the functions whose name (python's
    // get_func_name: transfer(address to, uint256 amount), unknown12345678(?),
    // _fallback(?)) starts with it; empty: all
    std::string only_function;
    bool verbose = false;  // the VM's ASM lines in the traces (--verbose)
    u32 keep = KEEP_ALL;   // the stages ContractResult keeps the traces of
    StageObserver* observer = nullptr;
    // The names of the functions (only_function, the logs): the signature
    // database; null: every selector unknown
    const sigdb::Database* db = nullptr;
    // a function's memory limit, bytes (0: the environment's,
    // job_memory_limit(threads)); its deadline is scaled(180 s) - and the
    // calling thread's budget's deadline, if earlier
    usize function_memory = 0;
};

// The stages up to options.upto of the code's contract, on the calling
// thread's context (cx(): a ContextScope is required; the caller's Budget
// bounds what is imported into it) - its functions on min(threads, jobs)
// threads, each job on a thread with limits::WORKER_STACK of stack (call it
// from such a thread: parallel_for runs jobs on the caller's too). Throws
// the Budget's errors of the caller's context (MemoryLimit, Timeout) and
// std::bad_alloc; a function that fails is a problem, never an exception.
ContractResult run_pipeline(std::span<const u8> code, const PipelineOptions& options);

// run_pipeline up to a stage (lot 11's hook)
ContractResult run_until(std::span<const u8> code, Stage upto, const PipelineOptions& options);

// decompile.hpp's decompile (pan::decompile is this): the pipeline to its
// last stage on a thread of limits::WORKER_STACK, on a context of its own
// (the asm's phase limits: the discovery half of a function's limit, the
// post-processing and the text base + imports + a function's limit), then
// the outputs. Throws DecompileError ("decompilation failed: ...": the
// contract phase's limits, a code past 4 GiB) and std::bad_alloc.
Decompilation decompile(std::span<const u8> code, const DecompileOptions& options);

// python's get_func_name(hash) of a function of the dispatcher (no color):
// its signature from the database, "unknown%08x(?)" for a selector it doesn't
// know (or knows unverified), "_fallback(?)"; an internal function's
// "internal_0x%x" (python's internal_name). The database's names are raw
// bytes: escape them to print them.
std::string function_name(const sigdb::Database* db, const FunctionInfo& fn);

}  // namespace pan::driver
