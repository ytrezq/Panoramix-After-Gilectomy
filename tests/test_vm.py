#!/usr/bin/env python3
"""Differential test of the symbolic VM: the raw traces of panoramix.vm.VM
against vm.s, on the corpus."""
import os, sys, glob, time
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "panoramix")))
sys.path.insert(0, os.environ.get("PANASM_BUILD") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import logging; logging.disable(logging.CRITICAL)
# no signature database on the asm side either (python's is disabled below)
os.environ.setdefault("PANORAMIX_SIGDB", "/nonexistent")
import panoramix_asm as A
from panoramix.loader import Loader
import panoramix.loader
# the signature database needs pypy's dbm here; the names don't matter
panoramix.loader.make_abi = lambda targets: None
panoramix.loader.get_func_name = lambda h: h
from panoramix.vm import VM
from panoramix.core.algebra import CannotCompare

CORPUS = os.environ.get("CORPUS", os.path.join(os.path.dirname(os.path.abspath(__file__)), "corpus"))

def py_run(code, start, just_fdests, stack=(), known=()):
    loader = Loader()
    loader.load_binary(code)
    vm = VM(loader, just_fdests=just_fdests)
    return vm.run(start, stack=stack, known=known)

def asm_run(code, start, just_fdests, stack=(), known=()):
    return A._test("vm_run", repr((code, start, 1 if just_fdests else 0, tuple(stack), tuple(known))))

def compare(name, code, start, just_fdests, stack=(), known=()):
    t0 = time.time()
    try:
        expected = repr(py_run(code, start, just_fdests, stack, known))
    except Exception as e:
        expected = "<exc %s: %s>" % (type(e).__name__, e)
    t1 = time.time()
    got = asm_run(code, start, just_fdests, stack, known)
    t2 = time.time()
    ok = expected == got or (expected.startswith("<exc") and got.startswith("'<exc"))
    print(f"{'ok  ' if ok else 'DIFF'} {name} start={start} fdests={just_fdests} py={t1-t0:.2f}s asm={t2-t1:.2f}s len={len(expected)}/{len(got)}", flush=True)
    if not ok:
        # first difference
        i = 0
        while i < min(len(expected), len(got)) and expected[i] == got[i]:
            i += 1
        print("   python: ..." + expected[max(0, i - 200):i + 300])
        print("   asm:    ..." + got[max(0, i - 200):i + 300])
    return ok

def functions_of(code):
    """(name, target, stack, known) of every function, from python's loader"""
    loader = Loader()
    loader.load_binary(code)
    loader.run(VM(loader, just_fdests=True))
    res = []
    for hash, fname, target, stack in loader.func_list:
        if target > 1 and loader.lines[target][1] == "jumpdest":
            target += 1
        known = loader.fallback_known if hash == "_fallback" else ()
        res.append((fname, target, stack, known))
    return res

if __name__ == "__main__":
    args = sys.argv[1:]
    funcs = "--functions" in args
    args = [a for a in args if not a.startswith("--")]
    files = args or sorted(glob.glob(CORPUS + "/*.hex"))
    bad = 0
    for f in files:
        code = open(f).read().strip()
        if code.startswith("0x"): code = code[2:]
        name = os.path.basename(f)
        if not funcs:
            if not compare(name, code, 0, True):
                bad += 1
            continue
        for fname, target, stack, known in functions_of(code):
            if not compare(name + " " + fname, code, target, False, stack, known):
                bad += 1
    print("failures:", bad)
