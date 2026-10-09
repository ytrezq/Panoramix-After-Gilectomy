#!/usr/bin/env python3
"""
What tests/test_storage.py compares the storage on: python's own traces.

    tests/storage_capture.py HEXFILE OUT.pkl

decompiles HEXFILE with python's decompiler (pypy: the signature database
is a shelve of its dbm) and pickles what storage.rewrite_functions is given,
before it runs: the code, and each function's hash, name, trace, getter,
returns and read_only. make storage-caps does it for the corpus and the
synthetic programs (build/storage_caps).
"""
import os, sys, pickle
sys.setrecursionlimit(20000)
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "panoramix")))
import logging
logging.disable(logging.CRITICAL)
from panoramix import storage
from panoramix.decompiler import decompile_bytecode

captured = []
rewrite_functions = storage.rewrite_functions


def capture(functions, code=None):
    captured.append({
        "code": bytes(code) if code is not None else None,
        "functions": [
            {
                "hash": f.hash,
                "name": f.name,
                "trace": f.trace,
                "getter": f.getter,
                "returns": getattr(f, "returns", None),
                "read_only": getattr(f, "read_only", False),
            }
            for f in functions
        ],
    })
    return rewrite_functions(functions, code)


storage.rewrite_functions = capture

src, out = sys.argv[1], sys.argv[2]
code = open(src).read().strip()
try:
    decompile_bytecode(code)
except Exception as e:
    print("failed", src, type(e).__name__, e, file=sys.stderr)
with open(out, "wb") as f:
    pickle.dump(captured, f, protocol=4)
print("ok", src, len(captured[0]["functions"]) if captured else None)
