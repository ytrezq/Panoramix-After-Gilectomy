#!/usr/bin/env python3
"""Differential tests of the simplifier passes on the traces of the corpus:
each pass is run on the trace after whiles.make (and on the intermediate
traces of simplify_trace's rounds), and compared with python's."""
import os, sys, glob, time, pickle
sys.path.insert(0, os.environ.get("PANORAMIX_PY", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "panoramix")))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import logging; logging.disable(logging.CRITICAL)
import panoramix_asm as A
from test_vm import py_run, functions_of, CORPUS
from panoramix import whiles, simplify as S, rewriter as R, postprocess as PP
from panoramix.utils.helpers import rewrite_trace, rewrite_trace_full, rewrite_trace_ifs, replace_f
from panoramix.core.memloc import split_setmem, split_store

import ast
def canon(o):
    """python's _max_op orders the terms of a max with a set (hash-seed
    dependent): compared modulo that order"""
    if isinstance(o, list): return [canon(x) for x in o]
    if isinstance(o, tuple):
        if o and o[0] == "max":
            return ("max",) + tuple(sorted((canon(x) for x in o[1:]), key=repr))
        return tuple(canon(x) for x in o)
    return o

def same_modulo_max_order(a, b):
    try:
        return canon(ast.literal_eval(a)) == canon(ast.literal_eval(b))
    except Exception:
        return False

def norm(r):
    if r is None: return "None"
    if r is True: return "True"
    if r is False: return "False"
    return repr(r)

def run(fn, *args):
    try:
        return norm(fn(*args))
    except Exception as e:
        return "<exc %s: %s>" % (type(e).__name__, e)

bad = 0
cases = 0
def check(name, arg, expected, ctx=""):
    global bad, cases
    cases += 1
    lit = repr(arg)
    try:
        got = A._test(name, lit)
    except Exception as e:
        got = "<asm exc %s>" % e
    ok = expected == got or (expected.startswith("<exc") and (got.startswith("'<exc") or got.startswith('"<exc')))
    if not ok and "max" in expected and same_modulo_max_order(expected, got):
        ok = True
    if not ok:
        bad += 1
        i = 0
        while i < min(len(expected), len(got)) and expected[i] == got[i]:
            i += 1
        print(f"MISMATCH {name} {ctx} (input {len(lit)} chars)\n   python: ...{expected[max(0, i - 150):i + 250]}\n   asm:    ...{got[max(0, i - 150):i + 250]}", flush=True)
        if os.environ.get("DUMP"):
            print("   input:", lit[:3000])
        if bad >= int(os.environ.get("MAXBAD", "6")):
            print("too many mismatches"); sys.exit(1)
    return ok

def pc_tuple(line):
    a = S.parse_counters(line)
    keys = ["setvars", "jds", "stepvars", "counter", "start", "stop", "step", "num_loops", "endvars"]
    def conv(k):
        if k not in a: return None
        v = a[k]
        if isinstance(v, dict): return [(i, x) for i, x in v.items()]
        return v
    return tuple(conv(k) for k in keys)

def whiles_of(trace):
    res = []
    for line in trace:
        if isinstance(line, tuple) and line and line[0] == "while":
            res.append(line); res += whiles_of(line[2])
        if isinstance(line, tuple) and line and line[0] == "if":
            res += whiles_of(line[2]); res += whiles_of(line[3])
    return res

def passes(trace, ctx):
    check("cleanup_conds", trace, run(S.cleanup_conds, trace), ctx)
    check("cleanup_msize", trace, run(S.cleanup_msize, trace), ctx)
    check("cleanup_vars", trace, run(S.cleanup_vars, trace), ctx)
    check("cleanup_mems", trace, run(S.cleanup_mems, trace), ctx)
    check("split_setmem_trace", trace, run(rewrite_trace, trace, split_setmem), ctx)
    check("split_store_trace", trace, run(rewrite_trace_full, trace, split_store), ctx)
    check("pp_cleanup_mul_1", trace, run(PP.cleanup_mul_1, trace), ctx)
    check("replace_bytes_or_string_length", trace, run(S.replace_bytes_or_string_length, trace), ctx)
    check("propagate_storage_in_loops", trace, run(S.propagate_storage_in_loops, trace), ctx)
    check("readability", trace, run(S.readability, trace), ctx)
    check("rewrite_string_stores", trace, run(R.rewrite_string_stores, trace), ctx)
    for w in whiles_of(trace):
        check("parse_counters", w, run(pc_tuple, w), ctx)
        check("loop_to_setmem", w, run(S.loop_to_setmem, w), ctx)
        check("while_max_memidx", w, run(S.while_max_memidx, w), ctx)
        check("extract_setmems", w, run(S.extract_setmems, w), ctx)

if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    full = "--full" in sys.argv
    files = args or sorted(glob.glob(CORPUS + "/*.hex"))
    for f in files:
        code = open(f).read().strip()
        if code.startswith("0x"): code = code[2:]
        name = os.path.basename(f)
        for fname, target, stack, known in functions_of(code):
            ctx = name + " " + fname
            try:
                trace = py_run(code, target, False, stack, known)
                trace = whiles.make(trace)
                trace = rewrite_trace(trace, lambda line: [] if (isinstance(line, tuple) and line[0] == "jumpdest") else [line])
            except Exception as e:
                print("skip", ctx, type(e).__name__); continue
            t0 = time.time()
            if full:
                exp = run(S.simplify_trace, trace)
                t1 = time.time()
                ok = check("simplify_trace", trace, exp, ctx)
                t2 = time.time()
                print(f"{'ok  ' if ok else 'DIFF'} {ctx} py={t1-t0:.2f}s asm={t2-t1:.2f}s", flush=True)
            else:
                passes(trace, ctx)
                # and on the trace after the first round of the simplifier
                trace2 = replace_f(trace, S.simplify_exp)
                trace2 = S.cleanup_vars(trace2)
                trace2 = S.cleanup_mems(trace2)
                passes(trace2, ctx + " (round 1)")
                print(f"done {ctx} {time.time()-t0:.1f}s", flush=True)
    print(f"{cases} cases, {bad} mismatches")
