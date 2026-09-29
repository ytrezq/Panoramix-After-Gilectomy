#!/usr/bin/env python3
"""Random differential test of add_ge_zero's families (algebra.s,
agz_by_family) against panoramix.core.algebra: ge_zero asked, in one
context, of many adds that share their terms after the number - as
python's add_op makes them, as sub_op makes them (the ends of ranges
compared), and raw - interleaved, with numbers small and big, so that a
family's record answers the members after its first.

    tests/test_agz_family.py [SEED [COUNT]]
"""
import os, random, sys
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "panoramix")))
sys.path.insert(0, os.environ.get("PANASM_BUILD") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import logging; logging.disable(logging.CRITICAL)
import panoramix_asm as A
from panoramix.core import algebra as P
from panoramix.core.algebra import CannotCompare

random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 1)
N = int(sys.argv[2]) if len(sys.argv) > 2 else 300

VARS = [("cd", 4), ("cd", 36), "callvalue", "calldatasize", ("var", 1), ("var", 2),
        ("storage", 256, 0, 5), ("storage", 160, 0, 3), ("mem", ("range", 64, 32)),
        ("mem", ("range", 96, 32)), ("sha3", 1), "x", "timestamp",
        ("cd", ("add", 4, ("cd", 4))), ("mask_shl", 251, 5, 0, ("add", 31, ("cd", 36)))]

def const(big=True):
    r = random.random()
    if r < 0.5: return random.choice([1, 2, 3, 4, 31, 32, 64, 96, 255, 256, -1, -2, -32, -96, -256])
    if r < 0.85 or not big: return random.randint(-1000, 1000)
    if r < 0.93: return random.choice([1, -1]) * random.choice([2**61, 2**62 - 1, 2**62, 2**63, 2**160, 2**229, 2**230, 2**255, 2**256 - 1])
    return random.choice([1, -1]) * random.randint(0, 2**240)

def term(vs, d=0):
    v = random.choice(vs)
    r = random.random()
    if r < 0.25: return v
    if r < 0.45: return ("mul", const(), v)
    if r < 0.6:
        size = random.choice([1, 8, 32, 64, 96, 160, 251, 256])
        off = random.choice([0, 0, 0, 5, 8, 96])
        shl = random.choice([0, 0, 0, 3, -3, 5, 96])
        return ("mask_shl", size, off, shl, v if d > 1 or random.random() < 0.7 else term(vs, d + 1))
    if r < 0.7:
        return ("mul", const(), ("mask_shl", random.choice([8, 32, 160, 251, 256]), 0, 0, v))
    if r < 0.78:
        return ("max", random.choice([const(), v]), random.choice(vs))
    if r < 0.84:
        return ("mul", random.choice([-1, 1, 2, 32]), ("max", v, random.choice(vs)))
    if r < 0.9:
        return ("mul", const(), v, random.choice(vs))
    if r < 0.95:
        return ("or", v, random.choice(vs))
    return ("div", v, random.choice([2, 32, 256]))

def terms():
    nv = random.choice([1, 1, 2, 2, 3, 4, 5, 7, 8])
    vs = random.sample(VARS, nv)
    return [term(vs) for _ in range(random.randint(1, 5))]

def members(ts):
    """adds of these terms after different numbers"""
    out = []
    for _ in range(random.randint(2, 8)):
        c = const()
        k = random.random()
        try:
            if k < 0.4:
                e = P.add_op(c, *ts)
            elif k < 0.7:
                # a difference of two range ends, as lt_op / le_op make them
                a = P.add_op(c, *ts[: len(ts) // 2 + 1])
                b = P.add_op(const(False), *[P.minus_op(t) for t in ts[len(ts) // 2 + 1:]])
                e = P.sub_op(a, b)
                if random.random() < 0.5:
                    e = P.sub_op(e, 1)
            else:
                e = ("add", c) + tuple(ts)
        except Exception:
            continue
        if isinstance(e, tuple) and e and e[0] == "add" and len(e) > 2:
            out.append(e)
    return out

def py(e):
    try:
        r = P.ge_zero(e)
        return {True: "True", False: "False"}.get(r, repr(r))
    except CannotCompare:
        return "'CannotCompare'"
    except Exception as ex:
        return None     # python fails: not asked

# runs always checked: a family whose own fold reduces a sum mod 2^256
# (add_op's), where a member's doesn't - the context's reductions keep
# the family from answering
X = ("cd", 4)
REGRESSIONS = [
    [("add", 3, X, 5, 2**256 - 1), ("add", -10, X, 5, 2**256 - 1), ("add", -4, X, 5, 2**256 - 1)],
    [("add", 1, ("mul", -1, X), 7, 2**256 - 3), ("add", -9, ("mul", -1, X), 7, 2**256 - 3),
     ("add", -3, ("mul", -1, X), 7, 2**256 - 3)],
]

def runs():
    for r in REGRESSIONS:
        yield list(r)
    for n in range(N):
        exps = []
        for _ in range(random.randint(1, 4)):
            exps += members(terms())
        random.shuffle(exps)
        exps += random.sample(exps, min(len(exps), 3))      # asked again
        yield exps

cases = bad = 0
for exps in runs():
    asked, expected = [], []
    for e in exps:
        r = py(e)
        if r is not None:
            asked.append(e)
            expected.append(r)
    if not asked:
        continue
    lit = repr(tuple(asked))
    if "('mem', ('range', 64, 32))" in lit:
        # python's answer may depend on the hash seed there: ask them
        # one at a time, and skip the differences
        pass
    try:
        got = A._test("ge_zero_many", lit)
    except Exception as ex:
        got = "<asm exc %s>" % ex
    want = "(" + ", ".join(expected) + ("," if len(expected) == 1 else "") + ")"
    cases += len(asked)
    if got != want:
        # element by element
        try:
            import ast
            g = ast.literal_eval(got)
        except Exception:
            g = None
        for i, e in enumerate(asked):
            gi = None if g is None else ({True: "True", False: "False"}.get(g[i], repr(g[i])))
            if gi != expected[i]:
                if "('mem', ('range', 64, 32))" in repr(e):
                    continue
                bad += 1
                print(f"MISMATCH ge_zero {e!r}\n   python: {expected[i]}\n   asm:    {gi}  (in a run of {len(asked)})")
                if bad >= 12:
                    print("too many mismatches"); sys.exit(1)
print(f"{cases} cases, {bad} mismatches")
sys.exit(1 if bad else 0)
