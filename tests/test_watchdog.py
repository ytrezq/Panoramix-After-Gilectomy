#!/usr/bin/env python3
"""The watchdog (rt_watch.s): a pass that takes forever is interrupted at
its deadline. fixtures/exponential_trace.txt is a random trace whose
simplification doubles an expression at every variable inlined (python
runs out of memory on it); simplify_trace under a 2 s deadline must come
back with the timeout, in about 2 s. Needs only the module in build/."""
import os, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "build"))
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
sys.exit(0 if ok and ok2 else 1)
