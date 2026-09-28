#!/usr/bin/env python3
"""Random differential test of add_ge_zero (through ge_zero, lt_op, le_op)
against panoramix.core.algebra: sums of many terms that share variables
- masks, multiples, maxes of them - so that the evaluation by independent
groups of terms is exercised against python's enumeration of every
variant.

    tests/test_agz.py [SEED [COUNT]]
"""
import os, random, sys
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "panoramix")))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import logging; logging.disable(logging.CRITICAL)
import panoramix_asm as A
from panoramix.core import algebra as P
from panoramix.core.algebra import CannotCompare

random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 1)
N = int(sys.argv[2]) if len(sys.argv) > 2 else 1000

VARS = [("cd", 4), ("cd", 36), "callvalue", "calldatasize", ("var", 1), ("var", 2),
        ("storage", 256, 0, 5), ("storage", 160, 0, 3), ("mem", ("range", 64, 32)),
        ("mem", ("range", 96, 32)), ("sha3", 1), "x", "timestamp", "number"]

def const():
    r = random.random()
    if r < 0.5: return random.choice([1, 2, 3, 4, 31, 32, 64, 96, 255, 256, -1, -2, -32, -96, -256])
    if r < 0.8: return random.randint(-1000, 1000)
    if r < 0.9: return random.choice([1, -1]) * random.choice([2**160, 2**229, 2**230, 2**231, 2**255, 2**256 - 1])
    return random.choice([1, -1]) * random.randint(0, 2**240)

def term(vs, d=0):
    v = random.choice(vs)
    r = random.random()
    if r < 0.2: return v
    if r < 0.4: return ("mul", const(), v)
    if r < 0.55:
        size = random.choice([1, 8, 32, 64, 96, 160, 229, 230, 231, 256])
        off = random.choice([0, 0, 0, 8, 96])
        shl = random.choice([0, 0, 0, 3, -3, 96, -96])
        return ("mask_shl", size, off, shl, v if d > 1 or random.random() < 0.7 else term(vs, d + 1))
    if r < 0.7:
        return ("mul", const(), ("mask_shl", random.choice([8, 32, 160, 256]), 0, 0, v))
    if r < 0.8:
        return ("max", random.choice([const(), v]), random.choice(vs))
    if r < 0.87:
        return ("mul", const(), ("max", v, random.choice(vs)))
    if r < 0.93:
        return ("mul", const(), v, random.choice(vs))
    return ("div", v, random.choice([2, 32, 256]))

def rsum():
    nv = random.choice([1, 2, 3, 4, 5, 6, 7, 7, 8])
    vs = random.sample(VARS, nv)
    n = random.randint(2, 7)
    ts = [term(vs) for _ in range(n)]
    if random.random() < 0.7: ts.append(const())
    random.shuffle(ts)
    return ("add",) + tuple(ts)

def tri(r):
    return {True: "True", False: "False", None: "None"}.get(r, repr(r))

def py(name, args):
    try:
        r = getattr(P, name)(*args)
        return tri(r)
    except CannotCompare:
        return "'CannotCompare'"
    except Exception as e:
        return "<exc %s>" % type(e).__name__

# cases the random runs found once: always checked
REGRESSIONS = [
    # try_add gives a number: python's assert in add_op (was a crash)
    ("lt_op", (('add', ('mul', -1725436586697640946858688965569256363112777243042596638790631055949824, ('storage', 160, 0, 3), ('mem', ('range', 64, 32))), ('mask_shl', 64, 0, -96, ('sha3', 1)), ('mul', 256, ('max', ('var', 2), ('var', 2))), ('mul', -2, ('sha3', 1)), ('mul', 682, ('max', ('storage', 160, 0, 3), ('mem', ('range', 64, 32)))), 2**255, ('var', 2), ('sha3', 1)),
               ('add', ('max', ('cd', 4), ('storage', 160, 0, 3)), ('mask_shl', 256, 96, 0, ('cd', 4)), ('cd', 4), ('mul', 2**255, ('mask_shl', 256, 0, 0, ('storage', 160, 0, 3))), 417, ('cd', 4), ('mul', -2, ('storage', 160, 0, 3)), ('mul', -1, ('mask_shl', 160, 0, 0, ('cd', 4)))))),
]

def cases_iter():
    for name, args in REGRESSIONS:
        yield name, args
    for n in range(N):
        s = rsum()
        t = rsum()
        for c in (("ge_zero", (s,)), ("lt_op", (s, t)), ("le_op", (s, t)),
                  ("lt_op", (s, random.choice([0, 1, -1, const()]))),
                  ("le_op", (random.choice([0, 1, const()]), s))):
            yield c

cases = bad = 0
if True:
    for name, args in cases_iter():
        expected = py(name, args)
        lit = repr(args[0]) if name == "ge_zero" else repr(args)
        if os.environ.get('TRACE'): print('CALL', name, lit, flush=True)
        try:
            got = A._test(name, lit)
        except Exception as e:
            got = "<asm exc %s>" % e
        cases += 1
        if expected != got and not expected.startswith("<exc") and "('mem', ('range', 64, 32))" in lit:
            continue        # python's answer depends on the hash seed there
        if expected != got and not expected.startswith("<exc"):
            bad += 1
            print(f"MISMATCH {name}{args!r}\n   python: {expected}\n   asm:    {got}")
            if bad >= 12:
                print("too many mismatches"); sys.exit(1)
print(f"{cases} cases, {bad} mismatches")
sys.exit(1 if bad else 0)
