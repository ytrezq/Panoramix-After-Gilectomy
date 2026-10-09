#!/usr/bin/env python3
"""SafeMath (safemath.s) against python's safemath.py: rewrite (the
checked arithmetic of the asts calls of the contract's SafeMath
functions) and pretty_defs (the lines of its block), on random asts -
the checks of OpenZeppelin's SafeMath, ds-math, solidity's since 0.8 and
the compiler's of a division, right and wrong, one after the other,
failing as they do (a message, a panic, a revert, an invalid), and the
lines after them (what they're used in, what can't fail, what changes
what they read), in branches and loops - and, with PANORAMIX_ASTS (a
directory of pickles: [(hash, name, ast)] for each contract), on the
asts of contracts.

    tests/test_safemath.py [SEED [COUNT]]
"""
import os, sys, random, copy, glob, pickle
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(HERE, "..", "..", "panoramix")))
sys.path.insert(0, os.environ.get("PANASM_BUILD") or os.path.join(HERE, "..", "build"))
import logging; logging.disable(logging.CRITICAL)
sys.setrecursionlimit(100000)
import panoramix_asm as A
from panoramix import safemath
from test_simplify import check, run
import test_simplify

seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
count = int(sys.argv[2]) if len(sys.argv) > 2 else 2000
rnd = random.Random(seed)

PANIC, ERROR = 0x4E487B71, 0x08C379A0
MAX = 2**256 - 1


class F:
    def __init__(self, ast):
        self.ast = ast


def py(asts):
    fs = [F(a) for a in asts]
    defs = safemath.rewrite(fs)
    return ([f.ast for f in fs], list(safemath.pretty_defs(defs)))


# (the storage as the asts have it, once named: python's printer recurses
# without end on the forms it doesn't know)
BALANCE = ("st", 256, ("si", ("sv", "balanceOf"), ("param", "account")), 256)
SUPPLY = ("st", 256, ("sv", "totalSupply"), 256)
ATOMS = [("param", "amount"), ("param", "value"), ("cd", 68), BALANCE, SUPPLY,
         ("var", "_1"), ("var", "_2"), ("mem", ("range", 64, 32)), "callvalue", "timestamp",
         ("mask_shl", 128, 0, 0, ("param", "amount")), 3, 1000, 10**18, 2**128, 86400]


def atom():
    return rnd.choice(ATOMS)


def operand():
    r = rnd.random()
    if r < 0.75:
        return atom()
    if r < 0.85:
        return ("mul", rnd.choice([2, 3, 10**18]), atom())
    return ("div", atom(), rnd.choice([2, 10**6, ("cd", 68)]))


MESSAGES = [b"SafeMath: addition overflow", b"SafeMath: subtraction overflow",
            b"SafeMath: multiplication overflow", b"SafeMath: division by zero",
            b"SafeMath: modulo by zero", b"ERC20: transfer amount exceeds balance",
            b"ERC20: transfer amount exceeds allowance", b"ds-math-add-overflow", b"x",
            b"a message longer than thirty-two bytes, on two words of the data", b"it's \\ odd\n"]


def error_body(msg):
    n = len(msg)
    style = rnd.random()
    if style < 0.6:
        padded = msg + bytes(-n % 32)
        parts = tuple(int.from_bytes(padded[k:k + 32], "big") for k in range(0, len(padded), 32))
    elif style < 0.8:
        parts = (("bytes", n, int.from_bytes(msg, "big")), ("mem", ("range", 232, 28)))
    elif style < 0.9:
        # the length past the bytes: no message
        parts = (("bytes", n, int.from_bytes(msg, "big")),)
        n += rnd.choice([0, 1])
    else:
        parts = (("mem", ("range", 100, 32)),)
    return [("revert", ("data", ("bytes", 4, ERROR), 32, n) + parts)]


def fail(kind=None):
    kind = kind or rnd.choice(["error", "error", "panic", "revert", "invalid", "other"])
    if kind == "error":
        return error_body(rnd.choice(MESSAGES))
    if kind == "panic":
        return [("revert", ("data", ("bytes", 4, PANIC), rnd.choice([0x11, 0x11, 0x12, 0x01])))]
    if kind == "revert":
        return [("revert", None)]
    if kind == "invalid":
        return [("invalid",)]
    return rnd.choice([[("revert", 0)], [("stop",)], [("revert", None), ("stop",)], [("return", 1)], []])


def neg(b):
    if type(b) == int:
        return -b
    if b[0] == "mul" and type(b[1]) == int:
        return ("mul", -b[1]) + b[2:]
    return ("mul", -1, b)


def flatten_add(*terms):
    out = []
    for t in terms:
        if type(t) == tuple and t[0] == "add":
            out += list(t[1:])
        else:
            out.append(t)
    return ("add",) + tuple(out)


