#!/usr/bin/env python3
"""postprocess.py against python's: logical and short_circuits (the
`and`s and `or`s of a merge's setvars) on random ifs and on the traces
python's contract.make_ast got (build/fn_inputs, gen_function_inputs.py),
cleanup_mul_1 (the widths of what's bytes kept) on random expressions and
on python's traces.

    tests/test_postprocess.py [SEED [COUNT]]
"""
import os, sys, glob, random, pickle
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(HERE, "..", "..", "panoramix")))
sys.path.insert(0, os.environ.get("PANASM_BUILD") or os.path.join(HERE, "..", "build"))
sys.setrecursionlimit(20000)
import logging; logging.disable(logging.CRITICAL)
import panoramix_asm as A
from test_simplify import check, run
import test_simplify
from panoramix import postprocess as PP

seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
count = int(sys.argv[2]) if len(sys.argv) > 2 else 1000
rnd = random.Random(seed)


def ch(*xs):
    return rnd.choice(xs)


CONDS = ["x", ("lt", "x", 5), ("iszero", "x"), ("bool", "y"), ("eq", "a", "b"), ("and", "x", "y"),
         ("or", ("lt", "x", 5), ("eq", "a", "b")), ("mask_shl", 1, 0, 0, "z"), ("storage", 1, 0, 3),
         ("mask_shl", 8, 0, 0, "z"), 0, 1, 7, ("lor", "x", "y"), ("land", "x", ("bool", "y")), True, False]


def rvalue(cond):
    return ch(cond, cond, 0, 1, True, False, "t", ("add", "x", 1), ("bool", cond), ("iszero", cond),
              rnd.choice(CONDS), 2**256, -1)


def rcond():
    return rnd.choice(CONDS)


def rsetvar(cond, var=None):
    return ("setvar", var or ch("_1", "_1", "_2", 3), rvalue(cond))


def rbranch(cond, d):
    r = rnd.random()
    if r < 0.6:
        return [rsetvar(cond)]
    if r < 0.7:
        return []
    if r < 0.8 and d < 3:
        return [rif(d + 1)]
    return [rsetvar(cond), ("stop",)]


def rif(d=0):
    cond = rcond()
    r = rnd.random()
    if r < 0.05:
        return ("if", cond, rbranch(cond, d))
    return ("if", cond, rbranch(cond, d), rbranch(cond, d))


def rtrace(d=0):
    res = []
    for _ in range(rnd.randint(1, 4)):
        r = rnd.random()
        if r < 0.6:
            res.append(rif(d))
        elif r < 0.75 and d < 2:
            res.append(("while", rcond(), rtrace(d + 1), "loop", ()))
        else:
            res.append(ch(("stop",), ("setvar", "_1", 3), ("return", ("var", "_1"))))
    return res


BYTES_OPS = ["data", "sha3", "return", "revert", "log"]


def rexp(d=0):
    r = rnd.random()
    if d > 3 or r < 0.25:
        return ch("caller", "x", 5, 2**256 + 3, -2, ("cd", 4), ("storage", 160, 0, 2), "'abcd'")
    if r < 0.4:
        return ("mul", 1, *[rexp(d + 1) for _ in range(rnd.randint(1, 3))])
    if r < 0.5:
        return ("mask_shl", ch(160, 256, 32, 8), ch(0, 0, 224, 96), ch(0, 0, -96), rexp(d + 1))
    if r < 0.55:
        return ("mask_shl", 160, 0, 0, "caller")
    if r < 0.6:
        return ("mask_shl", 32, 224, 0, "'abcd'")
    if r < 0.65:
        return ("bool", ch(0, 5, rexp(d + 1)))
    if r < 0.7:
        return ("mask_shl", 160, 0, 0, ("storage", 160, 0, 2))
    if r < 0.85:
        op = ch(*BYTES_OPS)
        return (op,) + tuple(rexp(d + 1) for _ in range(rnd.randint(1, 3)))
    return ("add", rexp(d + 1), rexp(d + 1))


def rpp_trace(d=0):
    res = []
    for _ in range(rnd.randint(1, 4)):
        r = rnd.random()
        if r < 0.2 and d < 2:
            res.append(("if", rexp(), rpp_trace(d + 1), rpp_trace(d + 1)))
        elif r < 0.3 and d < 2:
            res.append(("while", rexp(), rpp_trace(d + 1), "loop", (("setvar", "_1", rexp()),)))
        else:
            res.append(ch(("setvar", "_1", rexp()), ("return", rexp()), ("log", rexp(), rexp()),
                          ("setmem", ("range", 64, 32), rexp()), ("call", "gas", "x", 0, rexp(), rexp())))
    return res


if __name__ == "__main__":
    for i in range(count):
        ctx = f"case {i}"
        c = rcond()
        t, f = rvalue(c), rvalue(c)
        check("logical", (c, t, f), run(PP.logical, c, t, f), ctx)
        tr = rtrace()
        check("short_circuits", tr, run(PP.short_circuits, tr), ctx)
        tr = rpp_trace()
        check("pp_cleanup_mul_1", tr, run(PP.cleanup_mul_1, tr), ctx)

    # python's own: the traces make_ast got, the ones Function got
    for p in sorted(glob.glob(os.path.join(HERE, "..", "build", "fn_inputs", "*.pkl"))):
        rec = pickle.load(open(p, "rb"))
        name = os.path.basename(p)
        for k, tr in enumerate(rec["asts"]):
            check("short_circuits", tr, run(PP.short_circuits, tr), f"{name} ast {k}")
        for hash, tr, abi in rec["functions"]:
            check("pp_cleanup_mul_1", tr, run(PP.cleanup_mul_1, tr), f"{name} {hash}")
    print(f"{test_simplify.cases} cases, {test_simplify.bad} mismatches")
    sys.exit(1 if test_simplify.bad else 0)
