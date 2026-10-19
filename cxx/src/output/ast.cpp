// The ast of a function (python Contract.make_ast): its entry checks and
// trace, lot 7's short_circuits, the folder - on a context and budget of its
// own (the asm's fold_isolated: FOLD_LIMIT; past it, the trace unfolded) -
// the result imported into the caller's context; the Folded stage of a
// contract, the functions on threads (the asm's fold_many).
#include <mutex>
#include <optional>
#include <system_error>

#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/errors.hpp"
#include "core/jobs.hpp"
#include "core/platform.hpp"
#include "core/watchdog.hpp"
#include "output/fold.hpp"
#include "output/output.hpp"
#include "simplify/simplify.hpp"

namespace pan::output {

namespace {

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

// the ast on cx() (no isolation): the entry's checks (EntryCondition::
// entry_lines' IFs: a dispatcher's check whose other branch halts) and the
// SETMEMs the body may read, then the body (python's apply_entry: what the
// function's text runs); its calls' results kept where the text would take
// them for another call's; lot 7's short_circuits; the folder (its failures
// leave the trace unfolded); the ifs of branches the same but for their
// calls' ids gone
Value ast_here(Value trace, Value entry_lines, const AstOptions& opts)
{
    Value t = opts.entry_checks ? detail::with_entry(entry_lines, trace) : trace;
    t = detail::snapshot_call_results(t);
    if (opts.short_circuits)
        t = simplify::short_circuits(t);
    if (opts.fold) {
        t = detail::fold_trace(t);
        t = detail::merge_same_branches(t);
    }
    return t;
}

// fn's ast made on a context and budget of its own, imported into `into`
// (under lock when given): the trace unfolded (but its entry checks) when
// the fold's memory limit is reached
Value isolated_ast(const FunctionInfo& fn, Context& into, std::mutex* lock, const AstOptions& opts,
                   const ContractShared* shared)
{
    auto import_into = [&](auto&& make) {
        std::unique_lock<std::mutex> guard;
        if (lock)
            guard = std::unique_lock<std::mutex>(*lock);
        // (on this thread for the import: a budget of no limit, the caller's
        // context - what a fold made is bounded by its own limit)
        Budget imp_budget{Budget::Limits{}};
        Attach attach(imp_budget);
        ContextScope scope(into);
        return make();
    };
    try {
        Budget budget{Budget::Limits{.memory = opts.fold_limit, .deadline_ns = opts.deadline_ns}};
        Attach attach(budget);
        std::optional<Watchdog::Watch> watch;
        if (opts.deadline_ns)
            try {
                watch.emplace(budget, opts.deadline_ns);
            } catch (const std::system_error&) {  // (no watchdog: the deadline checked between functions)
            }
        std::unique_ptr<Context> ctx = Context::create(budget, shared);
        Value ast;
        {
            ContextScope scope(*ctx);
            Importer imp;
            const Value trace = imp(fn.trace);
            const Value entry = imp(fn.entry.entry_lines);
            ast = ast_here(trace, entry, opts);
        }
        return import_into([&] {
            Importer imp;
            return imp(ast);
        });
    } catch (const MemoryLimit&) {
    } catch (const SizeLimit&) {
    } catch (const DepthLimit&) {
    } catch (const std::bad_alloc&) {
    }
    // (python: past FOLD_LIMIT, unfolded)
    return import_into([&] {
        AstOptions o = opts;
        o.fold = false;
        o.short_circuits = false;
        return ast_here(fn.trace, fn.entry.entry_lines, o);
    });
}

}  // namespace

Value fold(Value trace) { return detail::fold_trace(trace); }

Value make_ast(const FunctionInfo& fn, const AstOptions& opts)
{
    if (!fn.trace.is_trace())
        return fn.trace;
    return isolated_ast(fn, cx(), nullptr, opts, cx().shared);
}

void ast_stage(std::span<const FunctionInfo> in, std::vector<FunctionInfo>& out, const AstStageOptions& opts)
{
    out.assign(in.begin(), in.end());
    if (in.empty())
        return;
    Context& into = cx();
    AstOptions ao = opts.ast;
    if (opts.deadline_ns && (!ao.deadline_ns || opts.deadline_ns < ao.deadline_ns))
        ao.deadline_ns = opts.deadline_ns;
    const ContractShared* shared = opts.shared ? opts.shared : into.shared;
    std::mutex lock;
    std::vector<std::optional<Value>> asts(in.size());
    std::vector<std::exception_ptr> errors(in.size());
    parallel_for(in.size(), opts.threads ? opts.threads : 1, [&](usize i) {
        const FunctionInfo& f = in[i];
        if (f.problem || !f.trace.is_trace())
            return;
        try {
            asts[i] = isolated_ast(f, into, &lock, ao, shared);
        } catch (...) {
            errors[i] = std::current_exception();  // (a Timeout: the stage's, rethrown below)
        }
    });
    for (usize i = 0; i < in.size(); ++i) {
        if (errors[i]) {
            try {
                std::rethrow_exception(errors[i]);
            } catch (const Abort&) {
                throw;
            } catch (const std::bad_alloc&) {
                throw;
            } catch (...) {  // (an Error: the function's trace stays unfolded)
            }
        }
        if (asts[i])
            out[i].trace = *asts[i];
    }
    if (opts.deadline_ns && platform::monotonic_ns() > opts.deadline_ns)
        throw Timeout("the post-processing and the text took more than 3 minutes");
}

}  // namespace pan::output
