#!/usr/bin/env python3
"""Random differential tests of the arithmetic layer against panoramix."""
import os, random, sys
sys.path.insert(0, "/home/claude/panoramix")
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import logging; logging.disable(logging.CRITICAL)
import panoramix_asm as A
from panoramix.core import arithmetic as P

M = 2**256
random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 1)

def rint():
    r = random.random()
    if r < 0.2: return random.randint(0, 300)
    if r < 0.3: return random.randint(-300, 0)
    if r < 0.5: return random.randint(0, 2**64)
    if r < 0.6: return 2**random.randint(0, 256) - random.randint(0, 1)
    if r < 0.7: return M - random.randint(0, 1000)
    if r < 0.8: return random.randint(0, M - 1)
    if r < 0.9: return random.randint(0, 2**62 + 5)
    return random.choice([0, 1, 2, 31, 32, 255, 256, 2**62, 2**62 - 1, -2**62, M - 1, 2**255, 2**255 - 1])

def rsym():
    return random.choice([("cd", 4), ("cd", 36), "callvalue", ("var", 1), ("storage", 256, 0, 5), ("mem", ("range", 64, 32)), ("bool", ("cd", 4)), ("eq", ("cd", 4), 3)])

def rarg(depth=0):
    r = random.random()
    if r < 0.6 or depth > 2: return rint()
    if r < 0.8: return rsym()
    return rexp(depth + 1)

BIN = ["add", "sub", "mul", "div", "sdiv", "mod", "smod", "exp", "signextend", "shl", "shr", "sar", "and", "or", "xor", "byte", "eq", "lt", "gt", "le", "ge", "slt", "sgt", "sle", "sge"]

def rexp(depth=0):
    op = random.choice(BIN + ["not", "addmod", "mulmod", "and", "iszero", "bool", "mask_shl"])
    if op == "not": return ("not", rarg(depth))
    if op in ("addmod", "mulmod"): return (op, rarg(depth), rarg(depth), rarg(depth))
    if op == "iszero": return ("iszero", rarg(depth))
    if op == "bool": return ("bool", rarg(depth))
    if op == "mask_shl": return ("mask_shl", rint(), rint(), rint(), rarg(depth))
    if op == "and" and random.random() < 0.3: return ("and", rarg(depth), rarg(depth), rarg(depth))
    return (op, rarg(depth), rarg(depth))

def norm(v):
    # python bools print as True/False in repr, ints as ints: our side does the same
    return repr(v)

def check(name, pyfn, asfn, arg, n):
    try:
        expected = norm(pyfn(arg))
    except Exception as e:
        expected = "<exc %s>" % type(e).__name__
    got = asfn(arg)
    if expected != got and not expected.startswith("<exc"):
        print(f"MISMATCH {name} #{n}: {arg!r}\n   python: {expected}\n   asm:    {got}")
        return 1
    return 0

bad = 0
N = int(sys.argv[2]) if len(sys.argv) > 2 else 3000
for n in range(N):
    e = rexp()
    bad += check("eval", P.eval, lambda a: A._test("eval", repr(a)), e, n)
    bad += check("is_zero", P.is_zero, lambda a: A._test("is_zero", repr(a)), e, n)
    bad += check("simplify_bool", P.simplify_bool, lambda a: A._test("simplify_bool", repr(a)), e, n)
    x = rint()
    bad += check("to_real_int", P.to_real_int, lambda a: A._test("to_real_int", repr(a)), x, n)
    if bad > 10:
        break
print("mismatches:", bad)
