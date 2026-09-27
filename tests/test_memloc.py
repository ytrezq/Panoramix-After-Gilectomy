#!/usr/bin/env python3
"""Random differential tests of memloc.s against panoramix.core.memloc."""
import os, random, sys
sys.path.insert(0, "/home/claude/panoramix")
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import logging; logging.disable(logging.CRITICAL)
import panoramix_asm as A
from panoramix.core import memloc as M
from panoramix.core import algebra as AL
from panoramix.core.masks import find_mask

random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 1)
N = int(sys.argv[2]) if len(sys.argv) > 2 else 300

ATOMS = [("cd", 4), ("cd", 36), "callvalue", ("var", "_1"), ("var", "_2"), ("storage", 256, 0, 5), ("mem", ("range", 64, 32)), "x", "undefined", ("sha3", ("mem", ("range", 0, 64)))]

def rint(small=False):
    if small or random.random() < 0.7: return random.choice([0, 1, 2, 4, 8, 16, 20, 31, 32, 33, 64, 65, 96, 100, 128, 160, 192, 224, 248, 255, 256, 288, 320])
    return random.choice([-1, -8, -32, 2**160 - 1, 2**255, 2**256 - 1, random.randint(0, 2**256)])

def rpos():
    r = random.random()
    if r < 0.6: return rint(True)
    if r < 0.8: return random.choice(ATOMS)
    return ("add", rint(True), random.choice(ATOMS))

def rrange():
    return ("range", rpos(), random.choice([32, 32, 32, 4, 20, 64, 96, 1, 0, rpos()]))

def rval(depth=0):
    r = random.random()
    if depth > 1 or r < 0.4: return rint() if random.random() < 0.4 else random.choice(ATOMS)
    op = random.choice(["mask_shl", "mem", "or", "storage", "add", "call.data", "bool", "mul", "data"])
    if op == "mask_shl":
        return ("mask_shl", random.choice([8, 32, 64, 96, 160, 224, 248, 253, 256, ("mask_shl", 253, 0, 3, ("cd", 4))]), random.choice([0, 0, 8, 96, 160, 192]), random.choice([0, 0, -8, -96, 8, 96, 3, 5]), rval(depth + 1))
    if op == "mem": return ("mem", rrange())
    if op == "or": return ("or",) + tuple(rval(depth + 1) for _ in range(random.randint(2, 3)))
    if op == "storage": return ("storage", random.choice([256, 160, 8, 32]), random.choice([0, 0, 8, 160]), random.choice([5, ("map", 1, 2)]))
    if op == "add": return ("add", rint(True), rval(depth + 1))
    if op == "call.data": return (random.choice(["call.data", "ext_call.return_data"]), rpos(), rpos())
    if op == "bool": return ("bool", rval(depth + 1))
    if op == "mul": return ("mul", random.choice([1, 2, 8, 32, -1]), rval(depth + 1))
    return ("data", rval(depth + 1), rval(depth + 1))

def run(fn, *args):
    try:
        r = fn(*args)
        if r is None: return "None"
        if r is True: return "True"
        if r is False: return "False"
        return repr(r)
    except Exception as e:
        return "<exc %s: %s>" % (type(e).__name__, e)

cases = bad = 0
def check(name, args, expected, single=False):
    global cases, bad
    cases += 1
    lit = repr(args[0]) if single else repr(args)
    try:
        got = A._test(name, lit)
    except Exception as e:
        got = "<asm exc %s>" % e
    ok = expected == got or (expected.startswith("<exc") and got.startswith("'<exc")) or (expected.startswith("<exc") and got.startswith('"<exc'))
    if not ok:
        bad += 1
        print(f"MISMATCH {name}({lit})\n   python: {expected}\n   asm:    {got}")
        if bad >= 12:
            print("too many mismatches"); sys.exit(1)

if __name__ == "__main__":
  for n in range(N):
    v = rval()
    check("to_bytes", (v,), run(AL.to_bytes, v), True)
    check("divisible_bytes", (v,), run(AL.divisible_bytes, v), True)
    i = rint()
    if i >= 0: check("find_mask", (i,), run(find_mask, i), True)
    r1, r2 = rrange(), rrange()
    check("apply_mask_to_range", (r1, random.choice([8, 32, 160, 256, ("mask_shl", 253, 0, 3, ("cd", 4)), 5]), random.choice([0, 0, 96, 8, 3])), run(M.apply_mask_to_range, r1, *_[1:]) if False else None) if False else None
    size = random.choice([8, 32, 160, 256, ("mul", 8, ("cd", 4)), 5, ("mask_shl", 253, 0, 3, ("cd", 4))])
    off = random.choice([0, 0, 96, 8, 3])
    check("apply_mask_to_range", (r1, size, off), run(M.apply_mask_to_range, r1, size, off))
    check("split_or", (v,), run(M.split_or, v), True)
    check("sizeof", (v,), run(M.sizeof, v), True)
    line = ("setmem", r1, v)
    check("split_setmem", (line,), run(M.split_setmem, line), True)
    st = random.choice([("store", 256, 0, rint(True), v), ("store", 256, 0, rint(True), ("mask_shl", random.choice([8, 160, 255]), random.choice([0, 96]), 0, ("storage", 256, 0, 5))), ("store", 160, 0, 5, v)])
    check("split_store", (st,), run(M.split_store, st), True)
    check("memloc_overwrite", (r1, r2), run(M.memloc_overwrite, r1, r2))
    l, r = rpos(), rpos()
    check("slice_exp", (v, l, r), run(M.slice_exp, v, l, r))
    sv = random.choice([None, "b", rval()])
    check("splits_mem", (r1, r2, v, sv), run(M.splits_mem, r1, r2, v, sv))
    mem = ("mem", r1)
    check("fill_mem", (mem, r2, v), run(M.fill_mem, mem, r2, v))
    check("range_overlaps", (r1, r2), run(M.range_overlaps, r1, r2))
    check("range_contains", (r1, r2), run(M.range_contains, r1, r2))
  print(f"{cases} cases, {bad} mismatches")
  sys.exit(1 if bad else 0)
