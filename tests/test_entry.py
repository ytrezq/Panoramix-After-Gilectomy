#!/usr/bin/env python3
"""Differential test of the loader's entry functions (entry.s) against
panoramix.loader: is_dispatch, selector_test, reverts, strip_markers,
entry_paths, apply_entry, entry_known, common_entry - on random traces
shaped like a dispatcher's.

    tests/test_entry.py [SEED [COUNT]]
"""
import os, random, sys
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "panoramix")))
sys.path.insert(0, os.environ.get("PANASM_BUILD") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import logging; logging.disable(logging.CRITICAL)
import panoramix_asm as A
from panoramix import loader as L
from panoramix.core.arithmetic import is_zero

random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 1)
N = int(sys.argv[2]) if len(sys.argv) > 2 else 500

SEL = [("mask_shl", 32, 224, -224, ("cd", 0)), ("cd", 0), ("div", ("cd", 0), 2**224), ("mask_shl", 256, -224, -224, ("cd", 0))]

def rhash():
    return random.choice([0x70a08231, 0xa9059cbb, 0xffffffff, 0, 1, 2**32, 2**40, -5, random.getrandbits(32)])

def rcond():
    sel = random.choice(SEL)
    h = rhash()
    r = random.random()
    if r < 0.2: c = ("eq", h, sel) if random.random() < 0.5 else ("eq", sel, h)
    elif r < 0.3: c = ("xor", h, sel) if random.random() < 0.5 else ("xor", sel, h)
    elif r < 0.4: c = ("add", -h, sel) if random.random() < 0.5 else ("add", h, ("mul", -1, sel))
    elif r < 0.5: c = (random.choice(["gt", "lt"]), h, sel)
    elif r < 0.6: c = random.choice([("lt", "calldatasize", 4), ("gt", "calldatasize", 3), ("iszero", ("lt", "calldatasize", 4)), ("bool", "calldatasize"), ("lt", "calldatasize", 5), ("le", 4, "calldatasize")])
    elif r < 0.7: c = random.choice(["callvalue", ("iszero", "callvalue"), ("eq", "address", 1234), ("lt", ("cd", 4), 2**160)])
    elif r < 0.8: c = (random.choice(["and", "or"]),) + tuple(rcond() for _ in range(random.randint(2, 3)))
    elif r < 0.85: c = ("add", h, sel)
    elif r < 0.9: c = ("eq", "('cd', 0)", h)
    else: c = ("sub", h, sel)
    for _ in range(random.choice([0, 0, 0, 1, 2])):
        c = ("iszero", c)
    return c

def rline():
    r = random.random()
    if r < 0.2: return "?"
    if r < 0.3: return ("jd", str(random.choice([175, 1088, 243, 0])), random.choice([(), (("mask_shl", 32, 224, -224, ("cd", 0)),)]))
    if r < 0.55: return ("setmem", ("range", random.choice([64, 0, 32]), 32), random.choice([96, 128, ("cd", 4), "caller"]))
    if r < 0.6: return ("setvar", "_1", ("cd", 4))
    return random.choice([("callvalue",), ("store", 256, 0, 1, 2)])

def rtrace(d=0):
    t = [rline() for _ in range(random.randint(0, 3))]
    r = random.random()
    if d < 4 and r < 0.45:
        t.append(("if", rcond(), rtrace(d + 1), rtrace(d + 1)))
    elif r < 0.6:
        t.append(("funccall", rhash(), random.choice([175, 411, 553]), random.choice([(), (("mask_shl", 32, 224, -224, ("cd", 0)),)])))
    elif r < 0.75:
        t.append(random.choice([("revert", None), ("invalid",), ("revert", ("mem", ("range", 0, 4)))]))
    elif r < 0.85:
        t.append(random.choice([("stop",), ("return", ("mem", ("range", 0, 32)))]))
    if random.random() < 0.1 and t:
        t.insert(0, ("funccall", rhash(), 9, ()))
    return t

cases = bad = 0
def check(name, args, expected):
    global cases, bad
    cases += 1
    lit = repr((name,) + tuple(args))
    try:
        got = A._test("entry_helper", lit)
    except Exception as e:
        got = "<asm exc %s>" % e
    if expected != got and not expected.startswith("<exc"):
        bad += 1
        print(f"MISMATCH {name}{tuple(args)!r}\n   python: {expected}\n   asm:    {got}", flush=True)
        if bad >= 12:
            print("too many mismatches"); sys.exit(1)

def run(fn, *args):
    try:
        return repr(fn(*args))
    except Exception as e:
        return "<exc %s: %s>" % (type(e).__name__, e)

for n in range(N):
    c = rcond()
    check("is_dispatch", (c,), run(L.is_dispatch, c))
    check("selector_test", (c,), run(L.selector_test, c))
    t = rtrace()
    check("reverts", (t,), run(L.reverts, t))
    check("strip_markers", (t,), run(L.strip_markers, t))
    paths = run(lambda: list(L.entry_paths(t, lambda line: L.opcode(line) == "funccall")))
    check("entry_paths", (t, 0, None), paths)
    target = random.choice(["175", "1088", "0"])
    check("entry_paths", (t, 1, target), run(lambda: list(L.entry_paths(t, lambda line: L.opcode(line) == "jd" and line[1] == target))))
    entries = [e for e, _ in L.entry_paths(t, lambda line: L.opcode(line) == "funccall")]
    for e in entries[:3]:
        check("apply_entry", (e, [("stop",)]), run(L.apply_entry, e, [("stop",)]))
        check("entry_known", (e,), run(L.entry_known, e))
    check("common_entry", (tuple(entries),), run(L.common_entry, entries))
    if entries:
        two = (entries[0], entries[0][: random.randint(0, len(entries[0]))])
        check("common_entry", (two,), run(L.common_entry, list(two)))

print(f"{cases} cases, {bad} mismatches")
sys.exit(1 if bad else 0)
