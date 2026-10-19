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

Decompilation decompile_here(std::span<const u8> code, const DecompileOptions& o)
{
    init();
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

    Budget budget{Budget::Limits{}};
    detail::Attach attach(budget);
    std::string explain;
    try {
        std::unique_ptr<Context> ctx = Context::create(budget);
        ContextScope scope(*ctx);
        detail::Run run(code, s);
        ctx->shared = &run.shared();
        run.functions();
        explain = run.take_explain();
        Decompilation d;
        if (!run.result().has_code) {
            d.text = detail::no_code_text(o.color);
            if (o.json)
                d.json = "{}";
            return d;
        }
        // the post-processing and the text: the rest of the limit, a deadline
        run.set_phase_limit();
        const i64 deadline = detail::deadline_after(limits::POST_TIMEOUT_NS);
        std::optional<Watchdog::Watch> watch;
        if (deadline)
            try {
                watch.emplace(budget, deadline);
            } catch (const std::system_error&) {
            }
        run.contract_phase();
        const ContractResult& r = run.result();
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
        d.explain = std::move(explain);
        if (log_enabled(log_debug))
            log(log_debug, detail::LOGGER,
                std::format("the contract: the arena took {} MiB at most", budget.counting().peak() >> 20));
        return d;
    } catch (const Timeout&) {
        failed(detail::MSG_POST_TIMEOUT, std::move(explain));
    } catch (const Abort& e) {
        failed(e.what(), std::move(explain));
    } catch (const Error& e) {
        failed(e.what(), std::move(explain));
    }
}

}  // namespace

Decompilation decompile(std::span<const u8> code, const DecompileOptions& options)
{
    std::optional<Decompilation> d;
    std::exception_ptr error;
    auto body = [&] {
        try {
            d.emplace(decompile_here(code, options));
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
    if (error)
        std::rethrow_exception(error);
    return std::move(*d);
}

}  // namespace pan::driver
