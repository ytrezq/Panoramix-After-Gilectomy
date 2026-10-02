#!/usr/bin/env python3
"""Random differential test of the printer: prettify (every combination of
its flags) and pretty_line on random expressions and lines - the shapes
the traces have, with numbers of every size (negative, past 2^62, past
2^256) - and pprint_logic on random traces (loops and their continues,
breaks, requires), against panoramix.prettify. The names the printer
avoids (set_names: the storage variables', the params') and the params of
the function printed (get_param_name) are random too.

    tests/test_prettify_random.py [SEED [COUNT]]
"""
import os, sys, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_prettify import *
from panoramix.utils import signatures as SIG

random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 1)
N = int(sys.argv[2]) if len(sys.argv) > 2 else 2000

def rint():
    r = random.random()
    if r < 0.35: return random.choice([0, 1, 2, 3, 4, 8, 31, 32, 64, 96, 128, 160, 224, 248, 255, 256, 3600, 86400, 10**6, 10**18])
    if r < 0.55: return random.randint(-300, 300)
    if r < 0.7: return random.choice([1, -1]) * 2 ** random.randint(0, 300) + random.randint(-2, 2)
    if r < 0.8: return random.randint(0, 2**256)
    if r < 0.9: return random.choice([0xa9059cbb, 0x70a08231, 0x23b872dd, 0xdeadbeef, 2**160 - 1, 2**255, 2**256 - 1])
    return random.randint(-2**70, 2**70)

def rtext(n):
    """n bytes, often text (letters, separators, escapes), as an int"""
    r = random.random()
    if r < 0.5:
        alphabet = b"abcXYZ019 _-.:'\\\n\t\r"
    elif r < 0.7:
        alphabet = b" ,;:-"
    else:
        alphabet = bytes(range(256))
    b = bytes(random.choice(alphabet) for _ in range(n))
    return int.from_bytes(b, "big")

def rword_text():
    """a word of text, padded with zeroes"""
    n = random.randint(1, 32)
    return rtext(n) << (8 * (32 - n))

NAMES = ["callvalue", "caller", "calldatasize", "timestamp", "number", "address", "origin",
         "gas", "chainid", "block.timestamp", "unknown", "x", "coinbase", "gasprice",
         "blobbasefee", "basefee", "difficulty", "returndatasize", "gaslimit"]
OPS2 = ["add", "sub", "mul", "div", "sdiv", "mod", "smod", "exp", "lt", "gt", "le", "ge",
        "slt", "sgt", "sle", "sge", "eq", "and", "or", "xor", "shl", "shr", "sar", "byte",
        "signextend", "max", "min", "land", "lor", "sadd", "smul"]
VAR_NAMES = ["_1", "_21", "signer", "hash", "caller", "x", "idx", "s", "owner", "True", "var3", "_old"]

def rloc(d=0):
    r = random.random()
    if d > 2 or r < 0.35: return ("sv", random.choice(["owner", "balanceOf", "stor0", "x", "caller"]))
    if r < 0.6: return ("si", rloc(d + 1), rexp(d + 2))
    if r < 0.7: return (random.choice(["sl", "sbl"]), rloc(d + 1))
    if r < 0.85: return ("sf", rloc(d + 1), random.choice([0, 8, 160, rint()]))
    return ("sr", random.choice([0, 1, 5, rint(), rexp(d + 2)]))

def rst(d=0):
    size = random.choice([256, 160, 8, 1, 64, 255, rint()])
    width = random.choice([size, 256, None, 160, 8, rint()])
    return ("st", size, rloc(d), width)

def rbytes(d=0):
    size = random.choice([1, 2, 3, 4, 4, 20, 31, 32, 32, 33, 64, 0, -1, -200, rint()])
    if isinstance(size, int) and 0 <= size <= 40 and random.random() < 0.7:
        val = rtext(size) if random.random() < 0.8 else random.randint(0, 2 ** (8 * size)) if size else 0
    else:
        val = random.choice([rint(), rexp(d + 1), 0])
    if isinstance(size, int) and abs(size) > 2**20:
        size = 4
    return ("bytes", size, val)

