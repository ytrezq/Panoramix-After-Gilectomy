#!/usr/bin/env python3
"""Differential test of the symbolic VM: the raw traces of panoramix.vm.VM
against vm.s, on the corpus.

    tests/test_vm.py [--functions [--verbose|--explain]] [--loader] [FILE.hex...]

Without options: the dispatcher's run (just_fdests, from 0, entry=() as
Loader.run makes it). --loader: what Loader.run finds - the functions, what
holds in the default function, the entries (what the dispatcher does before
each function). --functions: every function's trace, as the decompiler runs
the VM for it (its stack, what's known, its entry and the memory then), the
port's loader finding them on its side.

Python's loop numbers (vm.loop_keys) are global to the process; the port's
start at 1 for each VM: python's counter is reset before each run.
"""
import itertools, os, sys, glob, time
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "panoramix")))
sys.path.insert(0, os.environ.get("PANASM_BUILD") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import logging; logging.disable(logging.CRITICAL)
# no signature database on the asm side either (python's is disabled below)
os.environ.setdefault("PANORAMIX_SIGDB", "/nonexistent")
import panoramix_asm as A
from panoramix.loader import Loader
import panoramix.loader
import panoramix.vm
# the signature database needs pypy's dbm here; the names don't matter
panoramix.loader.make_abi = lambda targets: None
panoramix.loader.get_func_name = lambda h: h
from panoramix.vm import VM, entry_memory

CORPUS = os.environ.get("CORPUS", os.path.join(os.path.dirname(os.path.abspath(__file__)), "corpus"))
# python's VM is slow: a run past PY_LIMIT seconds is skipped
PY_LIMIT = float(os.environ.get("PY_LIMIT", "300"))

import signal
class PyTimeout(BaseException): pass
def _alarm(*a): raise PyTimeout()
signal.signal(signal.SIGALRM, _alarm)

def fresh_keys():
    panoramix.vm.loop_keys = itertools.count(1)

def load(code):
    loader = Loader()
    loader.load_binary(code)
    return loader

def py_dispatcher(code):
    loader = load(code)
    fresh_keys()
    return VM(loader, just_fdests=True).run(0, entry=())

def asm_dispatcher(code):
    return A._test("vm_run", repr((code, 0, 1, (), (), (), ())))

def py_loader(code):
    loader = load(code)
    fresh_keys()
    loader.run(VM(loader, just_fdests=True))
    funcs = [(h, t, s) for h, f, t, s in loader.func_list]
    entries = tuple((h, list(e)) for h, e in loader.entries.items())
    return loader, (funcs, loader.fallback_known, entries or None)

def py_function(loader, hash, target, stack):
    if target > 1 and loader.lines[target][1] == "jumpdest":
        target += 1
    known = loader.fallback_known if hash == "_fallback" and target == 0 else ()
    fresh_keys()
    return VM(loader).run(target, stack=stack, known=known, entry=loader.entry(hash),
                          memory=entry_memory(loader.entries.get(hash)))

def first_diff(expected, got):
    i = 0
    while i < min(len(expected), len(got)) and expected[i] == got[i]:
        i += 1
    print("   python: ..." + expected[max(0, i - 300):i + 300])
    print("   asm:    ..." + got[max(0, i - 300):i + 300], flush=True)

def compare(name, py, asm):
    t0 = time.time()
    signal.setitimer(signal.ITIMER_REAL, PY_LIMIT)
    try:
        expected = repr(py())
    except PyTimeout:
        print(f"skip {name} (python past {PY_LIMIT:g} s)", flush=True)
        return None
    except Exception as e:
        expected = "<exc %s: %s>" % (type(e).__name__, e)
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
    t1 = time.time()
    got = asm()
    t2 = time.time()
    ok = expected == got or (expected.startswith("<exc") and got.startswith("'<exc"))
    print(f"{'ok  ' if ok else 'DIFF'} {name} py={t1-t0:.2f}s asm={t2-t1:.2f}s len={len(expected)}/{len(got)}", flush=True)
    if not ok:
        first_diff(expected, got)
    return ok

if __name__ == "__main__":
    args = sys.argv[1:]
    funcs = "--functions" in args
    loader_mode = "--loader" in args
    # the lines of assembly in the traces: python reads sys.argv
    flags = 0
    if "--verbose" in args:
        flags = 1
    if "--explain" in args:
        flags = 3
    sys.argv = [sys.argv[0]] + (["--verbose"] if flags == 1 else ["--explain"] if flags == 3 else [])
    args = [a for a in args if not a.startswith("--")]
    files = args or sorted(glob.glob(CORPUS + "/*.hex"))
    bad = skipped = 0
    for f in files:
        code = open(f).read().strip()
        if code.startswith("0x"): code = code[2:]
        name = os.path.basename(f)
        if not funcs and not loader_mode:
            r = compare(name + " dispatcher", lambda: py_dispatcher(code), lambda: asm_dispatcher(code))
            bad += r is False
            skipped += r is None
            continue
        try:
            loader, expected = py_loader(code)
        except Exception as e:
            print(f"skip {name}: python's loader: {e}")
            continue
        if loader_mode:
            r = compare(name + " loader", lambda: expected, lambda: A._test("find_functions", repr(code)))
            bad += r is False
            continue
        for hash, target, stack in expected[0]:
            r = compare(f"{name} {hash}", lambda: py_function(loader, hash, target, stack),
                        lambda: A._test("vm_func", repr((code, hash, flags))))
            bad += r is False
            skipped += r is None
    print("failures:", bad, " skipped:", skipped)
    sys.exit(1 if bad else 0)
