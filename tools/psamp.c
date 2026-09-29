// psamp: a sampling profiler on perf_event_open's software CPU clock, for
// machines without perf (or without hardware counters, as in a VM).
//
//     cc -O2 -o build/psamp tools/psamp.c      (make build/psamp)
//     build/psamp OUT PERIOD_NS cmd args...
//     tools/psym.py OUT ...                    (the report)
//
// Runs the command and samples every thread of it every PERIOD_NS
// nanoseconds of its CPU time (250000: 4000 samples a second): the
// instruction pointer, the two words at the top of the stack (a leaf
// function's return address, when it pushed nothing) and the return
// addresses of the frames (the rbp chain: the assembly's functions keep
// one, ENTER). OUT gets a line per sample - "S tid ip w0 w1 ret..." in
// hex - and the command's last /proc/PID/maps ("M ..." lines). The
// counts are of CPU time, cache misses included, where callgrind counts
// instructions.
#define _GNU_SOURCE
#include <linux/perf_event.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#define NPAGES 128              // data pages of a ring buffer (a power of 2)
#define MAXCPU 256

static long pagesz;
static int ncpu;
static int fds[MAXCPU];
static void *rings[MAXCPU];
static FILE *out;
static long nsamples, nlost;
static char maps[1 << 20];
static size_t maps_len;

static void read_maps(pid_t pid) {
    char path[64];
    snprintf(path, sizeof path, "/proc/%d/maps", pid);
    FILE *m = fopen(path, "r");
    if (!m) return;
    size_t n = fread(maps, 1, sizeof maps - 1, m);
    fclose(m);
    if (n > 0) maps_len = n;
}

// the records of one CPU's ring buffer
static void drain(int c) {
    struct perf_event_mmap_page *meta = rings[c];
    char *data = (char *)rings[c] + pagesz;
    uint64_t size = (uint64_t)NPAGES * pagesz;
    uint64_t head = __atomic_load_n(&meta->data_head, __ATOMIC_ACQUIRE);
    uint64_t tail = meta->data_tail;
    static char buf[65536];
    while (tail < head) {
        struct perf_event_header h;
        uint64_t off = tail % size;
        // (a record may wrap around the end of the buffer)
        for (size_t i = 0; i < sizeof h; i++) ((char *)&h)[i] = data[(off + i) % size];
        if (h.size == 0) break;
        for (size_t i = 0; i < h.size; i++) buf[i] = data[(off + i) % size];
        if (h.type == PERF_RECORD_SAMPLE) {
            // ip, pid/tid, the callchain (nr, ips), the user stack (size,
            // data, dyn_size): the order of PERF_SAMPLE_* bits
            uint64_t ip = *(uint64_t *)(buf + 8);
            uint32_t tid = *(uint32_t *)(buf + 20);
            uint64_t nr = *(uint64_t *)(buf + 24);
            uint64_t *chain = (uint64_t *)(buf + 32);
            char *p = buf + 32 + nr * 8;
            uint64_t ssz = *(uint64_t *)p;
            uint64_t w0 = 0, w1 = 0;
            if (ssz >= 16) {
                uint64_t dyn = *(uint64_t *)(p + 8 + ssz);
                if (dyn >= 8) w0 = *(uint64_t *)(p + 8);
                if (dyn >= 16) w1 = *(uint64_t *)(p + 16);
            }
            fprintf(out, "S %u %llx %llx %llx", tid, (unsigned long long)ip,
                    (unsigned long long)w0, (unsigned long long)w1);
            int first = 1;              // (the markers, and the ip itself, left out)
            for (uint64_t k = 0; k < nr; k++) {
                if (chain[k] >= (uint64_t)-4095) continue;
                if (first && chain[k] == ip) { first = 0; continue; }
                first = 0;
                fprintf(out, " %llx", (unsigned long long)chain[k]);
            }
            fputc('\n', out);
            nsamples++;
        } else if (h.type == PERF_RECORD_LOST) {
            nlost += *(uint64_t *)(buf + 16);
        }
        tail += h.size;
    }
    __atomic_store_n(&meta->data_tail, tail, __ATOMIC_RELEASE);
}

int main(int argc, char **argv) {
    if (argc < 4) {
        fprintf(stderr, "usage: psamp OUT PERIOD_NS cmd args...\n");
        return 2;
    }
    out = fopen(argv[1], "w");
    if (!out) { perror(argv[1]); return 1; }
    long period = atol(argv[2]);
    pagesz = sysconf(_SC_PAGESIZE);
    ncpu = sysconf(_SC_NPROCESSORS_CONF);
    if (ncpu > MAXCPU) ncpu = MAXCPU;
    int pipefd[2];
    if (pipe(pipefd)) return 1;
    pid_t child = fork();
    if (child == 0) {
        char ch;
        close(pipefd[1]);
        if (read(pipefd[0], &ch, 1) != 1) _exit(1);  // the events first
        execvp(argv[3], argv + 3);
        _exit(127);
    }
    close(pipefd[0]);
    // an event per CPU for the child and the threads it makes (inherit),
    // enabled at its exec
    struct pollfd pfd[MAXCPU];
    for (int c = 0; c < ncpu; c++) {
        struct perf_event_attr a;
        memset(&a, 0, sizeof a);
        a.size = sizeof a;
        a.type = PERF_TYPE_SOFTWARE;
        a.config = PERF_COUNT_SW_CPU_CLOCK;
        a.sample_period = period;
        a.sample_type = PERF_SAMPLE_IP | PERF_SAMPLE_TID | PERF_SAMPLE_CALLCHAIN |
                        PERF_SAMPLE_STACK_USER;
        a.sample_stack_user = 16;
        a.exclude_callchain_kernel = 1;
        a.disabled = 1;
        a.enable_on_exec = 1;
        a.inherit = 1;
        a.exclude_kernel = 1;
        a.exclude_hv = 1;
        a.wakeup_events = 64;
        fds[c] = syscall(SYS_perf_event_open, &a, child, c, -1, PERF_FLAG_FD_CLOEXEC);
        if (fds[c] < 0) { perror("perf_event_open"); kill(child, SIGKILL); return 1; }
        rings[c] = mmap(NULL, (NPAGES + 1) * pagesz, PROT_READ | PROT_WRITE, MAP_SHARED, fds[c], 0);
        if (rings[c] == MAP_FAILED) { perror("mmap"); kill(child, SIGKILL); return 1; }
        pfd[c].fd = fds[c];
        pfd[c].events = POLLIN;
    }
    if (write(pipefd[1], "x", 1) != 1) return 1;
    close(pipefd[1]);
    int status = 0, done = 0;
    while (!done) {
        poll(pfd, ncpu, 100);
        for (int c = 0; c < ncpu; c++) drain(c);
        read_maps(child);               // (the last ones before it exits)
        if (waitpid(child, &status, WNOHANG) == child) done = 1;
    }
    for (int c = 0; c < ncpu; c++) drain(c);
    char *p = maps, *e = maps + maps_len;
    while (p < e) {
        char *nl = memchr(p, '\n', e - p);
        if (!nl) nl = e;
        fprintf(out, "M %.*s\n", (int)(nl - p), p);
        p = nl + 1;
    }
    fclose(out);
    fprintf(stderr, "psamp: %ld samples, %ld lost\n", nsamples, nlost);
    return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
}