def rdata(d=0):
    """a data, often of text or an ABI-encoded string"""
    r = random.random()
    terms = []
    if random.random() < 0.3:
        terms.append(("bytes", 4, random.choice([0x08C379A0, 0x4E487B71, 0xa9059cbb, rint()])))
    if r < 0.3:
        length = random.choice([random.randint(1, 70), random.randint(-3, 3), rint()])
        terms += [random.choice([32, ("bytes", 32, 32)]), random.choice([length, ("bytes", 32, length) if isinstance(length, int) and length >= 0 else length])]
        if isinstance(length, int) and 0 < length < 100:
            n = (length + 31) // 32
            b = b"".join(rtext(32).to_bytes(32, "big") for _ in range(n))
            b = b[:length] + bytes(32 * n - length) if random.random() < 0.8 else b
            for i in range(n):
                w = int.from_bytes(b[32 * i:32 * i + 32], "big")
                terms.append(w if random.random() < 0.8 else ("bytes", 32, w))
        if random.random() < 0.2:
            terms.append(rexp(d + 1))
    elif r < 0.6:
        for _ in range(random.randint(1, 4)):
            rr = random.random()
            if rr < 0.4: terms.append(rword_text())
            elif rr < 0.7: terms.append(rbytes(d + 1))
            else: terms.append(rexp(d + 1))
    else:
        terms += [rexp(d + 1) for _ in range(random.randint(0, 3))]
    return ("data",) + tuple(terms)

def rarr(d=0):
    l = random.choice([random.randint(0, 40), rint()])
    n = random.randint(0, 2)
    terms = [random.choice([rword_text(), rbytes(d + 1), rexp(d + 1)]) for _ in range(n)]
    if random.random() < 0.2:
        terms = [("mask_shl", 256, 0, 0, "'" + "ab" * random.randint(0, 3) + "'")]
        l = len(terms[0][4]) - 2 if random.random() < 0.7 else l
    return ("arr", l) + tuple(terms)

def atom():
    r = random.random()
    if r < 0.38: return rint()
    if r < 0.55: return random.choice(NAMES)
    if r < 0.68: return ("cd", random.choice([0, 4, 36, 68, 100, rint(), ("add", 4, ("cd", 4)), ("add", 68, ("cd", 36)),
                                              ("add", 36, ("cd", 4)), ("add", 4, ("param", "_param2")),
                                              ("add", 4, ("param", "amounts")), ("add", 100, ("cd", 4))]))
    if r < 0.8: return ("var", random.choice([1, 2, 0, 16, 17, -1, -5, -20, 3001, 2**70, -2**70] + VAR_NAMES))
    if r < 0.88: return ("param", random.choice(["_param1", "_param2", "amount"]))
    return ("mem", ("range", random.choice([0, 32, 64, 128, rint()]), random.choice([32, 20, 1, rint()])))

