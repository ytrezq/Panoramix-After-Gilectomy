#!/usr/bin/env python3
"""Differential tests of conds.s and simplify_vars.s against
panoramix.simplify: what a condition says of what it compares
(cond_bounds), the mins it decides (apply_constraint), the mins of the ifs
(min_ifs), the results of the precompiled contracts (precompiled_results),
what a line changes (changes_value), and the words of a trace that are
small (small_words).

    tests/test_conds.py [SEED [COUNT]]
"""
import os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_simplify as T
from test_simplify import S, run, check

random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 1)
N = int(sys.argv[2]) if len(sys.argv) > 2 else 300

def rint():
    return random.choice([0, 1, 2, 31, 32, 64, 100, 2**64 - 1, 2**64, 2**255 - 1, 2**255, 2**256 - 1, 2**256, -1, -5])

ATOMS = [("cd", 4), ("cd", 36), ("var", 1), ("var", 2), "returndatasize", ("mem", ("range", 64, 32)),
         ("storage", 256, 0, 1), "calldatasize", ("ext_call.return_data", 0, 32), ("mask_shl", 64, 0, 0, ("cd", 4)),
         ("add", 4, ("cd", 4)), ("mul", 32, ("cd", 36)), ("var", "_1")]

def ratom():
    return random.choice(ATOMS)

def rexp(d=0):
    r = random.random()
    if d > 1 or r < 0.4:
        return rint() if random.random() < 0.4 else ratom()
    op = random.choice(["min", "min", "add", "mask_shl", "mem", "cd"])
    if op == "min":
        return ("min", rexp(d + 1), random.choice(["returndatasize", rexp(d + 1), 32]))
    if op == "add":
        return ("add", rexp(d + 1), rexp(d + 1))
    if op == "mask_shl":
        return ("mask_shl", random.choice([8, 64, 256]), 0, 0, rexp(d + 1))
    if op == "mem":
        return ("mem", ("range", rexp(d + 1), random.choice([32, ("min", 32, "returndatasize"), rexp(d + 1)])))
    return ("cd", rexp(d + 1))

PRECOMPILED = ["sha256hash.result", "ripemd160hash.result", "bn256Add.result", "bn256ScalarMul.result",
               "bn256Pairing.result", "ecrecover.result", "signer"]

def rcond():
    r = random.random()
    if r < 0.15:
        c = random.choice(PRECOMPILED)
    elif r < 0.85:
        op = random.choice(["lt", "gt", "le", "ge", "eq", "slt", "sgt", "sle", "sge"])
        a, b = rexp(), rint()
        c = (op, a, b) if random.random() < 0.6 else (op, b, a)
    else:
        c = rexp()
    for _ in range(random.randint(0, 2)):
        c = (random.choice(["iszero", "bool"]), c)
    return c

def rline(d=0):
    r = random.random()
    if r < 0.2: return ("setmem", ("range", rexp(1), random.choice([32, rexp(1)])), rexp())
    if r < 0.35: return ("setvar", random.choice([1, 2, "_1"]), rexp())
    if r < 0.45: return ("store", 256, 0, random.choice([1, 5, ("cd", 4)]), rexp())
    if r < 0.5: return ("tstore", random.choice([1, ("cd", 4)]), rexp())
    if r < 0.6 and d < 2:
        if random.random() < 0.5:
            # `if a < b: v = a else: v = b` and its variants
            a, b = rexp(1), rexp(1)
            v = random.choice([1, 2, "_1"])
            op = random.choice(["lt", "le", "gt", "ge"])
            cond = (op, a, b)
            x, y = (a, b) if random.random() < 0.7 else (b, a)
            if random.random() < 0.3:
                cond = ("iszero", cond); x, y = y, x
            if op in ("gt", "ge") and random.random() < 0.7:
                x, y = y, x
            return ("if", cond, [("setvar", v, x)], [("setvar", random.choice([v, v, 3]), y)])
        return ("if", rcond(), [rline(d + 1) for _ in range(random.randint(0, 2))], [rline(d + 1) for _ in range(random.randint(0, 2))])
    if r < 0.7:
        k = random.choice([1, 2, 3, 5, 4])
        if k == 4:
            return ("precompiled", "copied", "identity", ("mem", ("range", 64, 32)))
        return ("precompiled", random.choice(["signer", "hash", "hash2"]),
                {1: "ecrecover", 2: "sha256hash", 3: "ripemd160hash", 5: "bigModExp"}[k], ("mem", ("range", 0, 64)))
    if r < 0.75: return ("call", "gas", ("cd", 4), 0, None, None)
    if r < 0.8 and d < 2:
        return ("while", rcond(), [rline(d + 1) for _ in range(random.randint(0, 2))] + [("continue", "jd", (("setvar", 1001, ("add", 1, ("var", 1001))),))], "jd", (("setvar", 1001, 0),))
    if r < 0.85: return ("require", rcond())
    if r < 0.9: return ("if", rcond(), [("revert", 0)], [])
    return ("log", ("mem", ("range", rexp(1), random.choice([32, ("cd", 4)]))), ("ext_call.return_data", 0, 32))

def rtrace():
    return [rline() for _ in range(random.randint(1, 8))] + [random.choice([("stop",), ("return", ("mem", ("range", rexp(1), 32)))])]

def bounds(c):
    return tuple((x, lo, hi) for x, (lo, hi) in S.cond_bounds(c).items())

if __name__ == "__main__":
    for n in range(N):
        c = rcond()
        check("cond_bounds", c, run(bounds, c), "random %d" % n)
        e = rexp()
        check("apply_constraint", (e, c), run(S.apply_constraint, e, c), "random %d" % n)
        t = rtrace()
        check("min_ifs", t, run(S.min_ifs, t), "random %d" % n)
        check("precompiled_results", t, run(S.precompiled_results, t), "random %d" % n)
        check("variable_values", t, run(lambda t: tuple((k, tuple(v)) for k, v in S.variable_values(t).items()), t), "random %d" % n)
        check("small_words", t, run(lambda t: tuple(sorted(S.small_words(t, S.variable_values(t)), key=lambda x: str(x) if type(x) != int else " " + str(x))), t), "random %d" % n)
        line = rline()
        check("changes_value", (line, e), run(S.changes_value, line, e), "random %d" % n)
    print(f"{T.cases} cases, {T.bad} mismatches")
    sys.exit(1 if T.bad else 0)
