#!/usr/bin/env python3
"""Differential test of the loader (loader.s) against panoramix.loader: the
free memory pointer the contract sets (sets_free_memory_pointer, the
loader's LD_NO_FREE_MEM) and the disassembly, on random code - prefixes
like solidity's, vyper's, a library's - and on the corpora.

    tests/test_loader.py [SEED [COUNT]]
"""
import glob, os, random, subprocess, sys, tempfile
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "panoramix")))
sys.path.insert(0, os.environ.get("PANASM_BUILD") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import logging; logging.disable(logging.CRITICAL)
import panoramix_asm as A
from panoramix.loader import Loader, sets_free_memory_pointer

HERE = os.path.dirname(os.path.abspath(__file__))
PANASM = os.path.join(os.environ.get("PANASM_BUILD") or os.path.join(HERE, "..", "build"), "panasm")

random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 1)
N = int(sys.argv[2]) if len(sys.argv) > 2 else 2000

def push(v, n=None):
    if n is None:
        n = max(1, (v.bit_length() + 7) // 8)
    return bytes([0x5f + n]) + v.to_bytes(n, "big") if n else b"\x5f"

def rinstr():
    r = random.random()
    if r < 0.35:
        v = random.choice([0, 0x40, 0x60, 0x80, 0x5f, 0x10000, 0xffff, 0xa0, 32, 4, 2**160 - 1, random.getrandbits(random.randint(1, 256))])
        return push(v, random.choice([None, None, 32, 2, 0]) if v == 0 or v < 2**16 else None)
    if r < 0.5: return bytes([0x80 + random.randint(0, 3)])        # dup1..4
    if r < 0.6: return bytes([0x90 + random.randint(0, 3)])        # swap1..4
    if r < 0.72: return b"\x52"                                    # mstore
    if r < 0.9: return bytes([random.choice([0x30, 0x14, 0x34, 0x36, 0x10, 0x11, 0x15])])
    return bytes([random.choice([0x50, 0x01, 0x57, 0x5b, 0x56, 0x0c, 0xfe, 0x49, 0x4a, 0x5c, 0x5d, 0x5e, 0x35, 0x51, 0x1e, 0xf5])])

PREFIXES = [
    bytes.fromhex("6080604052"),             # solidity
    bytes.fromhex("6060604052"),             # before 0.4.22
    bytes.fromhex("608060405234801561001057600080fd5b50"),
    bytes.fromhex("60806040819052"),          # via IR-like
    bytes.fromhex("73000000000000000000000000000000000000000030146080604052"),  # a library
    bytes.fromhex("600436101561000d57"),     # vyper
    bytes.fromhex("6003361161000c57"),
    bytes.fromhex("5f35601c52"),
    b"",
]

def rcode():
    code = random.choice(PREFIXES) if random.random() < 0.6 else b""
    code += b"".join(rinstr() for _ in range(random.randint(0, 40)))
    if random.random() < 0.2:
        code = code[: random.randint(0, len(code))]         # a push cut short
    return code

bad = cases = 0
def check(name, arg, expected, got):
    global bad, cases
    cases += 1
    if expected != got:
        bad += 1
        print(f"MISMATCH {name} {arg}\n   python: {expected}\n   asm:    {got}")
        if bad > 10:
            sys.exit(1)

def py_fmp(code):
    l = Loader()
    l.load_binary(code.hex())
    return repr(sets_free_memory_pointer(l.parsed_lines))

def disasm(code):
    l = Loader()
    l.load_binary(code.hex())
    expected = "\n".join(l.disasm()) + ("\n" if l.parsed_lines else "")
    with tempfile.NamedTemporaryFile("w", suffix=".hex") as f:
        f.write(code.hex())
        f.flush()
        got = subprocess.run([PANASM, "disasm", f.name], capture_output=True, text=True).stdout
    return expected, got

trues = 0
for n in range(N):
    code = rcode()
    e = py_fmp(code)
    trues += e == "True"
    check("sets_fmp", code.hex(), e, A._test("sets_fmp", repr(code.hex())))
    if n % 20 == 0:
        e, g = disasm(code)
        check("disasm", code.hex(), e, g)

for path in sorted(glob.glob(os.path.join(HERE, "corpus", "*.hex")) + glob.glob(os.path.join(HERE, "synthetic", "*.hex"))):
    code = open(path).read().strip()
    if code.startswith("0x"): code = code[2:]
    code = bytes.fromhex(code)
    check("sets_fmp", os.path.basename(path), py_fmp(code), A._test("sets_fmp", repr(code.hex())))

print(f"{cases} cases ({trues} setting the pointer), {bad} mismatches")
sys.exit(1 if bad else 0)
