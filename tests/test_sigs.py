#!/usr/bin/env python3
"""Differential test of the signatures with the database on both sides
(python's sqlite one, made from panoramix's data/abi_dump.xz, and the
port's build/abi_db3.bin, built from the same dump when it's missing):
fetch_sig and its hashes_to, Loader.find_sig, known_fname, the abis of the
functions (make_abi, get_func_name, get_abi_name), the events of the logs
(event_abi, pretty_line), the calls and the errors by their selectors,
and get_param_name with the params of the dump's functions (tuples,
arrays of them).

    tests/test_sigs.py [SEED [COUNT]]
"""
import os, sys, random, json, lzma, subprocess
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DB = os.path.join(ROOT, "build", "abi_db3.bin")
PY = os.environ.get("PANORAMIX_PY", os.path.join(ROOT, "..", "panoramix"))
DUMP = os.environ.get("PANORAMIX_ABI_DUMP", os.path.join(PY, "panoramix", "data", "abi_dump.xz"))
if not os.path.exists(DB):
    subprocess.run([os.path.join(ROOT, "build", "panasm"), "build-db", DUMP, DB], check=True)
os.environ["PANORAMIX_SIGDB"] = DB
sys.path.insert(0, HERE)
sys.path.insert(0, PY)
from panoramix.loader import Loader
find_sig = Loader.__dict__["find_sig"]          # (before test_prettify takes the database away)
from test_prettify import *
from panoramix.utils import supplement, signatures as SIG
Loader.find_sig = find_sig
P.fetch_sig = supplement.fetch_sig
# (the port's entries have no None: an input's missing components are nil)
_test = A._test
A._test = lambda name, lit: _test(name, lit).replace("<nil>", "None")
from eth_hash.auto import keccak

random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 1)
N = int(sys.argv[2]) if len(sys.argv) > 2 else 500

# the dump's entries (a sample of the lines)
entries = []
with lzma.open(DUMP, "rt") as f:
    for i, line in enumerate(f):
        if random.random() < 0.004 or ('"components"' in line and random.random() < 0.2) \
                or ('"event"' in line and random.random() < 0.05):
            entries.append(json.loads(line))
events = [e for e in entries if e["abi"].get("type") == "event"]
tuples = [e for e in entries if '"components"' in json.dumps(e)]
print(f"{len(entries)} entries, {len(events)} events, {len(tuples)} with tuples", flush=True)

def port_inputs(inputs):
    if inputs is None: return None
    def conv(i):
        comps, idx = i.get("components"), i.get("indexed")
        if comps is None and not idx:
            return (i["type"], i["name"])
        return (i["type"], i["name"], [conv(c) for c in comps] if comps is not None else None, 1 if idx else 0)
    return [conv(i) for i in inputs]

from panoramix.utils.helpers import clear_caches
def py_lookup(sel):
    # (afresh: make_abi and find_sig name the unnamed inputs of the dict
    # fetch_sig keeps - no one reads the names before them)
    clear_caches()
    a = supplement.fetch_sig("0x%08x" % sel)
    if a is None: return None
    return (a["name"], port_inputs(a["inputs"]), a.get("type", ""))

def signature(abi):
    return "{}({})".format(abi["name"], ",".join(SIG.canonical_type(i["type"], i.get("components")) for i in abi["inputs"]))

def rsel():
    r = random.random()
    if r < 0.7 and entries:
        return int(random.choice(entries)["selector"], 16)
    if r < 0.85:
        return random.choice([0xa9059cbb, 0x70a08231, 0x23b872dd, 0x095ea7b3, 0x08c379a0, 0x4e487b71, 0])
    return random.randint(0, 2**32 - 1)

def rexp():
    return random.choice([("cd", 4), ("var", 1), 5, 2**160 - 1, "caller", ("mask_shl", 160, 0, 0, ("cd", 36))])

