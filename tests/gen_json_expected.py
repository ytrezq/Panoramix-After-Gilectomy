#!/usr/bin/env python3
"""python's Decompilation (text, asm, json) of contracts, pickled for
tests/test_json.py: run by the python that runs panoramix (pypy, in the
repository's .venv), one contract per call.

    PYTHONPATH=../panoramix ../panoramix/.venv/bin/python tests/gen_json_expected.py FILE.hex OUT.pickle
"""
import os, sys, pickle, logging
sys.setrecursionlimit(10000)
# python's time limits scaled as for the references of the corpus: pypy
# is slower than the port, which doesn't hit them
os.environ.setdefault("PANORAMIX_TIMEOUT", "20")
from panoramix.decompiler import decompile_bytecode

code = open(sys.argv[1]).read().strip()

# another python holding the signatures' shelve (gdbm's lock) makes the
# lookups fail, anywhere (a function among the problems): again, later
import time
class LockSeen(logging.Handler):
    seen = False
    def emit(self, record):
        if record.exc_info and "Resource temporarily unavailable" in str(record.exc_info[1]):
            LockSeen.seen = True
logging.disable(logging.NOTSET)
logging.getLogger().addHandler(LockSeen())
logging.getLogger().setLevel(logging.ERROR)
for attempt in range(8):
    LockSeen.seen = False
    try:
        d = decompile_bytecode(code)
    except Exception as e:
        if "Resource temporarily unavailable" not in str(e):
            raise
        LockSeen.seen = True
    if not LockSeen.seen:
        break
    time.sleep(5 + 10 * attempt)
else:
    sys.exit("the signatures' shelve stayed locked")
with open(sys.argv[2], "wb") as f:
    pickle.dump((d.text, list(d.asm), d.json), f, protocol=4)
