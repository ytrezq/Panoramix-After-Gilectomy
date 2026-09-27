#!/usr/bin/env python3
"""Differential tests of simplify_exp.s against panoramix.simplify."""
import os, random, sys
sys.path.insert(0, "/home/claude/panoramix")
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import logging; logging.disable(logging.CRITICAL)
import panoramix_asm as A
from panoramix import simplify as S
from test_memloc import rval, rint, rpos, ATOMS, run

random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 1)
N = int(sys.argv[2]) if len(sys.argv) > 2 else 300

def rexp(depth=0):
    r = random.random()
    if depth > 2 or r < 0.3: return rint() if random.random() < 0.4 else random.choice(ATOMS)
    op = random.choice(["mask_shl", "mask_shl", "and", "iszero", "bool", "eq", "mod", "add", "mul", "div", "max", "mem", "or", "data", "lt", "cd", "storage", "exp"])
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

if __name__ == "__main__":
    for n in range(N):
        e = rexp()
        check("simplify_exp", e, run(S.simplify_exp, e))
        check("simplify_mask", e, run(S.simplify_mask, e))
        if isinstance(e, tuple) and e[0] == "mask_shl":
            check("cleanup_mask_data", e, run(S.cleanup_mask_data, e))
        check("canonise_max", e, run(S.canonise_max, e))
        check("sizeof_s", e, run(S.sizeof, e))
    print(f"{cases} cases, {bad} mismatches")
    sys.exit(1 if bad else 0)
