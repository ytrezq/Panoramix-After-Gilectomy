#!/usr/bin/env python3
"""python's text with --repr and --returns in sys.argv (which python -m
panoramix refuses: only the library reads them), for tests/test_verbose.py:

    PYTHONPATH=../panoramix ../panoramix/.venv/bin/python tests/gen_repr_expected.py FILE.hex OUT
"""
import os, sys
sys.setrecursionlimit(10000)
os.environ.setdefault("PANORAMIX_TIMEOUT", "0")
code = open(sys.argv[1]).read().strip()
out = sys.argv[2]
sys.argv = [sys.argv[0], "--repr", "--returns"]
from panoramix.decompiler import decompile_bytecode
d = decompile_bytecode(code)
with open(out, "w") as f:
    f.write(d.text + "\n")
