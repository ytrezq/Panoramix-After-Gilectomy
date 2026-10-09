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


def unbool(e):
    """
    True and False as 1 and 0: python's caches take True for 1, and its
    simplifier hands the storage a slot 1 written True now and then, which
    its dicts then take for the slot 1 (the port's True isn't 1, and its
    simplifier makes no such True: see DESIGN.md) - both are given ints.
    """
    if type(e) is bool:
        return int(e)
    if type(e) is tuple:
        return tuple(unbool(x) for x in e)
    if type(e) is list:
        return [unbool(x) for x in e]
    return e


def load_caps():
    res = []
    for p in sorted(glob.glob(os.path.join(CAPS, "*.pkl"))):
        try:
            caps = pickle.load(open(p, "rb"))
        except Exception:
            continue
        for c in caps:
            for d in c["functions"]:
                d["trace"] = unbool(d["trace"])
                d["returns"] = unbool(d["returns"])
                d["getter"] = unbool(d["getter"])
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


def checked_below(trace, loops=False, numbers=True):
    return list(S.checked_below(trace, loops=loops, numbers=numbers).items())


def var_values(trace):
    return list(S.var_values(trace).items())


def index_like(e, bounded, values):
    return S.index_like(e, dict(bounded), dict(values))


def index_candidates(trace):
    """what's added to a slot in the trace's accesses: the terms of their
    indexes, and the indexes"""
    res = []
    for a in S.find_f_list(trace, lambda e: [e] if S.opcode(e) == "storage" and len(e) == 4 else []):
        idx = a[3]
        res.append(idx)
        if S.opcode(idx) == "add":
            res += list(idx[1:])
    return res[:20]


def t_trace_functions():
    for name, cap, fs, acc, lang, rg, s in ANALYSES:
        traces = [d["trace"] for d in cap["functions"]]
        run("find_accesses", find_accesses, traces)
        for t in traces:
            run("checked_below", checked_below, t)
            run("checked_below", checked_below, t, True, False)
            run("checked_below", checked_below, t, True, True)
            run("checked_below", checked_below, t, False, False)
            run("var_values", var_values, t)
            bounded = checked_below(t, True, False)
            values = var_values(t)
            for e in index_candidates(t):
                run("index_like", index_like, e, bounded, values)
                run("points", S.points, e)
            run("narrow", lambda t: replace_f(t, S.narrow), t)
        code = cap["code"]
        run("language", lambda c, a: S.language(bytes.fromhex(c) if c is not None else None, {x: False for x in a}),
            code.hex() if code is not None else None, list(acc))
        run("language", lambda c, a: S.language(bytes.fromhex(c) if c is not None else None, {x: False for x in a}),
            None, list(acc))


def rexp(d=0):
    """a random expression for the worlds"""
    r = rnd.random()
    if d > 3 or r < 0.25:
        return rnd.choice([rint(), "caller", ("cd", 4), ("var", "x"), ("param", "a"), True, False, None,
                           ("mem", ("range", 0, 32)), [1, 2], (), "calldatasize", ("bytes", 32, ("cd", 4)),
                           ("storage", 256, 0, 3)])
    if r < 0.4:
        return ("add",) + tuple(rexp(d + 1) for _ in range(rnd.randrange(4)))
    if r < 0.5:
        return ("mul",) + tuple(rexp(d + 1) for _ in range(rnd.randrange(4)))
    if r < 0.6:
        return (rnd.choice(["div", "mod"]),) + tuple(rexp(d + 1) for _ in range(rnd.choice([2, 2, 2, 1, 3])))
    if r < 0.75:
        return ("mask_shl", rnd.choice([256, 160, 8, 1, 0, 257, -1, ("cd", 4)]), rnd.choice([0, 8, -8, 255, 256, 300, -300]),
                rnd.choice([0, 8, -8, 255, 256, 512, -512, 600]), rexp(d + 1))[:rnd.choice([5, 5, 5, 5, 4, 3])]
    if r < 0.9:
        parts = tuple(rnd.choice([("bytes", rnd.choice([32, 20, 1, 0, 33, ("cd", 4)]), rexp(d + 1)), rexp(d + 1),
                                  ("data", rexp(d + 1), ("bytes", 32, rexp(d + 1))), ("mem", ("range", 0, 64)),
                                  ("call.data", 4, 32), ("arr", 32, ("cd", 4))])
                      for _ in range(rnd.randrange(1, 4)))
        return ("sha3", ("data",) + parts) if rnd.random() < 0.5 else ("sha3",) + parts
    return rnd.choice([("bytes",), ("bytes", 32), ("lt", 1, 2), ("bytes", 32, rexp(d + 1))])


