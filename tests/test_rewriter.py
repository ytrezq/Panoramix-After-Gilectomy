#!/usr/bin/env python3
"""Random differential tests of rewriter.s against panoramix.rewriter:
postprocess_exp (the arrays of a data, ABI-encoded: abi_content,
byte_size), postprocess_trace (through rewrite_trace_ifs, as
simplify_trace does) and rewrite_string_stores.

    python3 tests/test_rewriter.py SEED COUNT     (ONLY=name,... MAXBAD=n)
"""
import os, random, sys
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "panoramix")))
sys.path.insert(0, os.environ.get("PANASM_BUILD") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import logging; logging.disable(logging.CRITICAL)
import panoramix_asm as A
from panoramix import rewriter as R
from panoramix.core import algebra as AL
from panoramix.utils.helpers import rewrite_trace_ifs, replace_f

random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 1)
N = int(sys.argv[2]) if len(sys.argv) > 2 else 300

WORDS = ["x", ("cd", 4), ("cd", 36), "callvalue", ("var", "_1"), ("storage", 256, 0, 5), ("mem", ("range", 64, 32)), 0, 1, 31, 100, 2**255]
LENGTHS = [("cd", 4), ("cd", ("add", 4, ("cd", 36))), 5, 32, 64, 0, ("mask_shl", 64, 0, 0, ("cd", 36)), "x", ("var", "_1"), ("storage", 256, 0, ("length", 3))]

def rlen():
    return random.choice(LENGTHS)

def words_of(l):
    return ("mask_shl", 251, 5, 0, AL.add_op(31, l))

def rcontent(l):
    """the content of an array of length l, as a data has it"""
    r = random.random()
    if r < 0.25:
        # whole words
        return tuple(random.choice(WORDS + [("mem", ("range", 128, 64)), ("call.data", 68, 32)]) for _ in range(random.randint(0, 3)))
    if r < 0.55:
        # its bytes, then the zeroes up to whole words
        src = random.choice([("call.data", ("add", 36, ("cd", 4)), l), ("mem", ("range", ("add", 160, "x"), l)), ("ext_call.return_data", 64, l), ("bytes", l, "y")])
        pad = random.choice([("bytes", AL.sub_op(words_of(l), l), 0), ("bytes", AL.sub_op(words_of(l), l), 0), 0, ("bytes", 31, 0), ("bytes", ("cd", 4), 0)])
        res = (src, pad)
        if random.random() < 0.2: res = res + (0,)
        if random.random() < 0.1: res = (("bytes", 4, ("cd", 0)),) + res
        return res
    if r < 0.7:
        # bytes that aren't whole words, no padding
        return tuple(random.choice([("bytes", random.choice([1, 4, 20, 31, 33]), "z"), ("mask_shl", 160, 0, 0, "caller"), ("call.data", 4, random.choice([4, 32, ("cd", 4)])), 2**300, ("bytes", ("cd", 4), "w")]) for _ in range(random.randint(1, 3)))
    if r < 0.8:
        # what has no width: an ABI array, a mem of no range (sizeof asserts)
        return random.choice([(("arr", ("cd", 4), "q"),), (("mem", "x"),), (("mem", ("range", 0, 32)), ("arr", 5, 5)), ("x", ("sall", 5))])
    return tuple(random.choice(WORDS + [("bytes", 4, "z"), 0, ("bytes", 3, 0)]) for _ in range(random.randint(0, 4)))

def rdata():
    """('data', ..., offset, ..., length, content...): an array at the offset"""
    r = random.random()
    if r < 0.7:
        before = [random.choice(WORDS[:6]) for _ in range(random.randint(0, 3))]
        l = rlen()
        content = rcontent(l)
        # the offset: where the length is, in words - among the words before it
        loc = len(before) + random.choice([1, 1, 1, 2, 0])
        off = random.choice([32 * loc, 32 * loc, 32 * (loc + 1), 32 * loc + 1])
        pos = random.randint(0, len(before))
        terms = before[:pos] + [off] + before[pos:]
        if random.random() < 0.1: terms.append(random.choice([64, 96, -32, 2**256]))
        if random.random() < 0.1: terms[random.randrange(len(terms))] = random.choice([("mask_shl", 160, 0, 0, "caller"), ("bytes", 4, "x"), ("mem", "y")])
        return ("data",) + tuple(terms) + (l,) + content
    return ("data",) + tuple(random.choice(WORDS + [32, 64, 96, -32, 2**260, ("bytes", 4, "x"), ("arr", 5, "x")]) for _ in range(random.randint(0, 5)))

