// The watchdog's thread and its list of watches.
#include "core/watchdog.hpp"

#include <chrono>
#include <new>
#include <thread>

#include "core/budget.hpp"
#include "core/platform.hpp"

namespace pan {

namespace {

// the watchdog's thread barely uses its stack
constexpr usize WATCHDOG_STACK = usize(1) << 20;

}  // namespace

Watchdog& Watchdog::instance() {
    // leaked on purpose: no destruction at exit while the thread runs
    static Watchdog* const wd = [] {
        auto* w = new Watchdog();
        // a forked child has no watchdog thread: the next Watch starts one
        platform::at_fork(nullptr, nullptr, [] { Watchdog::after_fork_child(); });
        return w;
    }();
    return *wd;
}

Watchdog::Watch::Watch(Budget& budget, i64 deadline_ns) : budget_(&budget), deadline_ns_(deadline_ns) {
    if (deadline_ns > 0) Watchdog::instance().add(*this);
}

Watchdog::Watch::~Watch() {
    if (linked_) Watchdog::instance().remove(*this);
}

void Watchdog::add(Watch& w) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!started_) {
        // throws std::system_error: nothing linked, the next Watch tries again
        platform::spawn([this] { run(); }, WATCHDOG_STACK).detach();
        started_ = true;
    }
    bool was_empty = head_ == nullptr;
    w.prev_ = nullptr;
    w.next_ = head_;
    if (head_) head_->prev_ = &w;
    head_ = &w;
    w.generation_ = generation_;
    w.fired_ = false;
    w.linked_ = true;
    if (was_empty) wake_.notify_one();
}

void Watchdog::remove(Watch& w) noexcept {
    std::lock_guard<std::mutex> lock(mutex_);
    w.linked_ = false;
    if (w.generation_ != generation_) return;  // linked before a fork: the list was reset
    if (w.prev_)
        w.prev_->next_ = w.next_;
    else
        head_ = w.next_;
    if (w.next_) w.next_->prev_ = w.prev_;
    w.prev_ = w.next_ = nullptr;
}

void Watchdog::run() {
    const auto period = std::chrono::milliseconds(limits::WATCHDOG_PERIOD_MS);
    std::unique_lock<std::mutex> lock(mutex_);
    for (;;) {
        // nothing watched: asleep until a watch comes (no wake-ups when idle)
        wake_.wait(lock, [this] { return head_ != nullptr; });
        // (an early wake-up only scans early)
        wake_.wait_for(lock, period);
        i64 now = platform::monotonic_ns();
        for (Watch* w = head_; w; w = w->next_) {
            if (w->fired_ || now <= w->deadline_ns_) continue;
            // past its deadline: the budget's next check_stack() / poll() throws
            // Timeout. The owner's ~Watch waits for this lock: the budget is alive.
            w->fired_ = true;
            w->budget_->expire();
        }
    }
}

void Watchdog::after_fork_child() noexcept {
    // only the forking thread exists here: no lock (it may be held forever)
    Watchdog& wd = instance();
    new (&wd.mutex_) std::mutex();
    new (&wd.wake_) std::condition_variable();
    wd.head_ = nullptr;
    wd.generation_++;  // the parent's watches: their destructors unlink nothing
    wd.started_ = false;
}

}  // namespace pan