def evb(e, seed):
    return S.evb(e, S.World(seed)).hex()


def t_worlds():
    es = [rexp() for _ in range(N * 2)]
    for size, off, idx in ACCESSES[:N]:
        es += [idx, off, size]
    for e in es:
        seed = rnd.randrange(4)
        run("ev", lambda e, seed: S.ev(e, S.World(seed)), e, seed)
        run("evb", evb, e, seed)


def defs_list(s):
    return [(name, d["slot"], d.get("off", 0), d["type"]) for name, d in s.defs.items()]


def read(f, defs, lang, seed):
    d = {name: ({"slot": slot, "off": off, "type": t} if off else {"slot": slot, "type": t}) for name, slot, off, t in defs}
    return S.read(f, d, lang, S.World(seed))


def checks(f, size, off, idx, defs, lang):
    d = {name: ({"slot": slot, "off": off, "type": t} if off else {"slot": slot, "type": t}) for name, slot, off, t in defs}
    return S.checks(f, size, off, idx, d, lang)


def t_checks():
    for name, cap, fs, acc, lang, rg, s in ANALYSES:
        if not s:
            continue
        defs = defs_list(s)
        items = []
        for a, st in s.steps.items():
            size, off, idx = a
            if st is None or type(size) != int:
                continue
            n, sts = st
            try:
                f = s.path_form(n, sts, size, off)
            except S.Fail:
                continue
            except Exception:
                continue
            items.append((f, size, off, idx))
            items.append((S.raw(size, off, idx), size, off, idx))
        rnd.shuffle(items)
        for f, size, off, idx in items[:max(40, N // 4)]:
            run("checks", checks, f, size, off, idx, defs, lang)
            run("read", read, f, defs, lang, rnd.randrange(4))
            g = mutate(f)
            run("checks", checks, g, size, off, idx, defs, lang)
            run("read", read, g, defs, lang, rnd.randrange(4))


def fn_tuple(d):
    return (d["hash"], d["name"], d["trace"], d["getter"], d["returns"], d["read_only"])


def rewrite_functions(code_hex, fns):
    fs = [F({"hash": h, "name": n, "trace": t, "getter": g, "returns": r, "read_only": ro})
          for h, n, t, g, r, ro in fns]
    try:
        lang, defs = S.rewrite_functions(fs, bytes.fromhex(code_hex) if code_hex is not None else None)
    except S.Fail:
        # (a Fail that nothing catches: raw's, of a write of a length)
        raise FailExc()
    return (lang, defs, [f.trace for f in fs])


def regroup(fns, lang):
    fs = [F({"hash": h, "name": n, "trace": t, "getter": g, "returns": r, "read_only": ro})
          for h, n, t, g, r, ro in fns]
    for f in fs:
        f.trace = replace_f(f.trace, S.narrow)
    rg = S.Regroup(fs, lang)
    return [rg.trace(f.trace) for f in fs]


def regroup_asm(fns, lang):
    fs = [(h, n, replace_f(t, S.narrow), g, r, ro) for h, n, t, g, r, ro in fns]
    return asm("regroup", fs, lang)


def t_whole():
    if os.environ.get("STORAGE_QUICK"):
        return
    for name, cap in CAPTURED:
        fns = [fn_tuple(d) for d in cap["functions"]]
        code = cap["code"].hex() if cap["code"] is not None else None
        for lang in ("solidity", "vyper"):
            if not ONLY or ONLY == "regroup":
                check("regroup", (name, lang), py(regroup, fns, lang), regroup_asm(fns, lang))
        t0 = time.time()
        if not ONLY or ONLY == "rewrite_functions":
            p = py(rewrite_functions, code, fns)
            t1 = time.time()
            a = asm("rewrite_functions", code, fns)
            t2 = time.time()
            ok = check("rewrite_functions", name, p, a)
            print(f"   {'ok  ' if ok else 'DIFF'} {name}: py {t1 - t0:.1f}s asm {t2 - t1:.1f}s", flush=True)
            if not ok and os.environ.get("STORAGE_DUMP"):
                open(f"/tmp/claude-0/-home-claude/0fe601fa-3d3d-56af-9a22-c5068d00d0e0/scratchpad/storage/diff_{name}.txt", "w").write(f"{p}\n{a}\n")


def bytes_keys(f, s):
    """the keys bytes_getter tries for f (its first part)"""
    keys = []
    for e in S.find_f_list(f.trace, lambda e: [e] if S.opcode(e) == "storage" else []):
        k = e[3][1] if S.opcode(e[3]) == "length" else e[3] if e[1:3] == (1, 0) else None
        if S.opcode(k) == "loc":
            k = k[1]
        if k is not None and k not in keys:
            keys.append(k)
    return [("loc", k) if type(k) == int else k for k in keys[:3]]


def tweak(trace):
    """a trace changed a little: a number, a line gone, a branch swapped"""
    t = list(trace)
    if not t:
        return t
    r = rnd.random()
    i = rnd.randrange(len(t))
    if r < 0.3:
        del t[i]
    elif r < 0.6:
        t[i] = mutate(t[i])
    elif r < 0.8 and S.opcode(t[i]) == "if" and len(t[i]) == 4:
        t[i] = ("if", t[i][1], t[i][3], t[i][2])
    else:
        t.insert(i, ("setmem", ("range", rnd.choice([0, 32, 64, 128]), 32), rnd.choice([0, 1, 32, ("cd", 4)])))
    return t


def t_bytes_tail():
    items = []
    for name, cap, fs, acc, lang, rg, s in ANALYSES:
        for f in fs:
            if not f.read_only or type(f.hash) != str or not f.hash.startswith("0x"):
                continue
            sel = int(f.hash, 16)
            for key in bytes_keys(f, s):
                items.append((f.trace, key, sel))
    rnd.shuffle(items)
    for trace, key, sel in items[:N]:
        run("bytes_tail", S.bytes_tail, trace, key, sel)
    for trace, key, sel in items[:N // 3]:
        run("bytes_tail", S.bytes_tail, tweak(trace), key, sel)


def t_names():
    names = ["balanceOf", "getBalance", "get", "getx", "getX", "_owner", "owner", "unknown1234", "stor5", "storABC",
             "stor5_3", "storE", "store", "int", "uint256", "bytes32", "bytes", "Mask", "if", "x1", "1x", "a-b",
             "stor0_x", "getOwner(uint256)", "name()", "total_supply", "storA1_2", "stor_1", "address", "addr", "é", ""]
    for n in names:
        run("good_name", S.good_name, n)
    for n in names:
        def getter_name(n):
            name = n.split("(")[0]
            if name.startswith("get") and len(name) > 3 and name[3].isupper():
                name = name[3].lower() + name[4:]
            return name
        run("getter_name", getter_name, n)
    defs = []
    for name, cap, fs, acc, lang, rg, s in ANALYSES:
        if s:
            defs += s.header()
    defs += [("sdef", "x", 2**40, 8, ("fixed", ("value", 8), 1, 32)), ("sdef", "y", 3, 0, ("fixed", ("struct", 2), 2, 4)),
             ("sdef", "z", 0, 0, ("fixed", ("mapping", ("value", 256)), 1)), ("sdef", "w", 1, 1, ("struct", None)),
             ("sdef", "v", 2**32, 0, ("struct", 1)), ("sdef", "u", 2**32 - 1, 0, ("other",))]
    for d in defs:
        run("pretty_def", S.pretty_def, d)


def t_make_ast():
    """contract.make_ast past the fold (fix_widths, other_1, other_2), on
    python's folded traces of the storage's results"""
    import panoramix.contract as C
    import panoramix.folder as folder
    from panoramix.postprocess import short_circuits

    class NoFold:
        fold = staticmethod(lambda t: t)

    for name, cap in CAPTURED[: max(5, N // 10)]:
        fs = [F(copy.deepcopy(d)) for d in cap["functions"]]
        try:
            S.rewrite_functions(fs, cap["code"])
        except Exception:
            continue
        for f in fs:
            try:
                folded = folder.fold(short_circuits(f.trace))
            except Exception:
                continue
            saved = C.short_circuits, C.folder
            C.short_circuits, C.folder = (lambda t: t), NoFold
            try:
                p = py(lambda t: C.Contract({}, {}).make_ast(t), folded)
            finally:
                C.short_circuits, C.folder = saved
            check("make_ast_folded", (name, f.name), p, asm("make_ast_folded", folded))


# ---------------------------------------------------------------------------
# random contracts: functions reading and writing the storage as compilers do

KEYS = [("mask_shl", 160, 0, 0, ("cd", 4)), ("cd", 36), "caller", ("var", "x"), ("cd", 4),
        ("mask_shl", 256, 0, 0, ("cd", 68)), ("param", "id"), 7]
INDEXES = [("cd", 4), ("var", "i"), ("cd", 36), ("mask_shl", 255, 0, 1, ("cd", 4)), ("add", 1, ("cd", 4)), 3, 0]


def rkey():
    k = rnd.choice(KEYS)
    return ("bytes", 32, k) if rnd.random() < 0.6 and type(k) != int else k


def rhash(parts, vyper):
    if rnd.random() < 0.15:
        return ("sha3",) + tuple(parts)
    return ("sha3", ("data",) + tuple(parts))


def rplace(vyper, d=0):
    """a slot as a compiler computes it"""
    n = rnd.choice([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 2**160, rnd.randrange(2**256)])
    r = rnd.random()
    if d > 2 or r < 0.25:
        return n
    if r < 0.45:   # a mapping
        inner = rplace(vyper, d + 1) if rnd.random() < 0.3 else n
        parts = [inner, rkey()] if vyper else [rkey(), inner]
        return rhash(parts, vyper)
    if r < 0.6:    # an element of an array: keccak(slot) + index
        stride = rnd.choice([1, 1, 2, 3])
        i = rnd.choice(INDEXES)
        off = i if stride == 1 else ("mul", stride, i)
        if rnd.random() < 0.3:
            off = ("add", rnd.randrange(stride), off) if stride > 1 else off
        return ("add", off, ("sha3", n)) if rnd.random() < 0.5 else ("add", ("sha3", n), off)
    if r < 0.7:    # a member of a struct
        return ("add", rnd.randrange(1, 4), rplace(vyper, d + 1))
    if r < 0.8:    # a fixed array
        return ("add", n, rnd.choice(INDEXES))
    if r < 0.88:   # a hash written as a number
        from panoramix.storage import keccak, w32
        return keccak(w32(n % 16)) + rnd.choice([0, 0, 1, 2])
    return ("length", ("loc", n))


def raccess(vyper):
    idx = rplace(vyper)
    size, off = rnd.choice([(256, 0), (256, 0), (160, 0), (8, 0), (8, 160), (1, 0), (248, 8), (255, 1), (7, 1),
                            (8, 8), (16, 16), (32, 224), (8, ("mask_shl", 5, 0, 3, ("cd", 4))), (64, 64),
                            (("cd", 4), 0), (96, 160), (128, 128)])
    return size, off, idx


def rline(vyper, getter, d=0):
    r = rnd.random()
    size, off, idx = raccess(vyper)
    if d < 2 and rnd.random() < 0.1:
        # a loop over a fixed array, a pointer: its counter set to what it
        # starts at, the condition its bound
        n = rnd.choice([0, 1, 2, 5, 8, 2**160])
        start = rnd.choice([0, 0, 1, ("sha3", n), ("mem", ("range", 64, 32)), ("cd", 4), 2**200])
        bound = rnd.choice([3, 10, ("storage", 256, 0, n), ("cd", 36), ("mem", ("range", 96, 32))])
        i = ("var", "i")
        body = [rline(vyper, getter, d + 1) for _ in range(rnd.randrange(0, 2))]
        body.append(rnd.choice([("setvar", "_7", ("storage", 256, 0, ("add", n, i))),
                                ("store", 256, 0, ("add", n, i), 0),
                                ("setvar", "_7", ("storage", 256, 0, ("add", 1, i)))]))
        return ("while", ("lt", i, bound), body, "jd%d" % d, [("setvar", "i", start)])
    if d < 2 and rnd.random() < 0.05:
        return ("setvar", "i", rnd.choice([0, ("add", ("var", "i"), 1), ("sha3", 3), ("mem", ("range", 64, 32))]))
    if r < 0.3:
        return ("setvar", "_" + str(rnd.randrange(5)), ("storage", size, off, idx))
    if r < 0.6 and not getter:
        val = rnd.choice([0, 1, ("cd", 36), ("add", 1, ("storage", size, off, idx)), 2**160 - 1, "caller", 5])
        if S.opcode(idx) == "length" and rnd.random() < 0.9:
            idx = idx[1][1]
        return ("store", size, off, idx, val)
    if r < 0.7:
        return ("if", ("lt", rnd.choice(INDEXES[:3]), rnd.choice([3, 4, 10, 32, ("storage", 256, 0, 1)])),
                [rline(vyper, getter, d + 1)], [("revert", None)])
    if r < 0.8:
        return ("if", ("iszero", ("storage", size, off, idx)), [("revert", None)], [rline(vyper, getter, d + 1)])
    return ("setvar", "_9", ("add", 1, ("storage", size, off, idx)))


NAMES = ["balanceOf", "getOwner", "owner", "totalSupply", "data", "items", "getBalance", "_hidden", "stor5",
         "allowance", "unknown12345678", "users", "Mask", "if", "x", "config", "getX", "values", "getvalue"]


def rcontract():
    vyper = rnd.random() < 0.3
    fns = []
    for k in range(rnd.randrange(1, 9)):
        getter = rnd.random() < 0.5
        trace = [rline(vyper, getter) for _ in range(rnd.randrange(0, 5))]
        g = None
        returns = []
        if getter:
            size, off, idx = raccess(vyper)
            ret = ("storage", size, off, idx)
            form = rnd.random()
            if form < 0.2:
                ret = ("bool", ret)
            elif form < 0.35:
                ret = ("mask_shl", size if type(size) == int else 256, 0, 0, ret)
            elif form < 0.45:
                ret = ("bytes", 32, ret)
            line = ("return", ret)
            trace.append(line)
            returns = [line]
            g = ("storage", size, off, idx) if rnd.random() < 0.9 else ("struct", ("loc", rnd.randrange(5)))
        else:
            trace.append(("stop",))
        read_only = not any("store" in repr(l) for l in trace)
        name = rnd.choice(NAMES) + ("(%s)" % rnd.choice(["", "uint256", "address", "address,address"]))
        fns.append(("0x%08x" % rnd.randrange(2**32), name, trace, g, returns, read_only))
    code = rnd.choice([None, "", "a165627a7a72305820", "6576797065728300", "0011"])
    return code, fns


def t_random_whole():
    for k in range(N):
        code, fns = rcontract()
        if ONLY and ONLY != "rewrite_functions":
            continue
        check("rewrite_functions", (code, fns), py(rewrite_functions, code, fns), asm("rewrite_functions", code, fns))


TESTS = [t_random_whole, t_make_ast, t_whole, t_bytes_tail, t_names, t_worlds, t_checks, t_hash_constant, t_parse, t_linear, t_packed, t_typeof, t_form, t_raw, t_layout, t_trace_functions]

if __name__ == "__main__":
    for t in TESTS:
        t0 = time.time()
        before = bad
        t()
        print(f"{t.__name__}: {'ok' if bad == before else 'DIFF'} ({time.time() - t0:.1f}s)", flush=True)
    print(f"{cases} cases, {bad} mismatches")
