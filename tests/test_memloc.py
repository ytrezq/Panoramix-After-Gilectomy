#!/usr/bin/env python3
"""Random differential tests of memloc.s against panoramix.core.memloc."""
import os, random, sys
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "panoramix")))
sys.path.insert(0, os.environ.get("PANASM_BUILD") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import logging; logging.disable(logging.CRITICAL)
import panoramix_asm as A
from panoramix.core import memloc as M
from panoramix.core import algebra as AL
from panoramix.core.masks import find_mask

random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 1)
N = int(sys.argv[2]) if len(sys.argv) > 2 else 300

ATOMS = [("cd", 4), ("cd", 36), "callvalue", ("var", "_1"), ("var", "_2"), ("storage", 256, 0, 5), ("mem", ("range", 64, 32)), "x", "undefined", ("sha3", ("mem", ("range", 0, 64)))]

def rint(small=False):
    if small or random.random() < 0.7: return random.choice([0, 1, 2, 4, 8, 16, 20, 31, 32, 33, 64, 65, 96, 100, 128, 160, 192, 224, 248, 255, 256, 288, 320])
    return random.choice([-1, -8, -32, 2**160 - 1, 2**255, 2**256 - 1, random.randint(0, 2**256)])

def rpos():
    r = random.random()
    if r < 0.6: return rint(True)
    if r < 0.8: return random.choice(ATOMS)
    return ("add", rint(True), random.choice(ATOMS))

def rrange():
    return ("range", rpos(), random.choice([32, 32, 32, 4, 20, 64, 96, 1, 0, rpos()]))

def rval(depth=0):
    r = random.random()
    if depth > 1 or r < 0.4: return rint() if random.random() < 0.4 else random.choice(ATOMS)
    op = random.choice(["mask_shl", "mem", "or", "storage", "add", "call.data", "bool", "mul", "data"])
    if op == "mask_shl":
        return ("mask_shl", random.choice([8, 32, 64, 96, 160, 224, 248, 253, 256, ("mask_shl", 253, 0, 3, ("cd", 4))]), random.choice([0, 0, 8, 96, 160, 192]), random.choice([0, 0, -8, -96, 8, 96, 3, 5]), rval(depth + 1))
    if op == "mem": return ("mem", rrange())
    if op == "or": return ("or",) + tuple(rval(depth + 1) for _ in range(random.randint(2, 3)))
    if op == "storage": return ("storage", random.choice([256, 160, 8, 32]), random.choice([0, 0, 8, 160]), random.choice([5, ("map", 1, 2)]))
    if op == "add": return ("add", rint(True), rval(depth + 1))
    if op == "call.data": return (random.choice(["call.data", "ext_call.return_data"]), rpos(), rpos())
    if op == "bool": return ("bool", rval(depth + 1))
    if op == "mul": return ("mul", random.choice([1, 2, 8, 32, -1]), rval(depth + 1))
    if random.random() < 0.5:
        return random.choice([
            ("bytes", random.choice([1, 4, 20, 32, 33, 64, ("cd", 4)]), rval(depth + 1)),
            ("extcodecopy", "x", ("range", rpos(), random.choice([32, 4, 64, rpos()]))),
            ("arr", ("cd", 4), rval(depth + 1)),
            ("sha3", rval(depth + 1), rval(depth + 1)),
            ("mem", rpos()),
            ("sall", 5),
            ("data", ("bytes", 4, ("cd", 4)), ("mem", ("range", 64, random.choice([32, 4, 100])))),
        ])
    return ("data",) + tuple(rval(depth + 1) for _ in range(random.randint(0, 3)))

def rwide():
    """what's in memory, of a width"""
    return random.choice([rval(), ("bytes", random.choice([4, 20, 32]), rval()), ("mem", rrange()), ("call.data", rpos(), random.choice([4, 32, 64])),
                          ("data", rval(), ("bytes", 4, ("cd", 4))), ("data", ("mem", ("range", 0, 4)), ("mem", ("range", 100, 28))), 5, 2**300, ("mask_shl", 160, 0, 0, ("cd", 4))])


# the parts of a word written to storage or memory (split_store, split_setmem)
SLOTS = [5, 0, ("map", 1, 2), ("var", "_1"), ("add", 1, ("sha3", 0)), 7]

def ratom():
    return random.choice(["x", "y", ("cd", 4), ("cd", 36), "callvalue", ("var", "_1"), "caller", ("mask_shl", 160, 0, 0, "caller")])

