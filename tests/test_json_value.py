#!/usr/bin/env python3
"""The JSON text of values (data.s, the json of decompile_bytecode and
panasm --json) against json.dumps, on random values: nested tuples and
lists, numbers of every size, None, True, False, strings of any code
point (controls, quotes, non-ASCII, astral, lone surrogates).

    tests/test_json_value.py [SEED [COUNT]]
"""
import os, sys, random, json, ast
sys.path.insert(0, os.environ.get("PANASM_BUILD") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import panoramix_asm as A

random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 1)
N = int(sys.argv[2]) if len(sys.argv) > 2 else 2000

def rchar():
    r = random.random()
    if r < 0.5: return chr(random.randint(0x20, 0x7e))
    if r < 0.65: return random.choice('"\\\'\n\r\t\b\f\x00\x7f')
    if r < 0.75: return chr(random.randint(0, 0x1f))
    if r < 0.85: return chr(random.randint(0x80, 0x7ff))
    if r < 0.93: return chr(random.randint(0x800, 0xffff))
    return chr(random.randint(0x10000, 0x10ffff))

def rval(d=0):
    r = random.random()
    if d > 3 or r < 0.5:
        k = random.random()
        if k < 0.2: return random.choice([None, True, False])
        if k < 0.5: return random.choice([0, 1, -1, 32, 2**62 - 1, 2**62, -2**62, -2**62 - 1, 2**63, 2**256 - 1, -2**255])
        if k < 0.6: return random.randint(-2**300, 2**300)
        return "".join(rchar() for _ in range(random.randint(0, 12)))
    items = [rval(d + 1) for _ in range(random.randint(0, 4))]
    return tuple(items) if random.random() < 0.6 else items

bad = 0
for i in range(N):
    v = rval()
    try:
        got = ast.literal_eval(A._test("json_value", repr(v)))
    except Exception as e:
        got = "<error %s>" % e
    exp = json.dumps(v)
    if got != exp:
        bad += 1
        print(f"MISMATCH {v!r}\n   json:  {exp}\n   port:  {got}")
        if bad > 10: break
print(f"{N} values, {bad} mismatches")
sys.exit(1 if bad else 0)
