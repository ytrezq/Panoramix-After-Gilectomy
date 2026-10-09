#!/usr/bin/env python3
"""The counts of tools/bbfreq (DynamoRIO, natively: the AVX-512 paths) of a
corpus, summed: the executions of every instruction of the binary, per
function (its symbols) and per source line (addr2line: the lines of the
.s files are the instructions).

    tools/bbf_agg.py BINARY DIR [--top N] [--lines FUNC...]
    tools/bbf_agg.py BINARY DIR --contracts FUNC[,FUNC...] [--top N]
    tools/bbf_agg.py BINARY DIR --compare BINARY2 DIR2 [--top N]

DIR holds a directory per contract, with its bbfreq.PID files
(tools/prof_corpus.sh bbfreq). --contracts: the contracts by the share of
their instructions in those functions. --compare: the functions of both
profiles (the same corpus, two builds), the instructions before and after.
"""
import bisect, collections, glob, os, subprocess, sys

args = sys.argv[1:]
if len(args) < 2:
    sys.exit(__doc__)


def opt(name, n=1):
    if name not in args:
        return None
    i = args.index(name)
    v = args[i + 1:i + 1 + n]
    del args[i:i + 1 + n]
    return v if n > 1 else v[0]


top = int(opt("--top") or 60)
contracts = opt("--contracts")
compare = opt("--compare", 2)
lines = None
if "--lines" in args:
    i = args.index("--lines")
    lines, args = set(args[i + 1:]), args[:i]
binary, root = args[0], args[1]


def symbols(binary):
    """the functions' addresses (FUNC's globals and the local labels nm
    lists as text), sorted"""
    syms = []
    out = subprocess.run(["nm", "-n", "--defined-only", binary], capture_output=True, text=True).stdout
    for l in out.splitlines():
        p = l.split()
        if len(p) >= 3 and p[1] in "tT" and not p[2].startswith(".L"):
            syms.append((int(p[0], 16), p[2]))
    return syms


def blocks(path):
    """(start, count, offsets) of a bbfreq file's blocks"""
    with open(path) as fh:
        for line in fh:
            p = line.split()
            if p and p[0] == "B":
                yield int(p[1], 16), int(p[2], 16), [int(o, 16) for o in p[4:]]


def counts_of(root):
    """the executions of each instruction (by offset), over the corpus"""
    counts = collections.Counter()
    nprocs = 0
    for f in glob.glob(os.path.join(root, "*", "bbfreq.*")):
        nprocs += 1
        for start, cnt, offs in blocks(f):
            for o in offs:
                counts[start + o] += cnt
    return counts, nprocs


def by_function(binary, counts):
    syms = symbols(binary)
    addrs = [a for a, _ in syms]

    def func_of(off):
        i = bisect.bisect_right(addrs, off) - 1
        return syms[i][1] if i >= 0 else "?"

    res = collections.Counter()
    for off, c in counts.items():
        res[func_of(off)] += c
    return res, func_of


if contracts:
    want = set(contracts.split(","))
    syms = symbols(binary)
    ranges = [(a, syms[i + 1][0] if i + 1 < len(syms) else a + (1 << 20))
              for i, (a, n) in enumerate(syms) if n in want]
    rows = []
    for d in glob.glob(os.path.join(root, "*")):
        tot = sel = 0
        for f in glob.glob(os.path.join(d, "bbfreq.*")):
            for start, cnt, offs in blocks(f):
                tot += cnt * len(offs)
                if any(a <= start < b for a, b in ranges):
                    sel += cnt * len(offs)
        if tot:
            rows.append((sel, tot, os.path.basename(d)))
    rows.sort(reverse=True)
    T, S = sum(r[1] for r in rows), sum(r[0] for r in rows)
    print("%s: %.2f%% of %d instructions" % (contracts, 100.0 * S / T, T))
    for s, t, n in rows[:top]:
        print("%16d %5.1f%% of %16d  %s" % (s, 100.0 * s / t, t, n))
    sys.exit(0)

counts, nprocs = counts_of(root)
total = sum(counts.values())
funcs, func_of = by_function(binary, counts)
if compare:
    counts2, nprocs2 = counts_of(compare[1])
    funcs2, _ = by_function(compare[0], counts2)
    total2 = sum(counts2.values())
    print(f"{nprocs} / {nprocs2} processes: {total:,} instructions -> {total2:,} "
          f"({100.0 * (total2 / total - 1):+.1f}%)")
    print(f"{'before':>16} {'%':>6} {'after':>16} {'%':>6}  function")
    names = sorted(set(funcs) | set(funcs2), key=lambda n: -max(funcs[n], funcs2[n]))
    for n in names[:top]:
        print(f"{funcs[n]:16,} {100.0 * funcs[n] / total:6.2f} {funcs2[n]:16,} "
              f"{100.0 * funcs2[n] / total2:6.2f}  {n}")
    sys.exit(0)
print(f"{nprocs} processes, {total:,} instructions executed in {os.path.basename(binary)}")
acc = 0
for fn, c in funcs.most_common(top):
    acc += c
    print(f"{c:16,} {100.0 * c / total:6.2f}% {100.0 * acc / total:6.2f}%  {fn}")
if lines:
    offs = sorted(o for o in counts if func_of(o) in lines)
    res = subprocess.run(["addr2line", "-e", binary] + [hex(o) for o in offs],
                         capture_output=True, text=True).stdout.split("\n")
    for o, loc in zip(offs, res):
        print(f"{counts[o]:16,}  {hex(o)}  {loc}")
