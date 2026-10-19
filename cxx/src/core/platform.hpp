// What the operating system gives, behind one header: the threads (their
// stacks, their signals), the clock, the machine's memory and CPUs, memory
// mappings, the environment. platform_posix.cpp is the implementation for
// Linux (and the other POSIX systems); a MinGW port puts a platform_win32.cpp
// beside it. Nothing else in the program calls the system's own interfaces
// for these (AGENTS.md rule 3). Integers only (rule 4).
#pragma once

#include <cstdint>
#include <functional>
#include <thread>

#include "core/base.hpp"

namespace pan::platform {

// the alignment and size granule of map_huge
inline constexpr usize HUGE_PAGE = usize(2) << 20;

// a std::thread running fn with a stack of stack_size bytes and the
// asynchronous signals blocked (a signal of the host program's mustn't run
// its handler in the middle of our work, nor cut our system calls short).
// The size goes through the process's default thread attributes, set for the
// length of the std::thread constructor under a lock and put back after; a
// size the system refuses (below its minimum) leaves the default stack.
std::thread spawn(std::function<void()> fn, usize stack_size);

// the calling thread's stack: its lowest address and its size; false when
// the system can't tell
bool thread_stack(std::uintptr_t* low, usize* size);

// CLOCK_MONOTONIC, in nanoseconds
i64 monotonic_ns();

// the machine's memory, or its cgroup's limit (v2 memory.max) when lower
usize physical_memory();
// the process's peak resident set size, in bytes; 0 when unknown
usize peak_rss();
// the CPUs this process may run on (its affinity), else
// std::thread::hardware_concurrency(); at least 1
unsigned cpu_count();

// a fresh mapping of `size` bytes (a multiple of HUGE_PAGE), aligned on
// HUGE_PAGE and advised to be backed by huge pages; nullptr when there's none
void* map_huge(usize size);
// a fresh mapping (zeroed); nullptr when there's none
void* map_pages(usize size);
// gives back a mapping of map_huge or map_pages, with its size
void unmap(void* p, usize size);

// an environment variable, or nullptr
const char* env(const char* name);
// is the file descriptor a terminal?
bool is_tty(int fd);

// blocks the asynchronous signals in the calling thread: every signal but the
// synchronous ones (SIGSEGV, SIGBUS, SIGFPE, SIGILL, SIGTRAP, SIGABRT,
// SIGSYS), so that a library thread never runs the host program's handlers.
// spawn's threads start that way.
void block_async_signals();

// fork handlers (pthread_atfork): prepare runs in the parent before a fork,
// parent after it, child in the new process (any may be null)
void at_fork(void (*prepare)(), void (*parent)(), void (*child)());

}  // namespace pan::platform
