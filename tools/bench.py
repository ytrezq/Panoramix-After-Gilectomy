#!/usr/bin/env python3
"""The CPU time of decompiling a corpus, for one binary or to compare several.

    tools/bench.py DIR[:DIR...] BIN [BIN...] [-j N] [--runs R] [--json OUT]
                   [--env NAME=VALUE]...

Every DIR/*.hex (the whole corpus: several directories, separated by
colons) is decompiled by every BIN (`decompile FILE --no-color -j N`, N 1
by default), the binaries taking turns file by file and in turns of order
(the machine's drifts shared between them), R times (1 by default). For
each binary: the mean of the runs' totals of user + system time, their
standard deviation, the best and the worst run, the user and system
means, the mean of the runs' elapsed times (what threads, -j, shorten),
the largest peak RSS; with two binaries, the ratio of the means and the
contracts whose mean times differ the most. --json: every time measured,
by binary, contract and run (for a later comparison).
"""
import glob, json, math, os, subprocess, sys, time

args = sys.argv[1:]
threads, runs, out, env_extra = "1", 1, None, {}
if "-j" in args:
    i = args.index("-j"); threads = args[i + 1]; del args[i:i + 2]
if "--runs" in args:
    i = args.index("--runs"); runs = int(args[i + 1]); del args[i:i + 2]
if "--json" in args:
    i = args.index("--json"); out = args[i + 1]; del args[i:i + 2]
while "--env" in args:
    i = args.index("--env")
    k, _, v = args[i + 1].partition("=")
    env_extra[k] = v
    del args[i:i + 2]
if len(args) < 2:
    sys.exit(__doc__)
dirs, bins = args[0].split(":"), args[1:]
files = sorted(f for d in dirs for f in glob.glob(os.path.join(d, "*.hex")))
if not files:
    sys.exit("no .hex in " + args[0])
env = dict(os.environ, PANORAMIX_LOG="error", **env_extra)
# times[b][f] = [(user, sys, maxrss_kib, elapsed), ...] one per run
times = {b: {f: [] for f in files} for b in bins}
for r in range(runs):
    for i, f in enumerate(files):
        for b in (bins if (i + r) % 2 == 0 else bins[::-1]):
            t0 = time.monotonic()
            p = subprocess.Popen([b, "decompile", f, "--no-color", "-j", threads],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env)
            _, _, ru = os.wait4(p.pid, 0)
            times[b][f].append((ru.ru_utime, ru.ru_stime, ru.ru_maxrss, time.monotonic() - t0))


def mean(xs):
    return sum(xs) / len(xs)


def stdev(xs):
    m = mean(xs)
    return math.sqrt(sum((x - m) ** 2 for x in xs) / (len(xs) - 1)) if len(xs) > 1 else 0.0


print(f"{len(files)} contracts, {runs} run(s), -j {threads}")
means = {}
for b in bins:
    totals = [sum(sum(times[b][f][r][:2]) for f in files) for r in range(runs)]
    users = [sum(times[b][f][r][0] for f in files) for r in range(runs)]
    syss = [sum(times[b][f][r][1] for f in files) for r in range(runs)]
    walls = [sum(times[b][f][r][3] for f in files) for r in range(runs)]
    rss = max(t[2] for f in files for t in times[b][f])
    means[b] = mean(totals)
    print("%8.2f s  +- %5.2f (best %.2f, worst %.2f; user %.2f, sys %.2f; elapsed %.2f; peak RSS %d MiB)  %s"
          % (mean(totals), stdev(totals), min(totals), max(totals), mean(users), mean(syss), mean(walls),
             rss >> 10, b))
if len(bins) > 1:
    b0, b1 = bins[0], bins[1]
    print("ratio of the means: %.4f (%+.2f%%)" % (means[b1] / means[b0], 100 * (means[b1] / means[b0] - 1)))
    m = {b: {f: mean([sum(t[:2]) for t in times[b][f]]) for f in files} for b in (b0, b1)}
    d = sorted(files, key=lambda f: m[b1][f] - m[b0][f])
    for f in d[:3] + [f for f in d[-3:] if f not in d[:3]]:
        print("   %7.3f -> %7.3f  %s" % (m[b0][f], m[b1][f], os.path.basename(f)))
if out:
    with open(out, "w") as fh:
        json.dump({"threads": threads, "runs": runs, "env": env_extra,
                   "times": {b: {f: times[b][f] for f in files} for b in bins}}, fh)