def arithmetic():
    """an operation and the checks of it: (res, [(cond, kind)])"""
    op = rnd.choice(["add", "add", "sub", "sub", "mul", "div", "mod", "inc", "dec"])
    a, b = operand(), operand()
    while b == a:
        b = operand()
    if op == "add":
        res = ("add", a, b) if rnd.random() < 0.8 else ("add", b, a)
        conds = [("lt", res, a), ("gt", a, res), ("le", res, a), ("ge", a, res), ("lt", res, b),
                 ("gt", a, ("not", b)), ("lt", ("not", b), a), ("gt", a, ("add", -1, neg(b))),
                 ("gt", res, a), ("lt", a, res)]
        kinds = ["error", "revert", "invalid", "panic"]
    elif op == "sub":
        res = flatten_add(a, neg(b))
        conds = [("gt", b, a), ("lt", a, b), ("gt", res, a), ("lt", a, res), ("ge", b, a), ("gt", a, b)]
        kinds = ["error", "revert", "invalid", "panic"]
    elif op == "mul":
        res = ("mul", a, b)
        ne = ("iszero", ("eq", ("div", res, a), b))
        ne2 = ("iszero", ("eq", b, ("div", res, a)))
        most = rnd.choice([("div", -1, a), ("div", MAX, a)])
        conds = [ne, ne2, ("and", a, ne), ("and", ne, a), ("and", a, ("gt", b, most)),
                 ("and", ("lt", most, b), a), ("and", b, ne)]
        kinds = ["error", "revert", "invalid", "panic"]
    elif op in ("div", "mod"):
        res = (op, a, b)
        conds = [("iszero", b), ("eq", b, 0), ("eq", 0, b), ("le", b, 0), ("iszero", a)]
        kinds = ["error", "panic", "invalid", "revert"]
    elif op == "inc":
        res = ("add", 1, a)
        conds = [("eq", a, -1), ("eq", -1, a), ("eq", a, MAX), ("eq", MAX, a), ("eq", a, 0)]
        kinds = ["panic", "panic", "error"]
    else:
        res = ("add", -1, a)
        conds = [("iszero", a), ("eq", a, 0), ("eq", 0, a), ("eq", a, -1)]
        kinds = ["panic", "panic", "error"]
    checks = []
    n = rnd.choice([1, 1, 1, 2, 2, 3])
    for _ in range(n):
        cond = rnd.choice(conds[:4]) if rnd.random() < 0.8 else rnd.choice(conds)
        checks.append((cond, rnd.choice(kinds)))
    if op in ("mul",) and rnd.random() < 0.3:
        # the compiler's check of the division a * b / a makes: before
        checks.insert(0, (rnd.choice([("iszero", a), ("eq", a, 0)]), rnd.choice(["invalid", "panic"])))
    if rnd.random() < 0.15:
        # a check of the compiler after the library's
        checks.append((rnd.choice(conds[:2]), "panic"))
    return res, checks


def check_line(cond, kind):
    body = fail(kind)
    if kind == "panic" and rnd.random() < 0.8:
        body = [("revert", ("data", ("bytes", 4, PANIC), rnd.choice([0x11, 0x12])))]
    return ("if", cond, body)


TRANSPARENT = [("setvar", "_3", ("cd", 100)), ("setmem", ("range", 128, 32), 7), "a comment",
               ("log", ("data", 5), 1234), ("set", ("st", 256, ("sv", "other"), 256), 5)]
CHANGING = [("setvar", "_1", 9), ("setmem", ("range", 64, 32), 1), ("set", BALANCE, 2),
            ("call", "gas", ("cd", 4), 0, None, None), ("revert", None)]


def use(res, depth):
    r = rnd.random()
    if r < 0.2:
        return [("setvar", "_9", res)]
    if r < 0.35:
        return [("set", BALANCE, res)]
    if r < 0.45:
        return [("setmem", ("range", 96, 32), res)]
    if r < 0.55:
        return [("return", ("data", res))]
    if r < 0.65:
        return [("log", ("data", res, ("param", "account")), 5555)]
    if r < 0.75 and depth < 3:
        return [("if", ("lt", res, ("param", "value")), block(depth + 1), block(depth + 1))]
    if r < 0.8 and depth < 3:
        return [("while", ("lt", res, ("var", "_1")), block(depth + 1), "jd", ())]
    if r < 0.85:
        return [("setvar", "_9", ("add", res, ("mul", 2, res)))]
    if r < 0.9:
        # the result in a later check
        a2, c2 = arithmetic()
        return [check_line(("lt", ("add", res, 5), res), "panic")]
    return [("setvar", "_8", ("cd", 4))]


def block(depth=0):
    lines = []
    for _ in range(rnd.randint(0, 4)):
        r = rnd.random()
        if r < 0.55:
            res, checks = arithmetic()
            for cond, kind in checks:
                lines.append(check_line(cond, kind))
                if rnd.random() < 0.1:
                    lines.append(rnd.choice(TRANSPARENT))
            for _ in range(rnd.choice([0, 0, 0, 1, 2])):
                lines.append(rnd.choice(TRANSPARENT + CHANGING[:2]))
            if rnd.random() < 0.1:
                lines.append(rnd.choice(CHANGING))
            lines += use(res, depth)
            if rnd.random() < 0.3:
                # used again
                lines += use(res, depth)
        elif r < 0.7 and depth < 3:
            lines.append(("if", rnd.choice([("param", "account"), ("iszero", "callvalue")]), block(depth + 1)))
        elif r < 0.8 and depth < 3:
            lines.append(("while", ("lt", ("var", "_1"), 9), block(depth + 1), "jd", ()))
        else:
            lines.append(rnd.choice(TRANSPARENT + CHANGING))
    return lines + rnd.choice([[("stop",)], [("return", 1)], [("revert", None)], []])


if __name__ == "__main__":
    for i in range(count):
        asts = [block() for _ in range(rnd.randint(1, 4))]
        if rnd.random() < 0.1:
            asts.append(None)
        check("safemath", asts, run(py, copy.deepcopy(asts)), f"case {i}")

    # the asts of contracts
    d = os.environ.get("PANORAMIX_ASTS")
    for f in sorted(glob.glob(os.path.join(d, "*.pkl"))) if d else []:
        try:
            data = pickle.load(open(f, "rb"))
        except Exception:
            continue
        asts = [ast for _, _, ast in data]
        check("safemath", asts, run(py, copy.deepcopy(asts)), os.path.basename(f))

    print(f"{test_simplify.cases} cases, {test_simplify.bad} mismatches")
    sys.exit(1 if test_simplify.bad else 0)
