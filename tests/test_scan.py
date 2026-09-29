#!/usr/bin/env python3
"""The mention flags of strings (str_scan_flags) with every vector level
(PANORAMIX_ISA=scalar|sse2|avx2|avx512) against a model of python's
substring tests, on random strings."""
import sys, random, subprocess, os, json
BUILD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build")
NAMES = ["storage", "balance", "ext_call", "returndatasize", "return_code", "new_address",
         "memcopy", ".result", "gas", "extcodesize", "extcodehash", "mem", "msize"]

if len(sys.argv) > 1 and sys.argv[1] == "run":
    sys.path.insert(0, BUILD)
    import panoramix_asm as A
    random.seed(int(sys.argv[2]))
    alphabet = "sotragebmxncldiuy.w_ 0123456789()'"
    out = []
    for i in range(20000):
        n = random.choice([1, 2, 3, 5, 10, 31, 32, 33, 34, 40, 63, 64, 65, 100, 200])
        t = "".join(random.choice(alphabet) for _ in range(n))
        if random.random() < 0.5:
            k = random.randrange(len(t) + 1)
            t = t[:k] + random.choice(NAMES) + t[k:]
        if random.random() < 0.2:
            t = t[:random.randrange(len(t) + 1)]
        if random.random() < 0.02:
            t = random.choice(["var", "setvar", "va", "setva", "svar", "setvar ", "goto", "got", "gotos",
                               "continue", "continu", "continues", "xontinue"])
        out.append((t, A._test("str_flags", repr(t))))
    print(json.dumps(out))
    sys.exit(0)

seed = sys.argv[1] if len(sys.argv) > 1 else "7"
res = {}
ISAS = ("scalar", "sse2", "avx2", "avx512")
for isa in ISAS:
    r = subprocess.run([sys.executable, __file__, "run", seed], capture_output=True, text=True,
                       env=dict(os.environ, PANORAMIX_ISA=isa))
    res[isa] = json.loads(r.stdout)
bad = 0
for rows in zip(*(res[isa] for isa in ISAS)):
    t = rows[0][0]
    vol = 1 if any(n in t for n in NAMES) else 0
    hf = (1 if "mem" in t else 0) | (2 if "msize" in t else 0) | (4 if "storage" in t else 0) | \
         (8 if t == "var" else 0) | (16 if t == "setvar" else 0) | (32 if t == "goto" else 0) | \
         (64 if t == "continue" else 0) | (128 if vol else 0)
    model = "(%d, %d)" % (vol, hf)
    if any(r[1] != model for r in rows):
        bad += 1
        if bad < 5:
            print(repr(t), [r[1] for r in rows], model)
print(len(res["scalar"]), "strings,", bad, "differences")
sys.exit(1 if bad else 0)
