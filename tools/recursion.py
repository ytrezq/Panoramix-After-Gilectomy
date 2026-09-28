#!/usr/bin/env python3
"""The recursive functions of the port: the cycles of the call graph, with
the functions whose address is taken (callbacks of the walkers) counted as
called by the function taking it. Prints one function per line (file,
name) and, with --check, fails if one of them lacks STACK_CHECK."""
import collections
import glob
import re
import sys
import os

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
funcs = {}          # name -> file
body = collections.defaultdict(list)
for f in sorted(glob.glob(os.path.join(root, "src", "*.s"))):
    cur = None
    for line in open(f):
        line = line.split("#", 1)[0]
        m = re.match(r"\s*(FUNC|API)\s+(\w+)", line)
        if m:
            cur = m.group(2)
            funcs[cur] = os.path.relpath(f, root)
            continue
        if re.match(r"\s*ENDF", line):
            cur = None
            continue
        if cur:
            body[cur].append(line)

edges = collections.defaultdict(set)
for fn, lines in body.items():
    for line in lines:
        for m in re.finditer(r"\b(?:call|jmp|j[a-z]+)\s+(\w+)", line):
            if m.group(1) in funcs:
                edges[fn].add(m.group(1))
        for m in re.finditer(r"\[rip \+ (\w+)\]", line):
            if m.group(1) in funcs:
                edges[fn].add(m.group(1))

# Tarjan
index = {}
low = {}
stack = []
on = set()
sccs = []
counter = [0]
sys.setrecursionlimit(100000)

def strong(v):
    index[v] = low[v] = counter[0]
    counter[0] += 1
    stack.append(v)
    on.add(v)
    for w in edges[v]:
        if w not in index:
            strong(w)
            low[v] = min(low[v], low[w])
        elif w in on:
            low[v] = min(low[v], index[w])
    if low[v] == index[v]:
        comp = []
        while True:
            w = stack.pop()
            on.discard(w)
            comp.append(w)
            if w == v:
                break
        sccs.append(comp)

for v in funcs:
    if v not in index:
        strong(v)

recursive = set()
for comp in sccs:
    if len(comp) > 1 or comp[0] in edges[comp[0]]:
        recursive.update(comp)

missing = []
for fn in sorted(recursive, key=lambda n: (funcs[n], n)):
    has = any("STACK_CHECK" in l for l in body[fn])
    if "--check" in sys.argv:
        if not has:
            missing.append(fn)
    else:
        print(funcs[fn], fn, "" if has else "(no STACK_CHECK)")

if "--check" in sys.argv:
    for fn in missing:
        print(f"{funcs[fn]}: {fn} is recursive and has no STACK_CHECK")
    sys.exit(1 if missing else 0)
