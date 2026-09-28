#!/usr/bin/env python3
"""The module's decompile_bytecode (text, asm, json) against python's
panoramix.decompiler.decompile_bytecode, on the contracts whose python
results tests/gen_json_expected.py pickled into build/json_expected/
(make json-expected); and `panasm decompile --json` against json.dumps
of python's json.

    tests/test_json.py [NAME...]
"""
import os, sys, glob, pickle, json, subprocess
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
BUILD = os.environ.get("PANASM_BUILD") or os.path.join(ROOT, "build")
sys.path.insert(0, BUILD)
import panoramix_asm as A
A.set_log_level("error")

sys.setrecursionlimit(10000)
EXPECTED = os.path.join(ROOT, "build", "json_expected")
PANASM = os.path.join(ROOT, "build", "panasm")

def first_difference(a, b, path="json"):
    """where two values first differ (types included: a tuple isn't a list,
    True isn't 1)"""
    if type(a) != type(b):
        return f"{path}: {type(a).__name__} {repr(a)[:200]} / {type(b).__name__} {repr(b)[:200]}"
    if isinstance(a, dict):
        if list(a) != list(b):
            return f"{path}: keys {list(a)[:20]} / {list(b)[:20]}"
        for k in a:
            d = first_difference(a[k], b[k], f"{path}[{k!r}]")
            if d: return d
        return None
    if isinstance(a, (list, tuple)):
        if len(a) != len(b):
            return f"{path}: {len(a)} elements / {len(b)}"
        for i, (x, y) in enumerate(zip(a, b)):
            d = first_difference(x, y, f"{path}[{i}]")
            if d: return d
        return None
    if a != b:
        return f"{path}: {repr(a)[:300]} / {repr(b)[:300]}"
    return None

names = sys.argv[1:] or sorted(os.path.basename(p)[:-7] for p in glob.glob(os.path.join(EXPECTED, "*.pickle")))
if not names:
    print("test_json: skipped, no python results in build/json_expected (make json-expected)")
    sys.exit(0)
bad = 0
for name in names:
    with open(os.path.join(EXPECTED, name + ".pickle"), "rb") as f:
        text, asm, pj = pickle.load(f)
    hexfile = os.path.join(HERE, "corpus", name + ".hex")
    code = open(hexfile).read().strip()
    d = A.decompile_bytecode(code, threads=2)
    problems = []
    if d.text != text:
        i = next((i for i, (x, y) in enumerate(zip(d.text, text)) if x != y), min(len(d.text), len(text)))
        problems.append(f"text differs at {i}: {d.text[i-50:i+100]!r} / {text[i-50:i+100]!r}")
    if d.asm != asm:
        problems.append(f"asm: {first_difference(d.asm, asm, 'asm')}")
    diff = first_difference(d.json, pj)
    if diff:
        problems.append(diff)
    # the command line's json text
    p = subprocess.run([PANASM, "decompile", hexfile, "--json", "-j", "2"], capture_output=True)
    if p.stdout.decode() != json.dumps(pj) + "\n":
        out = p.stdout.decode()
        ref = json.dumps(pj) + "\n"
        i = next((i for i, (x, y) in enumerate(zip(out, ref)) if x != y), min(len(out), len(ref)))
        problems.append(f"--json differs at {i}: {out[i-80:i+80]!r} / {ref[i-80:i+80]!r}")
    if problems:
        bad += 1
        print("DIFF", name)
        for pr in problems: print("   ", pr)
    else:
        print("ok  ", name, f"({len(pj.get('functions', []))} functions)", flush=True)
print(f"{len(names)} contracts, {bad} with differences")
sys.exit(1 if bad else 0)
