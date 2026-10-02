#!/usr/bin/env python3
"""Random differential tests of the algebra against panoramix.core.algebra."""
import os, random, sys
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "panoramix")))
sys.path.insert(0, os.environ.get("PANASM_BUILD") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import logging; logging.disable(logging.CRITICAL)
import panoramix_asm as A
from panoramix.core import algebra as P
from panoramix.core.algebra import CannotCompare

random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 1)
N = int(sys.argv[2]) if len(sys.argv) > 2 else 500

BIG = os.environ.get("BIG")     # BIG=1: the masks' numbers past 2^62 too (python's ints)

def rint():
    r = random.random()
    if r < 0.6: return random.choice([0, 1, 2, 3, 4, 5, 8, 16, 31, 32, 64, 96, 128, 160, 224, 255, 256, 288, -1, -4, -32, -256, 2**160, 2**160 - 1, 2**255, 2**256 - 1])
    if r < 0.95: return random.randint(-300, 300)
    return random.randint(0, 2**256)

def rbig():
    return random.choice([1, -1]) * random.choice([2**62, 2**62 - 1, 2**63 + 5, 2**64, 2**100 + 7, 2**255 + 255, 2**256 - 1])

ATOMS = [("cd", 4), ("cd", 36), ("cd", ("add", 4, ("cd", 4))), "callvalue", "calldatasize", ("var", 1), ("var", 2), ("storage", 256, 0, 5), ("storage", 160, 0, 3), ("mem", ("range", 64, 32)), ("mem", ("range", 96, 32)), ("sha3", 1), "x", ("ext_call.return_data", 0, 32)]

def ratom():
    return random.choice(ATOMS)

def rexp(depth=0):
    r = random.random()
    if depth > 2 or r < 0.3: return rint() if random.random() < 0.5 else ratom()
    op = random.choice(["add", "add", "mul", "mask_shl", "max", "or", "storage", "div"])
    if op == "add":
        n = random.randint(2, 4)
        return ("add",) + tuple(rexp(depth + 1) for _ in range(n))
    if op == "mul":
        return ("mul", rint(), rexp(depth + 1))
    if op == "mask_shl":
        if random.random() < 0.9:
            size = random.choice([1, 8, 32, 64, 96, 160, 224, 248, 251, 253, 255, 256])
            off = random.choice([0, 0, 0, 8, 32, 96, 160])
            shl = random.choice([0, 0, 0, 1, 3, 5, 32, 96, -3, -5, -32, -96])
            if BIG and random.random() < 0.3:
                k = random.randrange(3)
                if k == 0: off = rbig()
                elif k == 1: shl = rbig()
                else: off = shl = rbig()
            return ("mask_shl", size, off, shl, rexp(depth + 1))
        return ("mask_shl", rexp(depth + 1), rexp(depth + 1), rexp(depth + 1), rexp(depth + 1))
    if op == "max":
        return ("max",) + tuple(rexp(depth + 1) for _ in range(random.randint(2, 3)))
    if op == "or":
        return ("or",) + tuple(rexp(depth + 1) for _ in range(random.randint(2, 3)))
    if op == "storage":
        return ("storage", random.choice([256, 160, 8, 32]), random.choice([0, 0, 8, 160]), random.choice([5, ("map", 1, 2)]))
    return ("div", rexp(depth + 1), rint())

def run_py(fn, *args):
    try:
        return repr(fn(*args))
    except CannotCompare:
        return "'CannotCompare'"
    except Exception as e:
        return "<exc %s: %s>" % (type(e).__name__, e)

def tri(r):
    return {True: "True", False: "False", None: "None"}.get(r, repr(r))

import subprocess
SEED_PROG = """
import sys; sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "panoramix")))
import logging; logging.disable(logging.CRITICAL)
from panoramix.core import algebra as P
from panoramix.core.algebra import CannotCompare
name, args = %r, %r
def tri(r): return {True: "True", False: "False", None: "None"}.get(r, repr(r))
try:
    r = getattr(P, name)(*args)
    if name in ("lt_op", "le_op", "ge_zero"): print(tri(r))
    elif name == "get_sign": print("None" if r is None else repr(r))
    else: print(repr(r))
except CannotCompare: print("'CannotCompare'")
"""

