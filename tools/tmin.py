#!/usr/bin/env python3
"""Minimizes a difference between the port and python on one pass:

    tools/tmin.py PASS FILE [PYEXPR]

FILE holds the argument's python literal (a trace or an expression); PASS
is the name tests/test_simplify.py and the others give to A._test; PYEXPR
is the python function (default: S.<PASS>, S = panoramix.simplify). The
smallest argument found that still differs - with the same kind of
results: an exception or not on each side - is printed and written to
FILE.min.

The reductions, repeated until none applies: a list loses elements
(halves, then one at a time), a tuple is replaced by one of its elements
or by a small atom, a number by a smaller one.
"""
import ast, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tests"))
import test_simplify as T
from test_simplify import S, R, PP, run, same_modulo_max_order
from panoramix.utils.helpers import rewrite_trace, rewrite_trace_full
from panoramix.core.memloc import split_setmem, split_store
import panoramix_asm as A

name = sys.argv[1]
path = sys.argv[2]
fn = eval(sys.argv[3]) if len(sys.argv) > 3 else getattr(S, name)
arg0 = ast.literal_eval(open(path).read())

def results(a):
    exp = run(fn, a)
    try:
        got = A._test(name, repr(a))
    except Exception as e:
        got = "<asm exc %s>" % e
    return exp, got

def is_exc(r, asm):
    return r.startswith("'<exc") or r.startswith('"<exc') or r.startswith("<asm exc") if asm else r.startswith("<exc")

def differ(exp, got):
    if exp == got: return False
    if is_exc(exp, False) and is_exc(got, True): return False
    if "max" in exp and same_modulo_max_order(exp, got): return False
    return True

e0, g0 = results(arg0)
if not differ(e0, g0):
    print("no difference:", e0[:300]); sys.exit(1)
KIND = (is_exc(e0, False), is_exc(g0, True))

def bad(a):
    try:
        e, g = results(a)
    except RecursionError:
        return False
    return differ(e, g) and (is_exc(e, False), is_exc(g, True)) == KIND

ATOMS = [0, 1, 32, "x", ("var", 1)]

def candidates(a):
    """the arguments one step smaller than a, the biggest steps first"""
    if isinstance(a, list):
        n = len(a)
        k = n // 2
        while k >= 1:
            for i in range(0, n, k):
                yield a[:i] + a[i + k:]
            k //= 2
        for i, x in enumerate(a):
            for y in candidates(x):
                yield a[:i] + [y] + a[i + 1:]
    elif isinstance(a, tuple):
        for x in a[1:]:
            if isinstance(x, (tuple, int)) or (isinstance(x, str) and len(a) > 1):
                yield x
        for at in ATOMS:
            if at != a: yield at
        for i, x in enumerate(a):
            if i == 0: continue
            for y in candidates(x):
                yield a[:i] + (y,) + a[i + 1:]
    elif isinstance(a, int):
        for y in (0, 1, 32, 256):
            if abs(y) < abs(a): yield y
        if abs(a) > 256:
            if a > 0 and a.bit_length() > 1: yield a >> (a.bit_length() // 2)
            if a < 0: yield -a

def size(a):
    return len(repr(a))

cur = arg0
changed = True
while changed:
    changed = False
    for c in candidates(cur):
        if size(c) < size(cur) and bad(c):
            cur = c
            changed = True
            print("..", size(cur), file=sys.stderr, flush=True)
            break

e, g = results(cur)
print(repr(cur))
print("   python:", e[:2000])
print("   asm:   ", g[:2000])
open(path + ".min", "w").write(repr(cur) + "\n")
