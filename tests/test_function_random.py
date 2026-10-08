#!/usr/bin/env python3
"""function.py's Function on random traces, against python's: the checks
of the params (cleanup_masks: `require cd == address(cd)`, the reverts of
the bits above a type...), the params guessed from how the calldata is
used (masked, validated, pointers, truth values, unaligned), the check of
the value sent (after setmems and setvars, an or of conditions, a revert
or an invalid), the constants (what varies), the getters (words of data,
structs), rename_params - and the hooks of the parts: cleanup_masks,
varies, disjuncts.

    tests/test_function_random.py [SEED [COUNT]]
"""
import os, sys, random, copy
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(HERE, "..", "..", "panoramix")))
sys.path.insert(0, os.environ.get("PANASM_BUILD") or os.path.join(HERE, "..", "build"))
sys.setrecursionlimit(20000)
import logging; logging.disable(logging.CRITICAL)
os.environ.setdefault("PANORAMIX_SIGDB", "/nonexistent")
import panoramix_asm as A
from test_simplify import check, run
import test_simplify
from test_function import py_function, py_function_renamed, port_abi, fake_inputs, TAKEN
from panoramix import function as F
from panoramix.function import Function

seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
count = int(sys.argv[2]) if len(sys.argv) > 2 else 300
rnd = random.Random(seed)


def ch(*xs):
    return rnd.choice(xs)


def rcd():
    r = rnd.random()
    if r < 0.85:
        return ("cd", ch(4, 36, 68, 100))
    if r < 0.9:
        return ("cd", ch(0, 5, 132, -28, 2**70 + 4, *BOOLS))
    # an element of an array, its length: a pointer
    return ("cd", ch(("add", 4, ("cd", ch(4, 36))), ("add", 36, ("cd", 36), ("mul", 32, ("var", "_1"))),
                     ("add", 68, ("cd", 4)), ("add", 4, ("cd", ("add", 4, ("cd", 36))))))


def clean(cd):
    """cd as a valid value of a type would be"""
    return ch(("mask_shl", 160, 0, 0, cd), ("mask_shl", 8, 0, 0, cd), ("mask_shl", 32, 224, 0, cd),
              ("bool", cd), ("signextend", ch(0, 1, 15, 31), cd), ("mask_shl", 24, 0, 0, cd),
              ("mask_shl", 64, 192, 0, cd), ("mask_shl", 1, 0, 0, cd), ("mask_shl", 256, 0, 0, cd),
              ("mask_shl", 248, 8, 0, cd), ("mask_shl", 16, 8, 0, cd),
              *([("signextend", ch(True, False), cd), ("mask_shl", 255, True, 0, cd),
                 ("mask_shl", True, 0, False, cd)] if BOOLS else []))


def rmask(cd):
    """a use of cd, masked or not"""
    return ch(cd, cd, clean(cd), ("mask_shl", ch(8, 160, 256, 1, 24), ch(0, 0, 8, 96), ch(0, -8), cd),
              ("mask_shl", ("var", "_2"), 0, 0, cd))


def rexp(d=0):
    r = rnd.random()
    if d > 2 or r < 0.3:
        return ch(rmask(rcd()), rnd.randint(0, 300), "caller", "callvalue", "address", "codesize", ("var", "_1"),
                  ("storage", 256, 0, rnd.randint(0, 5)), "timestamp", 2**160, ("cd", 4))
    if r < 0.45:
        return ("add", rexp(d + 1), rexp(d + 1))
    if r < 0.55:
        return ("bytes", 32, rexp(d + 1))
    if r < 0.6:
        return ("sha3", rexp(d + 1), rexp(d + 1))
    if r < 0.65:
        return ("balance", rexp(d + 1))
    if r < 0.7:
        return ("extcodesize", rexp(d + 1))
    if r < 0.75:
        return ("iszero", rexp(d + 1))
    if r < 0.8:
        return ("bool", rexp(d + 1))
    if r < 0.85:
        return ("eq", rexp(d + 1), rexp(d + 1))
    if r < 0.9:
        return ("data", rexp(d + 1), rexp(d + 1))
    return ("mask_shl", 160, 0, 0, rexp(d + 1))


REVERTS = [[("revert", None)], [("invalid",)]]


def rcheck():
    """a check of a param: (cond, reverting branch first?)"""
    cd = rcd()
    x = clean(cd)
    r = rnd.random()
    if r < 0.35:
        return ("iszero", ch(("eq", cd, x), ("eq", x, cd))), True
    if r < 0.6:
        return ch(("eq", cd, x), ("eq", x, cd)), False
    if r < 0.75:
        size = ch(96, 248, 8, 128)
        return ("mask_shl", size, 256 - size, 0, cd), True
    if r < 0.85:
        return ("iszero", ("eq", cd, rexp(1))), True
    return rexp(1), ch(True, False)


def rline(d=0):
    r = rnd.random()
    if r < 0.12:
        return ("setmem", ("range", ch(64, 0, 128), 32), rexp())
    if r < 0.22:
        return ("store", 256, 0, rnd.randint(0, 5), rexp())
    if r < 0.3:
        return ("setvar", ch("_1", "_2"), rexp())
    if r < 0.36:
        return ("log", None, rnd.randint(1, 2**256 - 1), rexp())
    if r < 0.42:
        return ("call", "gas", rexp(), 0, None, ("data", rexp()))
    if r < 0.7 and d < 3:
        cond, first = rcheck()
        rev = copy.deepcopy(ch(*REVERTS)) if rnd.random() < 0.8 else rpath(d + 1)
        other = rpath(d + 1)
        return ("if", cond, rev, other) if first else ("if", cond, other, rev)
    if r < 0.78 and d < 3:
        return ("while", rexp(1), rpath(d + 1), "loop_" + str(rnd.randint(1, 3)),
                ch((), (("setvar", "_1", rexp(1)),)))
    return ("setvar", "_3", rexp())