def rpart(idx):
    r = random.random()
    if r < 0.3:
        size = random.choice([1, 7, 8, 16, 32, 64, 96, 160, 248, 255, 256])
        off = random.choice([0, 0, 0, 8, 96, 160])
        shl = random.choice([0, 0, 8, 96, 160, 224, -8, 5, 248])
        x = random.choice([ratom(), ("storage", 256, 0, idx), ("storage", 160, 0, idx), ("storage", 8, random.choice([0, 160, 168]), idx),
                           ("bool", ratom()), ("iszero", ratom()), ("lt", ratom(), 5), ("mask_shl", 8, 0, 0, ratom()), ("mem", ("range", 64, 32)), 5])
        return ("mask_shl", size, off, shl, x)
    if r < 0.5:
        return ("storage", random.choice([8, 16, 64, 96, 160, 1]), random.choice([0, 8, 160, 168, 224, -96, -8, -160, -64]), idx if random.random() < 0.8 else random.choice(SLOTS))
    if r < 0.6:
        return random.choice([("bool", ratom()), ("iszero", ratom()), ("lt", ratom(), ratom()), ("eq", ratom(), 5)])
    if r < 0.75:
        return random.choice([0, 1, 255, 0xff << 224, 0xffff << 160, 2**160 - 1, (2**96 - 1) << 160, 0x1234 << 8, 2**255])
    if r < 0.8:
        return ("mul", 1, rpart(idx))
    if r < 0.85:
        return "caller"
    return ("mask_shl", random.choice([8, 32, 160]), 0, random.choice([0, 8, 160, 224]), ("mask_shl", random.choice([1, 8]), 0, 0, ratom()))

def rbyte_field(idx):
    k = random.choice([0, 1, 2, 31, 32, ("var", "_1"), ("mask_shl", 5, 0, 0, ("cd", 4)), ("cd", 4), ("mask_shl", 8, 0, 0, "x"), ("mask_shl", 3, 0, 0, "x")])
    k2 = k if random.random() < 0.85 else random.choice([0, 1, ("cd", 4)])
    v = random.choice([("bool", "x"), ("mask_shl", 8, 0, 0, ("cd", 4)), 1, 0, 255, 256, ("cd", 4), "x", ("iszero", "x"), ("mask_shl", 16, 0, 0, "y"), ("mask_shl", 160, 0, 0, "caller")])
    mask = random.choice([1, 255, 65535, 2**160 - 1, 256, 0, -1, 2**256 - 1, 3, 7, 2**64 - 1])
    fp = [v, ("exp", 256, k)]
    if random.random() < 0.2: fp.append(1)
    if random.random() < 0.05: fp.append(("exp", 256, k))
    if random.random() < 0.05: fp.append("z")
    random.shuffle(fp)
    fm = [mask, ("exp", 256, k2)]
    if random.random() < 0.1: fm.append(1)
    random.shuffle(fm)
    cleared = ("not", ("mul",) + tuple(fm))
    if random.random() < 0.05: cleared = ("iszero", ("mul",) + tuple(fm))
    stor = ("storage", 256, 0, idx if random.random() < 0.9 else 7)
    keep = ("and", cleared, stor) if random.random() < 0.5 else ("and", stor, cleared)
    put = ("mul",) + tuple(fp)
    return ("store", 256, 0, idx, ("or", put, keep) if random.random() < 0.5 else ("or", keep, put))

def rstore_line():
    idx = random.choice(SLOTS)
    r = random.random()
    if r < 0.25:
        return rbyte_field(idx)
    if r < 0.35:
        return ("store", 256, 0, idx, ("mask_shl", random.choice([8, 160, 248, 255, 96]), random.choice([0, 8, 96, 160, -8]), 0, ("storage", 256, 0, idx)))
    if r < 0.45:
        return ("store", 256, 0, idx, rpart(idx))
    return ("store", 256, 0, idx, ("or",) + tuple(rpart(idx) for _ in range(random.randint(2, 4))))

def rmempart(base):
    r = random.random()
    if r < 0.4:
        at = random.choice([base, ("add", 12, base) if type(base) != int else base + 12, ("add", 32, base) if type(base) != int else base + 32, 0, 1000, "z"])
        if type(at) == tuple and at[0] == "add" and type(at[2]) == int: at = at[1] + at[2]
        return ("mask_shl", random.choice([160, 96, 8, 32, 256]), random.choice([0, 0, 96]), random.choice([0, 96, -96, 160, 224]), ("mem", ("range", at, random.choice([32, 32, 20, 4]))))
    if r < 0.5:
        return ("mask_shl", 8, 0, random.choice([0, 248]), "msize")
    return rpart(5)

def rsetmem_line():
    base = random.choice([64, 128, ("var", "_1"), 0, "x"])
    rng = ("range", base, random.choice([32, 32, 32, 20, 4, ("cd", 4)]))
    return ("setmem", rng, ("or",) + tuple(rmempart(base) for _ in range(random.randint(2, 4))))

