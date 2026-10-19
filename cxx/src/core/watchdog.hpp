// The watchdog: python's time limit of a function (3 minutes, a SIGALRM that
// interrupts it wherever it is). The stages check their own limits between
// their rounds, as python's do; a single pass can take longer than all of
// them, and python's alarm cuts it: here one thread wakes every
// limits::WATCHDOG_PERIOD_MS (50 ms) while something is watched and, for a
// watch past its deadline, calls its budget's expire() - the next
// check_stack() / poll() of that budget throws Timeout (an Abort, which the
// `catch (const Error&)` of the stages let through).
//
// Use: `Watchdog::Watch w(budget, deadline_ns);` for the length of the work.
// The Budget must outlive the Watch (construct the budget first).
#pragma once

#include <condition_variable>
#include <mutex>

#include "core/base.hpp"

namespace pan {

class Budget;

class Watchdog {
public:
    // the process's one watchdog (never destroyed: its thread may run until
    // the process exits)
    static Watchdog& instance();

    // RAII: `budget` is watched from the constructor to the destructor. Past
    // deadline_ns (platform::monotonic_ns()'s clock, absolute), the watchdog
    // calls budget.expire(), once. deadline_ns <= 0: no deadline, nothing is
    // watched. The first watch starts the thread: the constructor throws
    // std::system_error when the thread can't be started (nothing watched).
    class Watch {
    public:
        Watch(Budget& budget, i64 deadline_ns);
        ~Watch();
        Watch(const Watch&) = delete;
        Watch& operator=(const Watch&) = delete;

    private:
        friend class Watchdog;
        Budget* budget_;
        i64 deadline_ns_;
        Watch* prev_ = nullptr;  // the watchdog's list (its lock)
        Watch* next_ = nullptr;
        u64 generation_ = 0;     // the watchdog's generation when linked
        bool linked_ = false;    // (the owner's thread only)
        bool fired_ = false;     // expire() called (the watchdog's lock)
    };

    // for the child of a fork() (the watchdog's thread is gone, its lock may
    // have been held by another thread): everything anew, the watches of the
    // parent forgotten; the next Watch starts a thread again. The platform's
    // fork handler calls it (POSIX stays in *_posix.cpp, AGENTS.md rule 3).
    static void after_fork_child() noexcept;

    Watchdog(const Watchdog&) = delete;
    Watchdog& operator=(const Watchdog&) = delete;

private:
    Watchdog() = default;
    ~Watchdog() = default;

    void add(Watch& w);
    void remove(Watch& w) noexcept;
    void run();

    std::mutex mutex_;
    std::condition_variable wake_;  // the list became non-empty
    Watch* head_ = nullptr;
    u64 generation_ = 0;            // + 1 at every fork child
    bool started_ = false;
};

}  // namespace pan
