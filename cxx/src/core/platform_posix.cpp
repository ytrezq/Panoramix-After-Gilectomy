// The POSIX side of platform.hpp (Linux: huge pages, cgroups, affinity, the
// default thread attributes of glibc / musl). The only place of the core
// that calls the system's own interfaces (AGENTS.md rule 3).
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>

#include <cstdlib>
#include <mutex>

#include "core/platform.hpp"

#include "core/budget.hpp"
#include "core/sync.hpp"

namespace pan::platform {

namespace {

// every signal but the synchronous ones (the faults of the thread itself
// must still reach it)
void async_signals(sigset_t* set) {
    sigfillset(set);
    for (int s : {SIGSEGV, SIGBUS, SIGFPE, SIGILL, SIGTRAP, SIGABRT, SIGSYS}) sigdelset(set, s);
}

}  // namespace

// the lock of the creations (below); a fork waits for a creation to end
// (prepare), and the child starts with it free
namespace {
SpinLock spawn_lock;
[[maybe_unused]] const int spawn_lock_at_fork = [] {
    pthread_atfork([] { spawn_lock.lock(); }, [] { spawn_lock.unlock(); }, [] { spawn_lock.reset(); });
    return 0;
}();
}  // namespace

std::thread spawn(std::function<void()> fn, usize stack_size) {
    // std::thread takes the process's default attributes: the stack's size
    // set there for the length of the creation (a lock: two creations at
    // once would put back each other's), and the signals the new thread
    // inherits from this one blocked meanwhile
    std::lock_guard<SpinLock> g(spawn_lock);
    pthread_attr_t old;
    bool have_old = pthread_getattr_default_np(&old) == 0;
    bool set = false;
    if (have_old) {
        pthread_attr_t a;
        if (pthread_getattr_default_np(&a) == 0) {
            set = pthread_attr_setstacksize(&a, stack_size) == 0 && pthread_setattr_default_np(&a) == 0;
            pthread_attr_destroy(&a);
        }
    }
    sigset_t async, prev;
    async_signals(&async);
    pthread_sigmask(SIG_BLOCK, &async, &prev);
    auto restore = [&] {
        pthread_sigmask(SIG_SETMASK, &prev, nullptr);
        if (set) pthread_setattr_default_np(&old);
        if (have_old) pthread_attr_destroy(&old);
    };
    std::thread t;
    try {
        t = std::thread(std::move(fn));
    } catch (...) {
        restore();
        throw;
    }
    restore();
    return t;
}

bool thread_stack(std::uintptr_t* low, usize* size) {
    pthread_attr_t a;
    if (pthread_getattr_np(pthread_self(), &a)) return false;
    void* addr;
    usize sz;
    int r = pthread_attr_getstack(&a, &addr, &sz);
    pthread_attr_destroy(&a);
    if (r) return false;
    *low = reinterpret_cast<std::uintptr_t>(addr);
    *size = sz;
    return true;
}

i64 monotonic_ns() {
    timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return i64(t.tv_sec) * 1000000000 + t.tv_nsec;
}

usize physical_memory() {
    long pages = sysconf(_SC_PHYS_PAGES), psz = sysconf(_SC_PAGESIZE);
    usize mem = pages > 0 && psz > 0 ? usize(pages) * usize(psz) : 0;
    // cgroup v2: memory.max, "max" or a number of bytes
    int fd = open("/sys/fs/cgroup/memory.max", O_RDONLY | O_CLOEXEC);
    if (fd >= 0) {
        char buf[64];
        ssize_t n = read(fd, buf, sizeof buf - 1);
        close(fd);
        if (n > 0 && buf[0] >= '0' && buf[0] <= '9') {
            buf[n] = 0;
            u64 v = env::parse_u64(buf);  // a Ragel machine (core/env.rl)
            if (v && (mem == 0 || v < mem)) mem = usize(v);
        }
    }
    return mem;
}

usize peak_rss() {
    rusage ru;
    if (getrusage(RUSAGE_SELF, &ru) != 0 || ru.ru_maxrss <= 0) return 0;
#ifdef __APPLE__
    return usize(ru.ru_maxrss);  // bytes there
#else
    return usize(ru.ru_maxrss) * 1024;  // KiB on Linux and the BSDs
#endif
}

unsigned cpu_count() {
#ifdef __linux__
    cpu_set_t cpus;
    CPU_ZERO(&cpus);
    if (sched_getaffinity(0, sizeof cpus, &cpus) == 0) {
        int n = CPU_COUNT(&cpus);
        if (n > 0) return unsigned(n);
    }
#endif
    unsigned n = std::thread::hardware_concurrency();
    return n ? n : 1;
}

void* map_huge(usize size) {
    void* m = mmap(nullptr, size + HUGE_PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (m == MAP_FAILED) return nullptr;
    auto base = reinterpret_cast<std::uintptr_t>(m);
    std::uintptr_t al = (base + HUGE_PAGE - 1) & ~(std::uintptr_t(HUGE_PAGE) - 1);
    if (al > base) munmap(m, al - base);  // the head
    std::uintptr_t tail = base + size + HUGE_PAGE - (al + size);
    if (tail) munmap(reinterpret_cast<void*>(al + size), tail);
#ifdef MADV_HUGEPAGE
    madvise(reinterpret_cast<void*>(al), size, MADV_HUGEPAGE);  // (a hint)
#endif
    return reinterpret_cast<void*>(al);
}

void* map_pages(usize size) {
    void* m = mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    return m == MAP_FAILED ? nullptr : m;
}

void unmap(void* p, usize size) { munmap(p, size); }

const char* env(const char* name) { return std::getenv(name); }

bool is_tty(int fd) { return isatty(fd) == 1; }

void block_async_signals() {
    sigset_t async;
    async_signals(&async);
    pthread_sigmask(SIG_BLOCK, &async, nullptr);
}

void at_fork(void (*prepare)(), void (*parent)(), void (*child)()) { pthread_atfork(prepare, parent, child); }

}  // namespace pan::platform
