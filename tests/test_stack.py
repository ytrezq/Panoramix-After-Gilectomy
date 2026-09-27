#!/usr/bin/env python3
"""Differential tests of masks.s / stack.s against panoramix.core.masks and
panoramix.stack."""
import os, random, sys
sys.path.insert(0, "/home/claude/panoramix")
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import logging; logging.disable(logging.CRITICAL)
import panoramix_asm as A
from panoramix.core import masks as M
from panoramix.stack import Stack, fold_stacks

random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 1)
N = int(sys.argv[2]) if len(sys.argv) > 2 else 300

def rint():
    r = random.random()
    if r < 0.5: return random.choice([0, 1, 2, 3, 4, 8, 16, 31, 32, 64, 96, 128, 160, 224, 255, 256, 288, -1, -4, -32, -256, 2**160, 2**160 - 1, 2**255, 2**256 - 1, 2**256 - 2**96, 2**96 - 1, 2**8 - 1, (2**160 - 1) << 96, 2**256 - 1 - ((2**160 - 1) << 96)])
    if r < 0.8: return random.randint(-300, 300)
    if r < 0.9: return random.getrandbits(random.randint(1, 256))
    return random.randint(0, 2**256)

ATOMS = [("cd", 4), ("cd", 36), "callvalue", ("var", 1), ("storage", 256, 0, 5), ("mem", ("range", 64, 32)), ("sha3", 1), "x"]

def rexp(depth=0):
    r = random.random()
    if depth > 2 or r < 0.3: return rint() if random.random() < 0.5 else random.choice(ATOMS)
    op = random.choice(["add", "mul", "and", "and", "div", "not", "sub", "exp", "lt", "iszero", "bool", "or", "eq", "gt", "mask_shl"])
    if op == "add": return ("add", rexp(depth + 1), rexp(depth + 1))
    if op == "sub": return ("sub", rexp(depth + 1), random.choice([1, rexp(depth + 1)]))
    if op == "exp": return ("exp", random.choice([2, 2, 256, 10, rexp(depth + 1)]), random.choice([8, 96, 160, 255, rexp(depth + 1)]))
    if op == "mul": return ("mul", random.choice([2**random.randint(0, 255), rexp(depth + 1)]), rexp(depth + 1))
    if op == "div": return ("div", rexp(depth + 1), random.choice([2**random.randint(0, 255), rexp(depth + 1)]))
    if op in ("not", "iszero", "bool"): return (op, rexp(depth + 1))
    if op == "mask_shl": return ("mask_shl", random.choice([8, 32, 160, 256]), random.choice([0, 8, 96]), random.choice([0, 5, -5]), rexp(depth + 1))
    return (op, rexp(depth + 1), rexp(depth + 1))

def run(fn, *args):
    try:
        return repr(fn(*args))
    except Exception as e:
        return "<exc %s: %s>" % (type(e).__name__, e)

cases = bad = 0
def check(name, lit, expected):
    global cases, bad
    cases += 1
    try:
        got = A._test(name, lit)
    except Exception as e:
        got = "<asm exc %s>" % e
    if expected != got and not expected.startswith("<exc"):
        bad += 1
        print(f"MISMATCH {name}({lit})\n   python: {expected}\n   asm:    {got}")
        if bad >= 12:
            print("too many mismatches"); sys.exit(1)

for n in range(N):
    a = rexp()
    check("to_mask", repr(a), run(M.to_mask, a))
    check("to_neg_mask", repr(a), run(M.to_neg_mask, a))
    check("stack_simplify", repr(a), run(Stack.simplify, a))
    # cleanup on a random stack
    st = [rexp() for _ in range(random.randint(0, 5))]
    st += random.sample([("lt", rint(), rint()), ("iszero", rint()), ("iszero", ("bool", random.choice([0, 1]))), ("iszero", ("iszero", a)), ("iszero", ("iszero", ("lt", a, 5)))], random.randint(0, 4))
    s = Stack(list(st))
    s.cleanup()
    check("stack_cleanup", repr(tuple(st)), repr(tuple(s.stack)))
    # fold
    first = [rexp() for _ in range(random.randint(0, 6))]
    second = [e if random.random() < 0.6 else rexp() for e in first]
    depth = random.randint(0, 3)
    f, v = fold_stacks(first, second, depth)
    check("fold_stacks", repr((tuple(first), tuple(second), depth)), repr((tuple(f), tuple(v))))
print(f"{cases} cases, {bad} mismatches")
sys.exit(1 if bad else 0)
