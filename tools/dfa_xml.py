"""
The automaton ragel makes of spec/evm_decoder.rl (`ragel -x`: its XML), as
tools/rl2asm.py and tools/verify_dfa.py read it.

    dfa = load(path) / run_ragel(root)
    dfa.start, dfa.actions (names, by id), dfa.states[id].final,
    dfa.states[id].trans: [(lo, hi, target, (action ids...))]
    dfa.step(state, byte) -> (target, actions)

The actions of a transition are in the order of their ids - the order
spec/evm_decoder.rl defines them in: an instruction starts, ends, then the
idioms end (ragel's own order is the one their embeddings were made in).
"""
import os
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from collections import namedtuple

State = namedtuple("State", "id final trans")


class Dfa:
    def __init__(self, root):
        machine = root.find("ragel_def").find("machine")
        self.actions = {}
        for a in machine.find("action_list"):
            self.actions[int(a.get("id"))] = a.get("name")
        tables = {}
        for t in machine.find("action_table_list"):
            ids = tuple(sorted(int(x) for x in t.text.split()))
            assert len(set(ids)) == len(ids), t.text
            tables[int(t.get("id"))] = ids
        self.start = int(machine.find("start_state").text)
        self.states = {}
        for s in machine.find("state_list"):
            sid = int(s.get("id"))
            trans = []
            for t in s.find("trans_list"):
                lo, hi, target, table = t.text.split()
                trans.append((int(lo), int(hi), int(target), () if table == "x" else tables[int(table)]))
            # (no actions of their own at the end of the code, nor elsewhere
            # than on the transitions)
            assert all(c.tag == "trans_list" for c in s), [c.tag for c in s]
            self.states[sid] = State(sid, s.get("final") == "t", trans)
        self._step = {}
        for sid, st in self.states.items():
            row = [None] * 256
            for lo, hi, target, acts in st.trans:
                for b in range(lo, hi + 1):
                    assert row[b] is None, (sid, b)
                    row[b] = (target, acts)
            self._step[sid] = row

    def step(self, state, byte):
        """(the state after byte, the actions on the way), None where the
        automaton has no transition (an error)"""
        return self._step[state][byte]

    def action_id(self, name):
        return next(i for i, n in self.actions.items() if n == name)


def load(path):
    return Dfa(ET.parse(path).getroot())


def run_ragel(root, ragel="ragel"):
    """the automaton of root/spec/evm_decoder.rl, made by ragel now"""
    spec = os.path.join(root, "spec")
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "evm_decoder.xml")
        subprocess.run([ragel, "-x", "evm_decoder.rl", "-o", out], cwd=spec, check=True)
        return load(out)
