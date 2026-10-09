#!/usr/bin/env python3
"""
The decoder (src/decoder.s, the automaton of spec/evm_decoder.rl) against
what spec/evm.def says (tools/evm_spec.py: the instructions, the idioms) and
against python's Loader.load_binary (the instructions, the jumpdests, where
the code ends): every code of one and two bytes, every opcode cut at every
length, random codes dense with the idioms' instructions, the corpora;
panasm decode's report, against one made from the spec. And the tables the
decoder runs (src/evm_dfa.s) against the automaton ragel makes now, state
by state, byte by byte (when ragel is there).

    tests/test_decoder.py [SEED [COUNT]]
"""
import glob, os, random, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
PANASM = os.path.join(os.environ.get("PANASM_BUILD") or os.path.join(HERE, "..", "build"), "panasm")
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(HERE, "..", "..", "panoramix")))
sys.path.insert(0, os.environ.get("PANASM_BUILD") or os.path.join(HERE, "..", "build"))
sys.path.insert(0, os.path.join(HERE, "..", "tools"))
import logging; logging.disable(logging.CRITICAL)
import panoramix_asm as A
import evm_spec as E
from panoramix.loader import Loader, sets_free_memory_pointer

random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 1)
N = int(sys.argv[2]) if len(sys.argv) > 2 else 20000

bad = cases = 0


def check(what, code, expected, got):
    global bad, cases
    cases += 1
    if expected != got:
        bad += 1
        print(f"MISMATCH {what} on {code.hex()[:200]}\n   expected: {str(expected)[:600]}\n   got:      {str(got)[:600]}")
        if bad > 10:
            sys.exit(1)


def asm(code):
    insns, jumpdests, idioms, fmp, last = eval(A._test("decode", repr(code.hex())))
    return insns, jumpdests, idioms, fmp, last


def spec(code):
    insns = E.decode(code)
    return ([(i.pc, i.name, i.param) for i in insns], E.jumpdests(insns),
            sorted(E.idioms(insns), key=lambda x: (x[2], x[0])), any(k == "fmp" for k, _, _ in E.idioms(insns)), len(code))


def python(code):
    """python's Loader: each instruction as its lines have it (a dup's or a
    swap's n as its parameter), the jumpdests, where the code ends"""
    l = Loader()
    l.load_binary(code.hex())
    return [l.lines[k] for k in sorted(l.lines)], l.jump_dests, l.last_line


def as_python(insns):
    res = []
    for pc, name, param in insns:
        for p in ("dup", "swap"):
            if name.startswith(p):
                name = p
        res.append((pc, name, param))
    return res


def one(code):
    a = asm(code)
    s = spec(code)
    a_sorted = (a[0], a[1], sorted(a[2], key=lambda x: (x[2], x[0])), a[3], a[4])
    check("decode (spec)", code, s, a_sorted)
    p = python(code)
    check("decode (python)", code, p, (as_python(a[0]), a[1], a[4]))
    if a[3]:
        # the fast path: python's run of the stack finds it too
        l = Loader()
        l.load_binary(code.hex())
        check("fmp", code, True, sets_free_memory_pointer(l.parsed_lines))


