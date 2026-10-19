#!/usr/bin/env python3
"""The proofs of the decoder's automata - NaCl's verify_validators_dfa.py and
check_decoder.py, the asm's tools/verify_dfa.py - on the machines Ragel makes
of cxx/src/evm/*.rl (`ragel -x`: their states and transitions, the code -G2
compiles), against spec/evm.def as tools/evm_spec.py reads it:

1. Totality: every state of the decoding machines has a transition for every
   byte - no error state, EVM decoding is total.
2. The exec machine (exec_ref.rl, the skeleton of lot 5's vm_exec.rl) and the
   listing (listing.rl): the start state is their only final state, and from
   it every instruction - every opcode, every value of its immediate - fires
   $imm_byte on its immediate's bytes, the action of its evm.def class on its
   last byte and nothing else, and comes back to the start. So every
   instruction boundary is the start state: entered at any instruction start,
   they decode exactly as the linear pass (NaCl's class 1, trivially).
3. The analysis (analysis.rl): from every state the instructions before can
   leave it in, every instruction fires `begin` on its first byte, its class
   action on its last, $imm_byte on its immediate, the idioms' actions only on
   its last byte - and exactly the idioms tools/evm_spec.py's patterns say end
   with it: a walk of the pairs (state, the idioms begun), each pair with every
   instruction (the asm's verify_dfa.py). static_jumpi before selector when
   both end on a JUMPI (the order of the CodeMap's idioms).

The immediates' values aren't all enumerated: at each of their bytes, the
values the automaton takes to the same state with the same actions (and that
the idioms don't tell apart: a PUSH1's for fmp) stand for one another.

    python3 tests/evm_dfa_proof.py [BUILD_DIR]      (make check passes $(B); unused)
"""
import os
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
CXX = os.path.dirname(HERE)
ROOT = os.path.dirname(CXX)
sys.path.insert(0, os.path.join(ROOT, "tools"))
import evm_spec as E  # noqa: E402  (the asm's reference: evm.def, the idioms' patterns)

IDIOM_ACTIONS = ("static_jump", "static_jumpi", "selector", "fmp")
CLASS_ACTIONS = tuple("insn_" + c for c in ("plain", "push", "dup", "swap", "jump", "jumpi", "jumpdest", "halt", "unknown"))

failures = []


def fail(msg):
    failures.append(msg)
    if len(failures) <= 20:
        print("FAIL", msg)


def klass(op):
    """the class of an opcode by evm.def's flags (spec/evm.def's header)"""
    if op is None:
        return "insn_unknown"
    if "dup" in op.flags:
        return "insn_dup"
    if "swap" in op.flags:
        return "insn_swap"
    if "jumpdest" in op.flags:
        return "insn_jumpdest"
    if "jump" in op.flags:
        return "insn_jump" if op.pops == 1 else "insn_jumpi"
    if "halt" in op.flags:
        return "insn_halt"
    if op.imm > 0 or op.name.startswith("push"):
        return "insn_push"
    return "insn_plain"


class Dfa:
    """ragel -x's machine: start, finals, step(state, byte) -> (target, (action names, in order))"""

    def __init__(self, path):
        machine = ET.parse(path).getroot().find("ragel_def").find("machine")
        names = {int(a.get("id")): a.get("name") for a in machine.find("action_list")}
        tables = {}
        for t in machine.find("action_table_list"):
            tables[int(t.get("id"))] = tuple(names[int(x)] for x in t.text.split())
        self.start = int(machine.find("start_state").text)
        self.states = []
        self.finals = set()
        self.rows = {}
        for s in machine.find("state_list"):
            sid = int(s.get("id"))
            self.states.append(sid)
            if s.get("final") == "t":
                self.finals.add(sid)
            extra = [c.tag for c in s if c.tag != "trans_list"]
            if extra:
                fail(f"{path}: state {sid} has {extra} (no to/from-state or eof actions expected)")
            row = [None] * 256
            for t in s.find("trans_list"):
                lo, hi, target, table = t.text.split()
                for b in range(int(lo), int(hi) + 1):
                    row[b] = None if target == "x" else (int(target), tables[int(table)] if table != "x" else ())
            self.rows[sid] = row

    def step(self, state, byte):
        return self.rows[state][byte]


def ragel_xml(tmp, name):
    """the machine of src/evm/<name>.rl, through ragel -x now"""
    out = os.path.join(tmp, name + ".xml")
    subprocess.run(["ragel", "-x", "-I", tmp, "-I", os.path.join(CXX, "src"), "-I", os.path.join(CXX, "src", "evm"),
                    "-o", out, os.path.join(CXX, "src", "evm", name + ".rl")], check=True)
    return Dfa(out)


def check_total(name, dfa):
    for s in dfa.states:
        for b in range(256):
            if dfa.step(s, b) is None:
                fail(f"{name}: state {s} has no transition for {b:#04x}")
                return


def groups(dfa, state, refine=None):
    """the bytes from state, a byte for each (transition, refine) group"""
    res = {}
    for b in range(256):
        res.setdefault((dfa.step(state, b), refine(b) if refine else None), b)
    return list(res.values())


