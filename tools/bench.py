#!/usr/bin/env python3
"""The CPU time of decompiling a corpus, for one binary or to compare several.

    tools/bench.py DIR BIN [BIN...] [-j N] [--runs R]

Every DIR/*.hex is decompiled by every BIN (`decompile FILE --no-color
-j N`, N 1 by default), the binaries taking turns file by file (the
machine's drifts shared between them), R times (1 by default); prints each
binary's total of user + system time (the best of the runs) and the
contracts whose times differ the most between the first two.
"""
import glob, os, subprocess, sys

args = sys.argv[1:]
threads, runs = "1", 1
if "-j" in args:
    i = args.index("-j"); threads = args[i + 1]; del args[i:i + 2]
if "--runs" in args:
    i = args.index("--runs"); runs = int(args[i + 1]); del args[i:i + 2]
if len(args) < 2:
    sys.exit(__doc__)
corpus, bins = args[0], args[1:]
files = sorted(glob.glob(os.path.join(corpus, "*.hex")))
env = dict(os.environ, PANORAMIX_LOG="error")
best = {}
for r in range(runs):
    for i, f in enumerate(files):
        for b in (bins if (i + r) % 2 == 0 else bins[::-1]):
            p = subprocess.Popen([b, "decompile", f, "--no-color", "-j", threads],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env)
            _, _, ru = os.wait4(p.pid, 0)
            t = ru.ru_utime + ru.ru_stime
            best[b, f] = min(best.get((b, f), t), t)
for b in bins:
    print("%8.2f s  %s" % (sum(best[b, f] for f in files), b))
if len(bins) > 1:
    d = sorted(files, key=lambda f: best[bins[1], f] - best[bins[0], f])
    for f in d[:3] + [f for f in d[-3:] if f not in d[:3]]:
        print("   %7.3f -> %7.3f  %s" % (best[bins[0], f], best[bins[1], f], os.path.basename(f)))
