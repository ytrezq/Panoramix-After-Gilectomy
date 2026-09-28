#!/usr/bin/env python3
"""Random differential test of the simplifier on random traces - the
shapes of whiles.make's output (memory and storage writes, variables,
ifs, logs, calls, returns) over expressions of memory ranges, variables
and calldata - against panoramix.simplify: every pass of
tests/test_simplify.py, and the whole simplify_trace.

    tests/test_trace_random.py [SEED [COUNT]]

A crash of the port shows as the test dying: TRACE=1 prints each case
before it runs.
"""
import os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_simplify as T
from test_simplify import S, run, passes

# python's recursion limit (1000 frames) isn't the port's (the stack): an
# expression that grows deeper round after round stops python only
_check = T.check
RECURSION_LIMITED = 0
def check(name, arg, expected, ctx=""):
    global RECURSION_LIMITED
    if expected.startswith("<exc RecursionError"):
        RECURSION_LIMITED += 1
        return True
    return _check(name, arg, expected, ctx)
T.check = check

random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 1)
N = int(sys.argv[2]) if len(sys.argv) > 2 else 200

def rint():
    r = random.random()
    if r < 0.7: return random.choice([0, 1, 2, 4, 20, 31, 32, 36, 64, 68, 96, 100, 128, 160, 192, 224, 256, 0xa9059cbb])
    if r < 0.9: return random.choice([2**160 - 1, 2**255, 2**256 - 1, 2**256 - 32, -1, -32, 2**256, -2**256 - 5])
    return random.randint(0, 2**256 - 1)

VAR_IDS = [1, 2, 3, 1001]

def ratom():
    return random.choice([("cd", 4), ("cd", 36), ("cd", 68), "callvalue", "caller", "calldatasize",
                          ("var", random.choice(VAR_IDS)), ("mem", ("range", 64, 32)),
                          ("storage", 256, 0, random.choice([0, 1, 5])), "timestamp",
                          ("ext_call.return_data", 0, 32), "ext_call.success"])

def rpos():
    r = random.random()
    if r < 0.5: return random.choice([0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 4, 36])
    if r < 0.65: return ("mem", ("range", 64, 32))
    if r < 0.8: return ("add", random.choice([4, 32, 36, 64, 96]), ("mem", ("range", 64, 32)))
    if r < 0.9: return ("var", random.choice(VAR_IDS))
    return ("add", random.choice([32, 64]), ("var", random.choice(VAR_IDS)))

def rlen():
    return random.choice([32, 32, 32, 4, 64, 1, 20, ("cd", 4), ("add", 32, ("cd", 36)), 0])

def rrange():
    return ("range", rpos(), rlen())

def rexp(d=0):
    r = random.random()
    if d > 2 or r < 0.35: return rint() if random.random() < 0.4 else ratom()
    op = random.choice(["add", "add", "mul", "sub", "mem", "mem", "and", "or", "iszero", "lt", "gt",
                        "eq", "div", "mask_shl", "sha3", "exp", "shl", "shr", "not", "byte", "mod"])
    if op == "add": return ("add",) + tuple(rexp(d + 1) for _ in range(random.randint(2, 3)))
    if op == "mul": return ("mul", random.choice([1, 2, 32, -1, rint()]), rexp(d + 1))
    if op == "mem": return ("mem", rrange())
    if op == "mask_shl":
        return ("mask_shl", random.choice([8, 32, 160, 248, 256]), random.choice([0, 0, 8, 96]),
                random.choice([0, 0, 8, -8, 96]), rexp(d + 1))
    if op == "sha3": return ("sha3",) + tuple(rexp(d + 1) for _ in range(random.randint(1, 2)))
    if op in ("iszero", "not"): return (op, rexp(d + 1))
    return (op, rexp(d + 1), rexp(d + 1))

def rcond():
    r = random.random()
    if r < 0.3: return ("iszero", rexp(1))
    if r < 0.6: return (random.choice(["lt", "gt", "eq"]), rexp(1), rexp(1))
    return rexp(1)

def rline(d):
    r = random.random()
    if r < 0.3: return ("setmem", rrange(), rexp())
    if r < 0.45: return ("setvar", random.choice(VAR_IDS), rexp())
    if r < 0.55: return ("store", 256, 0, random.choice([0, 1, 5, rexp(2)]), rexp())
    if r < 0.65 and d < 2: return ("if", rcond(), rtrace(d + 1), rtrace(d + 1))
    if r < 0.72: return ("log", ("mem", rrange()), random.choice([0xddf252ad, rint()]), rexp(1))
    if r < 0.8:
        start = rpos()
        return ("call", random.choice(["gas", 2300]), rexp(1), random.choice([0, "callvalue"]),
                ("mem", ("range", start, 4)), ("mem", ("range", ("add", 4, start) if not isinstance(start, int) else start + 4, 64)))
    if r < 0.85: return ("require", rcond())
    if r < 0.92 and d < 2: return rwhile(d)
    return ("setmem", ("range", 64, 32), ("add", 32, ("mem", ("range", 64, 32))))

