// A job's budget: its memory (a counting std::pmr resource, MemoryLimit past
// the limit), its stack (DepthLimit below the thread's low mark) and its
// time (the watchdog's expire(): the mark raised to the top, so the next
// check_stack/poll throws Timeout). The asm's caps, one place (limits), and
// the environment's settings (env.rl: PANORAMIX_TIMEOUT, PANORAMIX_MAX_MEMORY,
// PANORAMIX_COMPACT_MIB), integers only (rule 4).
#pragma once

#include <atomic>
#include <cstdint>
#include <memory_resource>

#include "core/base.hpp"

namespace pan {

namespace limits {  // every cap with the asm's value (algorithms.md §12), one place
inline constexpr u32 MAX_NODE_COUNT = 20000, WIDE_NODE_COUNT = 5000, MAX_FDESTS_NODE_COUNT = 5000;
inline constexpr u32 VM_ROUNDS = 20, VM_ROUND_STEPS = 200, SIMPLIFY_ROUNDS = 40, MAX_EXP_SIZE = 150;
inline constexpr u32 MAX_CODECOPY_SIZE = 1024;
inline constexpr usize MAX_ZEROES_SIZE = usize{64} << 10;
inline constexpr i64 SEC = 1'000'000'000;  // integers only (rule 4: no 60e9 literals)
inline constexpr i64 LOADER_TIMEOUT_NS = 60 * SEC, VM_TIMEOUT_NS = 60 * SEC, WHILES_TIMEOUT_NS = 60 * SEC,
                     FUNC_TIMEOUT_NS = 180 * SEC, POST_TIMEOUT_NS = 180 * SEC;
inline constexpr usize FOLD_LIMIT = usize{1} << 30, MIN_JOB_MEMORY = usize{1} << 30,
                       COMPACT_THRESHOLD = usize{256} << 20;
inline constexpr u32 MAX_THREADS = 1024, WATCHDOG_PERIOD_MS = 50;
inline constexpr usize WORKER_STACK = usize{64} << 20;
inline constexpr usize RT_BYTES_MAX = usize{16} << 20, RT_WORK_MAX = usize{256} << 20, RT_MEMORY = usize{1} << 20;
inline constexpr u32 RT_STEPS = 20000;
// the asm's scaled_ns: no time limit (PANORAMIX_TIMEOUT ≤ 0), and the cap of a scaled one
inline constexpr i64 NO_TIMEOUT_NS = 0x3fff'ffff'ffff'ffff;
inline constexpr i64 MAX_TIMEOUT_NS = 4'000'000'000'000'000'000;
inline constexpr usize STACK_MARGIN = usize{1} << 20;
}  // namespace limits

// the environment (env.rl), read once
namespace env {
struct Settings {
    i64 timeout_milli = 1000;    // PANORAMIX_TIMEOUT in thousandths (unset: 1.0; ≤ 0: no time limits)
    bool max_memory_set = false; // PANORAMIX_MAX_MEMORY present
    usize max_memory = 0;        // its bytes (MiB << 20, saturated); 0: no limit
    usize compact_bytes = 0;     // PANORAMIX_COMPACT_MIB << 20; 0: unset
};
const Settings& settings();
// the machines themselves (tests): strtod's prefix of a decimal factor in
// thousandths (no number: 0; a positive one below 0.001: 1; inf: INT64_MAX;
// nan: 0), and strtoull(s, 0, 10)'s value (a '-' negates, overflow: max)
i64 parse_factor_milli(const char* s) noexcept;
u64 parse_u64(const char* s) noexcept;
}  // namespace env

// a time limit of python's scaled by PANORAMIX_TIMEOUT (asm's scaled_ns):
// base * factor, at most MAX_TIMEOUT_NS; NO_TIMEOUT_NS when the factor is ≤ 0
i64 scaled_timeout(i64 base_ns);
bool timeouts_enabled();
// a job's memory limit (asm's mem_limit_for): PANORAMIX_MAX_MEMORY when set
// (0: none), else the machine's memory (its cgroup's when lower) shared by
// the threads and the main one, MIN_JOB_MEMORY at least
usize job_memory_limit(usize threads);
// when the arena compacts (asm's compact_threshold): PANORAMIX_COMPACT_MIB as
// it is, else COMPACT_THRESHOLD, or a quarter of mem_limit when less
usize compact_threshold(usize mem_limit);

// bytes counted on the way to an upstream resource; MemoryLimit past the
// limit (0: none). One thread at a time (a job's).
class CountingResource : public std::pmr::memory_resource {
public:
    CountingResource(std::pmr::memory_resource* upstream, usize limit) noexcept
        : upstream_(upstream), limit_(limit) {}
    usize used() const noexcept { return used_; }
    usize peak() const noexcept { return peak_; }
    usize limit() const noexcept { return limit_; }
    void set_limit(usize limit) noexcept { limit_ = limit; }
    // bytes taken (> 0: MemoryLimit past the limit, nothing counted) or given back (< 0)
    void charge(isize bytes);

private:
    void* do_allocate(usize bytes, usize align) override;
    void do_deallocate(void* p, usize bytes, usize align) override;
    bool do_is_equal(const std::pmr::memory_resource& o) const noexcept override { return this == &o; }
    void take(usize bytes);

