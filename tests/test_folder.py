#!/usr/bin/env python3
"""Differential test of the folder on the traces of the corpus: fold is
compared with python's on the trace after whiles.make and on the simplified
trace (asm's simplify_trace, verified separately)."""
import os, sys, glob, time, ast
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "panoramix")))
sys.path.insert(0, os.environ.get("PANASM_BUILD") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import logging; logging.disable(logging.CRITICAL)
import panoramix_asm as A
from test_vm import py_run, functions_of, CORPUS
from test_simplify import check, run, cases, norm
import test_simplify
from panoramix import whiles, folder
from panoramix.utils.helpers import rewrite_trace

if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    files = args or sorted(glob.glob(CORPUS + "/*.hex"))
    for f in files:
        code = open(f).read().strip()
        if code.startswith("0x"): code = code[2:]
        name = os.path.basename(f)
        for fname, target, stack, known in functions_of(code):
            ctx = name + " " + fname
            try:
                trace = py_run(code, target, False, stack, known)
                trace = whiles.make(trace)
                trace = rewrite_trace(trace, lambda line: [] if (isinstance(line, tuple) and line[0] == "jumpdest") else [line])
            except Exception as e:
                print("skip", ctx, type(e).__name__); continue
            t0 = time.time()
            check("as_paths", trace, run(lambda t: list(folder.as_paths(t)), trace), ctx)
            check("fold", trace, run(folder.fold, trace), ctx)
            simplified = A._test("simplify_trace", repr(trace))
            try:
                trace_s = ast.literal_eval(simplified)
            except Exception as e:
                print("unparseable simplified trace", ctx, e); continue
            check("as_paths", trace_s, run(lambda t: list(folder.as_paths(t)), trace_s), ctx + " (simplified)")
            t1 = time.time()
            exp = run(folder.fold, trace_s)
            t2 = time.time()
            ok = check("fold", trace_s, exp, ctx + " (simplified)")
            t3 = time.time()
            print(f"{'ok  ' if ok else 'DIFF'} {ctx} py={t2-t1:.2f}s asm={t3-t2:.2f}s", flush=True)
    print(f"{test_simplify.cases} cases, {test_simplify.bad} mismatches")
