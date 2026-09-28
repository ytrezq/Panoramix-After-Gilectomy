#!/usr/bin/env python3
"""Differential test of the function analysis (function.py's Function):
names, parameters, payable/read-only/const/getter and the printed text,
on the corpus, with and without a (fake) abi."""
import os, sys, glob, time, ast
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "panoramix")))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import logging; logging.disable(logging.CRITICAL)
import panoramix_asm as A
from test_vm import py_run, functions_of, CORPUS
from test_simplify import check, run, norm
import test_simplify
from panoramix import whiles
from panoramix.loader import Loader
from panoramix.utils import signatures as S
from panoramix.function import Function
from panoramix.utils.helpers import rewrite_trace

Loader.find_sig = staticmethod(lambda sig, add_color=False: None)

def py_function(hash, trace, abi):
    name, inputs = abi
    S._abi = {hash: {"name": name} if inputs is None else {"name": name, "inputs": [{"type": t, "name": n} for t, n in inputs]}}
    f = Function(hash, trace)
    return (f.name, f.color_name, f.abi_name, [(k, v[0], v[1]) for k, v in f.inferred_params.items()], f.trace,
            f.payable, f.read_only, f.const, f.getter, f.returns, f.is_regular, f.print().split("\n"), f.priority())

def fake_inputs(fname, n):
    """a made-up abi with n parameters"""
    types = ["address", "uint256", "bool", "bytes32", "uint8", "string", "uint256[]", "bytes"]
    return ("fn_" + fname[2:], [(types[i % len(types)], f"arg{i}") for i in range(n)])

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
                trace_s = ast.literal_eval(A._test("simplify_trace", repr(trace)))
            except Exception as e:
                print("skip", ctx, type(e).__name__); continue
            t0 = time.time()
            before = test_simplify.bad
            hash = fname if fname.startswith("0x") else "_fallback"
            abis = [("unknown" + hash[2:] if hash.startswith("0x") else hash, None)]
            if hash.startswith("0x"):
                abis += [fake_inputs(fname, n) for n in (0, 1, 3)]
            for abi in abis:
                for t in (trace_s, trace):
                    check("function", (hash, t, abi), run(py_function, hash, t, abi), ctx + " " + repr(abi)[:30])
            print(f"{'ok  ' if test_simplify.bad == before else 'DIFF'} {ctx} {time.time()-t0:.1f}s", flush=True)
    print(f"{test_simplify.cases} cases, {test_simplify.bad} mismatches")
