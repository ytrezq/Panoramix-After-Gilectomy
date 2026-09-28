#!/usr/bin/env python3
"""Differential fuzzing against python: random solidity-like programs
(a selector dispatch, functions made of storage and memory writes, ifs,
requires, loops, logs, calls, returns) decompiled by both, the texts
compared.

    tests/difffuzz.py SEED COUNT [--keep DIR]

Python runs as `python -m panoramix` ($PANORAMIX_PYTHON, pypy by
default, in $PANORAMIX_PY), the port as build/panasm; both with the
signature database. The programs where they differ are kept in DIR
(default build/difffuzz), with both outputs.
"""
import os
import random
import subprocess
import sys
import concurrent.futures

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
PANASM = os.path.join(ROOT, "build", "panasm")
PY_REPO = os.environ.get("PANORAMIX_PY", os.path.join(ROOT, "..", "panoramix"))
PYTHON = os.environ.get("PANORAMIX_PYTHON", os.path.join(PY_REPO, ".venv", "bin", "python"))

OPS = {
    "STOP": 0x00, "ADD": 0x01, "MUL": 0x02, "SUB": 0x03, "DIV": 0x04, "MOD": 0x06,
    "EXP": 0x0a, "LT": 0x10, "GT": 0x11, "SLT": 0x12, "EQ": 0x14, "ISZERO": 0x15,
    "AND": 0x16, "OR": 0x17, "XOR": 0x18, "NOT": 0x19, "BYTE": 0x1a, "SHL": 0x1b,
    "SHR": 0x1c, "SHA3": 0x20, "ADDRESS": 0x30, "BALANCE": 0x31, "CALLER": 0x33,
    "CALLVALUE": 0x34, "CALLDATALOAD": 0x35, "CALLDATASIZE": 0x36,
    "RETURNDATASIZE": 0x3d, "TIMESTAMP": 0x42, "NUMBER": 0x43, "POP": 0x50,
    "MLOAD": 0x51, "MSTORE": 0x52, "SLOAD": 0x54, "SSTORE": 0x55, "JUMP": 0x56,
    "JUMPI": 0x57, "GAS": 0x5a, "JUMPDEST": 0x5b, "LOG1": 0xa1, "LOG2": 0xa2,
    "CALL": 0xf1, "RETURN": 0xf3, "STATICCALL": 0xfa, "REVERT": 0xfd, "INVALID": 0xfe,
    "SDIV": 0x05, "SMOD": 0x07, "ADDMOD": 0x08, "MULMOD": 0x09, "SIGNEXTEND": 0x0b,
    "SGT": 0x13, "SAR": 0x1d, "ORIGIN": 0x32, "CALLDATACOPY": 0x37, "GASPRICE": 0x3a,
    "EXTCODESIZE": 0x3b, "RETURNDATACOPY": 0x3e, "EXTCODEHASH": 0x3f, "BLOCKHASH": 0x40,
    "COINBASE": 0x41, "CHAINID": 0x46, "SELFBALANCE": 0x47, "LOG0": 0xa0,
    "SELFDESTRUCT": 0xff,
}


