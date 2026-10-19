// parallel_for: the caller and its workers take the iterations from one
// atomic index; the caller's storage (by index) gets the results.
#include "core/jobs.hpp"

#include <atomic>
#include <exception>
#include <thread>
#include <vector>

#include "core/budget.hpp"
#include "core/platform.hpp"

namespace pan {

namespace {

// what the threads of one parallel_for share (on the caller's stack: it
// returns only once every worker is joined)
struct Loop {
    usize n;
    const std::function<void(usize)>& fn;
    std::atomic<usize> next{0};
    std::atomic<bool> failed{false};
    std::exception_ptr error{};  // written once (failed), read after the joins

    void work() noexcept {
        try {
            for (;;) {
                usize i = next.fetch_add(1, std::memory_order_relaxed);
                if (i >= n) return;
                fn(i);
            }
        } catch (...) {
            if (!failed.exchange(true, std::memory_order_relaxed)) error = std::current_exception();
            next.store(n, std::memory_order_relaxed);  // none more handed out
        }
    }
};

}  // namespace

void parallel_for(usize n, usize threads, const std::function<void(usize)>& fn) {
    if (n == 0) return;
    usize width = threads < n ? threads : n;
    if (width > limits::MAX_THREADS) width = limits::MAX_THREADS;
    if (width <= 1) {
        for (usize i = 0; i < n; i++) fn(i);
        return;
    }
    Loop loop{n, fn};
    std::vector<std::thread> workers;
    try {
        workers.reserve(width - 1);
    } catch (...) {
        // (no room for the handles: this thread does it all)
    }
    while (workers.size() < workers.capacity() && workers.size() + 1 < width) {
        try {
            workers.push_back(platform::spawn([&loop] { loop.work(); }, limits::WORKER_STACK));
        } catch (...) {
            break;  // none more can be started: those that were and this one do it all
        }
    }
    loop.work();
    for (std::thread& t : workers) t.join();
    if (loop.error) std::rethrow_exception(loop.error);
}

}  // namespace pan
