// The pipeline (pipeline.hpp): the discovery, a job per function on
// threads, the waves of recursive internal functions, the stages assembled
// by job order (python decompiler.py's _decompile_with_loader; asm
// decompiler.s's decompile, decompile_worker, dc_merge_found).
#include "driver/pipeline.hpp"

#include <algorithm>
#include <format>
#include <limits>
#include <numeric>
#include <optional>
#include <system_error>
#include <unordered_map>
#include <unordered_set>
#include <utility>

#include "core/errors.hpp"
#include "core/jobs.hpp"
#include "core/platform.hpp"
#include "core/smallvec.hpp"
#include "core/watchdog.hpp"
#include "driver/internal.hpp"
#include "loops/loops.hpp"
#include "output/output.hpp"
#include "sigdb.hpp"
#include "simplify/simplify.hpp"

namespace pan::driver {

// (Analysed: lots 8 and 9's, when they land; Folded: lot 10's asts of the
// stage before it)
bool stage_available(Stage s) noexcept { return s != Stage::Analysed; }

Stage last_available() noexcept { return Stage::Folded; }

std::string function_name(const sigdb::Database* db, const FunctionInfo& fn)
{
    switch (fn.kind) {
        case FunctionInfo::Kind::Fallback:
            return "_fallback(?)";
        case FunctionInfo::Kind::Internal:
            return std::format("internal_0x{:x}", fn.entry_pc);
        case FunctionInfo::Kind::Selector:
            break;
    }
    if (db)
        if (const auto e = db->function(fn.selector); e && e->trust() == sigdb::Trust::verified) {
            // python's get_func_name: name(type name, ...), an unnamed param _param<i + 1>
            std::string s(e->name());
            s += '(';
            usize i = 0;
            for (const sigdb::Field f : e->params()) {
                if (i)
                    s += ", ";
                f.type().append_text(s);
                s += ' ';
                if (f.name().empty())
                    s += std::format("_param{}", i + 1);
                else
                    s += f.name();
                ++i;
            }
            s += ')';
            return s;
        }
    return std::format("unknown{:08x}(?)", fn.selector);
}

namespace detail {

namespace {

// what the logs call a function (the asm's: its hash, python's internal_name)
std::string log_name(const FunctionInfo& fn)
{
    switch (fn.kind) {
        case FunctionInfo::Kind::Selector:
            return std::format("0x{:08x}", fn.selector);
        case FunctionInfo::Kind::Fallback:
            return "_fallback";
        case FunctionInfo::Kind::Internal:
            return std::format("internal_0x{:x}", fn.entry_pc);
    }
    return "?";
}

void info(std::string_view message) { log(log_info, LOGGER, message); }

// A FunctionInfo's values imported into the current context.
FunctionInfo import_info(Importer& imp, const FunctionInfo& f)
{
    FunctionInfo r = f;
    r.entry.checks = imp(f.entry.checks);
    r.entry.value_fails = imp(f.entry.value_fails);
    r.entry.entry_lines = imp(f.entry.entry_lines);
    r.entry.vm_state = imp(f.entry.vm_state);
    r.trace = imp(f.trace);
    return r;
}

// The pcs of the lines of a trace imported (imp): (the imported line, its
// pc in `from`), every trace of it (IF / WHILE bodies) walked once.
void collect_pcs(const Context& from, const Importer& imp, Value trace, std::vector<std::pair<Value, u32>>& out)
{
    if (!trace.is_trace() || from.pcs.size() == 0)
        return;
    std::vector<Value> todo{trace};
    std::unordered_set<u64> seen;
    while (!todo.empty()) {
        const Value t = todo.back();
        todo.pop_back();
        if (!seen.insert(t.raw()).second)
            continue;
        for (const Value l : t.args()) {
            if (const auto pc = from.pcs.pc_of(l))
                if (const auto nl = imp.lookup(l))
                    out.emplace_back(*nl, *pc);
            if (l.is_expr())
                for (const Value a : l.args())
                    if (a.is_trace())
                        todo.push_back(a);
        }
    }
}

// The trace without its ASM lines (python's rewrite_trace of the strings,
// --explain's "Without assembly"), every trace of it (IF bodies) too.
Value drop_asm(Value trace, std::unordered_map<u64, Value>& memo)
{
    check_stack();
    if (!trace.is_trace())
        return trace;
    if (const auto it = memo.find(trace.raw()); it != memo.end())
        return it->second;
    SmallVec<Value, 32> lines;
    bool changed = false;
    for (const Value l : trace.args()) {
        poll();
        if (l.is(Op::ASM)) {
            changed = true;
            continue;
        }
        Value nl = l;
        if (l.is_expr()) {
            SmallVec<Value, 8> ops;
            bool c = false;
            for (const Value a : l.args()) {
                const Value na = a.is_trace() ? drop_asm(a, memo) : a;
                c |= na != a;
                ops.push_back(na);
            }
            if (c) {
                nl = mk_like(l, ops.span());
                cx().pcs.inherit(nl, l);
            }
        }
        changed |= nl != l;
        lines.push_back(nl);
    }
    const Value r = changed ? mk_trace(lines.span()) : trace;
    memo.emplace(trace.raw(), r);
    return r;
}

// the entry's lines, then the body: python's trace (apply_entry: what
// --explain shows of every stage; the stages keep the entry apart)
Value with_entry(Value entry_lines, Value trace)
{
    if (!entry_lines.is_trace() || entry_lines.size() == 0 || !trace.is_trace())
        return trace;
    std::vector<Value> lines(entry_lines.begin(), entry_lines.end());
    lines.insert(lines.end(), trace.begin(), trace.end());
    return mk_trace(std::span<const Value>(lines.data(), lines.size()));
}

// the simplifier's stages, as python's simplify_trace explains them
std::string_view stage_title(simplify::ExplainStage s)
{
    using simplify::ExplainStage;
    switch (s) {
        case ExplainStage::SimplifyExpressions: return "simplify expressions";
        case ExplainStage::CleanupVariables: return "cleanup variables";
        case ExplainStage::CleanupMems: return "cleanup mems";
        case ExplainStage::PrecompiledResults: return "results of precompiled contracts";
        case ExplainStage::Minimums: return "minimums";
        case ExplainStage::SplitSetmemsStorages: return "split setmems & storages";
        case ExplainStage::CleanupVars: return "cleanup vars";
        case ExplainStage::ReplaceStorageWithLength: return "replace storage with length";
        case ExplainStage::CleanupUnusedIfs: return "cleanup unused ifs";
        case ExplainStage::ConvertLoopsToSetmems: return "convert loops to setmems";
        case ExplainStage::MoveLoopIndexes: return "move loop indexes outside of loops";
        case ExplainStage::Heuristics: return "using heuristics to clean up some things";
        case ExplainStage::FinalCleanup: return "final setmem/condition cleanup";
        case ExplainStage::CleaningStorages: return "cleaning up storages slightly";
        case ExplainStage::NicerNames: return "adding nicer variable names";
    }
    return "?";
}

class ExplainStages final : public simplify::ExplainHook {
public:
    // entry_lines: where the job holds them (a compaction moves them)
    ExplainStages(Explainer& x, const Value* entry_lines) : x_(x), entry_(entry_lines) {}
    void stage(simplify::ExplainStage s, Value trace) override { x_.trace(stage_title(s), with_entry(*entry_, trace)); }

private:
    Explainer& x_;
    const Value* entry_;
};

// a function's time limit, checked between the stages (the asm's
// .Ldw_check_deadline): the watchdog cuts a stage in its middle
void check_deadline(i64 deadline)
{
    poll();
    if (deadline && platform::monotonic_ns() > deadline)
        throw Timeout(MSG_FUNCTION_TIMEOUT);
}

}  // namespace

Stage jobs_last(Stage upto) noexcept { return upto < Stage::Simplified ? upto : Stage::Simplified; }

i64 deadline_after(i64 base_ns) noexcept
{
    if (!timeouts_enabled())
        return 0;
    const i64 t = scaled_timeout(base_ns);
    if (t >= limits::NO_TIMEOUT_NS)
        return 0;
    const i64 now = platform::monotonic_ns();
    return t > std::numeric_limits<i64>::max() - now ? 0 : now + t;
}

// --- the jobs ---------------------------------------------------------------------

// What a job leaves (read after its wave, in job order): its stages, on the
// contract's context.
struct Run::JobOut {
    std::string name;            // the logs'
    bool ran = false;            // its job ran
    bool done = false;           // made to the last stage asked
    Stage at = Stage::Raw;       // else: the stage it failed at
    std::string message;         // why
    std::array<FunctionInfo, STAGE_COUNT> stage{};
    std::array<bool, STAGE_COUNT> has{};
    std::vector<vm::InternalEntry> found;  // what its VM found (when done)
    std::vector<std::pair<Value, u32>> pcs;  // its lines' pcs
    std::string explain;
    bool explain_first = false, explain_last = false;
    u64 first_hash = 0, last_hash = 0;
    usize first_end = 0;
};

// What a job made, on its own context.
struct Run::Local {
    std::array<FunctionInfo, STAGE_COUNT> stage{};
    std::array<bool, STAGE_COUNT> has{};
    std::vector<vm::InternalEntry> found;
    void keep(Stage s, const FunctionInfo& fn)
    {
        stage[stage_index(s)] = fn;
        has[stage_index(s)] = true;
    }
};

// The values a job holds besides the trace being simplified: the roots of
// the simplifier's compactions, written back when it's done - or when it
// throws (a compaction gave the old ones back).
struct Run::Roots {
    Roots(FunctionInfo& fn, Local& local) : fn_(fn), local_(local), held_(local.has)
    {
        hold(fn_, false);
        for (unsigned s = 0; s < STAGE_COUNT; ++s)
            if (held_[s])
                hold(local_.stage[s], true);
    }
    ~Roots()
    {
        usize k = 0;
        back(fn_, false, k);
        for (unsigned s = 0; s < STAGE_COUNT; ++s)
            if (held_[s])
                back(local_.stage[s], true, k);
    }
    Roots(const Roots&) = delete;
    Roots& operator=(const Roots&) = delete;
    std::vector<Value> values;

private:
    void hold(const FunctionInfo& f, bool with_trace)
    {
        values.insert(values.end(), {f.entry.checks, f.entry.value_fails, f.entry.entry_lines, f.entry.vm_state});
        if (with_trace)
            values.push_back(f.trace);
    }
    void back(FunctionInfo& f, bool with_trace, usize& k) noexcept
    {
        f.entry.checks = values[k++];
        f.entry.value_fails = values[k++];
        f.entry.entry_lines = values[k++];
        f.entry.vm_state = values[k++];
        if (with_trace)
            f.trace = values[k++];
    }
    FunctionInfo& fn_;
    Local& local_;
    const std::array<bool, STAGE_COUNT> held_;  // the stages held (local.has then)
};

Run::Run(std::span<const u8> code, const Settings& settings)
    : code_(code), s_(settings), map_(analyse(code)), main_(cx()), main_budget_(cx().budget)
{
    shared_.code = code_;
    shared_.map = &map_;
    shared_.db = s_.options.db;
    shared_.free_memory_pointer = map_.fmp || sets_free_memory_pointer(code_);
    if (const auto md = metadata(code_))
        shared_.lang = md->lang;
    result_.lang = shared_.lang;
    result_.has_code = map_.ninsn != 0;
    base_ = main_budget_.counting().used();
}

Run::~Run() = default;

Run::JobOut& Run::out_of(bool internal, u32 i) { return internal ? int_out_[i] : fn_out_[i]; }

void Run::set_phase_limit()
{
    if (!s_.own_contract)
        return;
    const usize x = s_.fn_memory;
    if (x == 0) {
        main_budget_.counting().set_limit(0);
        return;
    }
    // base + imports + a function's limit, saturated
    usize l = base_;
    l = imported_ > std::numeric_limits<usize>::max() - l ? std::numeric_limits<usize>::max() : l + imported_;
    l = x > std::numeric_limits<usize>::max() - l ? std::numeric_limits<usize>::max() : l + x;
    main_budget_.counting().set_limit(l);
}

void Run::functions()
{
    info("Running light execution to find functions.");
    if (!result_.has_code)
        return;  // (python: "# No code found for this contract.")
    set_phase_limit();
    discover();
    // the functions asked for: python's only_func_name, on the names of the loader
    std::vector<std::pair<bool, u32>> jobs;
    {
        std::vector<FunctionInfo> kept;
        for (FunctionInfo& f : fns_) {
            if (!s_.options.only_function.empty() &&
                !function_name(s_.options.db, f).starts_with(s_.options.only_function))
                continue;
            kept.push_back(std::move(f));
        }
        fns_ = std::move(kept);
    }
    fn_out_.resize(fns_.size());
    for (u32 i = 0; i < fns_.size(); ++i)
        jobs.emplace_back(false, i);
    // the waves: the functions, then the recursive internal functions they
    // found (python's internal), then those these found... each wave by entry
    while (!jobs.empty()) {
        run_wave(jobs);
        if (s_.parent_deadline && platform::monotonic_ns() > s_.parent_deadline)
            throw Timeout("the time limit was reached (PANORAMIX_TIMEOUT)");
        std::vector<vm::InternalEntry> fresh;
        merge_wave(jobs, fresh);
        jobs.clear();
        std::stable_sort(fresh.begin(), fresh.end(),
                         [](const vm::InternalEntry& a, const vm::InternalEntry& b) { return a.entry < b.entry; });
        for (const vm::InternalEntry& e : fresh) {
            FunctionInfo f;
            f.kind = FunctionInfo::Kind::Internal;
            f.entry_pc = e.entry;
            f.params.resize(e.nargs);
            jobs.emplace_back(true, u32(ints_.size()));
            ints_.push_back(std::move(f));
            recs_.push_back(e);
            int_out_.emplace_back();
        }
    }
    info("Functions decompilation finished, now doing post-processing.");
    assemble();
}

// python's Loader.run on the dispatcher (lot 5's discover), on a context of
// its own: half of a function's limit, the deadline of its VM and of a
// function after it; what it found imported into the contract's context
void Run::discover()
{
    i64 deadline = 0;
    if (timeouts_enabled()) {
        const i64 a = scaled_timeout(limits::LOADER_TIMEOUT_NS), b = scaled_timeout(limits::FUNC_TIMEOUT_NS);
        if (a < limits::NO_TIMEOUT_NS && b < limits::NO_TIMEOUT_NS) {
            const i64 now = platform::monotonic_ns();
            deadline = a + b > std::numeric_limits<i64>::max() - now ? 0 : now + a + b;
        }
    }
    deadline = earlier(deadline, s_.parent_deadline);
    const usize x = s_.fn_memory;
    Budget budget{Budget::Limits{.memory = x ? std::max<usize>(x / 2, 1) : 0, .deadline_ns = deadline}};
    std::string issue;
    {
        Attach attach(budget);
        std::optional<Watchdog::Watch> watch;
        if (deadline)
            try {
                watch.emplace(budget, deadline);
            } catch (const std::system_error&) {  // (no watchdog: the VM's own limits)
            }
        try {
            std::unique_ptr<Context> ctx = Context::create(budget, &shared_);
            std::vector<FunctionInfo> found;
            {
                ContextScope scope(*ctx);
                found = vm::discover(shared_, budget);
            }
            // into the contract's context (no deadline nor limit of the discovery's)
            Budget imp_budget{Budget::Limits{}};
            Attach imp_attach(imp_budget);
            ContextScope scope(main_);
            Importer imp;
            for (const FunctionInfo& f : found)
                fns_.push_back(import_info(imp, f));
        } catch (const Timeout&) {
            issue = MSG_DISCOVERY_TIMEOUT;
        } catch (const Abort& e) {
            issue = e.what();
        } catch (const Error& e) {
            issue = e.what();
        } catch (const std::bad_alloc&) {
            issue = MSG_NO_MEMORY;
        }
    }
    if (issue.empty())
        return;
    // python's "Loader issue": the default function alone, at 0, its entry unknown
    log(log_error, LOGGER, "Loader issue: " + issue);
    fns_.clear();
    FunctionInfo f;
    f.kind = FunctionInfo::Kind::Fallback;
    f.entry.checks = mk_list({});
    f.entry.entry_lines = mk_trace({});
    fns_.push_back(std::move(f));
}

void Run::run_wave(const std::vector<std::pair<bool, u32>>& jobs)
{
    parallel_for(jobs.size(), s_.options.threads, [&](usize k) { job(jobs[k].first, jobs[k].second); });
    // the lines' pcs, in job order (a line two functions share: the first's)
    for (const auto& [internal, i] : jobs) {
        JobOut& out = out_of(internal, i);
        for (const auto& [line, pc] : out.pcs)
            main_.pcs.note(line, pc);
        out.pcs.clear();
        out.pcs.shrink_to_fit();
    }
    // --explain: the jobs' texts in job order, python's prev_trace carried
    // from each to the next (a job's first trace equal to it not printed)
    if (s_.explain)
        for (const auto& [internal, i] : jobs) {
            JobOut& out = out_of(internal, i);
            usize from = 0;
            if (out.explain_first && explain_prev_ && out.first_hash == explain_prev_hash_)
                from = out.first_end;
            if (!explain_cut_) {
                if (explain_.size() + (out.explain.size() - std::min(from, out.explain.size())) > EXPLAIN_MAX) {
                    explain_ += EXPLAIN_CUT;
                    explain_cut_ = true;
                } else {
                    explain_.append(out.explain, std::min(from, out.explain.size()), std::string::npos);
                }
            }
            out.explain.clear();
            out.explain.shrink_to_fit();
            if (out.explain_last) {
                explain_prev_ = true;
                explain_prev_hash_ = out.last_hash;
            }
        }
}

// the recursive internal functions found by the jobs whose functions were
// made, in job order: those not known yet (python's internal.setdefault,
// new.append)
void Run::merge_wave(const std::vector<std::pair<bool, u32>>& jobs, std::vector<vm::InternalEntry>& fresh)
{
    auto known = [&](u32 entry) {
        for (const vm::InternalEntry& e : recs_)
            if (e.entry == entry)
                return true;
        for (const vm::InternalEntry& e : fresh)
            if (e.entry == entry)
                return true;
        return false;
    };
    for (const auto& [internal, i] : jobs) {
        JobOut& out = out_of(internal, i);
        if (out.done)
            for (const vm::InternalEntry& e : out.found)
                if (!known(e.entry))
                    fresh.push_back(e);
        out.found.clear();
    }
}

void Run::job(bool internal, u32 i) noexcept
{
    JobOut& out = out_of(internal, i);
    try {
        out.name = log_name(internal ? ints_[i] : fns_[i]);
        run_job(internal, i, out);
    } catch (...) {
        // (what the job's own handlers didn't take: its logs, the names - no memory)
        out.done = false;
        if (out.message.empty())
            out.message = MSG_NO_MEMORY;
    }
    out.ran = true;
    if (!out.done)
        try {
            log(log_error, LOGGER, "Problem with " + out.name + ": " + out.message);
        } catch (...) {  // (no memory for the line: not written)
        }
}

void Run::run_job(bool internal, u32 i, JobOut& out)
{
    const FunctionInfo& src = internal ? ints_[i] : fns_[i];  // (the contract's: read only meanwhile)
    const i64 deadline = earlier(deadline_after(limits::FUNC_TIMEOUT_NS), s_.parent_deadline);
    Budget budget{Budget::Limits{.memory = s_.fn_memory, .deadline_ns = deadline}};
    Attach attach(budget);
    std::optional<Watchdog::Watch> watch;
    if (deadline)
        try {
            watch.emplace(budget, deadline);
        } catch (const std::system_error&) {  // (no watchdog: the stages' own limits)
        }
    Local local;
    std::optional<Explainer> explainer;
    FunctionInfo fn;
    if (s_.explain)
        explainer.emplace(s_.color, &fn, s_.options.db);
    const Stage upto = s_.options.upto;
    Stage at = Stage::Raw;
    bool failed = false;
    std::string message;
    std::unique_ptr<Context> ctx;
    try {
        ctx = Context::create(budget, &shared_);
        ContextScope scope(*ctx);
        info("Decompiling " + out.name + "...");
        {
            Importer imp;
            fn = import_info(imp, src);
        }
        // lot 5's VM (python's VM(loader).run, an internal function knowing itself)
        info(" -> Interpreting EVM on function...");
        vm::VmOptions vo;
        vo.verbose = s_.options.verbose || s_.explain;
        std::vector<vm::InternalEntry> own;
        if (internal) {
            own.push_back(recs_[i]);
            vo.known_internals = &own;
        }
        vm::VmResult r = vm::run_function(shared_, fn, vo);
        fn.trace = r.trace;
        fn.calls = std::move(r.calls);
        fn.loops = std::move(r.loops);
        local.found = std::move(r.found_internals);
        check_deadline(deadline);
        if (explainer) {
            explainer->trace("Initial decompiled trace", with_entry(fn.entry.entry_lines, fn.trace));
            std::unordered_map<u64, Value> memo;
            fn.trace = drop_asm(fn.trace, memo);
            explainer->trace("Without assembly", with_entry(fn.entry.entry_lines, fn.trace));
        }
        local.keep(Stage::Raw, fn);
        // lot 6: python's make_whiles (whiles.make)
        if (upto >= Stage::Whiles) {
            at = Stage::Whiles;
            info(" -> Cleaning up AST, identifying loops...");
            loops::whiles_function(fn);
            if (explainer)
                explainer->trace("Loops -> whiles", with_entry(fn.entry.entry_lines, fn.trace));
            check_deadline(deadline);
            local.keep(Stage::Whiles, fn);
        }
        // lot 7: python's simplify_trace (make_whiles' end)
        if (upto >= Stage::Simplified) {
            at = Stage::Simplified;
            {
                // compacted between its rounds past the threshold (the job
                // owns its context): every other value the job holds a root,
                // written back whatever happens (a compaction freed the old ones)
                Roots roots(fn, local);
                simplify::SimplifyOptions so;
                so.compact = true;
                so.compact_roots = roots.values;
                std::optional<ExplainStages> hook;
                if (explainer)
                    hook.emplace(*explainer, &roots.values[2]);  // (fn's entry lines: Roots::hold)
                simplify::simplify_function(fn, so, hook ? &*hook : nullptr);
            }
            if (explainer) {
                explainer->trace("final", with_entry(fn.entry.entry_lines, fn.trace));
                explainer->trace("folded", output::fold(with_entry(fn.entry.entry_lines, fn.trace)));
            }
            check_deadline(deadline);
            local.keep(Stage::Simplified, fn);
        }
        // (Analysed: lot 8's traits, when it lands)
    } catch (const Timeout&) {
        failed = true;
        message = MSG_FUNCTION_TIMEOUT;
    } catch (const Abort& e) {
        failed = true;
        message = e.what();
    } catch (const Error& e) {
        failed = true;
        message = e.what();
    } catch (const std::bad_alloc&) {
        failed = true;
        message = MSG_NO_MEMORY;
    } catch (const std::exception& e) {
        failed = true;
        message = e.what();
    }
    out.done = !failed;
    out.at = at;
    out.message = std::move(message);
    if (!failed)
        out.found = std::move(local.found);
    if (explainer) {
        out.explain = std::move(explainer->out);
        out.explain_first = explainer->first;
        out.first_hash = explainer->first_hash;
        out.first_end = explainer->first_end;
        out.explain_last = explainer->last;
        out.last_hash = explainer->last_hash;
    }
    // what it made, into the contract's context (a failed one's stages
    // before its failure too), then its context freed
    if (ctx)
        import_job(local, *ctx, out);
    ctx.reset();
    if (log_enabled(log_debug))
        try {
            log(log_debug, LOGGER,
                std::format("{}: the arena took {} MiB at most", out.name, budget.counting().peak() >> 20));
        } catch (...) {
        }
}

void Run::import_job(Local& local, Context& from, JobOut& out)
{
    const u32 wanted = wanted_stages();
    std::lock_guard<std::mutex> lock(import_mutex_);
    // on this thread for the import: a budget of no deadline (the job's may
    // have expired), the contract's context with no limit of its own (what a
    // function made is bounded by its own limit)
    Budget imp_budget{Budget::Limits{}};
    Attach attach(imp_budget);
    const usize before = main_budget_.counting().used();
    if (s_.own_contract)
        main_budget_.counting().set_limit(0);
    try {
        ContextScope scope(main_);
        Importer imp;
        for (unsigned s = 0; s < STAGE_COUNT; ++s) {
            if (!local.has[s] || !(wanted & (u32(1) << s)))
                continue;
            out.stage[s] = import_info(imp, local.stage[s]);
            out.has[s] = true;
            collect_pcs(from, imp, local.stage[s].trace, out.pcs);
        }
    } catch (...) {
        // (the system's memory, or the caller's limit: the function is a
        // problem, nothing of it kept)
        std::string why = MSG_NO_MEMORY;
        try {
            throw;
        } catch (const MemoryLimit& e) {
            why = e.what();
        } catch (...) {
        }
        out.has = {};
        out.pcs.clear();
        out.found.clear();
        if (out.done) {
            out.done = false;
            out.at = Stage::Raw;
            out.message = std::move(why);
        }
    }
    const usize after = main_budget_.counting().used();
    if (after > before)
        imported_ += after - before;
    set_phase_limit();
}

// The stages of every function, by job order (python's dicts): the
// functions in the dispatcher's order, the internal ones by entry; the
// problems in the order of the jobs (the functions, then the waves).
void Run::assemble()
{
    ContractResult& r = result_;
    const Stage upto = s_.options.upto;
    // the internal functions by entry (python: sorted(internal_functions))
    std::vector<u32> perm(ints_.size());
    std::iota(perm.begin(), perm.end(), 0u);
    std::stable_sort(perm.begin(), perm.end(), [&](u32 a, u32 b) { return recs_[a].entry < recs_[b].entry; });
    std::vector<u32> where(ints_.size());
    for (u32 k = 0; k < perm.size(); ++k)
        where[perm[k]] = k;
    r.internal_entries.clear();
    for (const u32 k : perm)
        r.internal_entries.push_back(recs_[k]);
    // the problems
    std::vector<std::optional<u32>> fn_problem(fns_.size()), int_problem(ints_.size());
    for (u32 i = 0; i < fns_.size(); ++i)
        if (!fn_out_[i].done) {
            fn_problem[i] = u32(r.problems.size());
            r.problems.push_back(Problem{false, i, fn_out_[i].at, fn_out_[i].message});
        }
    for (u32 k = 0; k < ints_.size(); ++k)
        if (!int_out_[k].done) {
            int_problem[k] = u32(r.problems.size());
            r.problems.push_back(Problem{true, where[k], int_out_[k].at, int_out_[k].message});
        }
    // a function at a stage: its trace there, or (failed at it or before) none
    auto at_stage = [](const FunctionInfo& src, JobOut& out, std::optional<u32> problem, unsigned s) {
        if (out.done || s < stage_index(out.at)) {
            if (out.has[s])
                return std::move(out.stage[s]);
        }
        FunctionInfo f = src;
        f.trace = Value();
        f.problem = problem;
        return f;
    };
    const u32 wanted = wanted_stages();
    for (unsigned s = 0; s <= stage_index(jobs_last(upto)); ++s) {
        r.made[s] = true;
        r.last = Stage(s);
        if (!(wanted & (u32(1) << s)))
            continue;
        r.kept[s] = true;
        auto& fs = r.functions[s];
        fs.reserve(fns_.size());
        for (u32 i = 0; i < fns_.size(); ++i)
            fs.push_back(at_stage(fns_[i], fn_out_[i], fn_problem[i], s));
        auto& is = r.internals[s];
        is.reserve(ints_.size());
        for (const u32 k : perm)
            is.push_back(at_stage(ints_[k], int_out_[k], int_problem[k], s));
    }
    fn_out_.clear();
    int_out_.clear();
}

// the stages imported from the jobs: those kept, every one for the
// observer, and the one the contract phase starts from
u32 Run::wanted_stages() const noexcept
{
    u32 w = s_.options.keep;
    if (s_.options.observer)
        w = KEEP_ALL;
    if (s_.options.upto > jobs_last(s_.options.upto))
        w |= keep_bit(jobs_last(s_.options.upto));
    return w;
}

void Run::contract_phase()
{
    ContractResult& r = result_;
    // When they land (python's Contract.postprocess): lot 8's traits run in
    // the jobs after Simplified (python's Function(): params, payable - the
    // callvalue check out of the trace -, read_only, const, getter; --explain's
    // "function traits"); here lot 9's storage over every function (Analysed:
    // the storage forms, ContractResult::storage; its fallback the raw
    // accesses), then lot 8's SafeMath on the asts (ContractResult::safemath).
    //
    // Folded: lot 10's asts (python's make_asts) of the last stage made, each
    // function on a context of its own, on threads, to the contract phase's
    // deadline (a fold that can't leaves the trace unfolded)
    if (s_.options.upto >= Stage::Folded && r.made[stage_index(r.last)] && r.kept[stage_index(r.last)]) {
        const unsigned from = stage_index(r.last);
        output::AstStageOptions ao;
        ao.threads = s_.options.threads;
        ao.deadline_ns = post_deadline_;
        ao.shared = &shared_;
        constexpr unsigned f = stage_index(Stage::Folded);
        output::ast_stage(r.functions[from], r.functions[f], ao);
        output::ast_stage(r.internals[from], r.internals[f], ao);
        r.made[f] = r.kept[f] = true;
        r.last = Stage::Folded;
    }
    if (StageObserver* o = s_.options.observer)
        for (unsigned s = 0; s < STAGE_COUNT; ++s)
            if (r.made[s] && r.kept[s])
                o->stage(Stage(s), r.functions[s], r.internals[s]);
    for (unsigned s = 0; s < STAGE_COUNT; ++s)
        if (r.kept[s] && !(s_.options.keep & (u32(1) << s)) && Stage(s) != r.last) {
            r.kept[s] = false;
            r.functions[s].clear();
            r.functions[s].shrink_to_fit();
            r.internals[s].clear();
            r.internals[s].shrink_to_fit();
        }
}

}  // namespace detail

ContractResult run_pipeline(std::span<const u8> code, const PipelineOptions& options)
{
    if (!tl_ctx)
        throw InternalError("run_pipeline: no current context");
    detail::Settings s;
    s.options = options;
    usize threads = options.threads == 0 ? platform::cpu_count() : options.threads;
    if (threads > limits::MAX_THREADS)
        threads = limits::MAX_THREADS;
    s.options.threads = threads;
    if (s.options.upto > last_available())
        s.options.upto = last_available();
    s.fn_memory = options.function_memory ? options.function_memory : job_memory_limit(threads);
    if (const Budget* b = Budget::current())
        s.parent_deadline = b->limits().deadline_ns;
    detail::Run run(code, s);
    run.set_post_deadline(s.parent_deadline);
    run.functions();
    run.contract_phase();
    return std::move(run.result());
}

ContractResult run_until(std::span<const u8> code, Stage upto, const PipelineOptions& options)
{
    PipelineOptions o = options;
    o.upto = upto;
    return run_pipeline(code, o);
}

}  // namespace pan::driver
