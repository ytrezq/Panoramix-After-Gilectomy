#!/usr/bin/env python3
"""The folder's fold_paths on random paths against python's: paths of
lines from a small alphabet, made to share beginnings and endings (the
merges, the ors split in two - fold_or's search for the two stretches -
and the ors that can't be).

    tests/test_fold_random.py [SEED [COUNT]]
"""
import os, sys, random, copy
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(HERE, "..", "..", "panoramix")))
sys.path.insert(0, os.environ.get("PANASM_BUILD") or os.path.join(HERE, "..", "build"))
import logging; logging.disable(logging.CRITICAL)
sys.setrecursionlimit(10000)
import panoramix_asm as A
from panoramix import folder
from test_simplify import check, run
import test_simplify

seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
count = int(sys.argv[2]) if len(sys.argv) > 2 else 1000
rnd = random.Random(seed)

LINES = [("setmem", 64, 1), ("store", 256, 0, 1, 2), ("log", 5), "asm line", "",
         ("stop",), ("revert", 0), ("return", 1), ("setvar", "_1", 3),
         ("call", 1, 2, 3, 4, 5, 6)]
CONDS = [("lt", "x", 5), ("iszero", ("lt", "x", 5)), ("eq", "y", 1), ("iszero", ("eq", "y", 1)),
         ("gt", "z", 2), "callvalue", ("iszero", "callvalue")]

def rline():
    return rnd.choice(LINES + CONDS[:3])

def rpath(n):
    return [rline() for _ in range(n)]

def split_paths():
    """sides in two groups (by their first line), the k-th of each ending
    the same way: what fold_or splits in two - or nearly (a side off)"""
    h0, h1 = rnd.sample(CONDS, 2)
    pre0, pre1 = rpath(rnd.randint(0, 3)), rpath(rnd.randint(0, 3))
    m = rnd.randint(1, 3)
    tails = [rpath(rnd.randint(0, 4)) for _ in range(m)]
    a = [[h0] + pre0 + t for t in tails]
    b = [[h1] + pre1 + t for t in tails]
    if rnd.random() < 0.3:          # a side different
        g = rnd.choice([a, b])
        k = rnd.randrange(len(g))
        g[k] = g[k][:1] + rpath(rnd.randint(0, 3))
    # the two groups interleaved, each in its order
    res, ia, ib = [], 0, 0
    while ia < len(a) or ib < len(b):
        if ib >= len(b) or (ia < len(a) and rnd.random() < 0.5):
            res.append(a[ia]); ia += 1
        else:
            res.append(b[ib]); ib += 1
    begin = rpath(rnd.randint(0, 2))
    return [begin + p for p in res]

def paths():
    """a few paths: a shared beginning and ending around different middles,
    some of them starting with one of two conditions"""
    if rnd.random() < 0.4:
        return split_paths()
    k = rnd.randint(2, 6)
    begin = rpath(rnd.randint(0, 3))
    end = rpath(rnd.randint(0, 3))
    heads = rnd.sample(CONDS, 2)
    res = []
    shared = rpath(rnd.randint(0, 4))
    for i in range(k):
        mid = rpath(rnd.randint(0, 4))
        style = rnd.random()
        if style < 0.4:
            # two groups whose remainders pair up (fold_or's split)
            p = [heads[i % 2]] + rpath(rnd.randint(0, 3)) + shared
        elif style < 0.7:
            p = [heads[rnd.randint(0, 1)]] + mid
        else:
            p = rpath(rnd.randint(1, 5))
        res.append(begin + p + end if rnd.random() < 0.7 else p)
    return [p for p in res if p]

# python loops forever on some (the same path twice: the beginning they
# share never ends); python's fold_or prints before it raises
import signal, io, contextlib
class PyTimeout(Exception):
    pass
def alarm(*a):
    raise PyTimeout()
signal.signal(signal.SIGALRM, alarm)
skipped = 0
for i in range(count):
    ps = paths()
    if not ps:
        continue
    signal.alarm(5)
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            expected = run(lambda x: folder.fold_paths(copy.deepcopy(x)), ps)
    except PyTimeout:
        skipped += 1
        continue
    finally:
        signal.alarm(0)
    if "PyTimeout" in expected:
        skipped += 1
        continue
    check("fold_paths", ps, expected, f"case {i}")
print(f"{test_simplify.cases} cases, {test_simplify.bad} mismatches ({skipped} where python loops, skipped)")
sys.exit(1 if test_simplify.bad else 0)
