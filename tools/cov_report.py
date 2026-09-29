#!/usr/bin/env python3
"""The functions a coverage run never called.

    make coverage
    PANORAMIX_COVERAGE=cov.txt build/cov/panasm decompile ...     (as many runs as wanted)
    PANORAMIX_COVERAGE=cov.txt PANASM_BUILD=build/cov python3 tests/test_...py
    tools/cov_report.py cov.txt [more.txt...] [--all]

Sums the counts of the runs ("count name" lines, every function listed by
every run) and prints, file by file, the functions called by none (with
--all, every function and its count).
"""
import collections, glob, os, re, sys

args = [a for a in sys.argv[1:] if not a.startswith("--")]
if not args:
    sys.exit(__doc__)
counts = collections.Counter()
for path in args:
    for line in open(path):
        c, _, name = line.strip().partition(" ")
        if name:
            counts[name] += int(c)
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
where = {}
for f in sorted(glob.glob(os.path.join(root, "src", "*.s"))):
    for m in re.finditer(r"^(?:FUNC|API)\s+(\w+)", open(f).read(), re.M):
        where[m.group(1)] = os.path.basename(f)
never = [n for n in counts if counts[n] == 0]
print("%d functions, %d called, %d never" % (len(counts), len(counts) - len(never), len(never)))
byfile = collections.defaultdict(list)
for n in (counts if "--all" in sys.argv else never):
    byfile[where.get(n, "?")].append(n)
for f in sorted(byfile):
    print("%s:" % f)
    for n in sorted(byfile[f]):
        print("   %10d %s" % (counts[n], n))
