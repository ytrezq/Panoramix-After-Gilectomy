#!/usr/bin/env python3
"""Concurrency: several python threads decompiling at once (the module
releases the GIL; each call runs its own workers), each result compared
with the same contract decompiled alone. The shared parts - the chunk
pool, the interned strings, the watchdog's table, the signature
database - are what this exercises.

    tests/test_threads.py [THREADS [ROUNDS]]
"""
import os, sys, glob, threading, random
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "build"))
import panoramix_asm as A

NT = int(sys.argv[1]) if len(sys.argv) > 1 else 4
ROUNDS = int(sys.argv[2]) if len(sys.argv) > 2 else 3

files = sorted(glob.glob(os.path.join(HERE, "corpus", "*.hex")))
# the small and middle ones (the big ones take minutes under load)
files = [f for f in files if os.path.getsize(f) < 30000]
codes = {os.path.basename(f): open(f).read().strip() for f in files}
alone = {n: A.decompile(c, threads=1, color=False) for n, c in codes.items()}

bad = []
def worker(k):
    rnd = random.Random(k)
    names = list(codes) * ROUNDS
    rnd.shuffle(names)
    for n in names:
        t = A.decompile(codes[n], threads=rnd.choice([1, 2, 3]), color=False)
        if t != alone[n]:
            bad.append((k, n))

ts = [threading.Thread(target=worker, args=(k,)) for k in range(NT)]
for t in ts: t.start()
for t in ts: t.join()
total = NT * ROUNDS * len(codes)
print(f"{total} decompilations on {NT} threads, {len(bad)} differences")
for b in bad[:10]: print("  DIFF", b)
sys.exit(1 if bad else 0)