def seed_results(name, args, seeds=range(1, 7)):
    """python's answer under several hash seeds (the variants enumeration
    depends on set order when ('mem', ('range', 64, 32)) is a variable)"""
    out = set()
    for sd in seeds:
        env = dict(os.environ, PYTHONHASHSEED=str(sd))
        try:
            r = subprocess.run([sys.executable, "-c", SEED_PROG % (name, args)], capture_output=True, text=True, env=env, timeout=120)
            out.add(r.stdout.strip())
        except Exception as e:
            out.add("<exc %s>" % e)
    return out

cases = 0
bad = 0
for n in range(N):
    a, b = rexp(), rexp()
    tests = [
        ("add_op", (a, b), lambda: run_py(P.add_op, a, b)),
        ("add_op", (a, b, rexp()), None),
        ("mul_op", (rint(), a), lambda: run_py(P.mul_op, *_args)),
        ("mul_op", (a, b), None),
        ("sub_op", (a, b), None),
        ("or_op", (a, b), None),
        ("mask_op", (a, random.choice([8, 32, 160, 256, 255, 251, ("cd", 4)]), random.choice([0, 0, 8, 96]), random.choice([0, 0, 5, -5, 96]), random.choice([0, 0, 0, 3])), None),
        ("div_op", (a, rint()), None),
        ("neg_mask_op", (a, random.choice([8, 32, 160]), random.choice([0, 8, 96])), None),
        ("simplify", (a,), None),
        ("calc_max", (a,), None),
        ("max_to_add", (("max", a, b),), None),
        ("lt_op", (a, b), None),
        ("le_op", (a, b), None),
        ("ge_zero", (a,), None),
        ("max_op", (a, b), None),
        ("min_op", (a, b), None),
        ("get_sign", (a,), None),
        ("lt_op_m", (a, b), None),
        ("le_op_m", (a, b), None),
        ("ge_zero_m", (a,), None),
        ("max_op_m", (a, b), None),
        ("min_op_m", (a, b), None),
        ("get_sign_m", (a,), None),
        ("shr_op", (a, random.choice([0, 3, 8, 96, 255, 256, 300, ("cd", 4)])), None),
        ("shl_op", (a, random.choice([0, 3, 8, 96, 255, 256, 300, ("cd", 4), ("add", 5, ("cd", 4)), ("mul", -1, ("cd", 4))])), None),
        ("signextend_op", (random.choice([0, 1, 3, 15, 30, 31, 32, -1, 2**256 - 1, ("cd", 4), True]), random.choice([a, rint(), ("signextend", random.choice([0, 1, 3, 31]), a), ("mask_shl", random.choice([8, 16, 32, 256]), random.choice([0, 0, 8, 16]), random.choice([0, -8, -16, 8]), a), ("storage", random.choice([8, 16, 64, 256]), random.choice([0, 8, -8]), 5)])), None),
        ("bits", (a,), None),
        ("to_bytes", (a,), None),
    ]
    for name, args, _ in tests:
        _args = args
        if name.endswith("_m"):
            # memloc's: top=MEMORY_TOP
            pyfn = (lambda f: (lambda *a: f(*a, top=P.MEMORY_TOP)))(getattr(P, name[:-2]))
        else:
            pyfn = getattr(P, name)
        try:
            r = pyfn(*args)
            if name in ("lt_op", "le_op", "ge_zero", "lt_op_m", "le_op_m", "ge_zero_m"):
                expected = tri(r)
            elif name in ("get_sign", "get_sign_m"):
                expected = "None" if r is None else repr(r)
            else:
                expected = repr(r)
        except CannotCompare:
            expected = "'CannotCompare'"
        except Exception as e:
            expected = "<exc %s>" % type(e).__name__
        lit = repr(args[0]) if len(args) == 1 and name in ("simplify", "calc_max", "max_to_add", "ge_zero", "get_sign", "ge_zero_m", "get_sign_m", "bits", "to_bytes") else repr(args)
        if os.environ.get('TRACE'): print('CALL', name, lit, flush=True)
        try:
            got = A._test(name, lit)
        except Exception as e:
            got = "<asm exc %s>" % e
        cases += 1
        if expected != got and not expected.startswith("<exc"):
            bad += 1
            print(f"MISMATCH {name}{args!r}\n   python: {expected}\n   asm:    {got}")
            if bad >= 12:
                print("too many mismatches"); sys.exit(1)
print(f"{cases} cases, {bad} mismatches")
sys.exit(1 if bad else 0)
