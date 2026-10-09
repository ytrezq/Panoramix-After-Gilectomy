#!/usr/bin/env python3
"""Differential tests of simplify_exp.s against panoramix.simplify."""
import os, random, sys
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "panoramix")))
sys.path.insert(0, os.environ.get("PANASM_BUILD") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import logging; logging.disable(logging.CRITICAL)
import panoramix_asm as A
from panoramix import simplify as S
from test_memloc import rval, rint, rpos, ATOMS, run

random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 1)
N = int(sys.argv[2]) if len(sys.argv) > 2 else 300

def rexp(depth=0):
    r = random.random()
    if depth > 2 or r < 0.3: return rint() if random.random() < 0.4 else random.choice(ATOMS)
    op = random.choice(["mask_shl", "mask_shl", "and", "iszero", "bool", "eq", "mod", "add", "mul", "div", "max", "mem", "or", "data", "lt", "cd", "storage", "exp"]
                       + (NEW_OPS if NEW else []))
    if op in NEW_OPS: return rnew(op, depth)
    if op == "mask_shl":
        if random.random() < 0.3:
            return ("mask_shl", random.choice([246, 251, 253, 256]), random.choice([5, 0]), random.choice([0, 3, 5, -5]), rexp(depth + 1))
        return ("mask_shl", random.choice([8, 16, 32, 64, 96, 128, 160, 200, 224, 248, 255, 256, ("cd", 4), ("mask_shl", 253, 0, 3, ("cd", 4))]), random.choice([0, 0, 0, 5, 8, 96, 160, 192]), random.choice([0, 0, 0, -8, -96, 8, 96, 3, -5, -160, -192]), rexp(depth + 1))
    if op == "and": return ("and",) + tuple(rexp(depth + 1) for _ in range(random.randint(2, 3)))
    if op in ("iszero", "bool"): return (op, rexp(depth + 1))
    if op == "eq": return ("eq", rexp(depth + 1), random.choice([0, rexp(depth + 1)]))
    if op == "mod": return ("mod", rexp(depth + 1), random.choice([0, 32, 64, 5, rexp(depth + 1)]))
    if op == "add": return ("add",) + tuple(rexp(depth + 1) for _ in range(random.randint(1, 4)))
    if op == "mul": return ("mul", random.choice([1, 2, 8, 32, -1, rexp(depth + 1)]), rexp(depth + 1))
    if op == "div": return ("div", rexp(depth + 1), random.choice([1, 32, ("exp", 256, random.choice([1, 2, ("cd", 4)])), rexp(depth + 1)]))
    if op == "max": return ("max",) + tuple(rexp(depth + 1) for _ in range(random.randint(1, 3)))
    if op == "mem": return ("mem", ("range", rpos(), random.choice([32, 32, 0, 4, 20, rpos()])))
    if op == "or": return ("or",) + tuple(rexp(depth + 1) for _ in range(random.randint(2, 3))) if random.random() < 0.5 else ("or", rexp(depth + 1), 0)
    if op == "data": return ("data",) + tuple(rexp(depth + 1) for _ in range(random.randint(1, 4)))
    if op == "lt": return (random.choice(["lt", "le", "gt", "ge"]), ("add", rexp(depth + 1), rexp(depth + 1)), ("add", rexp(depth + 1), rexp(depth + 1)))
    if op == "cd": return ("cd", random.choice([0, 4, 36, ("add", 4, ("cd", 36))]))
    if op == "storage": return ("storage", random.choice([256, 160, 8, 32]), random.choice([0, 0, 8, 160]), random.choice([5, ("map", 1, 2)]))
    return ("exp", 256, rexp(depth + 1))

# the shapes of the rules of the PR's simplify_exp: bytes, shifts by a
# number, words of the calldata, comparisons with a number, differences,
# the slices of the same bytes one after the other
NEW = os.environ.get("NEW", "1") != "0"
NEW_OPS = ["bytes", "bytes", "shift", "signextend", "call.data", "xor", "cmp_c", "iszero_add", "data_slices", "ceil", "eq1"]

