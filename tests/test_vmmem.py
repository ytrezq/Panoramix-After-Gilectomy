#!/usr/bin/env python3
"""Differential test of the VM's memory model and path helpers (vmmem.s)
against panoramix.vm: mask_value, read_memory, write_memory, known_zeroes,
forget, upper_bound, known_bounds, bound, write_range, and_op, decided,
switch_values, entry_memory, is_known - on random facts.

    tests/test_vmmem.py [SEED [COUNT]]
"""
import ast, os, random, sys
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "panoramix")))
sys.path.insert(0, os.environ.get("PANASM_BUILD") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import logging; logging.disable(logging.CRITICAL)
import panoramix_asm as A
from panoramix import vm as V
from panoramix.core.arithmetic import VOLATILE

random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 1)
N = int(sys.argv[2]) if len(sys.argv) > 2 else 500

VARS = [("var", "_1"), ("var", "_2"), ("var", 1001), ("cd", 4), ("cd", 36), "calldatasize", "returndatasize",
        ("storage", 256, 0, 1), ("tload", 5), ("var", "_3")]

def rint():
    r = random.random()
    if r < 0.6: return random.choice([0, 1, 2, 3, 4, 8, 31, 32, 33, 36, 63, 64, 65, 96, 100, 128, 160, 224, 255, 256, 1000, 2**64, 2**128 - 1, 2**128, 2**255, 2**256 - 1])
    if r < 0.9: return random.randint(0, 300)
    return random.getrandbits(random.randint(1, 256))

def rexp(d=0):
    r = random.random()
    if d > 2 or r < 0.35: return rint() if random.random() < 0.4 else random.choice(VARS)
    op = random.choice(["add", "mul", "mask_shl", "exp", "sub", "and", "or", "min", "mod", "div", "iszero", "lt", "eq", "mem", "bool"])
    if op == "add": return ("add",) + tuple(rexp(d + 1) for _ in range(random.randint(2, 3)))
    if op == "mul": return ("mul", random.choice([1, 2, 32, 64, rexp(d + 1)]), rexp(d + 1))
    if op == "mask_shl":
        return ("mask_shl", random.choice([1, 2, 3, 8, 16, 160, 256, 9]), random.choice([0, 0, 3, 8, 224]),
                random.choice([0, 0, 5, -3, -224, 64, 70]), rexp(d + 1))
    if op == "exp": return ("exp", random.choice([2, 256, rexp(d + 1)]), rexp(d + 1))
    if op == "mem": return ("mem", ("range", random.choice([0, 32, 64, 96, 0x80, rexp(d + 1)]), random.choice([32, 32, 4, rexp(d + 1)])))
    if op in ("iszero", "bool"): return (op, rexp(d + 1))
    if op == "min": return ("min", rexp(d + 1), random.choice(["returndatasize", rint()]))
    if op == "mod": return ("mod", rexp(d + 1), random.choice([2, 3, 4, 256, 257, 1, rexp(d + 1)]))
    return (op, rexp(d + 1), rexp(d + 1))

def rcond():
    v = random.choice(VARS + VARS[:3] * 2 + [rexp(1)])
    n = rint() if random.random() < 0.9 else random.choice([-1, 2**256, True])
    op = random.choice(["lt", "le", "gt", "ge", "eq", "slt", "ne"])
    f = (op, v, n) if random.random() < 0.6 else (op, n, v)
    if random.random() < 0.15: f = (op, v, rexp(1))
    for _ in range(random.choice([0, 0, 0, 1, 1, 2])):
        f = ("iszero", f)
    return f

def rvalue():
    r = random.random()
    if r < 0.4: return rint()
    if r < 0.5: return None
    if r < 0.6: return ("mem", ("range", random.choice([0, 32, 64, 0x80, 0x90]), 32))
    return rexp(1)

def rmemfact():
    start = random.choice([0, 4, 28, 32, 60, 64, 0x80, 0x90, 0xa0, random.randint(0, 300), 2**200])
    size = random.choice([1, 32, 32, 32, 4, 20, random.randint(1, 70)])
    v = rvalue()
    if size not in (1, 32) and not (type(v) is int and size < 32): v = None
    return ("memory", start, size, v)

def rknown():
    k = [("memory_fresh",)] if random.random() < 0.3 else []
    for _ in range(random.randint(0, 7)):
        r = random.random()
        if r < 0.4: k.append(rmemfact())
        elif r < 0.5: k.append(("memory_fresh",))
        elif r < 0.6: k.append(("var_bits", random.choice(VARS[:3]), random.choice([0, 8, 32, 64, 128, 7])))
        elif r < 0.65: k.append(("returndatasize_zero",))
        else: k.append(rcond())
    return tuple(k)

def rstart():
    r = random.random()
    if r < 0.5: return random.choice([0, 4, 28, 32, 36, 64, 0x80, 0x90, 0xa0, random.randint(0, 300)])
    if r < 0.6: return random.choice(VARS)
    if r < 0.8: return ("add", random.choice([0x80, 0xa0, 4, 2**128, -32]), random.choice([("mul", 32, random.choice(VARS[:3])), ("mask_shl", 251, 0, 5, ("cd", 4)), ("mask_shl", 8, 0, -3, ("cd", 4)), ("mask_shl", 8, 0, 64, ("cd", 4)), random.choice(VARS)]))
    return rexp(1)

def rsize():
    r = random.random()
    if r < 0.6: return random.choice([0, 1, 32, 32, 4, 20, 64, 100, random.randint(0, 200), 2**130])
    if r < 0.8: return random.choice(VARS)
    if r < 0.9: return ("min", random.choice([32, 64, ("cd", 4)]), "returndatasize")
    return rexp(1)

