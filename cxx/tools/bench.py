#!/usr/bin/env python3
"""The CPU time and the memory of decompiling a corpus: the asm, the C++
build and its PGO build, side by side.

    tools/bench.py [INPUT...] [--asm PATH] [--asm-sigdb PATH] [--cxx PATH]
                   [--pgo PATH] [--sigdb PATH] [--bin LABEL=PATH[:SIGDB]]...
                   [--runs R] [-j N] [--threads T] [--limit N]
                   [--kill-after S] [--json FILE]

INPUT as tools/corpus.py's (by default its 1121 contracts). Every contract
is decompiled by every binary (`decompile FILE --no-color -j T`, T = 1 by
default: one thread's work), the binaries taking turns contract by contract
and in a rotating order (the machine's drifts shared between them), R times
(1 by default), N contracts at a time (1 by default: -j 2 makes two
contracts compete for the 2 CPUs of the machine). Like tools/corpus.py:
PANORAMIX_TIMEOUT=0, and a run longer than --kill-after S is killed.

The binaries: --asm (/home/claude/wt-cxx/build/panasm, with
PANORAMIX_SIGDB=--asm-sigdb, the asm's database), --cxx (cxx/$B/pancxx) and
--pgo (cxx/$B/pgo/pancxx), both with --sigdb (cxx/$B/sigdb2.bin), and any
--bin LABEL=PATH[:SIGDB]; a missing one is left out; `--asm ''` leaves the
asm out. The table, per binary: the contracts ok and not ok (failed,
crashed or timed out in a run), the CPU time (user + system) in total and
per contract (median, p90, p99, max: the mean of the runs), the peak RSS
(the max over the contracts) and its median, and the ratios of the total
and the median to the first binary's; then, for each other binary, the
contracts that lost the most time against the first.
"""
import argparse
import concurrent.futures
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import corpus  # noqa: E402

