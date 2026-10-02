#!/usr/bin/env python3
"""Differential test of the folder (folder.py) on python's own traces:
what its contract.make_ast folded (after short_circuits), recorded by
gen_function_inputs.py (build/fn_inputs/NAME.pkl) - as_paths and fold
compared with python's, whatever the port's VM and simplifier do
meanwhile. Also the traces Function got (before the storage's rewrites).

    tests/test_folder.py [build/fn_inputs/X.pkl ...]
"""
import os, sys, glob, time, pickle
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(HERE, "..", "..", "panoramix")))
sys.path.insert(0, os.environ.get("PANASM_BUILD") or os.path.join(HERE, "..", "build"))
sys.setrecursionlimit(20000)
import logging; logging.disable(logging.CRITICAL)
import panoramix_asm as A
from test_simplify import check, run
import test_simplify
from panoramix import folder
from panoramix.postprocess import short_circuits

INPUTS = os.path.join(HERE, "..", "build", "fn_inputs")

if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    paths = args or sorted(glob.glob(os.path.join(INPUTS, "*.pkl")))
    if not paths:
        print("test_folder: skipped, no python inputs in build/fn_inputs (make fn-inputs)")
        sys.exit(0)
    for p in paths:
        name = os.path.basename(p).rsplit(".", 1)[0]
        rec = pickle.load(open(p, "rb"))
        t0 = time.time()
        before = test_simplify.bad
        traces = [("ast %d" % k, short_circuits(tr)) for k, tr in enumerate(rec["asts"])]
        traces += [("fn " + h, tr) for h, tr, _ in rec["functions"]]
        for what, tr in traces:
            ctx = name + " " + what
            check("as_paths", tr, run(lambda t: list(folder.as_paths(t)), tr), ctx)
            check("fold", tr, run(folder.fold, tr), ctx)
        print(f"{'ok  ' if test_simplify.bad == before else 'DIFF'} {name} ({len(traces)} traces) {time.time() - t0:.1f}s", flush=True)
    print(f"{test_simplify.cases} cases, {test_simplify.bad} mismatches")
    sys.exit(1 if test_simplify.bad else 0)
