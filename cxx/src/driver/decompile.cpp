// decompile() (decompile.hpp, through pan::decompile): the pipeline on a
// thread of its own with a worker's stack (the asm's decompile_run), on a
// context of its own bounded by the asm's phase limits, then the outputs
// under the post-processing's deadline; what fails there fails the
// decompilation ("decompilation failed: ..."), a function that fails is a
// problem in the text.
#include <format>
#include <optional>
#include <system_error>
#include <thread>

#include "core/errors.hpp"
#include "core/platform.hpp"
#include "core/watchdog.hpp"
#include "driver/internal.hpp"
#include "sigdb.hpp"

namespace pan::driver {

namespace {

[[noreturn]] void failed(std::string_view why, std::string explain)
{
    std::string message = "decompilation failed: ";
    message += why;
    log(log_error, detail::LOGGER, message);
    throw DecompileError(message, std::move(explain));
}

// The contract's budget and context, made before its thread is: with their
// first chunk, so that a system that has no more memory to give (an address
// space limit) fails the functions, whose contexts can't be had, and not the
// contract (the asm's: the host process lives on, the text says so).
struct Contract {
    Budget budget{Budget::Limits{}};
    std::unique_ptr<Context> ctx;
    Contract()
    {
        ctx = Context::create(budget);
        ContextScope scope(*ctx);
        mk_list({mk_int(0)});  // (a node: the arena's first chunk)
    }
};

Decompilation decompile_here(std::span<const u8> code, const DecompileOptions& o, Contract& c)
{
    detail::Settings s;
    usize threads = o.threads == 0 ? platform::cpu_count() : o.threads;
    if (threads > limits::MAX_THREADS)
        threads = limits::MAX_THREADS;
    s.options.threads = threads;
    s.options.only_function = o.only_function;
    s.options.verbose = o.verbose || o.explain;
    s.options.upto = last_available();
    // what the outputs read: the last stage's traces (and --repr python's orig_trace)
    s.options.keep = keep_bit(last_available()) | (o.repr ? keep_bit(Stage::Simplified) : 0);
    s.options.db = sigdb::get();
    s.explain = o.explain;
    s.color = o.color;
    s.own_contract = true;
    s.fn_memory = job_memory_limit(threads);

    Budget& budget = c.budget;
    detail::Attach attach(budget);
    ContextScope scope(*c.ctx);
    std::optional<detail::Run> run;
    try {
        run.emplace(code, s);  // (the code analysed: SizeLimit past 4 GiB)
    } catch (const Error& e) {
        failed(e.what(), {});
    }
    c.ctx->shared = &run->shared();
    try {
        run->functions();
        Decompilation d;
        if (!run->result().has_code) {
            d.text = detail::no_code_text(o.color);
            if (o.json)
                d.json = "{}";
            return d;
        }
        // the post-processing and the text: the rest of the limit, a deadline
        run->set_phase_limit();
        const i64 deadline = detail::deadline_after(limits::POST_TIMEOUT_NS);
        std::optional<Watchdog::Watch> watch;
        if (deadline)
            try {
                watch.emplace(budget, deadline);
            } catch (const std::system_error&) {
            }
        run->set_post_deadline(deadline);
        run->contract_phase();
        const ContractResult& r = run->result();
        if (o.asm_lines)
            d.asm_lines = evm::disassembly_lines(code);
        if (o.json) {
            try {
                d.json = detail::contract_json(r, o, s.options.db);
            } catch (const Error& e) {  // (python's except Exception: the deadline goes on)
                log(log_error, detail::LOGGER, std::string("Failed json serialization. (") + e.what() + ")");
                d.json = "{}";
            }
        }
        d.text = detail::contract_text(r, o, s.options.db);
        if (deadline && platform::monotonic_ns() > deadline)
            throw Timeout(detail::MSG_POST_TIMEOUT);
        d.explain = run->take_explain();
        if (log_enabled(log_debug))
            log(log_debug, detail::LOGGER,
                std::format("the contract: the arena took {} MiB at most", budget.counting().peak() >> 20));
        return d;
    } catch (const Timeout&) {
        failed(detail::MSG_POST_TIMEOUT, run->take_explain());
    } catch (const Abort& e) {
        failed(e.what(), run->take_explain());
    } catch (const Error& e) {
        failed(e.what(), run->take_explain());
    }
}

}  // namespace

Decompilation decompile(std::span<const u8> code, const DecompileOptions& options)
{
    init();
    std::optional<Contract> contract;
    try {
        contract.emplace();
    } catch (const Error& e) {
        failed(e.what(), {});
    }
    std::optional<Decompilation> d;
    std::exception_ptr error;
    auto body = [&] {
        try {
            d.emplace(decompile_here(code, options, *contract));
        } catch (...) {
            error = std::current_exception();
        }
    };
    bool ran = false;
    try {
        std::thread t = platform::spawn(body, limits::WORKER_STACK);
        ran = true;
        t.join();
    } catch (const std::system_error&) {
    }
    if (!ran)
        body();  // (no thread: on this one, its stack bounded by check_stack)
    contract.reset();
    chunk_pool_trim();  // (the arenas' memory back to the system, but a few chunks)
    if (error)
        std::rethrow_exception(error);
    return std::move(*d);
}

}  // namespace pan::driver