def rstores(n):
    idx = random.choice(SLOTS)
    res, pos = [], 0
    while pos < 256 and len(res) < n:
        size = random.choice([1, 3, 7, 8, 16, 160, 5, 64])
        val = random.choice([0, 0, ("bool", ratom()), ratom(), ("storage", 8, random.choice([0, 8, 160]), idx), ("mask_shl", 8, 0, 0, ("storage", 256, 0, idx)), ("storage", 160, 0, random.choice(SLOTS))])
        res.append(("store", size, pos, idx, val))
        pos += size
    return res

def run(fn, *args):
    try:
        r = fn(*args)
        if r is None: return "None"
        if r is True: return "True"
        if r is False: return "False"
        return repr(r)
    except Exception as e:
        return "<exc %s: %s>" % (type(e).__name__, e)

ONLY = set(os.environ["ONLY"].split(",")) if os.environ.get("ONLY") else None

cases = bad = 0
def check(name, args, expected, single=False):
    global cases, bad
    if ONLY and name not in ONLY:
        return
    cases += 1
    lit = repr(args[0]) if single else repr(args)
    try:
        got = A._test(name, lit)
    except Exception as e:
        got = "<asm exc %s>" % e
    ok = expected == got or (expected.startswith("<exc") and got.startswith("'<exc")) or (expected.startswith("<exc") and got.startswith('"<exc'))
    if not ok:
        bad += 1
        print(f"MISMATCH {name}({lit})\n   python: {expected}\n   asm:    {got}")
        if bad >= int(os.environ.get("MAXBAD", "12")):
            print("too many mismatches"); sys.exit(1)

# (name, args, single): cases that differed once
REGRESSIONS = [
    # a ('mem', x) of something that isn't a range: apply_mask_to_range's
    # ValueError, which split_or doesn't catch (only its AssertionErrors)
    ("split_or", (("mask_shl", 8, 0, 0, ("mem", ("sha3", ("mem", ("range", 0, 64))))),), True),
    # a read of a negative length (the old VM's call arguments) inside the
    # split: its bytes, of that length
    ("fill_mem", (("mem", ("range", 100, -4)), ("range", 64, 32), 96), False),
    # a bool at the byte k of a packed array, k at most 31
    ("split_store", (("store", 256, 0, 5, ("or", ("mul", ("bool", "x"), ("exp", 256, ("mask_shl", 5, 0, 0, ("cd", 4)))), ("and", ("not", ("mul", 255, ("exp", 256, ("mask_shl", 5, 0, 0, ("cd", 4))))), ("storage", 256, 0, 5)))),), True),
    # two bytes swapped: no order
    ("split_store", (("store", 256, 0, 5, ("or", ("mask_shl", 8, 0, 8, ("storage", 8, 0, 5)), ("mask_shl", 8, 8, -8, ("storage", 256, 0, 5)))),), True),
    # a part reading what another part writes: it goes first
    ("split_setmem", (("setmem", ("range", 64, 32), ("or", ("mask_shl", 160, 0, 0, "caller"), ("mask_shl", 96, 0, 160, ("mem", ("range", 64, 32))))),), True),
    # a bool shifted left, next to what's above its byte
    ("split_or", (("or", ("mask_shl", 32, 0, 200, ("bool", "x")), ("mask_shl", 48, 0, 208, "y")),), True),
]

def regressions():
    for name, args, single in REGRESSIONS:
        fn = getattr(M, name)
        check(name, args, run(fn, *args), single)