def rexp(d=0):
    r = random.random()
    if d > 3 or r < 0.25: return atom()
    if r < 0.45:
        op = random.choice(OPS2)
        n = random.choice([2, 2, 2, 3]) if op in ("add", "mul", "and", "or", "max", "min", "land", "lor") else 2
        if random.random() < 0.03: n = random.choice([0, 1, 3])
        return (op,) + tuple(rexp(d + 1) for _ in range(n))
    if r < 0.52:
        return (random.choice(["iszero", "bool", "not"]), rexp(d + 1))
    if r < 0.64:
        size = random.choice([1, 8, 20, 32, 64, 96, 160, 224, 248, 251, 255, 256, 16, 24, 40, 7, rint()])
        off = random.choice([0, 0, 0, 5, 8, 96, 160, 248, 16, -3, rint()])
        shl = random.choice([0, 0, 0, 1, 3, 5, 8, 9, 96, -3, -5, -8, -9, -96, rint()])
        if random.random() < 0.3: shl = off
        if random.random() < 0.3: shl = -off if isinstance(off, int) else ("mul", -1, off)
        if random.random() < 0.15: size, off, shl = random.choice([(256, 0, 0), (32, 224, 0), (32, 224, -224), (160, 0, 0), (251, 5, 0)])
        if random.random() < 0.1: off, shl = rexp(d + 1), rexp(d + 1)
        if random.random() < 0.1: off = rexp(d + 1); shl = ("mul", -1, off); size = ("add", 256, ("mul", -1, off))
        val = rexp(d + 1)
        if random.random() < 0.15: val = rst(d + 1)
        if random.random() < 0.05: val = random.choice(["caller", "origin", ("cd", 0)])
        if random.random() < 0.03: return ("mask_shl", 32, 224, random.choice([0, -224]), ("cd", 0))
        if random.random() < 0.03: return (random.choice([("mask_shl", 251, 5, 0), ("mask", 251, 5)])
                                           + (random.choice([("add", 31, rexp(d + 1)), rexp(d + 1)]),))
        return ("mask_shl", size, off, shl, val)
    if r < 0.68:
        return ("storage", random.choice([256, 160, 8, 1, rint()]), random.choice([0, 0, 8, 160, rint()]),
                random.choice([0, 5, rint(), ("sha3", rexp(d + 1), 3), ("add", 1, ("sha3", 2))]))
    if r < 0.72:
        return ("sha3",) + tuple(random.choice([rexp(d + 1), rword_text(), rbytes(d + 1)]) for _ in range(random.randint(0, 3)))
    if r < 0.77:
        return rdata(d)
    if r < 0.8:
        return ("stor", random.choice([("name", "stor0", 0), ("length", ("name", "stor1", 1)),
                                       ("map", rexp(d + 1), ("name", "balanceOf", 3)),
                                       ("array", rexp(d + 1), ("name", "stor4", 4))]))
    if r < 0.82:
        return ("type", random.choice([256, 160, 8, 1]), ("field", random.choice([0, 8, 160]),
                                                            ("stor", ("name", "stor2", 2))))
    if r < 0.86: return rst(d)
    if r < 0.87: return ("sall", rloc(d))
    if r < 0.9: return rbytes(d)
    if r < 0.91: return rarr(d)
    if r < 0.92:
        b = random.choice([0, 1, 15, 31, 32, rint(), "x"])
        val = rexp(d + 1)
        if isinstance(b, int) and random.random() < 0.4:
            val = ("type", random.choice([8 * (b + 1), 256, 8]), ("stor", ("name", "stor0", 0)))
        return ("signextend", b, val)
    if r < 0.93: return ("tload", rexp(d + 1))
    if r < 0.94: return ("blobhash", rexp(d + 1))
    if r < 0.95: return ("extcodecopy", rexp(d + 1), ("range", rexp(d + 1), rexp(d + 1)))
    if r < 0.96: return (random.choice(["addmod", "mulmod"]),) + tuple(rexp(d + 1) for _ in range(random.choice([3, 3, 2])))
    if r < 0.97: return ("shift", rexp(d + 1), rexp(d + 1))
    if r < 0.98: return random.choice([("call.data", rexp(d + 1), random.choice([32, rexp(d + 1)])),
                                       ("ext_call.return_data", rexp(d + 1), random.choice([32, 64])),
                                       ("call.data", ("add", 36, ("param", "p")), ("cd", ("add", 4, ("param", "p")))),
                                       ("code.data", rexp(d + 1), rexp(d + 1))])
    return random.choice([("balance", rexp(d + 1)), ("extcodesize", rexp(d + 1)), ("blockhash", rexp(d + 1)),
                          ("ecrecover", rdata(d)), ("sha256hash", rexp(d + 1)), ("bool", 1), ("bool", 0),
                          ("mem", ("range", rexp(d + 1)))])

def rfname(d=0):
    return random.choice([None, None, ("bytes", 4, random.choice([0xa9059cbb, 0x12345678, 5, rint()])),
                          random.choice([0xa9059cbb, 0x70a08231, 2**33, -1, 0]), ("mem", ("range", 0, 4)),
                          rexp(d + 1)])

def rfparams(d=0):
    r = random.random()
    if r < 0.3: return None
    if r < 0.5: return ("bytes", 4, random.choice([0xa9059cbb, 7, rint()]))
    if r < 0.8:
        return ("data", ("bytes", 4, random.choice([0xa9059cbb, 7, rint()]))) + tuple(rexp(d + 1) for _ in range(random.randint(0, 3)))
    return rdata(d)

def rsetvars():
    res = []
    for _ in range(random.randint(0, 4)):
        idx = random.choice([1, 2, 3, "_1", "_2"])
        val = random.choice([("var", idx), ("add", 1, ("var", idx)), ("var", random.choice([1, 2, 3, "_1"])),
                             ("add", ("var", 1), ("var", 2)), rexp(2)])
        res.append(("setvar", idx, val))
    return res

