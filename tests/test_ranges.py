#!/usr/bin/env python3
"""
Random differential tests of the ranges (src/ranges.s) against
panoramix.core.algebra: value_range, memory_range, is_word, shift_sign,
readable_mask, proven_le, may_be_wide, unchecked and mentions_var, under
set_variables states (the variables of a trace, its small words) and both
free memory pointer assumptions. The queries of a case are asked one after
the other in the same context, its memos and all.

    tests/test_ranges.py [SEED [N]]
"""
import os, random, sys
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "panoramix")))
sys.path.insert(0, os.environ.get("PANASM_BUILD") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import logging; logging.disable(logging.CRITICAL)
import panoramix_asm as A
from panoramix.core import algebra as P
from panoramix.core import variants as V

random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 1)
N = int(sys.argv[2]) if len(sys.argv) > 2 else 400


def rint():
    r = random.random()
    if r < 0.55:
        return random.choice([0, 1, 2, 3, 4, 5, 8, 16, 31, 32, 64, 96, 128, 160, 224, 255, 256, 288,
                              -1, -4, -32, -256, 2**64 - 1, 2**64, 2**160, 2**160 - 1, 2**255, 2**256 - 1, 2**256])
    if r < 0.95:
        return random.randint(-300, 300)
    return random.randint(-2**257, 2**257)


ATOMS = [
    "calldatasize", "callvalue", "x", "msize", "gas", "codesize",
    ("cd", 4), ("cd", 36), ("cd", ("add", 4, ("cd", 36))),
    ("call.data", 4, 32), ("ext_call.return_data", 0, 32), ("ext_call.return_data", 64, 96),
    ("mem", ("range", 64, 32)), ("mem", ("range", 96, 32)), ("mem", ("range", ("var", 1), 64)),
    ("var", 1), ("var", 2), ("var", 3), ("var", 4),
    ("storage", 256, 0, 5), ("storage", 160, 8, ("map", 1, 2)), ("storage", 8, -8, 1), ("storage", 300, 0, 2),
    ("sha3", 1), ("bytes", 32, ("cd", 4)), ("bytes", 40, ("cd", 4)), ("data", ("cd", 4), 7),
    True, False,
]

BOOLS = ["lt", "gt", "eq", "iszero", "slt", "le", "bool"]


def ratom():
    return random.choice(ATOMS)


def rexp(depth=0):
    r = random.random()
    if depth > 3 or r < 0.25:
        return rint() if random.random() < 0.4 else ratom()
    op = random.choice(["add", "add", "add", "mul", "mul", "mask_shl", "mask_shl", "mask_shl",
                        "mod", "div", "and", "or", "xor", "min", "max", "bool", "not", "exp"])
    if op == "add":
        return ("add",) + tuple(rexp(depth + 1) for _ in range(random.randint(2, 4)))
    if op == "mul":
        k = random.random()
        if k < 0.6:
            return ("mul", rint(), rexp(depth + 1))
        if k < 0.8:
            return ("mul", rint(), rexp(depth + 1), rexp(depth + 1))
        return ("mul", rexp(depth + 1), rexp(depth + 1))
    if op == "mask_shl":
        if random.random() < 0.85:
            size = random.choice([1, 5, 8, 16, 32, 64, 96, 160, 224, 248, 251, 253, 255, 256, 300, 0, -3])
            off = random.choice([0, 0, 0, 1, 3, 5, 8, 16, 17, 32, 96, -8, True])
            shl = random.choice([0, 0, 0, 1, 3, 5, 32, 96, 255, 256, -3, -5, -32, -96, -300])
            return ("mask_shl", size, off, shl, rexp(depth + 1))
        return ("mask_shl", rexp(depth + 1), rexp(depth + 1), rexp(depth + 1), rexp(depth + 1))
    if op == "mod":
        return ("mod", rexp(depth + 1), rint() if random.random() < 0.6 else rexp(depth + 1))
    if op == "div":
        return ("div", rexp(depth + 1), rint() if random.random() < 0.7 else rexp(depth + 1))
    if op in ("and", "or", "xor", "min", "max"):
        return (op,) + tuple(rexp(depth + 1) for _ in range(random.randint(1, 3)))
    if op == "bool":
        b = random.choice(BOOLS)
        if b in ("iszero", "bool"):
            return (b, rexp(depth + 1))
        return (b, rexp(depth + 1), rexp(depth + 1))
    if op == "not":
        return ("not", rexp(depth + 1))
    return ("exp", rexp(depth + 1), rexp(depth + 1))


