#!/usr/bin/env python3
"""Compare `panasm disasm` with panoramix's Loader.disasm() on every .hex of a directory."""
import glob, os, subprocess, sys
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "panoramix")))
import logging; logging.disable(logging.CRITICAL)
from panoramix.loader import Loader

corpus = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("CORPUS", os.path.join(os.path.dirname(os.path.abspath(__file__)), "corpus"))
panasm = os.path.join(os.path.dirname(__file__), "..", "build", "panasm")
bad = 0
for path in sorted(glob.glob(os.path.join(corpus, "*.hex"))):
    code = open(path).read().strip()
    l = Loader()
    l.load_binary(code)
    expected = "\n".join(l.disasm()) + "\n"
    got = subprocess.run([panasm, "disasm", path], capture_output=True, text=True).stdout
    name = os.path.basename(path)
    if got == expected:
        print(f"ok   {name} ({len(l.parsed_lines)} instructions)")
    else:
        bad += 1
        e, g = expected.splitlines(), got.splitlines()
        for i, (a, b) in enumerate(zip(e, g)):
            if a != b:
                print(f"FAIL {name}: line {i}: expected {a!r} got {b!r}")
                break
        else:
            print(f"FAIL {name}: {len(e)} vs {len(g)} lines")
sys.exit(1 if bad else 0)
