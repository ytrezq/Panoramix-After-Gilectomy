#!/usr/bin/env python3
"""python's Decompilation (text, asm, json) of contracts, pickled for
tests/test_json.py: run by the python that runs panoramix (pypy, in the
repository's .venv), one contract per call.

    PYTHONPATH=../panoramix ../panoramix/.venv/bin/python tests/gen_json_expected.py FILE.hex OUT.pickle
"""
import sys, pickle, logging
logging.disable(logging.CRITICAL)
sys.setrecursionlimit(10000)
from panoramix.decompiler import decompile_bytecode

code = open(sys.argv[1]).read().strip()
d = decompile_bytecode(code)
with open(sys.argv[2], "wb") as f:
    pickle.dump((d.text, list(d.asm), d.json), f, protocol=4)