def report(code):
    """what panasm decode prints, from the spec"""
    insns = E.decode(code)
    idioms = E.idioms(insns)
    jds = set(E.jumpdests(insns))
    out = [f"{len(code)} bytes of code, {len(insns)} instructions, {len(jds)} jumpdests"]
    if any(k == "fmp" for k, _, _ in idioms):
        out.append(f"the free memory pointer is set first: mem[0x40] = {hex(insns[0].param)}")
    if insns and insns[-1].name.startswith("push") and insns[-1].size < 1 + E.OPS[insns[-1].op].imm:
        last = insns[-1]
        imm = E.OPS[last.op].imm
        out.append(f"the code ends in a {last.name} at {hex(last.pc)}: {last.size - 1} of its {imm} bytes")
    unknown = [i for i in insns if i.name == "UNKNOWN"]
    if unknown:
        out.append(f"{len(unknown)} bytes that aren't opcodes:")
        out += [f"  {hex(i.pc)}: {hex(i.op)}" for i in unknown]
    static = [(insns[f], insns[l]) for k, f, l in idioms if k in ("static_jump", "static_jumpi")]
    bad = [(p, j) for p, j in static if p.param not in jds]
    out.append(f"{len(static)} jumps to a number, {len(bad)} of them to no jumpdest")
    out += [f"  {hex(j.pc)}: {j.name} to {hex(p.param)}" for p, j in bad]
    jumps = sum(1 for i in insns if i.name in ("jump", "jumpi"))
    out.append(f"{jumps - len(static)} jumps to a computed place")
    selectors = [(insns[f + 1].param, insns[f + 3].param) for k, f, l in idioms if k == "selector"]
    if selectors:
        out.append(f"{len(selectors)} functions solc's dispatcher compares the selector with:")
        out += [f"  {'0x%08x' % sel} -> {hex(dest)}" for sel, dest in selectors]
    return "\n".join(out) + "\n"


def panasm_decode(code):
    with tempfile.NamedTemporaryFile("w", suffix=".hex") as f:
        f.write(code.hex() or "")
        f.flush()
        return subprocess.run([PANASM, "decode", f.name], capture_output=True, text=True).stdout


def tables():
    """src/evm_dfa.s's automaton, the one ragel makes now"""
    if not shutil.which("ragel"):
        print("tables: skipped, no ragel")
        return
    import dfa_xml
    dfa = dfa_xml.run_ragel(os.path.join(HERE, ".."))
    for state in sorted(dfa.states):
        for b in range(256):
            target, actions = dfa.step(state, b)
            check("dfa_step", bytes([state & 0xFF, b]), (target, tuple(a + 1 for a in actions)),
                  eval(A._test("dfa_step", repr((state, b)))))


PIECES = [b"\x80", b"\x63\x12\x34\x56\x78", b"\x14", b"\x61\x01\x23", b"\x60\x07", b"\x56", b"\x57", b"\x5f",
          b"\x60\x80", b"\x60\x40", b"\x52", b"\x60\x60", b"\x62\x01\x02\x03", b"\x01", b"\x5b", b"\x60\x5b",
          b"\x7f" + bytes(range(32)), b"\x0c", b"\xfe", b"\x81", b"\x90"]


def rcode():
    r = random.random()
    if r < 0.5:
        code = b"".join(random.choice(PIECES) for _ in range(random.randint(0, 30)))
    else:
        code = bytes(random.getrandbits(8) for _ in range(random.randint(0, 200)))
    if random.random() < 0.3:
        code = code[: random.randint(0, len(code))]
    return code


if __name__ == "__main__":
    tables()
    print(f"tables: {cases} transitions, {bad} mismatches", flush=True)
    for b in range(256):
        one(bytes([b]))
        for c in range(256):
            one(bytes([b, c]))
    print(f"every code of 1 and 2 bytes: {cases} cases, {bad} mismatches", flush=True)
    for op in range(256):
        imm = E.OPS[op].imm if op in E.OPS else 0
        for n in range(imm + 3):
            for _ in range(3):
                one(bytes([op]) + bytes(random.getrandbits(8) for _ in range(n)))
    for _ in range(N):
        one(rcode())
    corpora = sorted(glob.glob(os.path.join(HERE, "corpus", "*.hex")) + glob.glob(os.path.join(HERE, "synthetic", "*.hex")))
    for f in corpora:
        one(bytes.fromhex(open(f).read().strip().removeprefix("0x")))
    # panasm decode's report
    for f in corpora:
        code = bytes.fromhex(open(f).read().strip().removeprefix("0x"))
        check("panasm decode", code, report(code), panasm_decode(code))
    for _ in range(N // 50):
        code = rcode()
        if code:
            check("panasm decode", code, report(code), panasm_decode(code))
    print(f"{cases} cases, {bad} mismatches")
    sys.exit(1 if bad else 0)