def rnew(op, depth):
    if op == "bytes":
        return ("bytes", random.choice([1, 4, 20, 31, 32, 64, ("cd", 4)]), random.choice([0, rexp(depth + 1), ("mem", ("range", rpos(), random.choice([32, 20, 4, 64])))]))
    if op == "shift":
        return (random.choice(["shr", "shl"]), random.choice([0, 3, 8, 96, 160, 255, 256, 300, -8, ("cd", 4), ("mask_shl", 8, 0, 0, ("cd", 4)), ("mul", 8, ("cd", 4))]), rexp(depth + 1))
    if op == "signextend":
        return ("signextend", random.choice([0, 1, 15, 30, 31, 32, -1, ("cd", 4)]), rexp(depth + 1))
    if op == "call.data":
        return ("call.data", random.choice([4, 36, rpos(), "calldatasize"]), random.choice([32, 32, 4, 64, rint(), rpos()]))
    if op == "xor":
        return ("iszero", ("xor", rexp(depth + 1), rexp(depth + 1))) if random.random() < 0.7 else ("xor", rexp(depth + 1), rexp(depth + 1))
    if op == "cmp_c":
        c = random.choice([0, 1, 2, 255, 256, 2**160, 2**160 - 1, 2**256 - 1, -1, rint()])
        x = rexp(depth + 1)
        o = random.choice(["lt", "gt", "le", "ge"])
        return (o, x, c) if random.random() < 0.5 else (o, c, x)
    if op == "iszero_add":
        r = random.random()
        if r < 0.4: return ("iszero", ("add", rint(), rexp(depth + 1)))
        if r < 0.8: return ("iszero", ("add", rexp(depth + 1), ("mul", -1, rexp(depth + 1))) + ((rexp(depth + 1),) if random.random() < 0.3 else ()))
        return (random.choice(["iszero", "bool"]), ("mul", -1, rexp(depth + 1)))
    if op == "data_slices":
        p = rpos(); n = random.choice([4, 20, 28, 32])
        r = random.random()
        if r < 0.3:
            return ("data", ("mem", ("range", p, n)), ("mem", ("range", ("add", n, p) if not isinstance(p, int) else p + n, random.choice([4, 32, 0]))))
        if r < 0.6:
            a = random.choice(["ext_call.return_data", "call.data"])
            return ("data", (a, 0, n), (a, n, 32 - n), random.choice([0, ("bytes", 4, 0), rexp(depth + 1)]))
        return ("data",) + tuple(random.choice([0, ("bytes", random.choice([4, 28, 12]), 0), ("bytes", 4, rexp(depth + 1)), ("bytes", 32, ("cd", 4)), ("mask_shl", 160, 0, 0, "caller"), ("mem", ("range", rpos(), 0)), rexp(depth + 1)]) for _ in range(random.randint(1, 4)))
    if op == "ceil":
        return ("mask_shl", random.choice([251, 256, 248, 5]), random.choice([5, 0, 3]), random.choice([0, 0, 5, -5]),
                ("add", random.choice([31, 63, 95, 1, 3, 7, 32]), random.choice([("mul", 32, ("cd", 4)), ("mask_shl", 251, 5, 0, ("cd", 4)), ("cd", 4), 64, ("mul", 8, ("cd", 36))])) + ((("mul", 32, ("cd", 36)),) if random.random() < 0.3 else ()))
    if op == "eq1":
        return ("eq", random.choice([("lt", ("cd", 4), 5), ("iszero", ("cd", 4)), ("cd", 4), ("and", 1, ("cd", 4))]), 1) if random.random() < 0.5 else ("eq", 1, ("bool", rexp(depth + 1)))
    raise ValueError(op)

cases = bad = 0
def check(name, arg, expected):
    global cases, bad
    cases += 1
    lit = repr(arg)
    try:
        got = A._test(name, lit)
    except Exception as e:
        got = "<asm exc %s>" % e
    ok = expected == got or (expected.startswith("<exc") and (got.startswith("'<exc") or got.startswith('"<exc')))
    if not ok:
        bad += 1
        print(f"MISMATCH {name}({lit})\n   python: {expected}\n   asm:    {got}")
        if bad >= 12:
            print("too many mismatches"); sys.exit(1)

# cases the random runs found once: always checked
REGRESSIONS = [
    # the numbers of the rules past 2^62 (python's ints)
    ('mask_shl', 246, 5, 0, ('or', ('add', 'callvalue', 128, 255), ('add', ('storage', 256, 0, 5), 'undefined', ('var', '_2'), 2**160 - 1))),
    ('mask_shl', 2**70, 5, 0, ('add', 2**200 + 31, 'x')),
    ('mask_shl', 8, 2**62 + 5, -(2**62 + 5), ('cd', 4)),
    ('mask_shl', 8, 2**100, -(2**100), ('cd', 4)),
    # try_add's normalization of a mul whose coefficient isn't a number:
    # python's TypeError (num + 2**shl)
    ('lt', ('add', ('eq', ('and', 94964689875931252764577357350500699986261382086959835359635458281304267982331, 255), 'x'), ('var', '_1')), ('add', ('mul', ('or', ('var', '_2'), 0), ('mask_shl', 246, 5, 5, -1)), ('eq', ('iszero', ('var', '_1')), ('bool', 128)))),
    # the and-rule evaluates both sides before looking at either: the
    # second's TypeError (an add of four numbers) comes though the first
    # is a number
    ('and', ('div', 65, 1), ('data', ('add', 100, 0, 45833578640591742834686142070926924475193944920031094018015728496520947210164, -1))),
]

if __name__ == "__main__":
    for e in REGRESSIONS:
        check("simplify_exp", e, run(S.simplify_exp, e))
    for n in range(N):
        e = rexp()
        check("simplify_exp", e, run(S.simplify_exp, e))
        check("simplify_mask", e, run(S.simplify_mask, e))
        if isinstance(e, tuple) and e[0] == "mask_shl":
            check("cleanup_mask_data", e, run(S.cleanup_mask_data, e))
        check("canonise_max", e, run(S.canonise_max, e))
        check("sizeof", e, run(S.sizeof, e))
    print(f"{cases} cases, {bad} mismatches")
    sys.exit(1 if bad else 0)