def rvars():
    """set_variables' arguments: None, or (vars, small)"""
    if random.random() < 0.3:
        return None
    names = random.sample([1, 2, 3, 4], random.randint(0, 4))
    vs = tuple((n, tuple(rexp(2) for _ in range(random.randint(1, 3)))) for n in names)
    small = tuple(random.sample([("cd", 4), ("cd", 36), ("cd", ("add", 4, ("cd", 36))),
                                 ("ext_call.return_data", 0, 32), ("var", 1), ("mem", ("range", 64, 32))],
                                random.randint(0, 3)))
    return (vs, small)


def rbounds():
    if random.random() < 0.7:
        return None
    return tuple((random.choice([ratom(), rexp(2)]), random.randint(-5, 300), random.choice([300, 2**64, 2**256 - 1, 2**300]))
                 for _ in range(random.randint(1, 3)))


def rquery():
    k = random.choice([0, 0, 0, 0, 0, 1, 1, 2, 3, 4, 5, 6, 7, 8])
    if k == 0:
        return (0, rexp(), rbounds(), random.choice([0, 0, 1]))
    if k == 4:
        return (4, random.choice([rint(), rexp(2)]), random.choice([rint(), rexp(2)]), random.choice([rint(), rexp(2)]))
    if k == 5:
        return (5, rexp(), rexp(), None)
    if k == 8:
        return (8, rexp(), random.choice([1, 2, 3, 4, 5]), None)
    return (k, rexp(), None, None)


def py_run(args, fmp, queries):
    V.set_free_memory_pointer(fmp)
    if args is None:
        P.set_variables({})
    else:
        vs, small = args
        P.set_variables({n: list(vals) for n, vals in vs}, small)
    out = []
    for kind, a, b, c in queries:
        if kind == 0:
            bounds = None if b is None else {e: (lo, hi) for e, lo, hi in b}
            out.append(P.value_range(a, bounds, P.MEMORY_TOP if c else P.WORD_TOP))
        elif kind == 1:
            out.append(P.memory_range(a))
        elif kind == 2:
            out.append(P.is_word(a))
        elif kind == 3:
            out.append(P.shift_sign(a))
        elif kind == 4:
            out.append(P.readable_mask(a, b, c))
        elif kind == 5:
            out.append(P.proven_le(a, b))
        elif kind == 6:
            out.append(P.may_be_wide(a))
        elif kind == 7:
            out.append(P.unchecked(a, P._VARIABLES, P._SMALL))
        else:
            out.append(P.mentions_var(a, b))
    return tuple(out)


def main():
    cases = bad = skipped = 0
    for n in range(N):
        args = rvars()
        fmp = random.random() < 0.8
        queries = tuple(rquery() for _ in range(random.randint(1, 6)))
        try:
            expected = repr(py_run(args, fmp, queries))
        except Exception as e:
            skipped += 1
            continue
        lit = repr((args, fmp, queries))
        if os.environ.get("TRACE"):
            print("CALL", lit, flush=True)
        try:
            got = A._test("ranges", lit)
        except Exception as e:
            got = "<asm exc %s>" % e
        cases += 1
        if expected != got:
            # which query
            bad += 1
            print(f"MISMATCH {lit}\n   python: {expected}\n   asm:    {got}")
            if bad >= 12:
                print("too many mismatches")
                break
    print(f"{cases} cases, {bad} mismatches, {skipped} python exceptions")
    P.set_variables({})
    V.set_free_memory_pointer(True)
    sys.exit(1 if bad else 0)


main()