def rline():
    r = random.random()
    e = rexp()
    if r < 0.1:
        # (a number past 2^256 written to n bytes is Bytes(n, ...): python
        # makes 2 ** (8 * n), for any n - a small one)
        val = random.choice([e, rint(), rdata(), 2**300 + rint(), rbytes()])
        n = random.choice([32, 4, 64, rint() if not (isinstance(val, int) and val >= 2**256) else 40])
        return ("setmem", ("range", random.choice([0, 64, 128, rint()]), n), val)
    if r < 0.17: return ("store", random.choice([256, 160, 8]), random.choice([0, 0, 160]), random.choice([0, 3, rexp()]), e)
    if r < 0.24: return ("set", ("stor", ("name", "stor0", 0)), random.choice([
        e, ("add", random.choice([1, -1, 5, -5, 2**70]), ("stor", ("name", "stor0", 0))),
        ("add", ("stor", ("name", "stor0", 0)), ("mul", -1, e)), ("add", ("stor", ("name", "stor0", 0)), e),
        ("add", e, ("stor", ("name", "stor0", 0)))]))
    if r < 0.29: return ("setvar", random.choice([1, "_2", "signer"]), e)
    if r < 0.38: return ("return", random.choice([e, rdata(), rbytes(), ("data",), None, "mem",
                                                 ("data",) + tuple(rint() for _ in range(random.randint(5, 12)))]))
    if r < 0.47: return ("revert", random.choice([0, None, e, rdata(), ("bytes", 4, random.choice([0x12345678, rint()])),
                                                 ("data", ("bytes", 4, 0x4E487B71), random.choice([0x11, 0x32, 5, rint()])),
                                                 ("data", ("bytes", 4, 0x08C379A0), 32, 5, rword_text()),
                                                 ("mem", ("range", 0, ("sub", 64, 0))), ("mem", ("range", e, e))]))
    if r < 0.5: return ("require", e)
    if r < 0.58:
        topics = [random.choice([rint(), 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef, e])
                  for _ in range(random.randint(0, 4))]
        return ("log", random.choice([rdata(), e, ("data",), None, "mem"])) + tuple(topics)
    if r < 0.61: return ("selfdestruct", e)
    if r < 0.66: return ("call", rexp(), random.choice([rint(), 0x1234, 2**160 - 1, 2**170, -5, e]), random.choice([0, e]), rfname(), rfparams())
    if r < 0.7: return ("staticcall", rexp(), random.choice([rint(), e]), 0, rfname(), rfparams())
    if r < 0.72: return ("delegatecall", rexp(), random.choice([rint(), e]), rfname(), rfparams())
    if r < 0.74: return ("callcode", rexp(), random.choice([rint(), e]), random.choice([0, e]), rfname(), rfparams())
    if r < 0.76: return ("precompiled", random.choice(VAR_NAMES), random.choice(["ecrecover", "sha256hash"]), rdata())
    if r < 0.78: return ("create", random.choice([0, e]), rdata())
    if r < 0.8: return ("create2", random.choice([0, e]), rdata(), rexp())
    if r < 0.84: return ("continue", random.choice([1, 2, "jd"]), rsetvars())
    if r < 0.86: return ("tstore", rexp(), e)
    if r < 0.88: return random.choice([("invalid",), ("invalid", 5), ("stop",), ("undefined", "x", 5), ("break",)])
    if r < 0.9: return random.choice([["x", e, rexp()], ["y"], "a comment", ("comment", e)])
    if r < 0.92: return ("label", "loop", rsetvars())
    return ("selfdestruct", e)

def rtrace(d=0, loops=()):
    res = []
    for _ in range(random.randint(0, 4)):
        r = random.random()
        if d < 3 and r < (0.15 if not loops else 0.3):
            jd = random.choice([j for j in (1, 2, 3, 4, 5) if j not in loops] if random.random() < 0.8 else [1, 2, 3, 4])
            body = rtrace(d + 1, loops + (jd,))
            cond = random.choice([1, ("bool", 1), rexp(1), ("lt", ("var", 1), 10)])
            if random.random() < 0.8:
                res.append(("while", cond, body, jd, rsetvars()))
            else:
                res.append(("while", cond, body))
        elif d < 3 and r < 0.3:
            branch = lambda: random.choice([rtrace(d + 1, loops), [("revert", None)], [("invalid",)],
                                            rtrace(d + 1, loops) + [("break",)], []])
            if random.random() < 0.8:
                res.append(("if", rexp(1), branch(), branch()))
            else:
                res.append(("if", rexp(1), branch()))
        elif loops and r < 0.5:
            res.append(("continue", random.choice(loops + loops + (9,)), rsetvars()))
        elif r < 0.45:
            res.append(("require", rexp(1)))
        elif r < 0.48:
            res.append(("or", rtrace(d + 1, loops), rtrace(d + 1, loops)))
        else:
            res.append(rline())
    if random.random() < 0.3:
        res.append(("stop",))
    return res

