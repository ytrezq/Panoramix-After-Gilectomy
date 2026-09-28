#!/usr/bin/env python3
"""Differential test of the printer: prettify (with every combination of
its flags) on every sub-expression of the corpus traces, before and after
simplification and folding, against panoramix.prettify."""
import os, sys, glob, time, ast
sys.path.insert(0, "/home/claude/panoramix")
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build"))
import logging; logging.disable(logging.CRITICAL)
import panoramix_asm as A
from test_vm import py_run, functions_of, CORPUS
from test_simplify import check, run
import test_simplify
from panoramix import whiles, folder, prettify as P
from panoramix.loader import Loader
from panoramix.utils.helpers import rewrite_trace

# no signature database on either side (yet)
Loader.find_sig = staticmethod(lambda sig, add_color=False: None)

PF_REM_BOOL, PF_PARENS, PF_TOP, PF_COLOR = 1, 2, 4, 8

def py_prettify(exp, flags):
    return P.prettify(exp, rem_bool=bool(flags & PF_REM_BOOL), parentheses=bool(flags & PF_PARENS),
                      top_level=bool(flags & PF_TOP), add_color=bool(flags & PF_COLOR))

def subexps(exp, out):
    """every tuple, int and string in a trace, once"""
    if isinstance(exp, list):
        for e in exp: subexps(e, out)
        return
    if isinstance(exp, tuple):
        out.setdefault(repr(exp), exp)
        for e in exp: subexps(e, out)
        return
    if isinstance(exp, (int, str)) and not isinstance(exp, bool):
        out.setdefault(repr(exp), exp)

def lines_of(trace, out):
    """every line of a trace (the branches of the ifs and whiles too)"""
    for line in trace:
        out.setdefault(repr(line), line)
        if isinstance(line, tuple) and line and line[0] == "if":
            for branch in line[2:]: lines_of(branch, out)
        if isinstance(line, tuple) and line and line[0] == "while":
            lines_of(line[2], out)

def check_lines(lines, ctx):
    for r, line in lines.items():
        for flags in (0, PF_COLOR):
            check("pretty_line", (line, flags), run(lambda l, f: list(P.pretty_line(l, add_color=bool(f & PF_COLOR))), line, flags), ctx)

def check_exps(exps, ctx):
    for r, exp in exps.items():
        for flags in (0, PF_PARENS, PF_COLOR, PF_PARENS | PF_COLOR, PF_REM_BOOL | PF_COLOR, PF_PARENS | PF_TOP):
            check("prettify", (exp, flags), run(py_prettify, exp, flags), ctx)
        if isinstance(exp, tuple) and exp and exp[0] == "data":
            check("pretty_memory", (exp, PF_COLOR), run(lambda e: list(P.pretty_memory(e, add_color=True)), exp), ctx)
        if isinstance(exp, int):
            check("pretty_fname", (exp, 0, 0), run(P.pretty_fname, exp), ctx)
            check("pretty_bignum", exp, run(lambda e: __import__("panoramix.utils.helpers", fromlist=["x"]).pretty_bignum(e), exp), ctx)

if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
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
            exps = {}
            subexps(trace, exps)
            try:
                trace_s = ast.literal_eval(A._test("simplify_trace", repr(trace)))
            except Exception as e:
                print("unparseable simplified trace", ctx, e); continue
            subexps(trace_s, exps)
            folded = folder.fold(trace_s)
            subexps(folded, exps)
            before = test_simplify.bad
            check_exps(exps, ctx)
            lines = {}
            lines_of(trace, lines); lines_of(trace_s, lines); lines_of(folded, lines)
            check_lines(lines, ctx)
            for t in (trace, trace_s, folded):
                check("pprint_logic", (t, 2), run(lambda x: list(P.pprint_logic(x)), t), ctx)
            print(f"{'ok  ' if test_simplify.bad == before else 'DIFF'} {ctx} {len(exps)} expressions {time.time()-t0:.1f}s", flush=True)
    print(f"{test_simplify.cases} cases, {test_simplify.bad} mismatches")
