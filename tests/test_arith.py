#!/usr/bin/env python3
"""Random differential tests of the arithmetic layer against panoramix."""
import os, random, sys
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "panoramix")))
sys.path.insert(0, os.environ.get("PANASM_BUILD") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import logging; logging.disable(logging.CRITICAL)
import panoramix_asm as A
from panoramix.core import arithmetic as P

M = 2**256
random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 1)

# python's byte_op computes 256 ** (31 - position): for a position of
# -2^62 it takes all the memory there is before its MemoryError (an
# inconclusive case): 2 GiB of address space at most
import resource
_soft, _hard = resource.getrlimit(resource.RLIMIT_AS)
if _soft == resource.RLIM_INFINITY or _soft > (2 << 30):
    resource.setrlimit(resource.RLIMIT_AS, (2 << 30, _hard))

def rint():
    r = random.random()
    if r < 0.2: return random.randint(0, 300)
    if r < 0.3: return random.randint(-300, 0)
    if r < 0.5: return random.randint(0, 2**64)
    if r < 0.6: return 2**random.randint(0, 256) - random.randint(0, 1)
    if r < 0.7: return M - random.randint(0, 1000)
    if r < 0.8: return random.randint(0, M - 1)
    if r < 0.9: return random.randint(0, 2**62 + 5)
    return random.choice([0, 1, 2, 31, 32, 255, 256, 2**62, 2**62 - 1, -2**62, M - 1, 2**255, 2**255 - 1])

def rsym():
    return random.choice([("cd", 4), ("cd", 36), "callvalue", ("var", 1), ("storage", 256, 0, 5), ("mem", ("range", 64, 32)), ("bool", ("cd", 4)), ("eq", ("cd", 4), 3)])

def rarg(depth=0):
    r = random.random()
    if r < 0.6 or depth > 2: return rint()
    if r < 0.8: return rsym()
    return rexp(depth + 1)

BIN = ["add", "sub", "mul", "div", "sdiv", "mod", "smod", "exp", "signextend", "shl", "shr", "sar", "and", "or", "xor", "byte", "eq", "lt", "gt", "le", "ge", "slt", "sgt", "sle", "sge"]

def rexp(depth=0):
    op = random.choice(BIN + ["not", "addmod", "mulmod", "and", "iszero", "bool", "mask_shl", "nary", "land", "lor", "storage1"])
    if op == "not": return ("not", rarg(depth))
    if op in ("addmod", "mulmod"): return (op, rarg(depth), rarg(depth), rarg(depth))
    if op == "iszero": return ("iszero", rarg(depth))
    if op == "bool": return ("bool", rarg(depth))
    if op == "mask_shl":
        if random.random() < 0.3:
            return ("mask_shl", 1, random.choice([0, 3, 255, True]), random.choice([0, -3, -255, 3]), rarg(depth))
        return ("mask_shl", rint(), rint(), rint(), rarg(depth))
    if op == "and" and random.random() < 0.3: return ("and", rarg(depth), rarg(depth), rarg(depth))
    if op == "nary":
        # add, mul, or, xor of any number of operands (python's n-ary ones)
        return (random.choice(["add", "mul", "or", "xor"]),) + tuple(rarg(depth) for _ in range(random.randint(0, 4)))
    if op in ("land", "lor"):
        return (op,) + tuple(rarg(depth) for _ in range(random.randint(1, 3)))
    if op == "storage1":
        return ("storage", random.choice([1, 1, 8, True]), random.choice([0, 5, -1]), 3)
    return (op, rarg(depth), rarg(depth))

def rread():
    """reads of the state, for changed_reads"""
    return random.choice([("storage", 256, 0, 5), ("storage", 8, 0, ("sha3", 1, 2)), ("storage", 160, 0, rint() % 7),
                          ("storage", 256, 0, ("add", 1, ("sha3", 5))), ("tload", 3), ("tload", ("cd", 4)), ("balance", "caller"),
                          ("extcodesize", ("cd", 4)), "returndatasize", ("ext_call.return_data", 0, 32), ("delegate.return_data", 0, 32),
                          ("ext_call.success",), "ext_call.gas", ("create.new_address",), ("memcopy.success",), ("x.result",), "callvalue", ("cd", 4)])

def rstate(depth=0):
    if depth > 2 or random.random() < 0.4: return rread()
    return (random.choice(["add", "mul", "iszero", "eq"]),) + tuple(rstate(depth + 1) for _ in range(random.randint(1, 3)))

def norm(v):
    # python bools print as True/False in repr, ints as ints: our side does the same
    return repr(v)

def check(name, pyfn, asfn, arg, n):
    try:
        expected = norm(pyfn(arg))
    except Exception as e:
        expected = "<exc %s>" % type(e).__name__
    got = asfn(arg)
    if expected != got and not expected.startswith("<exc"):
        print(f"MISMATCH {name} #{n}: {arg!r}\n   python: {expected}\n   asm:    {got}")
        return 1
    return 0

bad = 0
N = int(sys.argv[2]) if len(sys.argv) > 2 else 3000
for n in range(N):
    e = rexp()
    bad += check("eval", P.eval, lambda a: A._test("eval", repr(a)), e, n)
    bad += check("is_zero", P.is_zero, lambda a: A._test("is_zero", repr(a)), e, n)
    bad += check("simplify_bool", P.simplify_bool, lambda a: A._test("simplify_bool", repr(a)), e, n)
    x = rint()
    bad += check("to_real_int", P.to_real_int, lambda a: A._test("to_real_int", repr(a)), x, n)
    bad += check("is_bool", P.is_bool, lambda a: A._test("is_bool", repr(a)), e, n)
    kt = random.choice([True, rexp(), ("le", ("cd", 4), rarg()), ("lt", ("cd", 4), rarg()), ("bool", rexp())])
    ex = random.choice([e, ("le", ("cd", 4), rarg()), ("lt", ("cd", 4), rarg()), ("gt", rarg(), rarg()), ("ge", rarg(), rarg()), rint()])
    for sym in (True, False):
        bad += check("eval_bool", lambda a: P.eval_bool(*a), lambda a: A._test("eval_bool", repr(a)), (ex, kt, sym), n)
    st = rstate()
    bad += check("state_read", P.state_read, lambda a: A._test("state_read", repr(a)), st, n)
    sa, sb = random.choice([rint() % 2**70, ("sha3", 1), ("add", 5, ("sha3", 2)), ("cd", 4), -3, 7]), random.choice([rint() % 2**70, ("sha3", 1), ("add", 5, ("sha3", 2)), ("cd", 4), 7])
    bad += check("may_alias", lambda a: P.may_alias(*a), lambda a: A._test("may_alias", repr(a)), (sa, sb), n)
    op = random.choice(["sstore", "store", "tstore", "staticcall", "call", "callcode", "delegatecall", "create", "create2", "mstore", "codecall"])
    bad += check("changed_reads", lambda a: tuple(P.changed_reads(*a)), lambda a: A._test("changed_reads", repr(a)), (st, op, random.choice([5, 3, ("cd", 4), ("sha3", 1, 2), 0])), n)
    if bad > 10:
        break
print("mismatches:", bad)
