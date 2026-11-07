#!/usr/bin/env python3
"""Count the loops left in decompiled texts: the `while` loops, and among
them the memory copies still printed as loops (a while whose body holds a
plain copy line `mem[...] = mem[...]`), per contract and in total.

    tools/loop_lines.py DIR [DIR2]     # DIR/NAME.txt: pancxx decompile --no-color

With DIR2, the two directories side by side (before / after), and the
contracts whose counts changed the most."""
import os
import re
import sys

# a plain copy: the whole right-hand side one memory read
COPY = re.compile(r"^\s*mem\[.*\]\s*=\s*mem\[[^\[\]]*(\[[^\[\]]*\][^\[\]]*)*\]\s*$")
WHILE = re.compile(r"^\s*while\b")


def count(path):
    copies = whiles = 0
    stack = []  # [indent, is_copy] of the open while blocks
    with open(path, errors="replace") as f:
        for line in f:
            if not line.strip():
                continue
            ind = len(line) - len(line.lstrip(" "))
            while stack and ind <= stack[-1][0]:
                copies += stack.pop()[1]
            if WHILE.match(line):
                whiles += 1
                stack.append([ind, 0])
            elif stack and COPY.match(line):
                stack[-1][1] = 1
    copies += sum(s[1] for s in stack)
    return copies, whiles


def table(d):
    out = {}
    for n in sorted(os.listdir(d)):
        if n.endswith(".txt"):
            out[n[:-4]] = count(os.path.join(d, n))
    return out


def main():
    dirs = sys.argv[1:]
    if not dirs:
        sys.exit(__doc__)
    tabs = [table(d) for d in dirs]
    for d, t in zip(dirs, tabs):
        c = sum(v[0] for v in t.values())
        w = sum(v[1] for v in t.values())
        print("%s: %d contracts; copy loops %d in %d contracts; while loops %d in %d contracts"
              % (d, len(t), c, sum(1 for v in t.values() if v[0]), w, sum(1 for v in t.values() if v[1])))
    if len(tabs) == 2:
        a, b = tabs
        changed = [(n, a[n], b[n]) for n in a if n in b and a[n] != b[n]]
        changed.sort(key=lambda x: (x[1][0] - x[2][0]), reverse=True)
        print("%d contracts changed (copy loops, while loops: before -> after):" % len(changed))
        for n, x, y in changed[:40]:
            print("  %-50s %4d -> %4d   %4d -> %4d" % (n, x[0], y[0], x[1], y[1]))


if __name__ == "__main__":
    main()
