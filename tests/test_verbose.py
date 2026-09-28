#!/usr/bin/env python3
"""python's --verbose and --explain (the instructions run and the stack
before each, as comments of the text; the trace at every stage of each
function's decompilation), against the port's: `panasm decompile FILE
--verbose` / `--explain`, and the module's decompile_bytecode(verbose=,
explain=) (what it prints on sys.stdout, then its text). The outputs of
`python -m panoramix` are in build/verbose_expected/ (make
verbose-expected: NAME.verbose.txt, NAME.explain.txt).

    tests/test_verbose.py [NAME...]
"""
import contextlib, glob, io, os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
BUILD = os.environ.get("PANASM_BUILD") or os.path.join(ROOT, "build")
sys.path.insert(0, BUILD)
import panoramix_asm as A
A.set_log_level("error")

EXPECTED = os.environ.get("VERBOSE_EXPECTED") or os.path.join(ROOT, "build", "verbose_expected")
CORPUS = os.path.join(HERE, "corpus")
PANASM = os.path.join(BUILD, "panasm")

files = sorted(glob.glob(os.path.join(EXPECTED, "*.txt")))
if sys.argv[1:]:
    files = [f for f in files if os.path.basename(f).split(".")[0] in sys.argv[1:]]
if not files:
    print("test_verbose: skipped, no python outputs in build/verbose_expected (make verbose-expected)")
    sys.exit(0)

def first_diff(a, b):
    i = next((i for i, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
    return f"at {i}: {a[max(0, i - 60):i + 60]!r} / {b[max(0, i - 60):i + 60]!r}"

bad = 0
for f in files:
    name, mode = os.path.basename(f).split(".")[:2]
    ref = open(f, encoding="utf-8", errors="surrogateescape").read()
    hexfile = os.path.join(CORPUS, name + ".hex")
    problems = []
    p = subprocess.run([PANASM, "decompile", hexfile, "--" + mode, "-j", "2"], capture_output=True,
                       env=dict(os.environ, PANORAMIX_LOG="error"))
    out = p.stdout.decode("utf-8", "surrogateescape")
    if out != ref:
        problems.append("panasm " + first_diff(out, ref))
    code = open(hexfile).read().strip()
    printed = io.StringIO()
    with contextlib.redirect_stdout(printed):
        d = A.decompile_bytecode(code, threads=2, verbose=(mode == "verbose"), explain=(mode == "explain"))
    got = printed.getvalue() + d.text + "\n"
    if got != ref:
        problems.append("decompile_bytecode " + first_diff(got, ref))
    if (d.explain is not None) != (mode == "explain") or (d.explain is not None and d.explain != printed.getvalue()):
        problems.append("decompile_bytecode: its .explain isn't what it printed")
    if problems:
        bad += 1
        print("DIFF", name, mode)
        for pr in problems:
            print("    ", pr)
    else:
        print("ok  ", name, mode, flush=True)
print(f"{len(files)} outputs, {bad} with differences")
sys.exit(1 if bad else 0)
