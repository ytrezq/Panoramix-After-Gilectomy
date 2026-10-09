#!/usr/bin/env python3
"""The folder's fold_paths on random paths against python's: paths of
lines from a small alphabet, made to share beginnings and endings (the
merges, the ors split in two - fold_or's search for the two stretches -
and the ors that can't be); the paths of traces whose ifs nest deep (one
branch ending: a path a level, a line shorter each). Both of their
folds: on stretches of the paths (fold_paths), and on lists, the paths
copied at each level (fold_path_lists, python's original algorithm).

    tests/test_fold_random.py [SEED [COUNT]]
"""
import os, sys, random, copy
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(HERE, "..", "..", "panoramix")))
sys.path.insert(0, os.environ.get("PANASM_BUILD") or os.path.join(HERE, "..", "build"))
import logging; logging.disable(logging.CRITICAL)
sys.setrecursionlimit(100000)
import resource
_soft, _hard = resource.getrlimit(resource.RLIMIT_STACK)
if _soft != resource.RLIM_INFINITY and _soft < (512 << 20):
    resource.setrlimit(resource.RLIMIT_STACK, (512 << 20 if _hard == resource.RLIM_INFINITY else min(512 << 20, _hard), _hard))
import panoramix_asm as A
from panoramix import folder
from test_simplify import check, run
import test_simplify

seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
count = int(sys.argv[2]) if len(sys.argv) > 2 else 1000
rnd = random.Random(seed)

LINES = [("setmem", 64, 1), ("store", 256, 0, 1, 2), ("log", 5), "asm line", "",
         ("stop",), ("revert", 0), ("revert", None), ("return", 1), ("return", 0), ("invalid",),
         ("setvar", "_1", 3), ("call", 1, 2, 3, 4, 5, 6)]
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

def deep_trace(depth):
    """ifs nested depth deep: one branch ends (a revert, an invalid), the
    other goes on - now and then with lines before, or both going on"""
    if depth == 0:
        return [rnd.choice(SLINES)] + copy.deepcopy(rnd.choice(SENDS))
    lines = [rnd.choice(SLINES) for _ in range(rnd.choice([0, 0, 0, 1, 2]))]
    cond = ("eq", ("cd", 4 + 32 * depth), rnd.randint(0, 3))
    end = copy.deepcopy(rnd.choice(SENDS))
    rest = deep_trace(depth - 1)
    if rnd.random() < 0.05 and depth < 40:
        branches = [rest, deep_trace(depth - 1)]
    else:
        branches = [rest, [rnd.choice(SLINES)] * rnd.randint(0, 1) + end]
    if rnd.random() < 0.5:
        branches.reverse()
    return lines + [("if", cond, branches[0], branches[1])]


# fold_aux, its final rules: a one-sided if followed by an end (a revert
# with no data, a return of 0, an invalid) takes the end in
ENDS = [[], [("revert", None)], [("revert", 0)], [("return", 0)], [("invalid",)], [("invalid",), ("stop",)],
        [("stop",)], [("revert", None), ("stop",)], [("return", 1)]]


def raux(d=0):
    lines = []
    for _ in range(rnd.randint(0, 3)):
        r = rnd.random()
        if r < 0.3 and d < 3:
            lines.append(("if", rnd.choice(CONDS), raux(d + 1)))
        elif r < 0.45 and d < 3:
            lines.append(("if", rnd.choice(CONDS), raux(d + 1), raux(d + 1)))
        elif r < 0.5 and d < 2:
            lines.append(("while", rnd.choice(CONDS), raux(d + 1), "jd", ()))
        else:
            lines.append(rline())
    return lines + copy.deepcopy(rnd.choice(ENDS))


# the whole fold (as_paths, meta_fold_paths - fold_paths, flatten's
# try_merge, cleanup_ors, make_ifs, merge_ifs and its try_merge_ifs -
# fold_aux) on traces like the VM's: branches beginning alike, conditions
# reading what the lines before them change (a variable, the memory, the
# storage, a call's result, the gas), ifs whose branches go on after them
SLINES = [("setvar", 1, ("add", ("var", 1), 1)), ("setvar", 2, 5), ("setmem", ("range", 64, 32), ("cd", 4)),
          ("store", 256, 0, 1, ("cd", 36)), ("log", ("data",), 7), ("call", "gas", ("cd", 4), 0, None, None),
          ("staticcall", "gas", ("cd", 4), 0, None, None), ("tstore", 1, 2), "a comment", ("jd", "100", ())]
SCONDS = [("lt", ("var", 1), 5), ("iszero", ("var", 2)), ("eq", ("storage", 256, 0, 1), 0),
          ("lt", ("mem", ("range", 64, 32)), 9), ("eq", "ext_call.success", 0), ("lt", "gas", 2300),
          ("gt", "msize", 64), ("lt", "callvalue", 3), ("eq", ("cd", 4), 1), ("tload", 1),
          ("eq", ("balance", "caller"), 0), ("lt", ("var", "_msize"), 5)]
SENDS = [[("stop",)], [("revert", None)], [("return", ("data", 1))], [("invalid",)], [("revert", ("data", 2))]]


def rfold(d=0):
    lines = [rnd.choice(SLINES) for _ in range(rnd.randint(0, 3))]
    if d < 3 and rnd.random() < 0.6:
        common = [rnd.choice(SLINES) for _ in range(rnd.randint(0, 3))]
        lines.append(("if", rnd.choice(SCONDS), common + rfold(d + 1), common + rfold(d + 1)))
        if rnd.random() < 0.2:
            lines += [rnd.choice(SLINES)] + copy.deepcopy(rnd.choice(SENDS))
        return lines
    return lines + copy.deepcopy(rnd.choice(SENDS))


if __name__ == "__main__":
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
        # and on lists (python loops forever on the same path twice)
        signal.alarm(5)
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                expected = run(lambda x: folder.fold_path_lists(copy.deepcopy(x)), ps)
        except PyTimeout:
            skipped += 1
            continue
        finally:
            signal.alarm(0)
        if "PyTimeout" not in expected:
            check("fold_path_lists", ps, expected, f"case {i}")

    for i in range(max(count // 50, 2)):
        # (the paths of n levels: n**2 lines, the text of the test a lot more)
        tr = deep_trace(rnd.randint(1, 250))
        ps = folder.as_paths(tr)
        check("fold_paths", ps, run(lambda x: folder.fold_paths(list(x)), ps), f"deep case {i}")
        check("fold_path_lists", ps, run(lambda x: folder.fold_path_lists(list(x)), ps), f"deep case {i}")
        if i % 5 == 0:
            tr = deep_trace(rnd.randint(250, 1500))
        check("fold", tr, run(lambda x: folder.fold(copy.deepcopy(x)), tr), f"deep fold case {i}")

    for i in range(count):
        tr = raux()
        check("fold_aux", tr, run(lambda x: folder.fold_aux(copy.deepcopy(x)), tr), f"fold_aux case {i}")
        check("is_end_block", tr, run(lambda x: x == [("return", 0)] or x == [("revert", None)]
                                      or (len(x) > 0 and isinstance(x[0], tuple) and x[0][:1] == ("invalid",)), tr),
              f"is_end_block case {i}")

    for i in range(count):
        tr = rfold()
        check("fold", tr, run(lambda x: folder.fold(copy.deepcopy(x)), tr), f"fold case {i}")
    print(f"{test_simplify.cases} cases, {test_simplify.bad} mismatches ({skipped} where python loops, skipped)")
    sys.exit(1 if test_simplify.bad else 0)