for n in range(N):
    sel = rsel()
    # fetch_sig (hashes_to's filter): the entry, or None
    check("sig_lookup", sel, run(py_lookup, sel), "lookup %d" % n)
    for flags in (0, PF_COLOR):
        check("find_sig", ("0x%08x" % sel, flags), run(Loader.find_sig, "0x%08x" % sel, bool(flags)), "find_sig %d" % n)
        check("known_fname", (sel, flags), run(P.known_fname, sel, bool(flags)), "known_fname %d" % n)
    # the abi of a function of the contract
    h = "0x%08x" % sel
    def py_names():
        SIG.make_abi({h: 0})
        return (SIG._abi[h]["name"], port_inputs(SIG._abi[h].get("inputs")),
                SIG.get_func_name(h), SIG.get_func_name(h, add_color=True), SIG.get_abi_name(h))
    check("abi_names", h, run(lambda: ((lambda r: ((r[0], r[1]),) + r[2:])(py_names()))), "abi %d" % n)
    # a call, an error, a return by the selector
    fparams = random.choice([None, ("data", rexp(), rexp()), rexp()])
    for line in (("call", "gas", 0x1234, random.choice([0, 5]), random.choice([("bytes", 4, sel), sel, None]), fparams),
                 ("call", "gas", 0x1234, 0, None, ("data", ("bytes", 4, sel), rexp())),
                 ("staticcall", "gas", ("cd", 4), 0, ("bytes", 4, sel), fparams),
                 ("delegatecall", "gas", ("cd", 4), ("bytes", 4, sel), fparams),
                 ("revert", ("data", ("bytes", 4, sel), rexp())),
                 ("revert", ("bytes", 4, sel)),
                 ("return", ("data", ("bytes", 4, sel), 32, 3, 0x616263 << 232))):
        for flags in (0, PF_COLOR):
            check("pretty_line", (line, flags), run(lambda: list(P.pretty_line(line, add_color=bool(flags)))), "line %d" % n)
    # an event: its topic, the log's params as the abi has them (or not)
    if events:
        e = random.choice(events)["abi"]
        topic = int.from_bytes(keccak(signature(e).encode()), "big") if random.random() < 0.9 else random.randint(0, 2**256)
        if random.random() < 0.05: topic = -topic
        check("event_abi", topic, run(lambda: (lambda a: None if a is None else (a["name"], port_inputs(SIG.fix_input_names(a["inputs"])), a.get("type")))(P.event_abi(topic))), "event %d" % n)
        nidx = sum(1 for i in e["inputs"] if i.get("indexed"))
        ndata = len(e["inputs"]) - nidx
        if random.random() < 0.3:
            nidx, ndata = random.randint(0, 3), random.randint(0, 3)
        data = ("data",) + tuple(rexp() for _ in range(ndata)) if ndata != 1 or random.random() < 0.5 else rexp()
        line = ("log", data, topic) + tuple(rexp() for _ in range(nidx))
        for flags in (0, PF_COLOR):
            check("pretty_line", (line, flags), run(lambda: list(P.pretty_line(line, add_color=bool(flags)))), "log %d" % n)
    # the params of a function with tuples, arrays of them
    if tuples:
        a = random.choice(tuples)["abi"]
        inputs = SIG.fix_input_names(json.loads(json.dumps(a["inputs"])))
        check("calldata_params", port_inputs(inputs), run(lambda: list(SIG.calldata_params(inputs).values())), "params %d" % n)
        SIG._abi = {"0x00000000": {"name": "f", "inputs": inputs}}
        SIG._func = SIG._abi["0x00000000"]
        try:
            for cd in (("cd", random.choice([4, 36, 68, 100, 132, 164, 196])),
                       ("cd", ("add", random.choice([4, 36, 68, 100, 132]), ("cd", random.choice([4, 36, 68, 100])))),
                       ("cd", ("add", 4, ("param", random.choice([i["name"] for i in inputs] or ["x"]))))):
                check("get_param_name", (port_inputs(inputs), cd, PF_COLOR), run(SIG.get_param_name, cd, True), "params %d" % n)
        finally:
            SIG._abi = SIG._func = None
        for i in inputs:
            comps = port_inputs([i])[0][2] if len(port_inputs([i])[0]) > 2 else None
            check("canonical_type", (i["type"], comps), run(SIG.canonical_type, i["type"], i.get("components")), "params %d" % n)
            check("is_dynamic", (i["type"], comps), run(SIG.is_dynamic, i["type"], i.get("components")), "params %d" % n)
print(f"{test_simplify.cases} cases, {test_simplify.bad} mismatches")
