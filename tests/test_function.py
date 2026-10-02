#!/usr/bin/env python3
"""Differential test of the function analysis (function.py's Function):
names, parameters, payable/read-only/const/getter, the trace once its
params are checked, and the printed text - then rename_params (with the
names contract.postprocess gives it) and the text again.

The traces are python's own: what reached Function(hash, trace) in its
whole decompilation of a contract, recorded by gen_function_inputs.py
(build/fn_inputs/NAME.pkl) - so that the function-level code is compared
alone, whatever the VM and the simplifier of the port do meanwhile. Each
is tried with the abi python had (the signature database's), without one
(an unknown function: its params guessed), and with made-up ones.

    tests/test_function.py [build/fn_inputs/X.pkl ...]
"""
import os, sys, glob, time, copy, random
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(HERE, "..", "..", "panoramix")))
sys.path.insert(0, os.environ.get("PANASM_BUILD") or os.path.join(HERE, "..", "build"))
sys.setrecursionlimit(20000)
import logging; logging.disable(logging.CRITICAL)
os.environ.setdefault("PANORAMIX_SIGDB", "/nonexistent")
import pickle
import panoramix_asm as A
from test_simplify import check, run
import test_simplify
from panoramix.loader import Loader
from panoramix.utils import signatures as S
from panoramix import prettify as P
from panoramix.function import Function
from panoramix.matcher import match
from panoramix.utils.helpers import replace_f

# no signature database on either side
Loader.find_sig = staticmethod(lambda sig, add_color=False: None)
P.fetch_sig = lambda h: None

INPUTS = os.path.join(HERE, "..", "build", "fn_inputs")


def port_inputs(inputs):
    if inputs is None:
        return None
    def conv(i):
        comps, idx = i.get("components"), i.get("indexed")
        if comps is None and not idx:
            return (i["type"], i["name"])
        return (i["type"], i["name"], [conv(c) for c in comps] if comps is not None else None, 1 if idx else 0)
    return [conv(i) for i in inputs]


def port_abi(abi):
    return (abi["name"], port_inputs(abi.get("inputs")))


def params_of(f):
    return [(k, v[0], v[1]) for k, v in f.inferred_params.items()]


def py_function(hash, trace, abi):
    S._abi = {hash: copy.deepcopy(abi)}
    f = Function(hash, copy.deepcopy(trace))
    lines = f.print().split("\n")
    return (f.name, f.color_name, f.abi_name, params_of(f), f.trace, f.payable, f.read_only, f.const,
            f.getter, f.returns, f.is_regular, lines, f.priority(), f.value_fails)


def py_function_renamed(hash, trace, abi, storage):
    S._abi = {hash: copy.deepcopy(abi)}
    f = Function(hash, copy.deepcopy(trace))
    # contract.postprocess: the storage's names, the params renamed and
    # put in the trace by name
    P.set_names(storage=storage)
    try:
        f.rename_params(storage)

        def replace_names(exp):
            if (m := match(exp, ("cd", ":int:idx"))) and m.idx in f.inferred_params:
                return ("param", f.inferred_params[m.idx][1])
            return exp

        f.trace = replace_f(f.trace, replace_names)
        lines = f.print().split("\n")
        return (f.name, f.color_name, f.abi_name, params_of(f), port_inputs(S._abi[hash].get("inputs")), lines)
    finally:
        P.set_names(storage=[])


# names the renaming takes: builtin ones, storage-like ones
TAKEN = ["caller", "owner", "block", "tx", "this", "code", "mem", "stor", "eth", "call", "msize", "to",
         "amount", "_owner", "__owner", "balance", "True"]


def fake_inputs(n, rnd):
    """a made-up abi's inputs: n params, of the kinds of calldata_params'
    cases (static tuples and arrays take several words)"""
    kinds = ["address", "uint256", "bool", "bytes32", "uint8", "string", "uint256[]", "bytes",
             "uint256[2]", "tuple", "address[3]", "int16", "bytes4"]
    res = []
    for i in range(n):
        k = rnd.choice(kinds)
        name = rnd.choice(TAKEN + [f"arg{i}", "x", "desc", "amounts", ""]) or f"_param{i + 1}"
        d = {"type": k, "name": name}
        if k == "tuple" and rnd.random() < 0.8:
            d["components"] = [{"type": rnd.choice(["uint256", "address", "bytes", "uint8[2]"]),
                                "name": rnd.choice(["a", "b", "srcToken", ""])}
                               for _ in range(rnd.randint(0, 3))]
        res.append(d)
    return res


def abis_of(hash, abi, rnd):
    """the abi python had, none (unknown), made-up ones"""
    res = [abi]
    if not hash.startswith("0x"):
        return res
    if "inputs" in abi:
        res.append({"name": "unknown" + hash[2:]})
    for n in (0, 1, 3):
        res.append({"name": "fn_" + hash[2:], "inputs": fake_inputs(n, rnd)})
    return res


def storage_names_of(names, rnd):
    names = list(names or [])
    return [names, names + rnd.sample(TAKEN, 3)]


def records(paths):
    for p in paths:
        with open(p, "rb") as f:
            rec = pickle.load(f)
        yield os.path.basename(p).rsplit(".", 1)[0], rec


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    paths = args or sorted(glob.glob(os.path.join(INPUTS, "*.pkl")))
    if not paths:
        print("test_function: skipped, no python inputs in build/fn_inputs (make fn-inputs)")
        sys.exit(0)
    rnd = random.Random(int(os.environ.get("SEED", "1")))
    for name, rec in records(paths):
        t0 = time.time()
        before = test_simplify.bad
        for hash, trace, abi in rec["functions"]:
            ctx = name + " " + hash
            for a in abis_of(hash, abi, rnd):
                check("function", (hash, trace, port_abi(a)), run(py_function, hash, trace, a),
                      ctx + " " + repr(port_abi(a))[:60])
                for storage in storage_names_of(rec["storage_names"], rnd):
                    check("function_renamed", (hash, trace, port_abi(a), storage),
                          run(py_function_renamed, hash, trace, a, storage),
                          ctx + " renamed " + repr(port_abi(a))[:60] + " " + repr(storage)[:60])
        print(f"{'ok  ' if test_simplify.bad == before else 'DIFF'} {name} ({len(rec['functions'])} functions) {time.time() - t0:.1f}s", flush=True)
    print(f"{test_simplify.cases} cases, {test_simplify.bad} mismatches")
    sys.exit(1 if test_simplify.bad else 0)
