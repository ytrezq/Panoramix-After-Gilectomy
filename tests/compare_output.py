#!/usr/bin/env python3
"""The final text of the decompilation: python's decompile_bytecode
against panoramix_asm.decompile, on the corpus (no signature database on
either side unless --db). Python's timeouts are scaled by 20 so that the
comparison doesn't depend on the machine (the assembly hits none)."""
import os, sys, glob, time, difflib
os.environ.setdefault("PANORAMIX_TIMEOUT", "20")
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "panoramix")))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "vendor"))
sys.path.insert(0, os.environ.get("PANASM_BUILD") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import logging; logging.disable(logging.CRITICAL)
if "--db" not in sys.argv:
    os.environ["PANORAMIX_SIGDB"] = "/nonexistent"
import panoramix_asm as A
CORPUS = os.environ.get("CORPUS", os.path.join(os.path.dirname(os.path.abspath(__file__)), "corpus"))
import panoramix.utils.supplement
import panoramix.utils.signatures
import panoramix.loader
from panoramix.loader import Loader
import panoramix.sparser

if "--db" not in sys.argv:
    panoramix.utils.signatures.fetch_sig = lambda h: None
    Loader.find_sig = staticmethod(lambda sig, add_color=False: None)

from panoramix.decompiler import decompile_bytecode

if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    files = args or sorted(glob.glob(CORPUS + "/*.hex"))
    outdir = os.environ.get("OUTDIR", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "compare_output"))
    os.makedirs(outdir, exist_ok=True)
    bad = 0
    for f in files:
        code = open(f).read().strip()
        name = os.path.basename(f)[:-4]
        panoramix.sparser.used_locs = set()
        t0 = time.time()
        py = decompile_bytecode(code).text
        t1 = time.time()
        asm = A.decompile(code)
        t2 = time.time()
        open(os.path.join(outdir, name + ".py.txt"), "w").write(py)
        open(os.path.join(outdir, name + ".asm.txt"), "w").write(asm)
        ok = py == asm
        if not ok:
            bad += 1
            diff = list(difflib.unified_diff(py.split("\n"), asm.split("\n"), "python", "asm", lineterm="", n=1))
            print("\n".join(diff[:40]))
        print(f"{'ok  ' if ok else 'DIFF'} {name} py={t1-t0:.1f}s asm={t2-t1:.2f}s", flush=True)
    print("differences:", bad)