def instructions(dfa, state, refine_push1=None):
    """every instruction from state, a byte of each group at each of its
    immediate's bytes: (bytes, the state after, [the actions of each byte])"""
    res = []
    for op in range(256):
        spec = E.OPS.get(op)
        imm = spec.imm if spec else 0
        refine = refine_push1 if spec and spec.name == "push1" else None
        paths = [([op], state, [])]
        for k in range(1 + imm):
            new = []
            for bs, st, acts in paths:
                for b in ([op] if k == 0 else groups(dfa, st, refine)):
                    step = dfa.step(st, b)
                    if step is None:
                        fail(f"no transition from {st} on {b:#04x} in {bytes(bs).hex()}")
                        continue
                    target, actions = step
                    new.append((bs + [b] if k else bs, target, acts + [actions]))
            paths = new
        res += paths
    return res


def check_insn_actions(name, state, bs, acts, first=()):
    """the actions of an instruction's bytes: `first` (begin) on the first
    byte, $imm_byte on the immediate's, the class action on the last - which
    evm.def's class gives - and the idioms' actions only there"""
    where = f"{name}: state {state}, instruction {bytes(bs).hex()}"
    (insn,) = E.decode(bytes(bs))
    if insn.size != len(bs):
        fail(f"{where}: {insn.size} bytes for {len(bs)}")
    want = klass(E.OPS.get(bs[0]))
    last = len(bs) - 1
    for k, names in enumerate(acts):
        core = [n for n in names if n not in IDIOM_ACTIONS]
        expected = list(first) if k == 0 else []
        if k > 0:
            expected.append("imm_byte")
        if k == last:
            expected.append(want)
        if sorted(core) != sorted(expected):
            fail(f"{where}: byte {k}: actions {names}, expected {expected} (and idioms on the last byte)")
        if k > 0 and k == last and core.index("imm_byte") > core.index(want):
            fail(f"{where}: $imm_byte after the class action: {names}")
        if k != last and any(n in IDIOM_ACTIONS for n in names):
            fail(f"{where}: an idiom's action on byte {k}, not the last: {names}")
    return insn


def check_insn_star(name, dfa):
    """2: an `insn*` machine"""
    check_total(name, dfa)
    if dfa.finals != {dfa.start}:
        fail(f"{name}: final states {sorted(dfa.finals)}, not only the start {dfa.start}")
    n = 0
    for bs, after, acts in instructions(dfa, dfa.start):
        n += 1
        check_insn_actions(name, dfa.start, bs, acts)
        if any(x in IDIOM_ACTIONS or x == "begin" for a in acts for x in a):
            fail(f"{name}: {bytes(bs).hex()}: actions {acts}")
        if after != dfa.start:
            fail(f"{name}: {bytes(bs).hex()} ends in state {after}, not the start")
    finals = "1 final = the start" if dfa.finals == {dfa.start} else f"finals {sorted(dfa.finals)}"
    print(f"{name}: {len(dfa.states)} states, {finals}; {n} instructions from the start")


# the idioms' elements that look at an immediate's value: a PUSH1's only
VALUED = [e for elements in list(E.IDIOMS.values()) + [E.FMP] for e in elements if e[1] is not None]
for names, values in VALUED:
    assert set(names) == {"push1"} and all(0 <= v < 256 for v in values), names


def push1_classes(b):
    return tuple(b in values for _, values in VALUED)


def ref_step(ref, insn):
    """the idioms begun after insn, from ref ((kind, k) of the idioms whose k
    first elements the last instructions are; how many instructions from the
    beginning of the code are fmp's beginning, -1: not), and those ending
    with it (tools/verify_dfa.py's)"""
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


def check_analysis(dfa):
    """3"""
    check_total("analysis", dfa)
    cache = {}
    start = (dfa.start, (frozenset(), 0))
    seen = {start}
    todo = [start]
    n = 0
    while todo:
        state, ref = todo.pop()
        if state not in cache:
            cache[state] = []
            for bs, after, acts in instructions(dfa, state, push1_classes):
                insn = check_insn_actions("analysis", state, bs, acts, first=("begin",))
                idioms = [a for a in acts[-1] if a in IDIOM_ACTIONS]
                if "static_jumpi" in idioms and "selector" in idioms and \
                        idioms.index("static_jumpi") > idioms.index("selector"):
                    fail(f"analysis: state {state}, {bytes(bs).hex()}: selector before static_jumpi")
                cache[state].append((insn, after, sorted(idioms)))
        for insn, after, idioms in cache[state]:
            n += 1
            ref2, ended = ref_step(ref, insn)
            if idioms != ended:
                fail(f"analysis: state {state} after {sorted(ref[0])} (fmp {ref[1]}): {insn}: "
                     f"the automaton ends {idioms}, the idioms {ended}")
            pair = (after, ref2)
            if pair not in seen:
                seen.add(pair)
                todo.append(pair)
    print(f"analysis: {len(dfa.states)} states, {len(cache)} at an instruction boundary, {len(seen)} pairs "
          f"(state, the idioms begun), {n} instructions from them: begin, class, $imm_byte and the idioms where "
          f"evm.def and tools/evm_spec.py say")


def main():
    with tempfile.TemporaryDirectory() as tmp:
        os.makedirs(os.path.join(tmp, "evm"))
        subprocess.run([sys.executable, os.path.join(CXX, "tools", "gen_grammar.py"), "--evm",
                        os.path.join(ROOT, "spec", "evm.def"), "-o", os.path.join(tmp, "evm", "evm_grammar.rlh")],
                       check=True)
        check_insn_star("exec_ref", ragel_xml(tmp, "exec_ref"))
        check_insn_star("listing", ragel_xml(tmp, "listing"))
        check_analysis(ragel_xml(tmp, "analysis"))
    print(f"evm_dfa_proof: {len(failures)} failures")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
