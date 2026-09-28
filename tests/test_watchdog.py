#!/usr/bin/env python3
"""The watchdog (rt_watch.s): a pass that takes forever is interrupted at
its deadline; a compaction interrupted puts the old arena back. fixtures/exponential_trace.txt is a random trace whose
simplification doubles an expression at every variable inlined (python
runs out of memory on it); simplify_trace under a 2 s deadline must come
back with the timeout, in about 2 s. Needs only the module in build/."""
import os, sys, time, lzma
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.environ.get("PANASM_BUILD") or os.path.join(HERE, "..", "build"))
# a compaction at every round of simplify_trace (before the first one
# reads it): the deadlines below then fall in compactions too, which must
# put the old arena back
os.environ["PANORAMIX_COMPACT_MIB"] = "1"
import panoramix_asm as A

trace = open(os.path.join(HERE, "fixtures", "exponential_trace.txt")).read().strip()
t0 = time.time()
r = A._test("simplify_trace_deadline", "(%s, 2000)" % trace)
dt = time.time() - t0
ok = "took more than 3 minutes" in r and dt < 10
print("watchdog: %s (%.1f s): %s" % ("ok" if ok else "FAIL", dt, r[:80]))
# and a trace that finishes in time comes back whole
t = "[('setmem', ('range', 64, 32), 128), ('return', ('mem', ('range', 64, 32)))]"
r2 = A._test("simplify_trace_deadline", "(%s, 2000)" % t)
ok2 = r2 == A._test("simplify_trace", t)
print("in time: %s" % ("ok" if ok2 else "FAIL " + r2[:80]))
# a real trace (UniV3Pool's largest function), cut at deadlines all along
# its simplification: each call comes back whole or with the timeout,
# and the context (the python thread's, the same for every call) stays
# sound for the next
big = lzma.decompress(open(os.path.join(HERE, "fixtures", "univ3pool_trace.txt.xz"), "rb").read()).decode()
t0 = time.time()
full = A._test("simplify_trace", big)
dt = time.time() - t0
whole = cut = wrong = 0
for ms in range(1, int(dt * 1000) + 40, 3):
    r = A._test("simplify_trace_deadline", "(%s, %d)" % (big, ms))
    if r == full: whole += 1
    elif "took more than 3 minutes" in r: cut += 1
    else: wrong += 1
ok3 = wrong == 0 and cut > 0
print("deadlines along a simplification: %s (%d whole, %d cut, %d wrong)" % ("ok" if ok3 else "FAIL", whole, cut, wrong))
sys.exit(0 if ok and ok2 and ok3 else 1)
