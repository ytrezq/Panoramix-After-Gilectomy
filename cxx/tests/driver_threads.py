#!/usr/bin/env python3
"""Lot 12: several python threads decompiling at once with the python module
(it lets go of the GIL; each call runs its own workers), each result
compared with the same contract decompiled alone - the text, and
decompile_bytecode's JSON and disassembly; the shared parts (the chunk pool,
the watchdog, the signature database, the log) are what this exercises
(the asm's tests/test_threads.py).

    tests/driver_threads.py BUILD_DIR [THREADS [ROUNDS]]
"""
import glob, importlib.util, os, random, sys, threading

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
BUILD = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "build")
NT = int(sys.argv[2]) if len(sys.argv) > 2 else 4
ROUNDS = int(sys.argv[3]) if len(sys.argv) > 3 else 2


def load(name, directory):
    for f in os.listdir(directory):
        if f.startswith(name + ".") and f.endswith(".so"):
            spec = importlib.util.spec_from_file_location(name, os.path.join(directory, f))
            m = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(m)
            return m
    return None


m = load("panoramix_cxx", BUILD)
if m is None:
    print("no panoramix_cxx in %s" % BUILD)
    sys.exit(1)
m.set_log_level("critical")

# the small contracts of the corpus and the synthetic ones (the big ones take
# minutes on a loaded machine)
TESTS = os.environ.get("PANORAMIX_TESTS_DIR") or os.path.join(REPO, "tests")
files = sorted(glob.glob(os.path.join(TESTS, "corpus", "*.hex")) + glob.glob(os.path.join(TESTS, "synthetic", "*.hex")))
files = [f for f in files if os.path.getsize(f) < 8000][:10]
codes = {os.path.basename(f): open(f).read().strip() for f in files}
alone = {n: m.decompile(c, threads=1, color=False) for n, c in codes.items()}
alone_d = {n: m.decompile_bytecode(c, threads=1, color=False) for n, c in codes.items()}

bad = []


def worker(k):
    rnd = random.Random(k)
    names = list(codes) * ROUNDS
    rnd.shuffle(names)
    for n in names:
        threads = rnd.choice([1, 2, 3])
        if rnd.random() < 0.3:
            d = m.decompile_bytecode(codes[n], threads=threads, color=False)
            a = alone_d[n]
            if d.text != a.text or d.json != a.json or d.asm != a.asm:
                bad.append((k, n, threads, "decompile_bytecode"))
            continue
        if m.decompile(codes[n], threads=threads, color=False) != alone[n]:
            bad.append((k, n, threads))


ts = [threading.Thread(target=worker, args=(k,)) for k in range(NT)]
for t in ts:
    t.start()
for t in ts:
    t.join()
total = NT * ROUNDS * len(codes)
print("%d decompilations of %d contracts on %d threads, %d differences" % (total, len(codes), NT, len(bad)))
for b in bad[:10]:
    print("  DIFF", b)
sys.exit(1 if bad or not codes else 0)