    std::pmr::memory_resource* upstream_;
    usize limit_;
    usize used_ = 0, peak_ = 0;
};

class Budget;
namespace detail {
// what check_stack reads: the low mark (0: none; max: expired)
struct StackGuard {
    std::atomic<uintptr_t> low{0};
    std::atomic<bool> expired{false};
};
inline constinit const StackGuard no_guard{};
inline constinit thread_local const StackGuard* tl_guard = &no_guard;
inline constinit thread_local Budget* tl_budget = nullptr;
[[noreturn, gnu::cold, gnu::noinline]] void stack_exceeded();
}  // namespace detail

class Budget {
public:
    struct Limits {
        usize memory = 0;     // bytes, 0: none
        i64 deadline_ns = 0;  // monotonic, 0: none (the watchdog's)
        usize stack_margin = limits::STACK_MARGIN;
    };
    explicit Budget(Limits l);
    ~Budget();  // detached when it is the calling thread's
    Budget(const Budget&) = delete;
    Budget& operator=(const Budget&) = delete;

    std::pmr::memory_resource* resource() noexcept { return &res_; }  // every per-job container
    CountingResource& counting() noexcept { return res_; }
    const Limits& limits() const noexcept { return limits_; }
    void charge(isize bytes) { res_.charge(bytes); }  // arena chunks, hash tables
    // the calling thread's budget from now on: its stack's low bound (platform)
    // plus the margin is the mark; detach_thread gives the previous one back
    void attach_thread();
    void detach_thread() noexcept;
    void expire() noexcept;  // the watchdog: the mark at the top, expired
    bool expired() const noexcept { return guard_.expired.load(std::memory_order_acquire); }
    // the memory limit lowered to half of what is left under it (asm's
    // phases); returns the old one, for set_limit (0: none, unchanged)
    usize half_budget() noexcept;
    static Budget* current() noexcept { return detail::tl_budget; }

private:
    Limits limits_;
    CountingResource res_;
    detail::StackGuard guard_;
    Budget* prev_ = nullptr;
    bool attached_ = false;
};

// one compare on the hot path: SP vs the thread's budget's mark
// (DepthLimit, or Timeout when expired); at the entry of every recursive function
PAN_ALWAYS_INLINE void check_stack() {
#if __has_builtin(__builtin_stack_address)
    auto sp = reinterpret_cast<uintptr_t>(__builtin_stack_address());
#else
    auto sp = reinterpret_cast<uintptr_t>(__builtin_frame_address(0));
#endif
    if (PAN_UNLIKELY(sp < detail::tl_guard->low.load(std::memory_order_relaxed))) detail::stack_exceeded();
}
// the same check for loops over nodes/rounds
inline void poll() { check_stack(); }

}  // namespace pan
