#!/usr/bin/env python3
"""Differential test of whiles.s: whiles.make on the VM traces of the corpus."""
import os, sys, glob, time
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "panoramix")))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import logging; logging.disable(logging.CRITICAL)
import panoramix_asm as A
from test_vm import py_run, functions_of, CORPUS
from panoramix import whiles

def compare(name, trace):
    try:
        expected = repr(whiles.make(trace))
    except Exception as e:
        expected = "<exc %s: %s>" % (type(e).__name__, e)
    got = A._test("whiles_make", repr(trace))
    ok = expected == got or (expected.startswith("<exc") and got.startswith("'<exc"))
    print(f"{'ok  ' if ok else 'DIFF'} {name} len={len(expected)}/{len(got)}", flush=True)
    if not ok:
        i = 0
        while i < min(len(expected), len(got)) and expected[i] == got[i]:
            i += 1
        print("   python: ..." + expected[max(0, i - 200):i + 300])
        print("   asm:    ..." + got[max(0, i - 200):i + 300])
    return ok

if __name__ == "__main__":
    files = sys.argv[1:] or sorted(glob.glob(CORPUS + "/*.hex"))
    bad = 0
    for f in files:
        code = open(f).read().strip()
        if code.startswith("0x"): code = code[2:]
        name = os.path.basename(f)
        for fname, target, stack, known in functions_of(code):
            try:
                trace = py_run(code, target, False, stack, known)
            except Exception as e:
                print("skip", name, fname, type(e).__name__)
                continue
            if not compare(name + " " + fname, trace):
                bad += 1
    print("failures:", bad)
