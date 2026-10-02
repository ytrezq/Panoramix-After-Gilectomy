#!/usr/bin/env python3
"""
Random differential tests of runtrace.s against panoramix.runtrace: random
traces and expressions run on concrete values by both machines, in worlds
made as storage.bytes_tail makes them (the words of bytes short and long,
Unsupported for another slot). Compared: how each run ends and its data,
the value of an expression asked first (storage's m.ev(key)), the steps,
the memory's length, the variables in their order, whether the bytes were
reached - or the exception (python's class against the port's code). One
machine runs every calldata of a case, reset in between (as storage would
reuse it), where python makes a Machine for each. The sizes past the
port's bound (RT_BYTES_MAX), where python goes on, aren't asked; a shift
count of 2^63 to 30 * 2^61, CPython's MemoryError, is the port's
OverflowError, pypy's (the references' python).

    python3 tests/test_runtrace.py [SEED [N]]
"""
import os, random, re, sys
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "panoramix")))
sys.path.insert(0, os.environ.get("PANASM_BUILD") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import logging; logging.disable(logging.CRITICAL)
import panoramix_asm as A
from panoramix.runtrace import Machine, Unsupported, keccak

# python's MemoryError for the absurd sizes (a shift by 2^64...) at once:
# 2 GiB of address space at most
import resource
_soft, _hard = resource.getrlimit(resource.RLIMIT_AS)
if _soft == resource.RLIM_INFINITY or _soft > (2 << 30):
    resource.setrlimit(resource.RLIMIT_AS, (2 << 30, _hard))
sys.setrecursionlimit(10000)

SEED = int(sys.argv[1]) if len(sys.argv) > 1 else 1
N = int(sys.argv[2]) if len(sys.argv) > 2 else 2000
rnd = random.Random(SEED)

CODES = {"Unsupported": 12, "IndexError": 7, "TypeError": 5, "ValueError": 10,
         "OverflowError": 13, "MemoryError": 8, "RecursionError": 9,
         "Continue": 14, "KeyError": 11}

M = 2**256

# what a case reads -------------------------------------------------------

def bytes_words(words, slot, content):
    """storage.bytes_tail's words of a bytes at slot"""
    padded = content + b"\0" * (-len(content) % 32)
    if len(content) < 32:
        words[slot] = int.from_bytes(padded.ljust(32, b"\0"), "big") | 2 * len(content)
    else:
        words[slot] = 2 * len(content) + 1
        base = keccak(slot.to_bytes(32, "big"))
        for i in range(len(padded) // 32 + 1):
            words[(base + i) % M] = int.from_bytes(padded[32 * i: 32 * i + 32].ljust(32, b"\0"), "big")


def world():
    words, slots = {}, []
    content = bytes(rnd.randrange(1, 256) for _ in range(rnd.choice([0, 1, 2, 30, 31, 32, 33, 63, 64, 65, 100])))
    for slot in rnd.sample([0, 1, 2, 5, 7, rnd.randrange(M)], rnd.randint(1, 3)):
        slots.append(slot)
        if rnd.random() < 0.7:
            bytes_words(words, slot, content)
        else:
            words[slot] = rint() % M      # (a word: never negative)
    if rnd.random() < 0.2:
        words[3] = rnd.choice([0, 1, 2**255, M - 1])
        slots.append(3)
    return words, slots, (content if rnd.random() < 0.85 else None)


def calldata():
    sel = rnd.randrange(2**32).to_bytes(4, "big")
    r = rnd.random()
    if r < 0.6:
        vals = [0, 1, 2, 255, 2**16 - 1, 2**160 - 1, 2**160, 2**255, M - 1]
        return sel + b"".join(rnd.choice(vals).to_bytes(32, "big") for _ in range(rnd.randint(0, 4)))
    if r < 0.8:
        return sel + b"\x01" * rnd.choice([0, 1, 31, 33])
    return bytes(rnd.randrange(256) for _ in range(rnd.randint(0, 80)))

# expressions -------------------------------------------------------------

KEYS = [1, 2, 3, "i", "x", "_msize", ("v", 1)]

def rint():
    r = rnd.random()
    if r < 0.35: return rnd.choice([0, 1, 2, 3, 4, 5, 7, 8, 16, 31, 32, 33, 36, 64, 68, 96, 100, 128, 160, 192, 224, 248, 255, 256, 257])
    if r < 0.5: return rnd.randint(0, 300)
    if r < 0.6: return rnd.choice([2**32 - 1, 2**32, 2**63, 2**64, 2**160 - 1, 2**160, 2**255 - 1, 2**255, M - 1, M - 32, 2**62, 2**62 - 1, -2**62])
    if r < 0.75: return rnd.randrange(M)
    if r < 0.85: return rnd.randint(-300, -1)
    if r < 0.92: return -rnd.randrange(M)
    return rnd.choice([M, M + 5, 2**300 + 12345, rnd.randrange(M, 2**320)])

def small():
    """a size, an offset, a shift"""
    r = rnd.random()
    if r < 0.6: return rnd.choice([0, 0, 1, 3, 8, 16, 32, 64, 96, 128, 160, 248, 255, 256, 300])
    if r < 0.75: return -rnd.choice([1, 3, 8, 16, 96, 160, 248, 256, 300])
    if r < 0.85: return rnd.choice([4096, 4097, -4096, -4097, 5000, 2**40, -2**40, 2**63 - 1, 2**63, -2**63, 2**64, -2**64, 2**70, -2**70, M - 8, 2**255])
    return rexp(1)

def atom():
    r = rnd.random()
    if r < 0.45: return rint()
    if r < 0.55: return rnd.choice(["calldatasize", "callvalue"])
    if r < 0.8: return ("var", rnd.choice(KEYS)) if VARS_SET or rnd.random() < 0.1 else rint()
    if r < 0.97: return ("cd", rnd.choice([0, 4, 36, 68, 100, 132, 2**32 - 1, 2**32, rnd.randint(0, 120)]))
    return rnd.choice([True, None, "x", ("var", [1]), (), (5,), ("var",)])

BIN = ["div", "mod", "sdiv", "smod", "exp", "signextend", "lt", "gt", "le", "ge", "eq",
       "slt", "sgt", "sle", "sge", "shr", "shl", "sar", "byte", "max", "min"]

def rexp(d=3):
    if d <= 0 or rnd.random() < 0.25:
        return atom()
    k = rnd.random()
    if k < 0.08: return ("cd", rexp(d - 1))
    if k < 0.12: return ("loc", rexp(d - 1))
    if k < 0.16: return ("bytes", rnd.choice([1, 20, 32, 40]), rexp(d - 1))
    if k < 0.24: return ("mask_shl", small(), small(), small(), rexp(d - 1))
    if k < 0.32: return rstorage(d)
    if k < 0.38: return ("mem", ("range", rpos(), rnd.choice([0, 1, 4, 20, 32, 32, 33, rexp(1)])))
    if k < 0.42: return ("call.data", rpos(), rnd.choice([0, 1, 4, 32, 33, rexp(1)]))
    if k < 0.48: return ("sha3", rbytes(d - 1))
    if k < 0.62: return (rnd.choice(["add", "mul", "and", "or", "xor"]),) + tuple(rexp(d - 1) for _ in range(rnd.choice([0, 1, 2, 2, 2, 3, 4])))
    if k < 0.70: return (rnd.choice(["not", "iszero", "bool"]), rexp(d - 1))
    if k < 0.94: return (rnd.choice(BIN), rexp(d - 1), rexp(d - 1))
    # what python can't run, or runs into an exception
    return rnd.choice([
        ("foo", rexp(d - 1)), ("div", rexp(d - 1)), ("not", 1, 2), ("sbytes", 5),
        ("mask_shl", 8, 0), ("mask_shl", 8, 0, 0), ("storage", 256), ("storage", 256, 0),
        ("mem", 5), ("mem", ("range", 0)), ("call.data", 0), ("sha3", 1, 2), ("bytes", 5),
        ("var",), ("loc",), ("cd",), (5, 1), ("range", 1, 2), ("sub", 3, 1),
        ("code.data", 0, ("add", 1, 2)), ("extcodecopy", 1, ("range", 0, 4)),
    ])

def rpos():
    return rnd.choice([0, 0, 32, 64, 96, 128, 160, 192, 1, 31, 2**20 - 32, 2**20, M - 1, rexp(1)])

def rslot():
    return rnd.choice(SLOTS + [rexp(1)]) if SLOTS else rexp(1)

def rstorage(d):
    size = rnd.choice([256, 256, 160, 8, 1, 248, small()])
    off = rnd.choice([0, 0, 0, 8, 96, 160, -8, -96, small()])
    if rnd.random() < 0.2:
        size, off = rnd.choice([(-1, -8), (2**64, -8), (2**70, -8), (2**63 - 1, -8), (8, -2**40), (8, -2**63), (8, 1 - 2**63),
                                (2**200, -1), (0, -2**200), (300, -300), (2**27, -1), (8, -2**27)])
    slot = rslot()
    if rnd.random() < 0.3:
        slot = ("length", slot)
    return ("storage", size, off, slot)

def rbytes(d=2):
    """an element of a data"""
    k = rnd.random()
    if d <= 0 or k < 0.3: return rexp(max(d, 1))
    if k < 0.5: return ("data",) + tuple(rbytes_elem(d - 1) for _ in range(rnd.randint(0, 4)))
    if k < 0.6: return ("mem", ("range", rpos(), rnd.choice([0, 1, 31, 32, 33, 64, 100, rexp(1)])))
    if k < 0.7: return ("call.data", rnd.choice([0, 4, 36, 100, M - 1, rexp(1)]), rnd.choice([0, 4, 32, 64, 100, 2**63, 2**62, M - 1, rexp(1)]))
    if k < 0.8: return ("bytes", rnd.choice([0, 1, 4, 20, 31, 32, 33, 40, 64, 2**64, rexp(1)]), rnd.choice([rint(), rexp(1)]))
    if k < 0.9: return ("sbytes", rslot())
    return rexp(d)

def rbytes_elem(d):
    if rnd.random() < 0.3:
        return ("arr", rnd.choice([0, 1, 5, 64, rexp(1)])) + tuple(rbytes(d) for _ in range(rnd.randint(0, 3)))
    return rbytes(d)

# traces -------------------------------------------------------------------

def rline(d, loops):
    k = rnd.random()
    if k < 0.25: return ("setvar", rnd.choice(KEYS), rexp())
    if k < 0.45:
        n = rnd.choice([32, 32, 32, 1, 4, 20, 0, 64, rexp(1)])
        v = rexp() if rnd.random() < 0.6 else rbytes()
        return ("setmem", ("range", rpos(), n), v)
    if k < 0.58 and d > 0:
        if rnd.random() < 0.4:
            return ("if", rexp(2), rtrace(d - 1, loops))
        return ("if", rexp(2), rtrace(d - 1, loops), rtrace(d - 1, loops))
    if k < 0.66 and d > 0:
        return rwhile(d, loops)
    if k < 0.72 and loops:
        return ("continue", rnd.choice(loops), [("setvar", rnd.choice(KEYS), rexp(2)) for _ in range(rnd.randint(0, 2))])
    if k < 0.84:
        return (rnd.choice(["return", "revert"]), rnd.choice([None, rbytes(), ("data", rbytes_elem(1), rbytes_elem(1))]))
    if k < 0.88: return (rnd.choice(["stop", "invalid"]),)
    if k < 0.96: return ("setvar", rnd.choice(KEYS), rexp(1))
    return rnd.choice([
        ("setvar", 1), ("setvar",), ("setmem", 5, 1), ("setmem", ("range", 0, 32)), ("foo",), 5, (),
        ("while", 1, [], "j"), ("if",), ("if", 1), ("continue", "nowhere", []), ("return",),
        ("if", 1, 5), ("if", 0, [], None), ("setvar", [1], 2), ("while", ("lt", ("var", "i"), 3), [], "j", 7),
        ("if", 1, "abc"), ("if", 1, ""), ("while", 0, [], "j", "x"), ("log", 1),
    ])

def rtrace(d, loops=()):
    return [rline(d, loops) for _ in range(rnd.randint(0, 4))]

def rtrace_top():
    """a trace whose variables are mostly set first"""
    global VARS_SET
    VARS_SET = rnd.random() < 0.8
    pre = [("setvar", k, rint()) for k in KEYS if rnd.random() < 0.8] if VARS_SET else []
    return pre + rtrace(3)

def rwhile(d, loops):
    jd = rnd.choice(["jd1", "jd2", ("jd", 3), 7])
    i = rnd.choice(["i", 1, ("v", 1)])
    n = rnd.choice([0, 1, 3, 10, 50, rexp(1)])
    step = [("setvar", i, ("add", ("var", i), rnd.choice([1, 1, 2, 31])))]
    body = rtrace(d - 1, loops + (jd,))
    k = rnd.random()
    if k < 0.5:
        body = body + [("continue", jd, step)]
    elif k < 0.8:
        body = body + [("if", ("lt", ("var", i), n), [("continue", jd, step)], rtrace(0, loops))]
    return ("while", ("lt", ("var", i), n), body, jd, [("setvar", i, rnd.choice([0, 0, 1, rexp(1)]))])

def getter(slot):
    """the copy of a bytes of the storage to memory, as solc does it"""
    w, n, i = ("var", "w"), ("var", "n"), ("var", "i")
    return [
        ("setvar", "w", ("storage", 256, 0, slot)),
        ("if", ("iszero", ("and", w, 1)),
         [("setvar", "n", ("div", ("and", w, 255), 2))],
         [("setvar", "n", ("div", ("add", w, -1), 2))]),
        ("setmem", ("range", 128, 32), 32),
        ("setmem", ("range", 160, 32), n),
        ("if", ("gt", n, 31),
         [("while", ("lt", ("mul", 32, i), n),
           [("setmem", ("range", ("add", 192, ("mul", 32, i)), 32),
             ("storage", 256, 0, ("add", ("sha3", slot), i))),
            ("continue", "jd", [("setvar", "i", ("add", i, 1))])],
           "jd", [("setvar", "i", 0)])],
         [("setmem", ("range", 192, 32), ("and", w, ("not", 255)))]),
        ("return", ("mem", ("range", 128, ("add", 64, ("mul", 32, ("div", ("add", n, 31), 32)))))),
    ]

def tail(slot):
    """storage.bytes_tail's: `return Array(len=b.length, data=b[all])`"""
    return [("return", ("data", ("arr", ("storage", 256, 0, ("length", slot)), ("sbytes", slot))))]

# the two machines ---------------------------------------------------------

def run_py(calldatas, words, content, callvalue, max_steps, key, trace):
    out = []
    for cd in calldatas:
        reached = []

        def sload(slot):
            if slot not in words:
                raise Unsupported("another slot")
            return words[slot]

        def bytes_length(slot):
            v = sload(slot)
            return (v - 1) // 2 if v & 1 else (v & 0xFF) // 2

        def bytes_data(slot):
            reached.append(slot)
            return content

        m = Machine(cd, sload, bytes_length, bytes_data=bytes_data if content is not None else None,
                    callvalue=callvalue, max_steps=max_steps)
        try:
            kv = m.ev(key) if key is not None else None
            kind = data = None
            if trace is not None:
                kind, data = m.run(trace)
                data = data.hex()
            out.append(repr((kv, kind, data, m.steps, len(m.mem), list(m.vars.items()), bool(reached))))
        except MemoryError:
            out.append("<exc 8>")
        except Exception as e:
            out.append("<exc %s>" % CODES.get(type(e).__name__, type(e).__name__))
    return out

def run_asm(calldatas, words, content, callvalue, max_steps, key, trace):
    lit = repr((tuple(cd.hex() for cd in calldatas), tuple(words.items()),
                None if content is None else content.hex(), callvalue, max_steps, key, trace))
    return parse_results(A._test("runtrace", lit))

def parse_results(text):
    """the results' reprs, from the port's tuple of them (its errors as
    their codes)"""
    import ast
    if not text.startswith("("):
        return [text]
    out = []
    depth, start, i, q = 0, 1, 1, None
    while i < len(text) - 1:
        c = text[i]
        if q:
            if c == "\\":
                i += 1
            elif c == q:
                q = None
        elif c in "'\"":
            q = c
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "," and depth == 0:
            out.append(text[start:i].strip())
            start = i + 1
        i += 1
    last = text[start:len(text) - 1].strip()
    if last:
        out.append(last)
    res = []
    for r in out:
        if r[:1] in "'\"" and r[1:6] == "<exc ":
            m = re.match(r"<exc (\d+):", ast.literal_eval(r))
            res.append("<exc %s>" % m.group(1))
        else:
            res.append(r)
    return res

# the cases ------------------------------------------------------------------

def regressions():
    """what the random cases reach seldom, every time"""
    cd = [bytes.fromhex("aabbccdd") + (5).to_bytes(32, "big"), b""]
    i, x = ("var", "i"), ("var", "x")
    inc = lambda v, k=1: [("setvar", v, ("add", ("var", v), k))]
    loop = lambda jd, n, body, init=0: ("while", ("lt", i, n), body, jd, [("setvar", "i", init)])
    traces = [
        [("continue", "j", [])],                                    # out of every loop
        [loop("a", 3, [("continue", "b", inc("i"))])],             # of another loop
        [loop("a", 3, [("setvar", "x", 7), ("continue", "a", inc("i"))]), ("return", ("data", i, x))],
        [loop("a", 2, [("setvar", "y", 0), ("while", ("lt", ("var", "y"), 3),
                        [("if", ("eq", ("var", "y"), 1), [("continue", "a", inc("i"))]),
                         ("continue", "b", inc("y"))], "b", []), ("revert", None)]),
         ("return", ("data", i, ("var", "y")))],                    # an inner loop continues the outer
        [("while", ("lt", i, 5), [("continue", "a", [("setvar", "i", ("add", i, 1)), ("setvar", "x", i)])], "a",
          [("setvar", "i", 1), ("setvar", "x", ("var", "i"))])],   # all at once: the old values
        [("setvar", "i", 0), ("while", 1, [("continue", "a", [("setvar", "i", 1), ("setvar", "i", ("add", i, 5))])], "a", [])],
        [("if", 1, "abc")], [("if", 1, "")], [("if", 0, [], "x")], "", "ab", 5, None, (("stop",),),
        [("while", 1, [], "a", "")], [("while", 1, [], "a", "s")], [("while", 1, [], "a", 5)],
        [("setvar", ("t", (1, 2)), 3), ("return", ("data", ("var", ("t", (1, 2)))))],
        [("setvar", ("t", [1]), 3)], [("setvar", 1, ("var", [1]))], [("setvar", [1], ("var", 9))],
        [("return", ("bytes", 2**60 - 1, 0))], [("return", ("bytes", 2**60, 0))], [("return", ("bytes", 2**61, 0))],
        [("return", ("bytes", 40, 2**300 + 2**256 + 7))], [("return", ("bytes", 33, -5))], [("return", ("bytes", 3, -5))],
        [("return", ("bytes", 0, ("var", 1)))], [("return", ("bytes", 36, 2**256))],
        [("return", ("call.data", 2, 2**63 - 1))], [("return", ("call.data", 2, 2**63 + 1))], [("return", ("call.data", 2**256 - 1, 3))],
        [("return", ("storage", 8, -2**63, 5))], [("return", ("storage", 8, 1 - 2**63, 5))], [("return", ("storage", 2**63, -8, 5))],
        [("return", ("storage", 2**63 - 1, -8, 5))], [("return", ("storage", -1, -8, 5))], [("return", ("storage", 0, -2**100, 5))],
        [("return", ("storage", 256, -255, 5))], [("return", ("storage", 300, -1, 5))], [("return", ("storage", 8, 250, ("length", 5)))],
        [("setmem", ("range", 2**20 - 32, 32), 1), ("return", ("mem", ("range", 0, 2**20)))],
        [("setmem", ("range", 2**20 - 31, 32), 1)], [("setmem", ("range", 2**20, 0), 1)], [("setmem", ("range", 50, 0), ("data",))],
        [("return", ("mem", ("range", 2**20, 0)))], [("setvar", 1, ("mem", ("range", 2**20 - 32, 32)))],
        [("return", ("sha3", ("data", ("call.data", 0, 300), ("arr", 3, 1, ("bytes", 7, 9)), ("arr", 0), 5)))],
        [("return", ("data", ("arr", ("var", 9)), ("arr", 1, ("var", 8))))],
        [("return", ("data", ("arr",)))], [("return", ("data", ("arr", 2, ("call.data", 0, 70)), ("mem", ("range", 0, 3))))],
        [("return", ("code.data", ("bytes",), ("add", 1, 2)))], [("return", ("code.data", 1, ("add", 1, 2, 29)))],
        [("return", ("code.data", 1, ("mul", -1, ("add", 0, -4))))], [("return", ("extcodecopy", 1, ("range", 0, 2)))],
        [("return", ("arr", 1, 2))], [("return", ("mem", 5))], [("return", 2**256 + 1)], [("return", 2**256)], [("return", -1)],
        [("return", ("mask_shl", 8, 0, 0, 2**300 - 1))], [("return", ("mask_shl", ("var", 1), 0, 0, 1))], [("return", ("storage", True, 0, 5))],
        [("setmem", ("range", 0, 3), ("sbytes", 5))], [("setmem", ("range", 0, 40), ("sbytes", 5))], [("setmem", ("range", 0, 2), 0x1234567)],
        [("setmem", ("range", 0, 5), ("bytes", 3, 7))], [("setmem", ("range", 0, 32), ("data", 1))],
    ]
    for c in [M - 1, 0, 2**255]:
        traces.append([("return", ("data", ("sdiv", c, M - 1), ("smod", c, M - 1), ("sdiv", 2**255, M - 1), ("signextend", 30, c),
                                    ("signextend", 31, c), ("sar", 255, c), ("sar", 256, c), ("byte", 0, c), ("exp", c, M - 1)))])
    for t in traces:
        for max_steps in (20000, 3):
            yield (cd, {5: 2 * 3, 7: 2 * 40 + 1}, b"abc", 0, max_steps, None, t)
    for content in [b"", b"a", bytes(range(1, 32)), bytes(range(1, 33)), bytes(range(1, 34)), bytes(range(1, 101))]:
        words = {}
        bytes_words(words, 5, content)
        for t in (getter(5), tail(5)):
            for max_steps in (20000, 20, 40):
                yield (cd, words, content, 0, max_steps, 5, t)
    # the steps around the limits: lines (max_steps), expressions (20 times)
    for k in range(1, 6):
        yield ([b""], {}, None, 0, k, None, [("setvar", 1, 2)] * 3)
        yield ([b""], {}, None, 0, k, ("add",) + (1,) * (20 * k - 1), None)
        yield ([b""], {}, None, 0, k, ("add",) + (1,) * (20 * k), None)

SLOTS = []
VARS_SET = False                        # (no variable is set before a trace)
cases = bad = 0
REG = list(regressions())
for n in range(len(REG) + N):
    if n < len(REG):
        args = REG[n]
    else:
        words, SLOTS, content = world()
        calldatas = [calldata() for _ in range(rnd.choice([1, 1, 2, 3]))]
        callvalue = 0 if rnd.random() < 0.8 else rnd.choice([1, 2**255, M - 1])
        max_steps = 20000 if rnd.random() < 0.85 else rnd.choice([0, 1, 3, 10, 30, 100])
        VARS_SET = False
        key = rexp() if rnd.random() < 0.5 else None
        r = rnd.random()
        if r < 0.12:
            trace = getter(rnd.choice(SLOTS))
            key = rnd.choice(SLOTS)
        elif r < 0.17:
            trace = tail(rnd.choice(SLOTS))
            key = rnd.choice(SLOTS)
        elif r < 0.25:
            trace = None
            key = rexp(rnd.randint(1, 5))
        else:
            trace = rtrace_top()
        args = (calldatas, words, content, callvalue, max_steps, key, trace)
    try:
        expected = run_py(*args)
    except RecursionError:
        continue
    try:
        got = run_asm(*args)
    except Exception as e:
        got = ["<asm %s: %s>" % (type(e).__name__, e)]
    cases += 1
    # CPython's MemoryError for a shift count of 2^63 to 30 * 2^61 is
    # pypy's OverflowError, the port's
    expected = ["<exc 13>" if e == "<exc 8>" and g == "<exc 13>" else e for e, g in zip(expected, got)] + expected[len(got):]
    if expected != got:
        bad += 1
        print(f"MISMATCH #{n}: {args!r}")
        for i, (e, g) in enumerate(zip(expected, got)):
            if e != g:
                print(f"   run {i}\n   python: {e[:600]}\n   asm:    {g[:600]}")
        if len(expected) != len(got):
            print(f"   python: {expected}\n   asm:    {got}")
        if bad >= 10:
            break
print(f"{cases} cases, {bad} mismatches")
sys.exit(1 if bad else 0)
