#!/usr/bin/env python3
"""
The proof that the decoder's automaton - spec/evm_decoder.rl, as ragel
makes it - decodes what spec/evm.def says, and recognizes the idioms of
tools/evm_spec.py where they end and only there: NaCl's verification of its
validator's automaton (verify_validators_dfa.py, verify_superinstructions.py)
for the EVM.

1. Every state has a transition for every byte: the automaton never stops.
2. From every state the instructions before can leave it in, every
   instruction - every opcode, every value of its immediate - is the one
   spec/evm.def describes: insn_start on its opcode, insn_end on its last
   byte and on no other, an idiom's action only where an instruction ends.
   An instruction is open at the end of the code only if a push is cut.
3. The idioms ending with an instruction are the ones the instructions so
   far end with - whatever they are: a walk of the pairs (the automaton's
   state, the beginnings of idioms the last instructions are), each pair
   with every instruction, compared with tools/evm_spec.py's patterns.

The immediates' values aren't all enumerated: at each of their bytes, the
values the automaton takes to the same state with the same actions, and
that the idioms don't tell apart (a push1's), are one - they lead to the
same.

    tools/verify_dfa.py [--xml FILE]
"""
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import dfa_xml  # noqa: E402
import evm_spec as E  # noqa: E402

ROOT = os.path.join(HERE, "..")
INSN = ("insn_start", "insn_end")

failures = []


def fail(msg):
    failures.append(msg)
    if len(failures) <= 20:
        print("FAIL", msg)


def push1_classes(b):
    """what the idioms tell apart of a push1's immediate: the value ranges
    of their elements it's in"""
    return tuple(b in values for _, values in VALUED)


# the elements of the idioms that look at an immediate's value: a push1's
# only (what push1_classes assumes)
VALUED = [e for elements in list(E.IDIOMS.values()) + [E.FMP] for e in elements if e[1] is not None]
for names, values in VALUED:
    assert set(names) == {"push1"} and all(0 <= v < 256 for v in values), names


def groups(dfa, state, refine=None):
    """the bytes from state, grouped by the transition they take (and by
    refine): one stands for its group"""
    res = {}
    for b in range(256):
        res.setdefault((dfa.step(state, b), refine(b) if refine else None), b)
    return list(res.values())


def instructions(dfa, state):
    """every instruction from state, a byte of each group at each of its
    bytes: (its bytes, the state after, the names of the actions on each)"""
    res = []
    for op in range(256):
        spec = E.OPS.get(op)
        imm = spec.imm if spec else 0
        refine = push1_classes if spec and spec.name == "push1" else None
        paths = [([op], state, [])]
        for k in range(1 + imm):
            new = []
            for bs, st, acts in paths:
                for b in ([op] if k == 0 else groups(dfa, st, refine)):
                    target, actions = dfa.step(st, b)
                    new.append((bs + [b] if k else bs, target, acts + [[dfa.actions[a] for a in actions]]))
            paths = new
        res += paths
    return res


def check_instruction(state, bs, acts):
    """2. on the instruction bs from state"""
    where = f"state {state}, instruction {bytes(bs).hex()}"
    (insn,) = E.decode(bytes(bs))
    if insn.size != len(bs):
        fail(f"{where}: {insn.size} bytes for {len(bs)}")
    for k, names in enumerate(acts):
        last = k == len(bs) - 1
        if ("insn_start" in names) != (k == 0):
            fail(f"{where}: insn_start on byte {k}: {names}")
        if ("insn_end" in names) != last:
            fail(f"{where}: insn_end on byte {k}: {names}")
        idioms = [n for n in names if n not in INSN]
        if idioms and not last:
            fail(f"{where}: idiom {idioms} on byte {k}, not where it ends")
        # (the order the decoder runs them in: an instruction starts, ends,
        # then the idioms ending with it)
        order = [INSN.index(n) if n in INSN else len(INSN) for n in names]
        if order != sorted(order):
            fail(f"{where}: actions out of order {names}")
    return insn


def ref_step(ref, insn):
    """the idioms' beginnings after insn, from ref - (the idioms' (kind, k)
    whose k first elements the last instructions are, how many instructions
    from the beginning of the code are fmp's beginning, -1: not) - and the
    idioms ending with it"""
    begun, fmp = ref
    new, ended = set(), []
    for kind, elements in E.IDIOMS.items():
        for k in {0} | {k for kd, k in begun if kd == kind}:
            if E.matches(elements[k], insn):
                if k + 1 == len(elements):
                    ended.append(kind)
                else:
                    new.add((kind, k + 1))
    if fmp >= 0 and E.matches(E.FMP[fmp], insn):
        fmp += 1
        if fmp == len(E.FMP):
            ended.append("fmp")
            fmp = -1
    else:
        fmp = -1
    return (frozenset(new), fmp), sorted(ended)


def check_reference(n=3000, seed=1):
    """ref_step against evm_spec.idioms' patterns, on random instructions
    dense with the idioms' ones"""
    rnd = random.Random(seed)
    pieces = [b"\x80", b"\x63\x12\x34\x56\x78", b"\x14", b"\x61\x01\x23", b"\x60\x07", b"\x56", b"\x57",
              b"\x5f", b"\x60\x80", b"\x60\x40", b"\x52", b"\x60\x60", b"\x62\x01\x02\x03", b"\x01", b"\x5b"]
    for _ in range(n):
        code = b"".join(rnd.choice(pieces) for _ in range(rnd.randint(0, 12)))
        insns = E.decode(code)
        expected = sorted((kind, last) for kind, _, last in E.idioms(insns))
        got, ref = [], (frozenset(), 0)
        for k, insn in enumerate(insns):
            ref, ended = ref_step(ref, insn)
            got += [(kind, k) for kind in ended]
        if sorted(got) != expected:
            fail(f"the reference of the walk differs from evm_spec.idioms on {code.hex()}: {sorted(got)} / {expected}")


def main():
    args = sys.argv[1:]
    dfa = dfa_xml.load(args[1]) if args[:1] == ["--xml"] else dfa_xml.run_ragel(ROOT)
    names = set(dfa.actions.values())
    assert names == set(INSN) | set(E.IDIOMS) | {"fmp"}, names

    # 1
    for sid in dfa.states:
        for b in range(256):
            if dfa.step(sid, b) is None:
                fail(f"state {sid} has no transition for {b:#x}")

    check_reference()

    # 2 and 3: the walk
    cache = {}
    start = (dfa.start, (frozenset(), 0))
    seen = {start}
    todo = [start]
    insns = 0
    while todo:
        state, ref = todo.pop()
        if state not in cache:
            cache[state] = []
            for bs, after, acts in instructions(dfa, state):
                insn = check_instruction(state, bs, acts)
                cache[state].append((insn, after, sorted(n for n in acts[-1] if n not in INSN)))
        for insn, after, idioms in cache[state]:
            insns += 1
            ref2, ended = ref_step(ref, insn)
            if idioms != ended:
                fail(f"state {state} after {sorted(ref[0])} (fmp {ref[1]}): {insn}: the automaton ends {idioms}, the idioms {ended}")
            pair = (after, ref2)
            if pair not in seen:
                seen.add(pair)
                todo.append(pair)

    print(f"{len(dfa.states)} states, {len(cache)} at the end of an instruction, {len(seen)} pairs "
          f"(state, the idioms begun), {insns} instructions from them: {len(failures)} failures")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
