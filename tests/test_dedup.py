#!/usr/bin/env python3
"""The deduplication modes against each other ($PANORAMIX_DEDUP, see
src/ksm.s): every contract of the corpora decompiled in each mode, the
texts compared with eager's (the hash-consing: the reference).

    tests/test_dedup.py [--compact] [-j N] [--modes a,b,...] [DIR...]

DIRs default to tests/corpus and tests/synthetic. -j defaults to twice
the processors plus one: more threads than cores, the merging thread
included, so that the races have the chance to happen on one core too.
--compact compacts the arena at every round of the simplification
(PANORAMIX_COMPACT_MIB=1: the merging thread kept away, its queue
dropped). The CPU time of each mode is summed."""
import glob, os, subprocess, sys

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(here)
args = sys.argv[1:]
compact = "--compact" in args
jobs = str(2 * (os.cpu_count() or 1) + 1)
modes = ["eager", "lazy", "ksm", "sync", "defer"]
dirs = []
i = 0
while i < len(args):
    a = args[i]
    if a == "-j":
        jobs = args[i + 1]; i += 1
    elif a == "--modes":
        modes = args[i + 1].split(","); i += 1
    elif a != "--compact":
        dirs.append(a)
    i += 1
dirs = dirs or [os.path.join(here, "corpus"), os.path.join(here, "synthetic")]
panasm = os.path.join(root, "build", "panasm")
db = os.path.join(root, "build", "abi_db.bin")
cpu = {m: 0.0 for m in modes}
n = 0
bad = []
for d in dirs:
    for f in sorted(glob.glob(os.path.join(d, "*.hex"))):
        n += 1
        outs = {}
        for m in modes:
            env = dict(os.environ, PANORAMIX_DEDUP=m, PANORAMIX_LOG="error")
            if os.path.exists(db):
                env["PANORAMIX_SIGDB"] = db
            if compact:
                env["PANORAMIX_COMPACT_MIB"] = "1"
            p = subprocess.Popen([panasm, "decompile", f, "--no-color", "-j", jobs],
                                 stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env=env)
            out = p.stdout.read()
            _, st, ru = os.wait4(p.pid, 0)
            cpu[m] += ru.ru_utime + ru.ru_stime
            outs[m] = (st, out)
        for m in modes[1:]:
            if outs[m] != outs[modes[0]]:
                bad.append("%s (%s)" % (os.path.basename(f)[:-4], m))
                print("DIFF", bad[-1], flush=True)
print("CPU: " + ", ".join("%s %.1fs" % (m, cpu[m]) for m in modes))
print("%d contracts, -j %s, %d differences" % (n, jobs, len(bad)))
sys.exit(1 if bad or n == 0 else 0)