def rnames():
    storage = random.sample(["owner", "balanceOf", "stor0", "s", "x", "idx", "u", "signer", "a", "var1", "hash"], random.randint(0, 4))
    params = random.sample(["x", "amount", "t", "v", "w", "_param1", "signer_", "z", "var2"], random.randint(0, 3))
    return random.choice([None, storage]), random.choice([None, params])

def rinputs():
    """a function's params (the abi's inputs)"""
    if random.random() < 0.2: return None
    kinds = ["uint256", "address", "bytes", "string", "uint256[]", "bytes32[2]", "address[]", "array",
             "uint8[3][]", "tuple", "tuple[]", "tuple[2]", "string[]", "bool"]
    res = []
    for i in range(random.randint(0, 4)):
        k = random.choice(kinds)
        d = {"type": k, "name": random.choice(["amounts", "p", "_param2", "to", "x"]) if random.random() < 0.8 else f"_param{i + 1}"}
        if k.startswith("tuple") and random.random() < 0.85:
            d["components"] = [{"type": random.choice(["uint256", "address", "bytes", "uint8[2]"]), "name": random.choice(["a", "b", ""])}
                               for _ in range(random.randint(0, 3))]
        res.append(d)
    return res

def rtype(d=0):
    """a type of the storage (pretty_type's)"""
    r = random.random()
    if d > 2 or r < 0.35:
        return random.choice([256, 160, 8, 1, 32, 64, 128, 0, 2, 255, 7, 2**200, "bytes", "struct", ("struct", 1),
                              ("struct", random.choice([0, 2, 32, 64]))])
    if r < 0.5: return ("array", rtype(d + 1))
    if r < 0.65: return ("mapping", rtype(d + 1))
    if r < 0.85: return ("def", random.choice(["stor0", "owner", "x"]), random.choice([0, 3, 1000, 1001, 2**255, "loc"]), rtype(d + 1))
    return ("def", "x", random.choice([1, 2000]), ("mask", random.choice([8, 160, 256, 1]), random.choice([0, 8, 96, -1])))

def port_inputs(inputs):
    if inputs is None: return None
    def conv(i):
        comps, idx = i.get("components"), i.get("indexed")
        if comps is None and not idx:
            return (i["type"], i["name"])
        return (i["type"], i["name"], [conv(c) for c in comps] if comps is not None else None, 1 if idx else 0)
    return [conv(i) for i in inputs]

def py_with_names(storage, params, fn):
    P.set_names(storage=storage, params=params)
    try:
        return fn()
    finally:
        P.set_names(storage=[], params=None)

def py_with_inputs(inputs, fn):
    SIG._abi = {"0x00000000": {"name": "f", **({"inputs": inputs} if inputs is not None else {})}}
    SIG._func = SIG._abi["0x00000000"]
    try:
        return fn()
    finally:
        SIG._abi = None
        SIG._func = None

_check = check
def check(name, arg, expected, ctx=""):
    # python's MemoryError (a mask of 2^47 bits, whose range python makes
    # with 2 ** size: the port's algebra clamps it) says nothing of the
    # printer
    if expected.startswith("<exc MemoryError"):
        return True
    return _check(name, arg, expected, ctx)

# cases the random runs found once: always checked
REGRESSIONS = [
    # the length of a string in memory data, negative: python's index
    # goes back by it ('' for -1, an IndexError further)
    ("setmem", ("range", 0, 96), ("data", 32, -40, 5)),
    ("setmem", ("range", 0, 96), ("data", 32, -200, 1, 2)),
    ("return", ("data", 1, 2, 32, -40)),
]
for line in REGRESSIONS:
    for flags in (0, PF_COLOR):
        check("pretty_line", (line, flags), run(lambda l, f: list(P.pretty_line(l, add_color=bool(f & PF_COLOR))), line, flags), "regression")