class Asm:
    """A tiny assembler: ops, pushes, labels (PUSH2 of their offset)."""

    def __init__(self):
        self.items = []
        self.n = 0

    def op(self, *names):
        for name in names:
            self.items.append(("op", OPS[name]))

    def push(self, value, size=None):
        if size is None:
            size = max(1, (value.bit_length() + 7) // 8)
        self.items.append(("push", value, size))

    def dup(self, k):
        assert 1 <= k <= 16
        self.items.append(("op", 0x7f + k))

    def swap(self, k):
        assert 1 <= k <= 16
        self.items.append(("op", 0x8f + k))

    def label(self):
        self.n += 1
        return "L%d" % self.n

    def jumpdest(self, label):
        self.items.append(("label", label))
        self.op("JUMPDEST")

    def push_label(self, label):
        self.items.append(("plabel", label))

    def assemble(self):
        offsets = {}
        pc = 0
        for it in self.items:
            if it[0] == "op":
                pc += 1
            elif it[0] == "push":
                pc += 1 + it[2]
            elif it[0] == "plabel":
                pc += 3
            else:
                offsets[it[1]] = pc
        out = bytearray()
        for it in self.items:
            if it[0] == "op":
                out.append(it[1])
            elif it[0] == "push":
                out.append(0x5f + it[2])
                out += it[1].to_bytes(it[2], "big")
            elif it[0] == "plabel":
                out.append(0x61)
                out += offsets[it[1]].to_bytes(2, "big")
        return bytes(out)


class Gen:
    def __init__(self, rnd):
        self.r = rnd
        self.a = Asm()
        self.depth = 0          # values on the stack above the function's base
        self.counters = []      # stack depths of the loop counters in scope
        self.nparams = 0
        # half the programs use the rest of the instructions and patterns:
        # internal functions, dynamic arrays, calldata copies, static calls
        self.rich = rnd.random() < 0.5
        self.internal = []      # (label, kind) of the internal functions to emit

    # --- expressions: push one value ---

    def expr(self, d=0):
        r = self.r.random()
        if d > 3 or r < 0.35:
            return self.leaf()
        if r < 0.65:
            ops = ["ADD", "SUB", "MUL", "DIV", "MOD", "AND", "OR", "XOR",
                   "LT", "GT", "EQ", "SHL", "SHR", "SLT", "BYTE"]
            if self.rich:
                ops += ["SDIV", "SMOD", "SGT", "SAR", "SIGNEXTEND"]
            op = self.r.choice(ops)
            if self.rich and self.r.random() < 0.05:
                # addmod / mulmod (x, y, n)
                self.expr(d + 1)
                self.expr(d + 1)
                self.expr(d + 1)
                self.a.op(self.r.choice(["ADDMOD", "MULMOD"]))
                self.depth -= 2
                return
            if self.rich and self.r.random() < 0.08:
                self.internal_call(d)
                return
            self.expr(d + 1)
            if op in ("SHL", "SHR", "SAR", "BYTE", "SIGNEXTEND") and self.r.random() < 0.8:
                # the shift on top: mostly a small one (python computes
                # x << 2**255 and runs out of memory)
                self.a.push(self.r.choice([0, 1, 8, 31, 96, 160, 224, 255, 256, 300]))
                self.depth += 1
            else:
                self.expr(d + 1)
            self.a.op(op)
            self.depth -= 1
            return
        if r < 0.72:
            self.expr(d + 1)
            self.a.op(self.r.choice(["ISZERO", "NOT"]))
            return
        if r < 0.78:
            self.expr(d + 1)
            self.a.push((1 << 160) - 1)
            self.a.op("AND")
            return
        if r < 0.86:
            self.expr(d + 1)
            self.a.op("SLOAD")
            return
        if r < 0.93:
            # a mapping's slot: keccak(key . slot)
            self.expr(d + 1)
            self.a.push(0)
            self.a.op("MSTORE")
            self.a.push(self.r.randint(0, 5))
            self.a.push(32)
            self.a.op("MSTORE")
            self.depth -= 1
            self.a.push(64)
            self.a.push(0)
            self.a.op("SHA3")
            self.depth += 1
            if self.r.random() < 0.7:
                self.a.op("SLOAD")
            return
        if r < 0.97:
            self.expr(d + 1)
            self.a.op("MLOAD")
            return
        self.a.push(self.r.randint(0, 3))
        self.expr(d + 1)
        self.a.op("EXP")

    def leaf(self):
        r = self.r.random()
        self.depth += 1
        if r < 0.3:
            self.nparams = max(self.nparams, 1)
            k = self.r.randint(0, 4)
            self.nparams = max(self.nparams, k + 1)
            self.a.push(4 + 32 * k)
            self.a.op("CALLDATALOAD")
        elif r < 0.55:
            self.a.push(self.r.choice([0, 1, 2, 10, 32, 255, 256, 1000, 10 ** 18,
                                       2 ** 255, 2 ** 256 - 1, 0xdeadbeef]))
        elif r < 0.7:
            env = ["CALLER", "CALLVALUE", "TIMESTAMP", "NUMBER", "ADDRESS", "CALLDATASIZE", "GAS"]
            if self.rich:
                env += ["ORIGIN", "GASPRICE", "COINBASE", "CHAINID", "SELFBALANCE", "RETURNDATASIZE"]
            self.a.op(self.r.choice(env))
            if self.rich and self.r.random() < 0.15:
                self.a.op(self.r.choice(["EXTCODESIZE", "EXTCODEHASH", "BLOCKHASH", "BALANCE"]))
        elif r < 0.8 and self.counters:
            # a loop counter
            pos = self.r.choice(self.counters)
            k = self.depth - pos
            if 1 <= k <= 16:
                self.a.dup(k)
            else:
                self.a.push(7)
        elif r < 0.9:
            self.a.push(self.r.randint(0, 7))
            self.a.op("SLOAD")
        else:
            self.a.push(self.r.choice([0, 0x20, 0x40, 0x80, 0xa0]))
            self.a.op("MLOAD")

    def cond(self):
        r = self.r.random()
        if r < 0.5:
            self.expr(1)
            self.expr(1)
            self.a.op(self.r.choice(["LT", "GT", "EQ", "SLT"]))
            self.depth -= 1
        else:
            self.expr(1)
            if self.r.random() < 0.5:
                self.a.op("ISZERO")

    def internal_call(self, d):
        """f(x): push the return address and the argument, jump to the
        function, which leaves its result in place of both (solidity's
        calling convention)"""
        ret = self.a.label()
        if not self.internal or self.r.random() < 0.4:
            self.internal.append((self.a.label(), self.r.randint(0, 3)))
        fn, _ = self.r.choice(self.internal)
        self.a.push_label(ret)
        self.depth += 1
        self.expr(d + 1)
        self.a.push_label(fn)
        self.a.op("JUMP")
        self.a.jumpdest(ret)
        self.depth -= 1                 # (the return address and the argument: the result)

    def internal_functions(self):
        """the bodies: (ret, x) -> result, ending with SWAP1 JUMP"""
        for fn, kind in self.internal:
            a = self.a
            a.jumpdest(fn)
            if kind == 0:               # x + 1, checked
                a.push(1)
                a.dup(2)
                a.op("ADD")
            elif kind == 1:             # storage[x]
                a.dup(1)
                a.op("SLOAD")
            elif kind == 2:             # mapping: keccak(x . 3)
                a.dup(1)
                a.push(0)
                a.op("MSTORE")
                a.push(3)
                a.push(32)
                a.op("MSTORE")
                a.push(64)
                a.push(0)
                a.op("SHA3")
                a.op("SLOAD")
            else:                       # x & 0xff..ff, x * 2
                a.push((1 << 160) - 1)
                a.dup(2)
                a.op("AND")
                a.push(2)
                a.op("MUL")
            a.swap(1)
            a.op("POP")                 # (ret, result)
            a.swap(1)
            a.op("JUMP")

    # --- statements: the stack as it was ---

    def stmts(self, n, d):
        for _ in range(n):
            if self.stmt(d):
                return True     # the path ended
        return False

    def stmt(self, d):
        r = self.r.random()
        if r < 0.25:
            self.expr()
            self.expr()
            self.a.op("SSTORE")
            self.depth -= 2
        elif r < 0.35:
            self.expr()
            self.a.push(self.r.choice([0x80, 0xa0, 0xc0, 0x100]))
            self.depth += 1
            self.a.op("MSTORE")
            self.depth -= 2
        elif r < 0.5 and d < 3:
            # if / else
            els, end = self.a.label(), self.a.label()
            self.cond()
            self.a.op("ISZERO")
            self.a.push_label(els)
            self.a.op("JUMPI")
            self.depth -= 1
            base = self.depth
            ended = self.stmts(self.r.randint(1, 3), d + 1)
            if not ended:
                self.a.push_label(end)
                self.a.op("JUMP")
            self.a.jumpdest(els)
            self.depth = base
            if self.r.random() < 0.5:
                self.stmts(self.r.randint(1, 2), d + 1)
                self.depth = base
            self.a.jumpdest(end)
        elif r < 0.62:
            # require
            ok = self.a.label()
            self.cond()
            self.a.push_label(ok)
            self.a.op("JUMPI")
            self.depth -= 1
            self.a.push(0)
            self.a.dup(1)
            self.a.op("REVERT")
            self.a.jumpdest(ok)
        elif r < 0.72 and d < 2 and len(self.counters) < 2:
            # for (i = 0; i < n; i++)
            head, done = self.a.label(), self.a.label()
            self.a.push(0)
            self.depth += 1
            pos = self.depth
            self.counters.append(pos)
            self.a.jumpdest(head)
            self.a.push(self.r.choice([3, 10, 100]))
            self.a.dup(2)
            self.a.op("LT")
            self.a.op("ISZERO")
            self.a.push_label(done)
            self.a.op("JUMPI")
            self.stmts(self.r.randint(1, 3), d + 1)
            self.depth = pos
            self.a.push(1)
            self.a.op("ADD")
            self.a.push_label(head)
            self.a.op("JUMP")
            self.a.jumpdest(done)
            self.a.op("POP")
            self.counters.pop()
            self.depth -= 1
        elif r < 0.8:
            # an event
            self.expr()
            self.a.push(0x80)
            self.a.op("MSTORE")
            self.depth -= 1
            self.expr()                     # topic1
            # LOG2(offset, size, topic0, topic1): offset on top
            self.a.push(self.r.getrandbits(256), 32)
            self.a.push(0x20)
            self.a.push(0x80)
            self.a.op("LOG2")
            self.depth -= 1
        elif r < 0.88:
            # a call; the result required, or dropped
            self.a.push(0)
            self.a.push(0)
            self.a.push(0)
            self.a.push(0)
            self.depth += 4
            self.expr()                     # value
            self.expr()                     # address
            self.a.op("GAS")
            self.a.op("CALL")
            self.depth -= 5                 # (the six values, the result)
            if self.r.random() < 0.5:
                ok = self.a.label()
                self.a.push_label(ok)
                self.a.op("JUMPI")
                self.a.push(0)
                self.a.dup(1)
                self.a.op("REVERT")
                self.a.jumpdest(ok)
            else:
                self.a.op("POP")
            self.depth -= 1
        elif self.rich and r < 0.97 and self.r.random() < 0.5:
            self.rich_stmt(d)
        elif r < 0.94 and not self.counters:
            # return a value
            self.expr()
            self.a.push(0x80)
            self.a.op("MSTORE")
            self.depth -= 1
            self.a.push(0x20)
            self.a.push(0x80)
            self.a.op("RETURN")
            return True
        else:
            self.expr()
            self.a.op("POP")
            self.depth -= 1
        return False

    def rich_stmt(self, d):
        k = self.r.randint(0, 4)
        a = self.a
        if k == 0:
            # array.push(v): slot p, length at p, data at keccak(p) + length
            p = self.r.randint(0, 6)
            self.expr()
            a.push(p)
            a.op("SLOAD")
            a.push(p)
            a.push(0)
            a.op("MSTORE")
            a.push(32)
            a.push(0)
            a.op("SHA3")
            a.op("ADD")
            a.op("SSTORE")
            self.depth -= 1
            a.push(1)
            a.push(p)
            a.op("SLOAD")
            a.op("ADD")
            a.push(p)
            a.op("SSTORE")
        elif k == 1:
            # the calldata copied to memory, and returned or logged
            a.op("CALLDATASIZE")
            a.push(0)
            a.push(0x80)
            a.op("CALLDATACOPY")
            a.op("CALLDATASIZE")
            a.push(0x80)
            a.op("LOG0")
        elif k == 2:
            # a static call, its return data read back
            ok = a.label()
            a.push(32)
            a.push(0x80)
            a.push(4)
            a.push(0x80)
            self.depth += 4
            self.expr()                     # address
            a.op("GAS")
            a.op("STATICCALL")
            self.depth -= 4
            a.op("ISZERO")
            a.op("ISZERO")
            a.push_label(ok)
            a.op("JUMPI")
            self.depth -= 1
            a.op("RETURNDATASIZE")
            a.push(0)
            a.dup(1)
            a.op("RETURNDATACOPY")
            a.op("RETURNDATASIZE")
            a.push(0)
            a.op("REVERT")
            a.jumpdest(ok)
            a.push(0x80)
            a.op("MLOAD")
            a.push(self.r.randint(0, 6))
            a.op("SSTORE")
        elif k == 3:
            # a signed value stored: signextend(b, x)
            self.expr()
            a.push(self.r.choice([0, 1, 3, 15, 31]))
            a.op("SIGNEXTEND")
            a.push(self.r.randint(0, 6))
            a.op("SSTORE")
            self.depth -= 1
        else:
            # an internal function's result stored
            self.internal_call(0)
            a.push(self.r.randint(0, 6))
            a.op("SSTORE")
            self.depth -= 1

    def program(self):
        a = self.a
        a.push(0x80)
        a.push(0x40)
        a.op("MSTORE")
        fallback = a.label()
        a.push(4)
        a.op("CALLDATASIZE")
        a.op("LT")
        a.push_label(fallback)
        a.op("JUMPI")
        a.push(0)
        a.op("CALLDATALOAD")
        a.push(0xe0)
        a.op("SHR")
        funcs = []
        for _ in range(self.r.randint(1, 4)):
            lbl = a.label()
            funcs.append(lbl)
            a.dup(1)
            a.push(self.r.getrandbits(32), 4)
            a.op("EQ")
            a.push_label(lbl)
            a.op("JUMPI")
        a.jumpdest(fallback)
        if self.r.random() < 0.5:
            a.push(0)
            a.dup(1)
            a.op("REVERT")
        else:
            a.op("STOP")
        for lbl in funcs:
            a.jumpdest(lbl)
            self.depth = 0
            self.counters = []
            if not self.stmts(self.r.randint(1, 6), 0):
                a.op("STOP")
        self.internal_functions()
        return a.assemble()


def run_python(code):
    env = dict(os.environ, PYTHONPATH=PY_REPO, PYTHONINTMAXSTRDIGITS="0")
    try:
        p = subprocess.run([PYTHON, "-m", "panoramix", code.hex()], capture_output=True,
                           text=True, timeout=900, env=env)
        out = p.stdout
    except subprocess.TimeoutExpired:
        return None
    import re
    return re.sub(r"\x1b\[[0-9;]*m", "", out)


def run_port(path):
    env = dict(os.environ, PANORAMIX_LOG="error")
    env.setdefault("PANORAMIX_SIGDB", os.path.join(ROOT, "build", "abi_db.bin"))
    p = subprocess.run([PANASM, "decompile", path, "--no-color", "-j", "1"],
                       capture_output=True, text=True, timeout=900, env=env)
    return p.returncode, p.stdout


def one(args):
    seed, i, keep = args
    rnd = random.Random("%d-%d" % (seed, i))
    code = Gen(rnd).program()
    path = os.path.join(keep, "case_%d_%d.hex" % (seed, i))
    with open(path, "w") as f:
        f.write(code.hex())
    rc, got = run_port(path)
    expected = run_python(code)
    if expected is None:
        os.remove(path)
        return i, "python timeout"
    if rc == 0 and got == expected:
        os.remove(path)
        return i, None
    with open(path[:-4] + ".py.txt", "w") as f:
        f.write(expected)
    with open(path[:-4] + ".asm.txt", "w") as f:
        f.write(got)
    return i, "rc=%d" % rc if rc else "differs"


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    seed, count = int(args[0]), int(args[1])
    keep = os.path.join(ROOT, "build", "difffuzz")
    if "--keep" in sys.argv:
        keep = sys.argv[sys.argv.index("--keep") + 1]
    os.makedirs(keep, exist_ok=True)
    jobs = int(os.environ.get("JOBS", "2"))
    bad = 0
    with concurrent.futures.ThreadPoolExecutor(jobs) as ex:
        for i, res in ex.map(one, [(seed, i, keep) for i in range(count)]):
            if res:
                if res != "python timeout":
                    bad += 1
                print("case %d: %s" % (i, res), flush=True)
    print("%d cases, %d differences" % (count, bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