REPO = os.path.dirname(corpus.CXX_DIR)
BUILD = os.path.join(corpus.CXX_DIR, os.environ.get("B", "build"))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("inputs", nargs="*", help="lists of .hex paths, directories, .hex files")
    ap.add_argument("--asm", default=os.path.join(REPO, "build", "panasm"))
    ap.add_argument("--asm-sigdb", default=os.path.join(REPO, "build", "abi_db.bin"))
    ap.add_argument("--cxx", default=os.path.join(BUILD, "pancxx"))
    ap.add_argument("--pgo", default=os.path.join(BUILD, "pgo", "pancxx"))
    ap.add_argument("--sigdb", default=os.path.join(BUILD, "sigdb2.bin"))
    ap.add_argument("--bin", action="append", default=[], metavar="LABEL=PATH[:SIGDB]")
    ap.add_argument("--runs", type=int, default=1)
    ap.add_argument("-j", "--jobs", type=int, default=1, help="contracts at a time (1)")
    ap.add_argument("--threads", type=int, default=1, help="the decompiler's -j (1)")
    ap.add_argument("--limit", type=int, help="only the first N contracts")
    ap.add_argument("--kill-after", type=float, default=600.0, metavar="S")
    ap.add_argument("--worst", type=int, default=3, help="the contracts listed per binary (3)")
    ap.add_argument("--json", metavar="FILE", help="every measure")
    a = ap.parse_args()

    files = corpus.read_inputs(a.inputs or [corpus.DEFAULT_LIST])
    if a.limit:
        files = files[:a.limit]
    if not files:
        sys.exit("bench.py: no contracts")
    names = corpus.unique_names(files)

    bins = []  # (label, path, sigdb)
    for label, path, sigdb in (("asm", a.asm, a.asm_sigdb), ("cxx", a.cxx, a.sigdb), ("pgo", a.pgo, a.sigdb)):
        if path:
            bins.append((label, path, sigdb))
    for spec in a.bin:
        label, _, rest = spec.partition("=")
        path, _, sigdb = rest.partition(":")
        bins.append((label, path, sigdb or None))
    present = []
    for label, path, sigdb in bins:
        if not os.access(path, os.X_OK):
            print("bench.py: no %s binary (%s): left out" % (label, path), file=sys.stderr)
        else:
            if sigdb and not os.path.exists(sigdb):
                print("bench.py: warning: no signature database %s for %s" % (sigdb, label), file=sys.stderr)
            present.append((label, path, corpus.environment(sigdb)))
    if not present:
        sys.exit("bench.py: no binary to measure")
    labels = [b[0] for b in present]
    args = ["-j", str(a.threads)]

    # res[label][i] = [Result per run]
    res = {lb: [[] for _ in files] for lb in labels}

    def contract(r, i):
        k = (i + r) % len(present)
        out = []
        for label, path, env in present[k:] + present[:k]:
            out.append((label, corpus.run_one(path, files[i], names[i], args, env, a.kill_after)))
        return i, out

    for r in range(a.runs):
        with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, a.jobs)) as pool:
            for fut in concurrent.futures.as_completed([pool.submit(contract, r, i) for i in range(len(files))]):
                i, out = fut.result()
                for label, result in out:
                    res[label][i].append(result)
        print("run %d/%d done" % (r + 1, a.runs), file=sys.stderr)

    def mean_cpu(label, i):
        rs = res[label][i]
        return sum(x.cpu for x in rs) / len(rs)

    print("%d contracts, %d run(s), %d at a time, decompile -j %d, PANORAMIX_TIMEOUT=0"
          % (len(files), a.runs, a.jobs, a.threads))
    head = ("%-6s %5s %6s %11s %10s %10s %10s %10s %9s %9s %8s %8s"
            % ("", "ok", "not ok", "total CPU", "median", "p90", "p99", "max", "peak RSS", "med RSS",
               "total", "median"))
    print(head)
    print("%-6s %5s %6s %11s %10s %10s %10s %10s %9s %9s %8s %8s"
          % ("", "", "", "(s)", "(ms)", "(ms)", "(ms)", "(ms)", "(MiB)", "(MiB)",
             "vs " + labels[0], "vs " + labels[0]))
    base = None
    for label in labels:
        cpu = sorted(mean_cpu(label, i) for i in range(len(files)))
        total = sum(cpu)
        med = corpus.percentile(cpu, 50)
        bad = sum(1 for rs in res[label] if any(x.status != "ok" for x in rs))
        rss = [max(x.rss_kib for x in rs) for rs in res[label]]
        if base is None:
            base = (total, med)
        ratio = lambda x, y: ("%8.3f" % (x / y)) if y else "%8s" % "-"
        print("%-6s %5d %6d %11.2f %10.1f %10.1f %10.1f %10.1f %9d %9d %s %s"
              % (label, len(files) - bad, bad, total, 1e3 * med, 1e3 * corpus.percentile(cpu, 90),
                 1e3 * corpus.percentile(cpu, 99), 1e3 * cpu[-1], max(rss) >> 10,
                 corpus.percentile(sorted(rss), 50) >> 10, ratio(total, base[0]), ratio(med, base[1])))
        if a.runs > 1:
            totals = [sum(res[label][i][r].cpu for i in range(len(files))) for r in range(a.runs)]
            m = sum(totals) / len(totals)
            sd = math.sqrt(sum((t - m) ** 2 for t in totals) / (len(totals) - 1))
            print("%-6s %26s +- %.2f s between runs (best %.2f, worst %.2f)" % ("", "", sd, min(totals), max(totals)))
    for label in labels[1:]:
        d = sorted(range(len(files)), key=lambda i: mean_cpu(labels[0], i) - mean_cpu(label, i))
        if a.worst:
            print("%s against %s, the most time lost:" % (label, labels[0]))
            for i in d[:a.worst]:
                print("  %9.1f -> %9.1f ms  %s" % (1e3 * mean_cpu(labels[0], i), 1e3 * mean_cpu(label, i), names[i]))
    for label in labels:
        bad = [(names[i], x) for i, rs in enumerate(res[label]) for x in rs[:1] if x.status != "ok"]
        if bad:
            print("%s not ok: %s" % (label, ", ".join("%s (%s)" % (n, corpus.fmt_status(x)) for n, x in bad[:10])
                                     + (" and %d more" % (len(bad) - 10) if len(bad) > 10 else "")))
    if a.json:
        with open(a.json, "w") as fh:
            json.dump({"runs": a.runs, "jobs": a.jobs, "threads": a.threads,
                       "bins": {lb: p for lb, p, _ in present},
                       "results": {lb: {names[i]: [r.__dict__ for r in res[lb][i]] for i in range(len(files))}
                                   for lb in labels}}, fh)


if __name__ == "__main__":
    main()
