#!/usr/bin/env python3
"""Random differential tests of the algebra against panoramix.core.algebra."""
import os, random, sys
sys.path.insert(0, "/home/claude/panoramix")
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import logging; logging.disable(logging.CRITICAL)
import panoramix_asm as A
from panoramix.core import algebra as P
from panoramix.core.algebra import CannotCompare

random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 1)
N = int(sys.argv[2]) if len(sys.argv) > 2 else 500

def rint():
    r = random.random()
    if r < 0.6: return random.choice([0, 1, 2, 3, 4, 5, 8, 16, 31, 32, 64, 96, 128, 160, 224, 255, 256, 288, -1, -4, -32, -256, 2**160, 2**160 - 1, 2**255, 2**256 - 1])
    if r < 0.95: return random.randint(-300, 300)
    return random.randint(0, 2**256)

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
    ]
    for name, args, _ in tests:
        _args = args
        pyfn = getattr(P, name)
        try:
            r = pyfn(*args)
            if name in ("lt_op", "le_op", "ge_zero"):
                expected = tri(r)
            elif name == "get_sign":
                expected = "None" if r is None else repr(r)
            else:
                expected = repr(r)
        except CannotCompare:
            expected = "'CannotCompare'"
        except Exception as e:
            expected = "<exc %s>" % type(e).__name__
        lit = repr(args[0]) if len(args) == 1 and name in ("simplify", "calc_max", "max_to_add", "ge_zero", "get_sign") else repr(args)
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
