#!/usr/bin/env python3
"""Random differential test of the pattern matcher (matcher.s) against
panoramix.matcher: patterns made from random expressions (subtrees
replaced with wildcards, typed or not, names repeated, 'Any', '...'),
matched against the expression and against others; through the
runtime reading of the wildcards ("match") and through the compiled
patterns the PAT literals are made into ("match_compiled").

    tests/test_matcher.py [SEED [COUNT]]
"""
import os, random, sys
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "panoramix")))
sys.path.insert(0, os.environ.get("PANASM_BUILD") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import logging; logging.disable(logging.CRITICAL)
import panoramix_asm as A
from panoramix.matcher import match, Any

random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 1)
N = int(sys.argv[2]) if len(sys.argv) > 2 else 2000

def rexp(d=0):
    r = random.random()
    if d > 2 or r < 0.3:
        return random.choice([0, 1, 5, 32, 2**200, -3, "x", "callvalue", "mem", ("var", 1)])
    op = random.choice(["add", "mul", "mask_shl", "mem", "cd", "storage"])
    n = random.randint(1, 4)
    return (op,) + tuple(rexp(d + 1) for _ in range(n))

NAMES = ["a", "b", "c", "val", "size"]
TYPES = ["", "int:", "str:", "tuple:", "list:"]

def rpat(e, d=0):
    r = random.random()
    if r < 0.25:
        return ":" + random.choice(TYPES) + random.choice(NAMES)
    if r < 0.3:
        return "Any"
    if isinstance(e, tuple) and d < 3:
        els = [rpat(x, d + 1) for x in e]
        if len(els) > 1 and random.random() < 0.2:
            k = random.randint(1, len(els) - 1)
            els = els[:k] + ["..."]
        return tuple(els)
    return e

def to_py(p):
    """the pattern as python writes it: 'Any' -> Any, '...' -> Ellipsis"""
    if p == "Any": return Any
    if p == "...": return Ellipsis
    if isinstance(p, tuple): return tuple(to_py(x) for x in p)
    return p

def names_in_order(p, out):
    """the wildcards' names, in the order they are bound"""
    if isinstance(p, str) and p.startswith(":"):
        n = p[1:].split(":")[-1]
        if n not in out: out.append(n)
    elif isinstance(p, tuple):
        for x in p:
            if x == "...": break
            names_in_order(x, out)
    return out

cases = bad = 0
for n in range(N):
    e = rexp()
    p = rpat(e)
    for exp in (e, rexp()):
        m = match(exp, to_py(p))
        if m is None:
            expected = "None"
        else:
            expected = repr([getattr(m, k) for k in names_in_order(p, [])])
        lit = repr((exp, p))
        for hook in ("match", "match_compiled"):
            got = A._test(hook, lit)
            cases += 1
            if got != expected:
                bad += 1
                print(f"MISMATCH {hook}{lit}\n   python: {expected}\n   asm:    {got}")
                if bad > 10: sys.exit(1)
print(f"{cases} cases, {bad} mismatches")
sys.exit(1 if bad else 0)
