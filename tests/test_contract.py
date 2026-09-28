#!/usr/bin/env python3
"""Differential test of the contract postprocessing (sparser.py and
contract.py): the storage definitions, the rewritten traces, the asts
and the final text of every function, on the corpus."""
import os, sys, glob, time, ast
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "panoramix")))
sys.path.insert(0, os.environ.get("PANASM_BUILD") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import logging; logging.disable(logging.CRITICAL)
import panoramix_asm as A
from test_vm import py_run, functions_of, CORPUS
from test_simplify import check, run
import test_simplify
from test_function import fake_inputs
from panoramix import whiles
from panoramix.loader import Loader
from panoramix.utils import signatures as S
from panoramix.function import Function
from panoramix.contract import Contract
from panoramix.utils.helpers import rewrite_trace
import panoramix.sparser

Loader.find_sig = staticmethod(lambda sig, add_color=False: None)

def py_contract(entries):
    S._abi = {}
    for hash, trace, (name, inputs) in entries:
        S._abi[hash] = {"name": name} if inputs is None else {"name": name, "inputs": [{"type": t, "name": n} for t, n in inputs]}
    panoramix.sparser.used_locs = set()
    functions = {}
    for hash, trace, abi in entries:
        functions[hash] = Function(hash, trace)
    c = Contract(functions, {})
    c.postprocess()
    return (c.stor_defs, [(f.name, f.trace, f.ast, f.print().split("\n"), f.priority()) for f in c.functions], [f.name for f in c.consts])

if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    files = args or sorted(glob.glob(CORPUS + "/*.hex"))
    for f in files:
        code = open(f).read().strip()
        if code.startswith("0x"): code = code[2:]
        name = os.path.basename(f)
        t0 = time.time()
        entries = []
        for fname, target, stack, known in functions_of(code):
            try:
                trace = py_run(code, target, False, stack, known)
                trace = whiles.make(trace)
                trace = rewrite_trace(trace, lambda line: [] if (isinstance(line, tuple) and line[0] == "jumpdest") else [line])
                trace_s = ast.literal_eval(A._test("simplify_trace", repr(trace)))
            except Exception as e:
                print("skip", name, fname, type(e).__name__); continue
            hash = fname if fname.startswith("0x") else "_fallback"
            entries.append((hash, trace_s, ("unknown" + hash[2:] if hash.startswith("0x") else hash, None)))
        before = test_simplify.bad
        check("contract", entries, run(py_contract, entries), name)
        # with made-up abis for half of the functions
        entries2 = [(h, t, fake_inputs(h, i % 4) if i % 2 == 0 and h.startswith("0x") else abi) for i, (h, t, abi) in enumerate(entries)]
        check("contract", entries2, run(py_contract, entries2), name + " (abis)")
        print(f"{'ok  ' if test_simplify.bad == before else 'DIFF'} {name} {len(entries)} functions {time.time()-t0:.1f}s", flush=True)
    print(f"{test_simplify.cases} cases, {test_simplify.bad} mismatches")
