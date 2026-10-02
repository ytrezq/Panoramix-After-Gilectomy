#!/usr/bin/env python3
"""
keccak.s against eth_hash (python's keccak, runtrace's): the digest as
runtrace has it, int.from_bytes(keccak(b), "big"), of random bytes of
random lengths up to 1000 - and every time the lengths around the rate's
boundaries (135, 136, 137 bytes and their multiples), of random bytes, of
zeros and of 0xff (the padding's bytes); and runtrace.s's keccak of a
slot, keccak(slot.to_bytes(32, "big")).

    python3 tests/test_keccak.py [SEED [N]]
"""
import os, random, sys
sys.path.insert(0, os.environ.get("PANASM_BUILD") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import panoramix_asm as A
from eth_hash.auto import keccak

SEED = int(sys.argv[1]) if len(sys.argv) > 1 else 1
N = int(sys.argv[2]) if len(sys.argv) > 2 else 1000
rnd = random.Random(SEED)

cases = bad = 0

def check(b):
    global cases, bad
    cases += 1
    expected = str(int.from_bytes(keccak(b), "big"))
    got = A._test("keccak", repr(b.hex()))
    if got != expected:
        bad += 1
        print(f"MISMATCH len {len(b)}: {b.hex()}\n   python: {expected}\n   asm:    {got}")
        if bad >= 10:
            print(f"{cases} cases, {bad} mismatches")
            sys.exit(1)

edges = sorted({k * 136 + d for k in range(0, 8) for d in (-2, -1, 0, 1, 2)} - {-2, -1})
for n in edges + [32, 64, 1000]:
    check(bytes(rnd.randrange(256) for _ in range(n)))
    check(b"\0" * n)
    check(b"\xff" * n)
for _ in range(N):
    check(bytes(rnd.randrange(256) for _ in range(rnd.randint(0, 1000))))
# runtrace's of a slot: keccak(slot.to_bytes(32, "big"))
for v in [0, 1, 2**62 - 1, 2**62, 2**64, 2**255, 2**256 - 1] + [rnd.randrange(2**rnd.randint(1, 256)) for _ in range(N // 10)]:
    cases += 1
    expected = str(int.from_bytes(keccak(v.to_bytes(32, "big")), "big"))
    got = A._test("keccak_word", repr(v))
    if got != expected:
        bad += 1
        print(f"MISMATCH keccak_word({v})\n   python: {expected}\n   asm:    {got}")
print(f"{cases} cases, {bad} mismatches")
sys.exit(1 if bad else 0)