def rline(depth=0):
    r = random.random()
    if r < 0.25:
        return ("return", rdata())
    if r < 0.35:
        return ("log", 123, rdata())
    if r < 0.45:
        return ("store", 256, 0, random.choice([3, 4]), random.choice(WORDS))
    if r < 0.55:
        return ("setmem", ("range", 64, 32), random.choice(WORDS))
    if depth < 2:
        return rif(depth + 1)
    return ("stop",)

ARRS = [lambda l: ("return", ("data", 32, ("arr", ("storage", 256, 0, l), ("mem", ("range", 128, 32))))),
        lambda l: ("log", 1, ("data", ("arr", ("storage", 256, 0, l), "x"))),
        lambda l: ("return", ("data", 32, ("arr", l, "x"))),
        lambda l: ("setmem", ("range", 0, 32), ("arr", l)),
        ]

def rbranch(l, depth):
    res = [rline(depth + 1) for _ in range(random.randint(0, 2))]
    for _ in range(random.choice([0, 1, 1, 2])):
        res.insert(random.randint(0, len(res)), random.choice(ARRS)(l))
    return res

def rif(depth=0):
    r = random.random()
    l = random.choice([("loc", 1), 3, ("cd", 4), ("var", "_1")])
    if r < 0.3:
        return ("if", ("iszero", ("storage", 5, 0, l)), rbranch(l, depth), rbranch(l, depth))
    if r < 0.6:
        return ("if", ("iszero", ("mask_shl", 5, 0, 0, l)), rbranch(l, depth), rbranch(l, depth))
    if r < 0.9:
        some_len = random.choice([("storage", 256, 0, ("length", 1)), ("cd", ("add", 4, ("cd", 4))), ("var", "_2")])
        first = random.choice([("store", 256, 0, 1, ("add", 1, ("mul", 2, some_len))), ("store", 256, 0, 1, 5), ("setmem", ("range", 0, 32), some_len)])
        second = random.choice([("if", ("iszero", some_len), [rline(depth + 1)], [rline(depth + 1), ("stop",)]), ("if", ("iszero", "zz"), [], []), ("stop",)])
        if_true = [first, second] + [rline(depth + 1) for _ in range(random.randint(0, 2))]
        if random.random() < 0.1: if_true = if_true[:1]
        return ("if", ("lt", 31, some_len), if_true, [rline(depth + 1)])
    return ("if", random.choice([("iszero", "x"), ("lt", 32, "y")]), [rline(depth + 1)], [rline(depth + 1)])

def norm(r):
    if r is None: return "None"
    if r is True: return "True"
    if r is False: return "False"
    return repr(r)

def run(fn, *args):
    try:
        return norm(fn(*args))
    except Exception as e:
        return "<exc %s: %s>" % (type(e).__name__, e)

ONLY = set(os.environ["ONLY"].split(",")) if os.environ.get("ONLY") else None
MAXBAD = int(os.environ.get("MAXBAD", "12"))

cases = bad = 0
def check(name, arg, expected):
    global cases, bad
    if ONLY and name not in ONLY:
        return
    cases += 1
    lit = repr(arg)
    try:
        got = A._test(name, lit)
    except Exception as e:
        got = "<asm exc %s>" % e
    ok = expected == got or (expected.startswith("<exc") and (got.startswith("'<exc") or got.startswith('"<exc')))
    if not ok:
        bad += 1
        print(f"MISMATCH {name}({lit})\n   python: {expected}\n   asm:    {got}")
        if bad >= MAXBAD:
            print("too many mismatches"); sys.exit(1)

if __name__ == "__main__":
    for n in range(N):
        d = rdata()
        check("postprocess_exp", d, run(R.postprocess_exp, d))
        terms = d[1:]
        check("byte_size", terms, run(R.byte_size, terms))
        if len(terms) >= 1:
            k = random.randrange(len(terms))
            check("abi_content", (terms[k], terms[k + 1:]), run(lambda a, b: R.abi_content(a, b), terms[k], terms[k + 1:]))
        line = rif()
        check("postprocess_trace", line, run(R.postprocess_trace, line))
        trace = [rline() for _ in range(random.randint(1, 4))]
        check("postprocess_trace_ifs", trace, run(rewrite_trace_ifs, trace, R.postprocess_trace))
        check("postprocess_exp_f", trace, run(lambda t: replace_f(replace_f(t, R.postprocess_exp), R.postprocess_exp), trace))
    print(f"{cases} cases, {bad} mismatches")
    sys.exit(1 if bad else 0)
