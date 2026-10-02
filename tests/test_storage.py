#!/usr/bin/env python3
"""
Differential tests of the storage (storage.s, storage_check.s,
storage_getter.s) against panoramix.storage: storage.py's functions one by
one on inputs taken from the corpus - the traces python's Contract gives
storage.rewrite_functions, pickled (see CAPTURE below) - and random ones
around them; then rewrite_functions itself on those traces (the
definitions, the language, every function's trace after it).

    python3 tests/test_storage.py [SEED [N]] [--caps DIR] [--only NAME]

The captures: tests/storage_capture.py HEXFILE OUT.pkl (pypy) runs
python's decompiler on a contract and pickles what storage.rewrite_functions
is given; DIR holds one .pkl per contract ($STORAGE_CAPS by default). The
whole storage of a contract depends on simplify (not the port's yet, maybe):
that's why it's compared on python's own traces.
"""
import os, sys, random, pickle, glob, copy, time
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "panoramix")))
sys.path.insert(0, os.environ.get("PANASM_BUILD") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import logging; logging.disable(logging.CRITICAL)
import panoramix_asm as A
from panoramix import storage as S
from panoramix.utils.helpers import replace_f

sys.setrecursionlimit(20000)

args = [a for a in sys.argv[1:] if not a.startswith("--")]
opts = {}
i = 1
while i < len(sys.argv):
    if sys.argv[i].startswith("--"):
        k = sys.argv[i][2:]
        if i + 1 < len(sys.argv) and not sys.argv[i + 1].startswith("--"):
            opts[k] = sys.argv[i + 1]
            if sys.argv[i + 1] in args:
                args.remove(sys.argv[i + 1])
            i += 1
        else:
            opts[k] = True
    i += 1
SEED = int(args[0]) if args else 1
N = int(args[1]) if len(args) > 1 else 300
CAPS = opts.get("caps") or os.environ.get("STORAGE_CAPS") or "/tmp/claude-0/-home-claude/0fe601fa-3d3d-56af-9a22-c5068d00d0e0/scratchpad/storage/cap"
ONLY = opts.get("only")
rnd = random.Random(SEED)

CODES = {"IndexError": 7, "TypeError": 5, "ValueError": 10, "KeyError": 11,
         "AssertionError": 3, "OverflowError": 13, "ZeroDivisionError": 42,
         "Unknown": 41, "Fail": 40, "RecursionError": 9, "Unsupported": 12,
         "MemoryError": 8}

cases = 0
bad = 0
shown = {}


def asm(name, *a):
    return A._test("storage", repr((name,) + a))


def py(fn, *a):
    try:
        return repr(fn(*a))
    except S.Fail:
        return repr("Fail")
    except Exception as e:
        return ("exc", type(e).__name__)


def check(name, inp, p, a):
    global cases, bad
    cases += 1
    if isinstance(p, tuple):
        ok = a.lstrip("'\"").startswith("<exc %d:" % CODES.get(p[1], -1))
    else:
        ok = p == a
    if not ok:
        bad += 1
        shown[name] = shown.get(name, 0) + 1
        if shown[name] <= 5:
            print(f"MISMATCH {name}: {inp!r}"[:3000])
            print(f"   py:  {p}"[:3000])
            print(f"   asm: {a}"[:3000])
    return ok


def run(name, fn, *a):
    """python's fn(*a) against the hook name"""
    if ONLY and name != ONLY:
        return
    check(name, a, py(fn, *a), asm(name, *a))


# ---------------------------------------------------------------------------
# the corpus: what rewrite_functions is given, and python's analysis of it

class F:
    def __init__(self, d):
        self.__dict__.update(d)


def load_caps():
    res = []
    for p in sorted(glob.glob(os.path.join(CAPS, "*.pkl"))):
        try:
            caps = pickle.load(open(p, "rb"))
        except Exception:
            continue
        for c in caps:
            res.append((os.path.basename(p)[:-4], c))
    return res


def analysis(cap):
    """python's rewrite_functions up to the Storage (its state, for the
    inputs of the functions)"""
    fs = [F(copy.deepcopy(d)) for d in cap["functions"]]
    for f in fs:
        f.trace = replace_f(f.trace, S.narrow)
    acc = {}
    for f in fs:
        S.find_accesses(f.trace, acc)
    lang = S.language(cap["code"], acc)
    rg = S.Regroup(fs, lang)
    for f in fs:
        f.trace = rg.trace(f.trace)
    try:
        s = S.Storage(fs, lang)
    except Exception:
        s = None
    return fs, acc, lang, rg, s


CAPTURED = load_caps()
print(f"{len(CAPTURED)} captured contracts from {CAPS}")
ANALYSES = []
for name, cap in CAPTURED:
    try:
        ANALYSES.append((name, cap) + analysis(cap))
    except Exception as e:
        print("analysis failed", name, type(e).__name__, e)

IDXS = []           # the slots of the accesses
ACCESSES = []       # (size, off, idx)
for name, cap, fs, acc, lang, rg, s in ANALYSES:
    for (size, off, idx) in acc:
        IDXS.append((idx, lang))
        ACCESSES.append((size, off, idx))

# ---------------------------------------------------------------------------
# random inputs around them

HASHES = [h for h, p in S.hash_table("solidity")]
VHASHES = [h for h, p in S.hash_table("vyper")]
WORDS = [("mask_shl", 160, 0, 0, ("cd", 4)), ("cd", 36), "caller", ("var", "x"),
         ("mask_shl", 256, 0, 0, ("cd", 68)), ("param", "_a"), ("var", 3),
         ("mask_shl", 8, 0, 0, ("cd", 4)), ("storage", 256, 0, 5),
         ("bytes", 32, ("cd", 4)), ("bytes", 32, "caller"), 5, 0, 7]


def rint():
    r = rnd.random()
    if r < 0.4:
        return rnd.randrange(0, 70)
    if r < 0.55:
        return rnd.choice(HASHES) + rnd.choice([0, 1, 2, 5, 65535, 65536, -1])
    if r < 0.6:
        return rnd.choice(VHASHES) + rnd.randrange(3)
    if r < 0.7:
        return -rnd.randrange(1, 10)
    if r < 0.8:
        return rnd.randrange(2**256)
    return rnd.choice([0, 1, 2, 32, 64, 256, 2**160, 2**255])


def rword(d=0):
    r = rnd.random()
    if r < 0.4 or d > 3:
        return rnd.choice(WORDS)
    if r < 0.6:
        return rint()
    if r < 0.8:
        return ("bytes", 32, ridx(d + 1))
    return ridx(d + 1)


def ridx(d=0):
    """a random slot"""
    r = rnd.random()
    if d > 3 or r < 0.2:
        return rnd.choice([rint(), ("loc", rnd.randrange(10)), ("cd", 4)])
    if r < 0.45:
        k = rnd.choice([1, 1, 2, 2, 2, 3])
        parts = tuple(rword(d + 1) for _ in range(k))
        if rnd.random() < 0.5:
            return ("sha3", ("data",) + parts)
        return ("sha3",) + parts
    if r < 0.7:
        terms = [ridx(d + 1)]
        for _ in range(rnd.randrange(3)):
            terms.append(rnd.choice([rint(), ("mul", 2, ("cd", 4)), ("cd", 36), ("var", "i"),
                                     ("mask_shl", 255, 0, 1, ("cd", 4)), ("add", 1, ("var", "j"))]))
        return ("add",) + tuple(terms)
    if r < 0.8:
        return ("length", ridx(d + 1))
    if r < 0.9:
        return ("bytes", 32, ridx(d + 1))
    return rnd.choice([("mask_shl", 8, 0, 0, ("cd", 4)), ("param", "x"), ("var", 1),
                       ("add", 1), ("sha3",), ("bytes",), ("mask_shl", 1, 2)])


def mutate(e, d=0):
    """e with a part changed"""
    if d > 6 or type(e) != tuple or not e or rnd.random() < 0.15:
        r = rnd.random()
        if r < 0.3:
            return rint()
        if r < 0.6:
            return rword()
        return ridx()
    i = rnd.randrange(len(e))
    if i == 0:
        return e
    return e[:i] + (mutate(e[i], d + 1),) + e[i + 1:]


# ---------------------------------------------------------------------------
# the tests

def t_parse():
    items = list(IDXS)
    rnd.shuffle(items)
    items = items[:N]
    for _ in range(N):
        items.append((ridx(), rnd.choice(["solidity", "vyper"])))
    for _ in range(N // 2):
        idx, lang = rnd.choice(IDXS) if IDXS else (ridx(), "solidity")
        items.append((mutate(idx), lang))
    for idx, lang in items:
        run("parse", S.parse, idx, lang)
        try:
            p = S.parse(idx, lang)
        except Exception:
            continue
        run("steps", S.steps, p)
        run("word", S.word, idx)
        run("is_word", S.is_word, idx)
        run("from_calldata", S.from_calldata, idx)


def t_hash_constant():
    for _ in range(N):
        c = rint()
        lang = rnd.choice(["solidity", "vyper"])
        run("hash_constant", S.hash_constant, c, lang)


def t_linear():
    es = [rnd.choice([rint(), ("var", "i"), ("cd", 4), ("mul", rnd.choice([2, 3, -1, 0, 64]), ("var", "i")),
                      ("mask_shl", rnd.choice([255, 251, 256, 1]), 0, rnd.choice([1, 5, 0, 256]), ("cd", 4)),
                      ("add", rint(), ("mul", 2, ("var", "i"))), ("add", rint(), rint()),
                      ("add", 1, ("var", "i"), ("var", "j")), ("add",), ("add", ("mul", 32, ("cd", 4)), 3, 4)])
          for _ in range(N)]
    for name, cap, fs, acc, lang, rg, s in ANALYSES:
        if s:
            for st in s.steps.values():
                if st:
                    for step in st[1]:
                        if step[0] == "off":
                            es.append(step[1])
    for e in es:
        run("linear", lambda e: S.linear(e), e)


def t_packed():
    for _ in range(N):
        width = rnd.choice([8, 16, 32, 64, 128, 160, 256, 24, 0, 1, 2, 4, -8, 512])
        lw = S.log2(width) if width > 0 else 3
        lp = S.log2(256 // width) if width > 0 and 256 // width > 0 else 1
        lp = lp if lp is not None else 1
        lw = lw if lw is not None else 3
        x = rnd.choice([("cd", 4), ("var", "i")])
        off = rnd.choice([0, 8, 16, 7, -8, width, ("mask_shl", lp, 0, lw, x), ("mask_shl", max(lp - 1, 0), 0, lw, x),
                          ("mask_shl", lp, 0, lw + 1, x), ("cd", 4)])
        e = rnd.choice([0, 1, 2, -1, ("mask_shl", 256 - lp, lp, -lp, x), ("mask_shl", 256 - lp, lp, -lp, ("cd", 36)), ("var", "i")])
        run("packed", S.packed, e, off, width)


def accs_of(s):
    """by_root's accesses of python's Storage, per root: [(st, size, off)]"""
    res = {}
    for a, st in s.steps.items():
        size, off, idx = a
        if st is not None and type(size) == int:
            res.setdefault(st[0], []).append((st[1], size, off))
    return res


def t_typeof():
    groups = []
    for name, cap, fs, acc, lang, rg, s in ANALYSES:
        if s:
            groups += list(accs_of(s).values())
    items = list(groups)
    for _ in range(N):
        if groups:
            g = list(rnd.choice(groups))
            for _ in range(rnd.randrange(3)):
                if rnd.random() < 0.5 and len(groups) > 1:
                    g.append(rnd.choice(rnd.choice(groups)))
                elif g:
                    st, size, off = rnd.choice(g)
                    g.append((st, rnd.choice([size, 8, 160, 256, 1, 248]), rnd.choice([off, 0, 8, 1, ("cd", 4)])))
            items.append(g)
    for g in items:
        run("typeof", S.typeof, g)


def t_form():
    items = []
    for name, cap, fs, acc, lang, rg, s in ANALYSES:
        if not s:
            continue
        for a, st in s.steps.items():
            size, off, idx = a
            if st is None or type(size) != int:
                continue
            n, sts = st
            t = s.types.get(n)
            if t is not None:
                items.append((("sv", "x"), t, sts, size, off))
    types = [it[1] for it in items] or [("value", 256)]
    stss = [it[2] for it in items] or [[]]
    for _ in range(N):
        items.append((("sv", rnd.choice(["x", None])), rnd.choice(types + [("value", 8), ("struct", 3), ("struct", None), ("bytes",),
                                                                  ("fixed", ("value", 8), 1), ("array", ("struct", 2), 2)]),
                      rnd.choice(stss), rnd.choice([256, 8, 160, 1, 255, ("cd", 4)]), rnd.choice([0, 8, 1, 96, ("cd", 4), -8])))
    for it in items:
        run("form", S.form, *it)


def raw(size, off, idx, write):
    # (a Fail of raw: nothing catches it, the port's E_STFAIL)
    try:
        return S.raw(size, off, idx, write)
    except S.Fail:
        raise FailExc()


class FailExc(Exception):
    pass


CODES["FailExc"] = 40


def t_raw():
    for size, off, idx in ACCESSES[:N] + [(rnd.choice([256, 8, ("cd", 4)]), rnd.choice([0, 8, -8, ("cd", 4)]), ridx()) for _ in range(N)]:
        for write in (False, True):
            run("raw", raw, size, off, idx, write)


def t_layout():
    items = []
    for name, cap, fs, acc, lang, rg, s in ANALYSES:
        by = {}
        for (size, off, idx), wr in acc.items():
            try:
                c = S.slot_class(S.steps(S.parse(idx, lang)))
            except Exception:
                c = None
            run("slot_class", S.slot_class, S.steps(S.parse(idx, lang)) if c is not None else None)
            if c is not None and type(size) == int and type(off) == int:
                by.setdefault(c, []).append((size, off, wr))
        items += list(by.values())
    for _ in range(N):
        g = [(rnd.choice([8, 16, 160, 256, 1, 248, 64, 96]), rnd.choice([0, 8, 16, 160, 248, 1, 96, 200]),
              rnd.choice([True, False, "const"])) for _ in range(rnd.randrange(1, 6))]
        items.append(g)
    for g in items:
        run("layout", S.layout, g)


def find_accesses(exp):
    res = {}
    S.find_accesses(exp, res)
    return list(res.items())


def checked_below(trace):
    return list(S.checked_below(trace).items())


def t_trace_functions():
    for name, cap, fs, acc, lang, rg, s in ANALYSES:
        traces = [d["trace"] for d in cap["functions"]]
        run("find_accesses", find_accesses, traces)
        for t in traces:
            run("checked_below", checked_below, t)
            run("narrow", lambda t: replace_f(t, S.narrow), t)
        code = cap["code"]
        run("language", lambda c, a: S.language(bytes.fromhex(c) if c is not None else None, {x: False for x in a}),
            code.hex() if code is not None else None, list(acc))
        run("language", lambda c, a: S.language(bytes.fromhex(c) if c is not None else None, {x: False for x in a}),
            None, list(acc))


TESTS = [t_hash_constant, t_parse, t_linear, t_packed, t_typeof, t_form, t_raw, t_layout, t_trace_functions]

if __name__ == "__main__":
    for t in TESTS:
        t0 = time.time()
        before = bad
        t()
        print(f"{t.__name__}: {'ok' if bad == before else 'DIFF'} ({time.time() - t0:.1f}s)", flush=True)
    print(f"{cases} cases, {bad} mismatches")