LOOP_VARS = [15001, 15002, 27001]

def rwhile(d):
    """a loop as whiles.make gives it: ('while', cond, path, jd, setvars),
    the path ending with ('continue', jd, setvars); the jds are the
    strings the tests make of the VM's nodes"""
    k = random.choice(LOOP_VARS)
    jd = "Node((%d, 10, ('%d',)))" % (random.randint(100, 999), random.randint(1, 999))
    cond = random.choice([("lt", ("var", k), rexp(2)), ("add", -1, ("var", k)),
                          ("gt", rexp(2), ("var", k)), ("iszero", ("eq", ("var", k), rexp(2)))])
    body = [rline(d + 1) for _ in range(random.randint(0, 4))]
    if random.random() < 0.5:
        # a copy loop: mem[dst + i] = mem[src + i] (or storage)
        body.append(("setmem", ("range", ("add", random.choice([32, 96, 128]), ("var", k)), 32),
                     random.choice([("mem", ("range", ("add", 64, ("var", k)), 32)),
                                    ("storage", 256, 0, ("add", ("var", k), 5)), rexp(2)])))
    step = random.choice([("add", 1, ("var", k)), ("add", 32, ("var", k)), ("add", -1, ("var", k))])
    setvars = (("setvar", k, step),)
    if random.random() < 0.3:
        k2 = random.choice([v for v in LOOP_VARS if v != k])
        setvars += (("setvar", k2, ("add", 32, ("var", k2))),)
    body.append(("continue", jd, setvars))
    init = (("setvar", k, random.choice([0, 1, ("cd", 4), ("mem", ("range", 64, 32))])),)
    if len(setvars) > 1:
        init += (("setvar", setvars[1][1], random.choice([0, 128, ("var", 1)])),)
    return ("while", cond, body, jd, init)

def rtrace(d=0):
    t = [rline(d) for _ in range(random.randint(1, 6 if d else 12))]
    end = random.random()
    if end < 0.4: t.append(("return", ("mem", rrange())))
    elif end < 0.6: t.append(("revert", 0))
    elif end < 0.8: t.append(("stop",))
    return t

# cases the random runs found once: always checked
REGRESSIONS = [
    # conditions that simplify to None (mem[x len 0]): python's eval_bool
    # can't decide them, the ifs stay
    [("if", None, [("revert", 0)], [("stop",)])],
    [("if", ("iszero", None), [("revert", 0)], [("stop",)])],
    [("if", ("iszero", ("mem", ("range", 32, 0))), [("revert", 0)], [("stop",)])],
    # a negative shift: python's ValueError
    [("setmem", ("range", 64, 32), ("shl", -32, "caller")), ("return", ("mem", ("range", 64, 32)))],
    # numbers past 256 bits written to memory: python's sizeof counts the
    # bytes of those above 2^256 only (not 2^256, not the negative ones)
    [("setmem", ("range", 192, 2), -2**256), ("return", ("mem", ("range", 160, 64)))],
    [("setmem", ("range", 192, 32), 2**256), ("return", ("mem", ("range", 160, 64)))],
    [("setmem", ("range", 192, 1), ("mul", -1, ("mul", 2**251 + 3, 32))), ("return", ("mem", ("range", 160, 64)))],
    [("setmem", ("range", 192, 3), 2**256 + 1), ("return", ("mem", ("range", 160, 64)))],
    # and the postprocessing keeps a mask_shl 256 of the numbers >= 2^256
    [("return", ("mask_shl", 256, 0, 0, -2**300)), ("return", ("mask_shl", 256, 0, 0, 2**256))],
]

if __name__ == "__main__":
    for i, trace in enumerate(REGRESSIONS):
        passes(trace, "regression %d" % i)
        check("simplify_trace", trace, run(S.simplify_trace, trace), "regression %d" % i)
    from panoramix import folder
    for n in range(N):
        trace = rtrace()
        if os.environ.get("TRACE"): print("TRACE", n, repr(trace), flush=True)
        passes(trace, "random %d" % n)
        exp = run(S.simplify_trace, trace)
        check("simplify_trace", trace, exp, "random %d" % n)
        # the folder, on the trace and on its simplification
        check("fold", trace, run(folder.fold, trace), "random %d" % n)
        try:
            simplified = S.simplify_trace(trace)
        except Exception:
            continue
        check("fold", simplified, run(folder.fold, simplified), "random %d (simplified)" % n)
    if RECURSION_LIMITED: print(f"{RECURSION_LIMITED} cases past python's recursion limit")
    print(f"{T.cases} cases, {T.bad} mismatches")
    sys.exit(1 if T.bad else 0)