FLAGS = (0, PF_PARENS, PF_COLOR, PF_PARENS | PF_COLOR, PF_REM_BOOL | PF_COLOR, PF_PARENS | PF_TOP, PF_REM_BOOL | PF_PARENS)
for n in range(N):
    exp = rexp()
    for flags in FLAGS:
        check("prettify", (exp, flags), run(py_prettify, exp, flags), "random %d" % n)
    line = rline()
    for flags in (0, PF_COLOR):
        check("pretty_line", (line, flags), run(lambda l, f: list(P.pretty_line(l, add_color=bool(f & PF_COLOR))), line, flags), "random %d" % n)
    # the names of the storage and of the params
    storage, params = rnames()
    flags = random.choice(FLAGS)
    check("prettify_n", (storage, params, exp, flags),
          run(lambda: py_with_names(storage, params, lambda: py_prettify(exp, flags))), "names %d" % n)
    check("pretty_line_n", (storage, params, line, PF_COLOR),
          run(lambda: py_with_names(storage, params, lambda: list(P.pretty_line(line, add_color=True)))), "names %d" % n)
    # the data
    data = random.choice([rdata(), rexp(), ("data",), "mem", None, rbytes(), rarr()])
    for flags in (0, PF_COLOR, PF_COLOR | 16, 16):
        check("pretty_memory_l", (data, flags),
              run(lambda: list(P.pretty_memory(data, add_color=bool(flags & PF_COLOR), abi_text=bool(flags & 16)))), "data %d" % n)
    el = random.choice([rbytes(), rexp(), rst(), rdata(), rword_text()])
    check("pretty_with_width", el, run(P.with_width, el), "width %d" % n)
    nn = random.choice([1, 4, 20, 32, 33])
    check("setmem_value", (el, nn), run(P.setmem_value, el, nn), "setmem_value %d" % n)
    fname, fparams = rfname(), rfparams()
    check("split_selector", (fname, fparams), run(P.split_selector, fname, fparams), "split %d" % n)
    check("callee_name", (fname, PF_COLOR), run(P.callee_name, fname, True), "callee %d" % n)
    b = rbytes()
    ctx = random.choice([0, 1, 4, 9, 13])
    check("pretty_bytes", (b[1], b[2], PF_COLOR, ctx), run(P.pretty_bytes, b[1], b[2], True, ctx), "bytes %d" % n)
    # a trace with loops
    trace = rtrace()
    check("pprint_logic", (trace, 2), run(lambda x: list(P.pprint_logic(x)), trace), "trace %d" % n)
    check("pprint_logic_n", (storage, params, trace, 2),
          run(lambda: py_with_names(storage, params, lambda: list(P.pprint_logic(trace)))), "trace names %d" % n)
    check("fix_widths", trace, run(P.fix_widths, trace), "fix_widths %d" % n)
    sv = rsetvars()
    check("sequential_setvars", sv, run(P.sequential_setvars, sv), "setvars %d" % n)
    t = rtype()
    check("pretty_type", t, run(P.pretty_type, t), "type %d" % n)
    # the params of the function printed
    inputs = rinputs()
    cd = random.choice([("cd", random.choice([4, 36, 68, 100, 132, 5, rint()])),
                        ("cd", ("add", random.choice([4, 36, 68, 100, 37]), ("cd", random.choice([4, 36, 68, 100])))),
                        ("cd", ("add", 4, ("param", random.choice(["amounts", "p", "x", "to"])))),
                        ("cd", ("add", 36, ("mul", 1, ("cd", 4))))])
    check("get_param_name", (port_inputs(inputs), cd, PF_COLOR),
          run(lambda: py_with_inputs(inputs, lambda: SIG.get_param_name(cd, add_color=True))), "params %d" % n)
    check("prettify_f", (port_inputs(inputs), exp, PF_PARENS),
          run(lambda: py_with_inputs(inputs, lambda: P.prettify(exp))), "params %d" % n)
    if inputs:
        check("calldata_params", port_inputs(inputs), run(lambda: list(SIG.calldata_params(inputs).values())), "params %d" % n)
        i = random.choice(inputs)
        check("canonical_type", (i["type"], port_inputs([i])[0][2] if len(port_inputs([i])[0]) > 2 else None),
              run(SIG.canonical_type, i["type"], i.get("components")), "params %d" % n)
        check("is_dynamic", (i["type"], port_inputs([i])[0][2] if len(port_inputs([i])[0]) > 2 else None),
              run(SIG.is_dynamic, i["type"], i.get("components")), "params %d" % n)
print(f"{test_simplify.cases} cases, {test_simplify.bad} mismatches")
