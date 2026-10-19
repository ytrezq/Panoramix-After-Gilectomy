// The driver's own parts (lot 12 only): the run of the pipeline as
// decompile() and run_pipeline() share it, --explain's text of a job, and
// the placeholders of lot 10's outputs until it lands (output.cpp).
#pragma once

#include <mutex>
#include <span>
#include <string>
#include <string_view>
#include <vector>

#include "core/budget.hpp"
#include "core/context.hpp"
#include "decompile.hpp"
#include "driver/pipeline.hpp"
#include "evm/decoder.hpp"

namespace pan::driver::detail {

inline constexpr std::string_view LOGGER = "panoramix.decompiler";

// the asm's messages (decompiler.s, rt_watch.s)
inline constexpr const char* MSG_FUNCTION_TIMEOUT = "the function took more than 3 minutes";
inline constexpr const char* MSG_DISCOVERY_TIMEOUT = "finding the functions took more than 4 minutes";
inline constexpr const char* MSG_POST_TIMEOUT = "the post-processing and the text took more than 3 minutes";
inline constexpr const char* MSG_NO_MEMORY = "out of memory: the system gave no more";

// now + base scaled by PANORAMIX_TIMEOUT (scaled_timeout); 0: no time limit
i64 deadline_after(i64 base_ns) noexcept;
// the earlier of two deadlines (0: none)
constexpr i64 earlier(i64 a, i64 b) noexcept { return a == 0 ? b : b == 0 ? a : a < b ? a : b; }

// a budget attached to the calling thread for a scope (they nest)
class Attach {
public:
    explicit Attach(Budget& b) : b_(b) { b_.attach_thread(); }
    ~Attach() { b_.detach_thread(); }
    Attach(const Attach&) = delete;
    Attach& operator=(const Attach&) = delete;

private:
    Budget& b_;
};

// --explain's text of a job (python's explain / explain_text, the
// placeholder of lot 10's printer): a section per trace, none for the trace
// printed last (python's prev_trace, compared by content hash: the traces
// may be in arenas a compaction gave back since). The jobs' texts are
// merged in job order (Run::merge_explain), prev_trace carried across.
class Explainer {
public:
    explicit Explainer(bool color) : color_(color) {}
    void trace(std::string_view title, Value trace);
    std::string out;
    bool first = false;  // a trace printed: the first one's hash and where its section ends
    u64 first_hash = 0;
    usize first_end = 0;
    bool last = false;   // the last one printed
    u64 last_hash = 0;

private:
    bool color_;
};

// The settings of a run of the pipeline.
struct Settings {
    PipelineOptions options;    // threads settled (1 .. MAX_THREADS), upto at most last_available()
    bool explain = false;       // --explain's text made
    bool color = true;          // in it
    bool own_contract = false;  // the contract's context and budget are the driver's (decompile): the asm's
                                // phase limits (the jobs' and the post-processing's: base + imports + a
                                // function's limit; each import unlimited, a function's result being
                                // bounded by its own limit)
    usize fn_memory = 0;        // a function's memory limit (0: none)
    i64 parent_deadline = 0;    // the caller's deadline (its budget's), bounds every job's
};

// The run of the pipeline on the calling thread's context (cx()): the
// discovery, the jobs and their waves, the stages assembled - by job order.
class Run {
public:
    Run(std::span<const u8> code, const Settings& settings);
    ~Run();
    Run(const Run&) = delete;
    Run& operator=(const Run&) = delete;

    // phases 1-3: the discovery, the functions' jobs, the waves of internal
    // functions; the result assembled (the observer not called yet)
    void functions();
    // the contract phase's stages (Analysed, Folded: lots 8-10, when they
    // land), then the observer, then the stages not kept dropped
    void contract_phase();

    ContractResult& result() noexcept { return result_; }
    const ContractShared& shared() const noexcept { return shared_; }
    std::string take_explain() { return std::move(explain_); }
    const std::string& explain() const noexcept { return explain_; }
    // own_contract: the post-processing's memory limit (base + imports + a function's)
    void set_phase_limit();

private:
    struct JobOut;
    struct Local;
    void discover();
    void run_wave(const std::vector<std::pair<bool, u32>>& jobs);
    void job(bool internal, u32 i) noexcept;
    void run_job(bool internal, u32 i, JobOut& out);
    void import_job(Local& local, Context& from, JobOut& out);
    void merge_wave(const std::vector<std::pair<bool, u32>>& jobs, std::vector<vm::InternalEntry>& fresh);
    void assemble();
    JobOut& out_of(bool internal, u32 i);

    std::span<const u8> code_;
    const Settings& s_;
    CodeMap map_;
    ContractShared shared_;
    Context& main_;
    Budget& main_budget_;
    usize base_ = 0, imported_ = 0;
    std::mutex import_mutex_;
    std::vector<FunctionInfo> fns_, ints_;  // main's: the functions run, the internal ones as found
    std::vector<vm::InternalEntry> recs_;   // ints_'s records
    std::vector<JobOut> fn_out_, int_out_;
    std::string explain_;
    bool explain_prev_ = false;
    u64 explain_prev_hash_ = 0;
    ContractResult result_;
};

// --- the placeholders of lot 10's outputs (output.cpp) ---

// python's "# No code found for this contract."
std::string no_code_text(bool color);
// the text of the contract as python's decompiler prints it (the
// placeholder: the functions' last traces as S-expressions)
std::string contract_text(const ContractResult& r, const DecompileOptions& o, const sigdb::Database* db);
// python's decompilation.json (the placeholder: the problems, the functions' names and texts)
std::string contract_json(const ContractResult& r, const DecompileOptions& o, const sigdb::Database* db);

}  // namespace pan::driver::detail
