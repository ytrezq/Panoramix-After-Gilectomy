#!/usr/bin/env python3
"""Records, from python's whole decompilation of contracts, what reaches
the function-level code - so that it can be compared alone, on python's
own traces (the port's VM and simplifier may differ meanwhile):

  - every Function(hash, trace): its hash, the trace, the abi entry then
    (python's signatures._abi[hash], with the signature database);
  - the storage names contract.postprocess gives set_names and
    rename_params;
  - every trace contract.make_ast gets (short_circuits, then the folder).

    PANORAMIX_TIMEOUT=5 pypy tests/gen_function_inputs.py OUTDIR a.hex b.hex...

writes OUTDIR/NAME.pkl for each (pypy: CPython takes ten times as long),
read by test_function.py, test_postprocess.py and test_folder.py.
"""
import copy, os, pickle, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(HERE, "..", "..", "panoramix")))
sys.setrecursionlimit(20000)
import logging
logging.disable(logging.CRITICAL)
import panoramix.decompiler as D
import panoramix.contract as C
from panoramix.utils import signatures as SIG

rec = None
_Function = D.Function


class Recorded(_Function):
    def __init__(self, hash, trace):
        rec["functions"].append((hash, copy.deepcopy(trace), copy.deepcopy(SIG._abi[hash])))
        super().__init__(hash, trace)


D.Function = Recorded
_set_names = C.set_names


def set_names(storage=None, params=None):
    if storage is not None:
        rec["storage_names"] = list(storage)
    return _set_names(storage=storage, params=params)


C.set_names = set_names
_make_ast = C.Contract.make_ast


def make_ast(self, trace):
    rec["asts"].append(copy.deepcopy(trace))
    return _make_ast(self, trace)


C.Contract.make_ast = make_ast

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
for path in sys.argv[2:]:
    name = os.path.basename(path).rsplit(".", 1)[0]
    dest = os.path.join(out, name + ".pkl")
    if os.path.exists(dest):
        continue
    rec = {"functions": [], "storage_names": None, "asts": []}
    code = open(path).read().strip()
    t0 = time.time()
    try:
        D.decompile_bytecode(code)
    except Exception as e:
        print("failed", name, type(e).__name__, e, flush=True)
    with open(dest + ".tmp", "wb") as f:
        pickle.dump(rec, f, protocol=4)
    os.rename(dest + ".tmp", dest)
    print(f"{name}: {len(rec['functions'])} functions, {len(rec['asts'])} asts, {time.time() - t0:.0f}s", flush=True)
