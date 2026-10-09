"""
The EVM's instructions as spec/evm.def describes them, and what the decoder
makes of a code by the letter of it: the instructions (decode), and the
idioms among them (idioms) - the reference the generated automaton is
verified against (tools/verify_dfa.py, tests/test_decoder.py).
"""
import os
from collections import namedtuple

HERE = os.path.dirname(os.path.abspath(__file__))
DEF = os.path.join(HERE, "..", "spec", "evm.def")

Op = namedtuple("Op", "code name imm pops pushes since flags")


def read_def(path=DEF):
    """{opcode: Op} of evm.def"""
    ops = {}
    for n, line in enumerate(open(path), 1):
        line = line.split("#", 1)[0].split()
        if not line:
            continue
        code, name, imm, pops, pushes, since, *flags = line
        code = int(code, 16)
        assert 0 <= code < 256 and code not in ops, (path, n)
        assert name not in (o.name for o in ops.values()), (path, n)
        ops[code] = Op(code, name, int(imm), int(pops), int(pushes), since, frozenset(flags))
    return ops


OPS = read_def()

# An instruction: where it starts, its opcode, its name (python's UNKNOWN
# for a byte that isn't one), its parameter (python's: a push's number, a
# dup's or a swap's n, an unknown byte's value, else None), and how many of
# its immediate's bytes the code has (fewer than the opcode's at the end of
# a code cut in the middle of a push).
Insn = namedtuple("Insn", "pc op name param size")


def decode(code):
    """The instructions of code (bytes), as the EVM reads them: a push's
    immediate past the end of the code is of zeroes."""
    res = []
    pc = 0
    while pc < len(code):
        b = code[pc]
        op = OPS.get(b)
        if op is None:
            res.append(Insn(pc, b, "UNKNOWN", b, 1))
            pc += 1
            continue
        imm = code[pc + 1 : pc + 1 + op.imm]
        if "dup" in op.flags or "swap" in op.flags:
            param = int(op.name[4 if op.name.startswith("swap") else 3 :])
        elif op.name.startswith("push"):
            param = int.from_bytes(imm + bytes(op.imm - len(imm)), "big")
        else:
            param = None
        res.append(Insn(pc, b, op.name, param, 1 + len(imm)))
        pc += 1 + len(imm)
    return res


def jumpdests(insns):
    """the places of the jumpdests: the instructions', not a byte 0x5b of a
    push's immediate"""
    return [i.pc for i in insns if i.name == "jumpdest"]


# The idioms (NaCl's superinstructions): sequences of instructions the
# decoder recognizes as it goes, without changing what it decodes. Each is
# a list of the instructions it's made of, the last one where it ends:
# (the names they can have, the values of their immediate - a push1's only
# - or None for any).

PUSHES = frozenset(o.name for o in OPS.values() if o.name.startswith("push"))

IDIOMS = {
    # a jump to a number: where it goes is known
    "static_jump": [(PUSHES, None), ({"jump"}, None)],
    "static_jumpi": [(PUSHES, None), ({"jumpi"}, None)],
    # solc's dispatcher: the selector (on the stack) compared with one of
    # the functions', the jump to it if it's that one
    "selector": [
        ({"dup1"}, None),
        ({"push4"}, None),
        ({"eq"}, None),
        ({"push1", "push2", "push3", "push4"}, None),
        ({"jumpi"}, None),
    ],
}

# solidity's free memory pointer, set before anything else: mstore(0x40,
# v), v a push1 of at least 0x60 (what loader.sets_free_memory_pointer finds
# then without running the stack) - at the beginning of the code only
FMP = [({"push1"}, range(0x60, 0x100)), ({"push1"}, range(0x40, 0x41)), ({"mstore"}, None)]


def matches(element, i):
    names, values = element
    return i.name in names and (values is None or i.param in values)


def idioms(insns):
    """(kind, index of its first instruction, index of its last) of every
    idiom in insns, by where they end, then by kind (fmp last)"""
    res = []
    for k in range(len(insns)):
        for kind, elements in IDIOMS.items():
            n = len(elements)
            if k + 1 >= n and all(matches(e, i) for e, i in zip(elements, insns[k + 1 - n : k + 1])):
                res.append((kind, k + 1 - n, k))
        if k == len(FMP) - 1 and all(matches(e, i) for e, i in zip(FMP, insns)):
            res.append(("fmp", 0, k))
    return res