def rend():
    return ch(("stop",), ("return", rexp()), ("return", ("data", rexp(), rexp())), ("revert", None),
              ("revert", ("data", ("bytes", 4, 147028384), rexp())), ("invalid",), ("return", 0),
              ("revert", 0), ("selfdestruct", "caller"))


def rpath(d=0):
    return [rline(d) for _ in range(rnd.randint(0, 3 if d else 5))] + [rend()]


def rgetter():
    """the trace of a getter, or of a const"""
    loc = rnd.randint(0, 3)
    ret = ch(("storage", 256, 0, loc), ("bool", ("storage", 8, 0, loc)),
             ("mask_shl", 160, 0, 0, ("storage", 160, 0, loc)), ("bytes", 32, ("storage", 256, 0, loc)),
             ("data", ("bytes", 32, ("storage", 256, 0, loc)), ("storage", 256, 0, ("add", 1, loc))),
             ("data", ("storage", 256, 0, ("sha3", ("data", ("cd", 4), loc))),
              ("storage", 256, 0, ("add", 1, ("sha3", ("data", ("cd", 4), ch(loc, loc + 1)))))),
             ("data", ("storage", 256, 0, ("sha3", ch(loc, -1, 0, 2000)))),
             ("data", ("storage", 256, 0, ("sha3", -1)), ("storage", 256, 0, ("sha3", ch(5, -1, 7)))),
             ("data", ("storage", 256, 0, ("sha3", ("data", 1, ch(-1, 3, *BOOLS)))), ("bytes", 32, ("sha3", 3))),
             ("data",), rnd.randint(0, 9), ("data", ("bytes", 32, 5), ("bytes", 4, 7)),
             ("bytes", 32, "address"), "codesize", ("data", 1, 2, "address"))
    return [("return", ret)]


def rtrace():
    r = rnd.random()
    pre = [ch(("setmem", ("range", 64, 32), 128), ("setvar", "_1", 0), ("setmem", ("range", 0, 32), rexp()))
           for _ in range(ch(0, 0, 1, 2))]
    body = rgetter() if rnd.random() < 0.3 else rpath()
    if r < 0.6:
        # the check of the value sent
        cond = ch("callvalue", ("bool", "callvalue"), ("iszero", ("iszero", "callvalue")),
                  ("or", "callvalue", ("lt", "calldatasize", 36)),
                  ("or", ("lt", "calldatasize", 4), ("or", "callvalue", ("bool", "callvalue"))),
                  ("eq", "callvalue", 0))
        fails = copy.deepcopy(ch(*REVERTS, [("revert", 0)], [("revert", None), ("stop",)], []))
        if rnd.random() < 0.3:
            return pre + [("if", ("iszero", cond), body, fails)]
        return pre + [("if", cond, fails, body)]
    return pre + body


import ast


def check_fields(name, arg, expected, ctx):
    """check, but the printed text left out (with python's bools in the
    trace, which the printer's port takes as numbers no more than its
    matcher does: what's compared here is the function's analysis)"""
    test_simplify.cases += 1
    got = A._test(name, repr(arg))
    if expected == got:
        return
    try:
        e, g = ast.literal_eval(expected), ast.literal_eval(got)
        cut = {"function": (11, 12), "function_renamed": (5,)}[name]
        e = [x for k, x in enumerate(e) if k not in cut]
        g = [x for k, x in enumerate(g) if k not in cut]
        if e == g:
            return
    except Exception:
        pass
    test_simplify.cases -= 1
    check(name, arg, expected, ctx)


BOOLS = ()
for i in range(count):
    # (python's bools, which the matcher takes for ints, in a fifth of them)
    BOOLS = (True, False) if rnd.random() < 0.2 else ()
    chk = check_fields if BOOLS else check
    trace = rtrace()
    hash = ch("0x12345678", "0x12345678", "_fallback")
    if hash == "_fallback":
        abis = [{"name": "_fallback"}]
    else:
        abis = [{"name": "unknown12345678"}, {"name": "unknown12345678"},
                {"name": "fn", "inputs": fake_inputs(rnd.randint(0, 4), rnd)}]
    ctx = f"case {i}"
    check("cleanup_masks", trace, run(Function.cleanup_masks, None, trace), ctx)
    check("varies", trace, run(F.varies, trace), ctx)
    for line in trace:
        if isinstance(line, tuple) and line[0] == "if":
            check("disjuncts", line[1], run(F.disjuncts, line[1]), ctx)
    for a in abis:
        chk("function", (hash, trace, port_abi(a)), run(py_function, hash, trace, a), ctx + " " + repr(port_abi(a))[:60])
        storage = rnd.sample(TAKEN, rnd.randint(0, 4))
        chk("function_renamed", (hash, trace, port_abi(a), storage),
            run(py_function_renamed, hash, trace, a, storage), ctx + " renamed")
print(f"{test_simplify.cases} cases, {test_simplify.bad} mismatches")
sys.exit(1 if test_simplify.bad else 0)
