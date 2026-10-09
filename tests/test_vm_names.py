#!/usr/bin/env python3
"""Differential test of the names the VM gives its variables, against
panoramix.vm.VM: what a function is given - its stack, what's known there,
what runs before it - comes from the dispatcher, whose variables another VM
named, and the function's own are named past them (VM.name_past): a loop's
(1000 * its number + a place on the stack), the _1, _2... of the memory
reads, the results of the precompiles (signer, signer2...). Small programs,
each given one of these variables in each of the three places.

    tests/test_vm_names.py [-v]
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_vm import A, Run, first_diff, py_run

OPS = {"STOP": 0x00, "ADD": 0x01, "GT": 0x11, "ISZERO": 0x15, "CALLDATALOAD": 0x35, "POP": 0x50,
       "MLOAD": 0x51, "MSTORE": 0x52, "SSTORE": 0x55, "JUMP": 0x56, "JUMPI": 0x57, "GAS": 0x5a,
       "DUP1": 0x80, "STATICCALL": 0xfa}

def assemble(src):
    """the code of mnemonics, `PUSH1 x` (x a number or a label), `label:` (a
    jumpdest)"""
    toks = src.split()
    labels, pc, i = {}, 0, 0
    while i < len(toks):
        if toks[i].endswith(":"):
            labels[toks[i][:-1]] = pc
        elif toks[i] == "PUSH1":
            pc += 1
            i += 1
        pc += 1
        i += 1
    out, i = [], 0
    while i < len(toks):
        t = toks[i]
        if t.endswith(":"):
            out.append(0x5b)
        elif t == "PUSH1":
            i += 1
            out += [0x60, labels[toks[i]] if toks[i] in labels else int(toks[i], 0)]
        else:
            out.append(OPS[t])
        i += 1
    return bytes(out).hex()

PROGRAMS = {
    # a loop, the variable given kept on the stack under it
    "loop": """PUSH1 0 loop: DUP1 PUSH1 10 GT ISZERO PUSH1 end JUMPI PUSH1 1 ADD PUSH1 loop JUMP
               end: PUSH1 0 SSTORE PUSH1 1 SSTORE STOP""",
    # two reads of the memory where it may have been written
    "mload": """PUSH1 7 PUSH1 0 CALLDATALOAD MSTORE PUSH1 32 CALLDATALOAD MLOAD PUSH1 0 SSTORE
                PUSH1 64 CALLDATALOAD MLOAD PUSH1 2 SSTORE PUSH1 1 SSTORE STOP""",
    # two ecrecovers
    "precompiled": """PUSH1 32 PUSH1 0x80 PUSH1 128 PUSH1 0 PUSH1 1 GAS STATICCALL POP PUSH1 0x80 MLOAD
                      PUSH1 0 SSTORE PUSH1 32 PUSH1 0xa0 PUSH1 128 PUSH1 0 PUSH1 1 GAS STATICCALL POP
                      PUSH1 0xa0 MLOAD PUSH1 2 SSTORE PUSH1 1 SSTORE STOP""",
}

GIVEN = [1001, 5003, 999, 0, "_1", "_7", "_0", "_x", "_", "signer", "signer2", "signer12", "hash3",
         "signerx", "bn_add", "mod_exp7", "x"]

if __name__ == "__main__":
    verbose = "-v" in sys.argv
    bad = cases = 0
    for name, src in PROGRAMS.items():
        code = assemble(src)
        for v in GIVEN:
            var = ("var", v)
            for stack, known, entry in [((var,), (), ()), ((5,), (("eq", var, 3),), ()),
                                        ((5,), (), (("setmem", ("range", 0x200, 32), var),))]:
                cases += 1
                expected = repr(py_run(code, 0, False, stack, Run(known, entry, ())))
                got = A._test("vm_run", repr((code, 0, 0, stack, known, entry, ())))
                if expected != got:
                    bad += 1
                    print(f"DIFF {name} {stack} {known} {entry}")
                    first_diff(expected, got)
                elif verbose:
                    print(f"ok   {name} {stack} {known} {entry}\n     {expected[:500]}")
    print(f"{cases} cases, {bad} differences")
    sys.exit(1 if bad else 0)
