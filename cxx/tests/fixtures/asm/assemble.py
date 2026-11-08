#!/usr/bin/env python3
"""assemble.py X.asm: the bytecode of a hand-written listing, one line of hex.

The listing is Huff's macro language without macros: words separated by
spaces, `//` comments to the end of the line -
  0x1f        a push of the number, as small as it fits (PUSH1..PUSH32)
  name:       a JUMPDEST here, the label `name`
  @name       PUSH2 of the label's offset
  mnemonic    an opcode by its name (add, sstore, dup1, swap2, log3...)
"""
import sys

OPS = {
    "stop": 0x00, "add": 0x01, "mul": 0x02, "sub": 0x03, "div": 0x04, "sdiv": 0x05, "mod": 0x06,
    "smod": 0x07, "addmod": 0x08, "mulmod": 0x09, "exp": 0x0a, "signextend": 0x0b,
    "lt": 0x10, "gt": 0x11, "slt": 0x12, "sgt": 0x13, "eq": 0x14, "iszero": 0x15, "and": 0x16,
    "or": 0x17, "xor": 0x18, "not": 0x19, "byte": 0x1a, "shl": 0x1b, "shr": 0x1c, "sar": 0x1d,
    "sha3": 0x20, "address": 0x30, "balance": 0x31, "origin": 0x32, "caller": 0x33,
    "callvalue": 0x34, "calldataload": 0x35, "calldatasize": 0x36, "calldatacopy": 0x37,
    "codesize": 0x38, "codecopy": 0x39, "gasprice": 0x3a, "returndatasize": 0x3d,
    "returndatacopy": 0x3e, "timestamp": 0x42, "number": 0x43, "chainid": 0x46,
    "selfbalance": 0x47, "pop": 0x50, "mload": 0x51, "mstore": 0x52, "mstore8": 0x53,
    "sload": 0x54, "sstore": 0x55, "jump": 0x56, "jumpi": 0x57, "pc": 0x58, "msize": 0x59,
    "gas": 0x5a, "jumpdest": 0x5b, "push0": 0x5f, "call": 0xf1, "return": 0xf3,
    "delegatecall": 0xf4, "staticcall": 0xfa, "revert": 0xfd, "invalid": 0xfe,
}
OPS.update({"dup%d" % k: 0x7f + k for k in range(1, 17)})
OPS.update({"swap%d" % k: 0x8f + k for k in range(1, 17)})
OPS.update({"log%d" % k: 0xa0 + k for k in range(5)})


def words(text):
    for line in text.splitlines():
        yield from line.split("//", 1)[0].split()


def assemble(text):
    items = list(words(text))
    labels, pc = {}, 0
    for w in items:  # the labels' offsets
        if w.endswith(":"):
            labels[w[:-1]] = pc
            pc += 1
        elif w.startswith("@"):
            pc += 3
        elif w.startswith("0x"):
            pc += 1 + max(1, (int(w, 16).bit_length() + 7) // 8)
        else:
            pc += 1
    out = bytearray()
    for w in items:
        if w.endswith(":"):
            out.append(0x5b)
        elif w.startswith("@"):
            out += bytes([0x61]) + labels[w[1:]].to_bytes(2, "big")
        elif w.startswith("0x"):
            v = int(w, 16)
            n = max(1, (v.bit_length() + 7) // 8)
            out += bytes([0x5f + n]) + v.to_bytes(n, "big")
        else:
            out.append(OPS[w])
    return out.hex()


if __name__ == "__main__":
    with open(sys.argv[1]) as f:
        print(assemble(f.read()))