if __name__ == "__main__":
  regressions()
  for n in range(N):
    v = rval()
    check("to_bytes", (v,), run(AL.to_bytes, v), True)
    check("divisible_bytes", (v,), run(AL.divisible_bytes, v), True)
    i = rint()
    if i >= 0: check("find_mask", (i,), run(find_mask, i), True)
    r1, r2 = rrange(), rrange()
    check("apply_mask_to_range", (r1, random.choice([8, 32, 160, 256, ("mask_shl", 253, 0, 3, ("cd", 4)), 5]), random.choice([0, 0, 96, 8, 3])), run(M.apply_mask_to_range, r1, *_[1:]) if False else None) if False else None
    size = random.choice([8, 32, 160, 256, ("mul", 8, ("cd", 4)), 5, ("mask_shl", 253, 0, 3, ("cd", 4))])
    off = random.choice([0, 0, 96, 8, 3])
    check("apply_mask_to_range", (r1, size, off), run(M.apply_mask_to_range, r1, size, off))
    check("split_or", (v,), run(M.split_or, v), True)
    check("sizeof", (v,), run(M.sizeof, v), True)
    line = ("setmem", r1, v)
    check("split_setmem", (line,), run(M.split_setmem, line), True)
    st = random.choice([("store", 256, 0, rint(True), v), ("store", 256, 0, rint(True), ("mask_shl", random.choice([8, 160, 255]), random.choice([0, 96]), 0, ("storage", 256, 0, 5))), ("store", 160, 0, 5, v)])
    check("split_store", (st,), run(M.split_store, st), True)
    check("memloc_overwrite", (r1, r2), run(M.memloc_overwrite, r1, r2))
    l, r = rpos(), rpos()
    check("slice_exp", (v, l, r), run(M.slice_exp, v, l, r))
    sv = random.choice([None, "b", rval()])
    check("splits_mem", (r1, r2, v, sv), run(M.splits_mem, r1, r2, v, sv))
    mem = ("mem", r1)
    check("fill_mem", (mem, r2, v), run(M.fill_mem, mem, r2, v))
    check("range_overlaps", (r1, r2), run(M.range_overlaps, r1, r2))
    check("range_contains", (r1, r2), run(M.range_contains, r1, r2))
    # the widths of what's in memory, and what's known of the bits of a value
    w1, w2 = rwide(), rwide()
    check("value_bits", (w1,), run(M.value_bits, w1), True)
    bnd = random.choice([None, ((("cd", 4), 64),), ((("var", "_1"), 8), ("x", 3))])
    check("max_value_bits", (w1, bnd), run(M.max_value_bits, w1, None if bnd is None else dict(bnd)))
    check("max_value", (w1,), run(M.max_value, w1), True)
    check("low_zero_bits", (w1,), run(M.low_zero_bits, w1), True)
    check("width_of", (w1,), run(M.width_of, w1), True)
    check("sized", (w1,), run(M.sized, w1), True)
    check("words", (w1,), run(M.words, w1), True)
    wd = random.choice([256, 160, 32, 8 * random.randint(0, 40), ("mul", 8, ("cd", 4))])
    check("implicit", (w1, wd), run(M.implicit, w1, wd))
    check("keep_width", (w1, w2), run(M.keep_width, w1, w2))
    op = random.choice(["sha3", "data", "return", "log", "call", "setmem", "arr", "add"])
    old_e = (op,) + tuple(rwide() for _ in range(random.randint(1, 6)))
    if op == "setmem": old_e = ("setmem", rrange(), rwide())
    new_e = tuple(e if random.random() < 0.5 else rwide() for e in old_e)
    check("keep_widths", (old_e, new_e), run(M.keep_widths, old_e, new_e))
    ln = random.choice([32, 4, 20, 64, 1, ("cd", 4)])
    check("keep_setmem_width", (ln, w1, w2), run(M.keep_setmem_width, ln, w1, w2))
    sz = random.choice([32, 4, 20, 64, 1, 33, ("cd", 4)])
    check("resize_bytes", (w1, sz), run(M.resize_bytes, w1, sz))
    check("with_width", (w1, sz), run(M.with_width, w1, sz))
    check("byte_elements", (old_e,), run(lambda e: tuple(M.byte_elements(e)), old_e), True)
    l2, r2_ = random.choice([(0, 4), (4, 32), (0, 32), (12, 32), (28, 36), (l, r)])
    wdt = random.choice([None, 256, 160, 512, 32])
    check("slice_exp", (w1, l2, r2_, wdt), run(M.slice_exp, w1, l2, r2_, wdt))
    # the parts of a word written to storage or memory
    st = rstore_line()
    check("split_store", (st,), run(M.split_store, st), True)
    check("byte_field_store", (st,), run(M.byte_field_store, st), True)
    sm = rsetmem_line()
    check("split_setmem", (sm,), run(M.split_setmem, sm), True)
    check("split_or", (sm[2],), run(M.split_or, sm[2]), True)
    check("split_or", (st[4],), run(M.split_or, st[4]), True)
    sts = rstores(random.randint(1, 6))
    check("merge_zeros", (sts,), run(M.merge_zeros, sts), True)
    check("in_order_store", (sts,), run(M.in_order, sts, M.store_reads_written), True)
    if len(sts) >= 2:
        check("store_reads_written", (sts[0], sts[1]), run(M.store_reads_written, sts[0], sts[1]))
    sms = [("setmem", ("range", random.choice([64, 76, 96, 128, "x"]), random.choice([32, 20, 12])), rmempart(64)) for _ in range(random.randint(1, 4))]
    check("in_order_setmem", (sms,), run(M.in_order, sms, M.setmem_reads_written), True)
    if len(sms) >= 2:
        check("setmem_reads_written", (sms[0], sms[1]), run(M.setmem_reads_written, sms[0], sms[1]))
  print(f"{cases} cases, {bad} mismatches")
  sys.exit(1 if bad else 0)
