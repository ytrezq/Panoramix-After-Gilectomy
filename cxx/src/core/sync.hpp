// A spinlock for the shared tables held a few instructions at a time (the
// chunk pool's, the log's): a fork's child resets it, where a std::mutex
// held by a thread that isn't in the child would stay held.
#pragma once

#include <atomic>

namespace pan {

class SpinLock {
public:
    void lock() {
        while (f_.exchange(true, std::memory_order_acquire))
            while (f_.load(std::memory_order_relaxed)) relax();
    }
    bool try_lock() { return !f_.exchange(true, std::memory_order_acquire); }
    void unlock() { f_.store(false, std::memory_order_release); }
    void reset() { f_.store(false, std::memory_order_relaxed); }

private:
    static void relax() {
#if defined(__x86_64__) || defined(__i386__)
        __builtin_ia32_pause();
#elif defined(__aarch64__)
        asm volatile("yield");
#endif
    }
    std::atomic<bool> f_{false};
};

}  // namespace pan
