#!/usr/bin/env python3
"""Random differential test of the printer: prettify (every combination of
its flags) and pretty_line on random expressions and lines - the shapes
the traces have, with numbers of every size (negative, past 2^62, past
2^256), against panoramix.prettify.

    tests/test_prettify_random.py [SEED [COUNT]]
"""
import os, sys, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_prettify import *

random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 1)
N = int(sys.argv[2]) if len(sys.argv) > 2 else 2000

def rint():
    r = random.random()
    if r < 0.35: return random.choice([0, 1, 2, 3, 4, 8, 31, 32, 64, 96, 128, 160, 224, 248, 255, 256, 3600, 86400, 10**6, 10**18])
    if r < 0.55: return random.randint(-300, 300)
    if r < 0.7: return random.choice([1, -1]) * 2 ** random.randint(0, 300) + random.randint(-2, 2)
    if r < 0.8: return random.randint(0, 2**256)
    if r < 0.9: return random.choice([0xa9059cbb, 0x70a08231, 0x23b872dd, 0xdeadbeef, 2**160 - 1, 2**255, 2**256 - 1])
    return random.randint(-2**70, 2**70)

NAMES = ["callvalue", "caller", "calldatasize", "timestamp", "number", "address", "origin",
         "gas", "chainid", "block.timestamp", "unknown", "x", "coinbase"]
OPS2 = ["add", "sub", "mul", "div", "sdiv", "mod", "smod", "exp", "lt", "gt", "le", "ge",
        "slt", "sgt", "eq", "and", "or", "xor", "shl", "shr", "sar", "byte", "signextend", "max", "min"]

def atom():
    r = random.random()
    if r < 0.4: return rint()
    if r < 0.6: return random.choice(NAMES)
    if r < 0.75: return ("cd", random.choice([4, 36, 68, rint(), ("add", 4, ("cd", 4))]))
    if r < 0.85: return ("var", random.choice([1, 2, 3001, "_1", "_21"]))
    if r < 0.93: return ("param", random.choice(["_param1", "_param2", "amount"]))
    return ("mem", ("range", random.choice([0, 32, 64, 128, rint()]), random.choice([32, 20, 1, rint()])))

def rexp(d=0):
    r = random.random()
    if d > 3 or r < 0.3: return atom()
    if r < 0.5:
        op = random.choice(OPS2)
        n = random.choice([2, 2, 2, 3]) if op in ("add", "mul", "and", "or", "max", "min") else 2
        return (op,) + tuple(rexp(d + 1) for _ in range(n))
    if r < 0.6:
        return (random.choice(["iszero", "bool", "not"]), rexp(d + 1))
    if r < 0.75:
        size = random.choice([1, 8, 20, 32, 64, 96, 160, 224, 248, 251, 255, 256, rint()])
        off = random.choice([0, 0, 0, 8, 96, 160, 248, rint()])
        shl = random.choice([0, 0, 0, 1, 3, 5, 8, 9, 96, -3, -5, -8, -9, -96, rint()])
        if random.random() < 0.3: shl = off
        if random.random() < 0.2: shl = -off
        return ("mask_shl", size, off, shl, rexp(d + 1))
    if r < 0.82:
        return ("storage", random.choice([256, 160, 8, 1, rint()]), random.choice([0, 0, 8, 160, rint()]),
                random.choice([0, 5, rint(), ("sha3", rexp(d + 1), 3), ("add", 1, ("sha3", 2))]))
    if r < 0.88:
        return ("sha3",) + tuple(rexp(d + 1) for _ in range(random.randint(1, 3)))
    if r < 0.93:
        return ("data",) + tuple(rexp(d + 1) for _ in range(random.randint(1, 3)))
    if r < 0.97:
        return ("stor", random.choice([("name", "stor0", 0), ("length", ("name", "stor1", 1)),
                                       ("map", rexp(d + 1), ("name", "balanceOf", 3)),
                                       ("array", rexp(d + 1), ("name", "stor4", 4))]))
    return ("type", random.choice([256, 160, 8, 1]), ("field", random.choice([0, 8, 160]),
                                                        ("stor", ("name", "stor2", 2))))

def rline():
    r = random.random()
    e = rexp()
    if r < 0.2: return ("setmem", ("range", random.choice([0, 64, 128, rint()]), random.choice([32, rint()])), e)
    if r < 0.35: return ("store", random.choice([256, 160, 8]), random.choice([0, 0, 160]), random.choice([0, 3, rexp()]), e)
    if r < 0.45: return ("set", ("stor", ("name", "stor0", 0)), e)
    if r < 0.55: return ("setvar", random.choice([1, "_2"]), e)
    if r < 0.65: return ("return", e)
    if r < 0.72: return ("revert", random.choice([0, e]))
    if r < 0.8: return ("require", e)
    if r < 0.87: return ("log", rexp(), rint(), e)
    if r < 0.93: return ("selfdestruct", e)
    return ("invalid",)

# cases the random runs found once: always checked
REGRESSIONS = [
    # the length of a string in memory data, negative: python's index
    # goes back by it ('' for -1, an IndexError further)
    ("setmem", ("range", 0, 96), ("data", 32, -40, 5)),
    ("setmem", ("range", 0, 96), ("data", 32, -200, 1, 2)),
    ("return", ("data", 1, 2, 32, -40)),
]
for line in REGRESSIONS:
    for flags in (0, PF_COLOR):
        check("pretty_line", (line, flags), run(lambda l, f: list(P.pretty_line(l, add_color=bool(f & PF_COLOR))), line, flags), "regression")

bad = 0
for n in range(N):
    exp = rexp()
    for flags in (0, PF_PARENS, PF_COLOR, PF_PARENS | PF_COLOR, PF_REM_BOOL | PF_COLOR, PF_PARENS | PF_TOP):
        check("prettify", (exp, flags), run(py_prettify, exp, flags), "random %d" % n)
    line = rline()
    for flags in (0, PF_COLOR):
        check("pretty_line", (line, flags), run(lambda l, f: list(P.pretty_line(l, add_color=bool(f & PF_COLOR))), line, flags), "random %d" % n)
print(f"{test_simplify.cases} cases, {test_simplify.bad} mismatches")
