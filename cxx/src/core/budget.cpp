#include "core/budget.hpp"

#include <limits>
#include <new>

#include "core/errors.hpp"
#include "core/platform.hpp"

namespace pan {

namespace {
constexpr const char* MSG_MEMORY = "out of memory: a function's memory limit was reached (PANORAMIX_MAX_MEMORY)";
constexpr const char* MSG_DEPTH = "maximum recursion depth exceeded";
constexpr const char* MSG_TIMEOUT = "the time limit was reached (PANORAMIX_TIMEOUT)";
constexpr uintptr_t EXPIRED_MARK = std::numeric_limits<uintptr_t>::max();
}  // namespace

// --- CountingResource ---

void CountingResource::take(usize bytes) {
    if (limit_ && (bytes > limit_ || used_ > limit_ - bytes)) throw MemoryLimit(MSG_MEMORY);
    used_ += bytes;
    if (used_ > peak_) peak_ = used_;
}

void CountingResource::charge(isize bytes) {
    if (bytes >= 0) {
        take(static_cast<usize>(bytes));
    } else {
        usize n = static_cast<usize>(-(bytes + 1)) + 1;
        used_ = n > used_ ? 0 : used_ - n;
    }
}

void* CountingResource::do_allocate(usize bytes, usize align) {
    take(bytes);
    try {
        return upstream_->allocate(bytes, align);
    } catch (...) {
        used_ -= bytes;
        throw;
    }
}

void CountingResource::do_deallocate(void* p, usize bytes, usize align) {
    upstream_->deallocate(p, bytes, align);
    used_ = bytes > used_ ? 0 : used_ - bytes;
}

// --- Budget ---

Budget::Budget(Limits l) : limits_(l), res_(std::pmr::new_delete_resource(), l.memory) {}

Budget::~Budget() {
    if (detail::tl_budget == this) detach_thread();
}

void Budget::attach_thread() {
    uintptr_t low = 0;
    usize size = 0;
    uintptr_t mark = 0;
    if (platform::thread_stack(&low, &size) && low) {
        usize margin = limits_.stack_margin;
        if (margin > size / 2) margin = size / 2;  // a small stack: half of it
        mark = low + margin;
    }
    if (!expired()) guard_.low.store(mark, std::memory_order_relaxed);
    if (detail::tl_budget != this) {
        prev_ = detail::tl_budget;
        detail::tl_budget = this;
        detail::tl_guard = &guard_;
    }
    attached_ = true;
}

void Budget::detach_thread() noexcept {
    if (!attached_ || detail::tl_budget != this) return;
    detail::tl_budget = prev_;
    detail::tl_guard = prev_ ? &prev_->guard_ : &detail::no_guard;
    prev_ = nullptr;
    attached_ = false;
}

void Budget::expire() noexcept {
    guard_.expired.store(true, std::memory_order_release);
    guard_.low.store(EXPIRED_MARK, std::memory_order_release);
}

usize Budget::half_budget() noexcept {
    usize old = res_.limit();
    if (!old) return 0;
    usize used = res_.used();
    res_.set_limit(used >= old ? old : used + (old - used) / 2);
    return old;
}

void detail::stack_exceeded() {
    const StackGuard* g = tl_guard;
    if (g->expired.load(std::memory_order_acquire) || g->low.load(std::memory_order_acquire) == EXPIRED_MARK)
        throw Timeout(MSG_TIMEOUT);
    throw DepthLimit(MSG_DEPTH);
}

// --- the environment's limits ---

bool timeouts_enabled() { return env::settings().timeout_milli > 0; }

i64 scaled_timeout(i64 base_ns) {
    i64 milli = env::settings().timeout_milli;
    if (milli <= 0) return limits::NO_TIMEOUT_NS;
    __int128 t = static_cast<__int128>(base_ns) * milli / 1000;
    if (t > limits::MAX_TIMEOUT_NS) return limits::MAX_TIMEOUT_NS;
    if (t < 0) return 0;
    return static_cast<i64>(t);
}

usize job_memory_limit(usize threads) {
    const env::Settings& s = env::settings();
    if (s.max_memory_set) return s.max_memory;
    usize mem = platform::physical_memory();
    usize parts = threads + 1;  // the threads and the main one
    if (!parts) parts = threads;
    usize share = mem / parts;
    return share < limits::MIN_JOB_MEMORY ? limits::MIN_JOB_MEMORY : share;
}

usize compact_threshold(usize mem_limit) {
    const env::Settings& s = env::settings();
    if (s.compact_bytes) return s.compact_bytes;
    usize t = limits::COMPACT_THRESHOLD;
    usize q = mem_limit / 4;
    return q && q < t ? q : t;
}

}  // namespace pan