cases = bad = 0
def check(name, args, expected):
    global cases, bad
    cases += 1
    lit = repr((name,) + tuple(args))
    try:
        got = A._test("vm_helper", lit)
    except Exception as e:
        got = "<asm exc %s>" % e
    if callable(expected):
        ok, expected = expected(got)
    else:
        ok = expected == got
    if not ok and not expected.startswith("<exc"):
        bad += 1
        print(f"MISMATCH {name}{tuple(args)!r}\n   python: {expected}\n   asm:    {got}", flush=True)
        if bad >= 12:
            print("too many mismatches"); sys.exit(1)

def run(fn, *args):
    try:
        return repr(fn(*args))
    except Exception as e:
        return "<exc %s: %s>" % (type(e).__name__, e)

def as_dict_cmp(py):
    def f(got):
        try:
            g = sorted(map(repr, ast.literal_eval(got)))
        except Exception:
            return False, repr(py)
        e = sorted(repr((k, v)) for k, v in py.items())
        return g == e, repr(e)
    return f

NAMES = {0: VOLATILE, 1: ("storage",), 2: ("tload",)}

for n in range(N):
    known = rknown()
    # mask_value
    val = rvalue() if random.random() < 0.8 else rint()
    if val is not None:
        size, off, shl = random.choice([(256, 0, 0), (8, 0, 0), (8, 8, -8), (16, 240, -16), (24, 0, 232), (32, 224, 0), (256, 0, 8)])
        check("mask_value", (val, size, off, shl), run(V.mask_value, val, size, off, shl))
    # read_memory
    addr = random.choice([0, 4, 28, 32, 64, 0x80, 0x90, 0xa0, random.randint(0, 300), ("cd", 4), True, 2**200])
    check("read_memory", (known, addr), run(V.read_memory, known, addr))
    # write_memory
    rng = ("range", rstart(), rsize())
    v = rvalue()
    if v is None: v = random.choice([5, ("cd", 4)])
    check("write_memory", (known, rng, v), run(V.write_memory, known, rng, v))
    # known_zeroes
    # (up to MAX_ZEROES_SIZE bytes: past it, not known)
    st, sz = random.choice([0, 32, 64, 0x80, 0x90, ("cd", 4)]), random.choice([0, 1, 32, 64, 96, 4, -1, 2**16, 2**16 + 1, 2**130, ("cd", 4)])
    check("known_zeroes", (known, st, sz), run(V.known_zeroes, known, st, sz))
    # forget
    kind = random.choice([0, 1, 2])
    check("forget", (known, kind), run(V.forget, known, NAMES[kind]))
    # upper_bound, bound
    x = random.choice(VARS + [rexp(1), ("min", random.choice(VARS), random.choice([32, ("cd", 4), -5, 2**200]))])
    # (a bool as a bound - n of ('ge', True, x) - is only ever added to
    # numbers: the int it is)
    unbool = lambda f: lambda *a: (lambda r: int(r) if type(r) is bool else r)(f(*a))
    check("upper_bound", (x, known), run(unbool(V.upper_bound), x, known))
    check("bound", (x, known), run(unbool(V.bound), x, known))
    # known_bounds
    try:
        kb = V.known_bounds(known)
        check("known_bounds", (known,), as_dict_cmp(kb))
    except Exception:
        pass
    # write_range
    s0, s1 = rstart(), rsize()
    try:
        wr = V.write_range(known, s0, s1)
        exp = repr("float") if wr and any(type(e) is float for e in wr) else repr(wr)
    except Exception as e:
        exp = "<exc %s>" % e
    check("write_range", (known, s0, s1), exp)
    # and_op
    l = random.choice([rexp(1), ("sub", ("exp", 256, random.choice(VARS)), 1), ("sub", ("exp", 2, ("mul", 8, random.choice(VARS))), 1), 2**160 - 1, rint()])
    r = random.choice([rexp(1), random.choice(VARS), rint()])
    if random.random() < 0.5: l, r = r, l
    check("and_op", (l, r, known), run(V.and_op, l, r, known))
    # decided, is_known
    e = random.choice([rexp(1), rcond(), random.choice(VARS), rint(), known[-1] if known else 3])
    check("decided", (e, known), run(V.decided, e, known))
    check("is_known", (e, known), run(V.is_known, e, known))
    # switch_values
    sw = random.choice([rexp(1), ("add", 5, ("mod", ("cd", 4), random.choice([2, 3, 4, 256, 257]))), ("mask_shl", random.choice([1, 2, 8, 9]), random.choice([0, 1, 5]), random.choice([0, 3, -1, -9]), ("cd", 4))])
    try:
        res = V.switch_values(sw)
        exp = repr(None if res is None else (res[0], tuple(res[1])))
    except Exception as ex:
        exp = "<exc %s>" % ex
    check("switch_values", (sw,), exp)
    # entry_memory
    entries = None if random.random() < 0.1 else [
        tuple(("setmem", ("range", rstart(), rsize()), random.choice([rvalue() or 5, 0x80, ("cd", 4)])) if random.random() < 0.8 else ("check", rcond(), True, (("revert", None),))
              for _ in range(random.randint(0, 4)))
        for _ in range(random.randint(0, 3))]
    check("entry_memory", (entries,), run(V.entry_memory, entries))

print(f"{cases} cases, {bad} mismatches")
sys.exit(1 if bad else 0)
