#!/usr/bin/env python3
"""Converts a chain of `cmp eax, X` / `je L` into a jump table (the
JT_SWITCH / JT_CASE / JT_END macros of defs.inc), at a given line.

    jt_convert.py file.s LINE NAME [BOUND]

LINE is the line (1-based) of the chain's first `cmp`. The chain may end
with a `jmp DEFAULT`; otherwise the default is the code that follows,
labelled .Ljt_NAME_default. Prints the case labels, whose first
instructions must not read rax or rcx (JT_SWITCH clobbers them)."""
import re, sys

path, line, name = sys.argv[1], int(sys.argv[2]), sys.argv[3]
bound = sys.argv[4] if len(sys.argv) > 4 else "OP_COUNT"
lines = open(path).read().split("\n")
i = line - 1
cases = []
while i + 1 < len(lines):
    m = re.match(r"(\s*)cmp eax, ([\w' +*()-]+?)\s*(#.*)?$", lines[i])
    m2 = re.match(r"\s*je (\S+)\s*(#.*)?$", lines[i + 1])
    if not (m and m2):
        break
    indent = m.group(1)
    cases.append((m.group(2), m2.group(1)))
    i += 2
if len(cases) < 2:
    sys.exit("no chain at line %d" % line)
end = i
m = re.match(r"\s*jmp (\S+)\s*(#.*)?$", lines[i])
if m:
    default = m.group(1)
    end = i + 1
    extra = []
else:
    default = ".Ljt_%s_default" % name
    extra = [default + ":"]
new = ["%sJT_SWITCH %s, %s, %s" % (indent, name, bound, default)]
new += ["%sJT_CASE %s, %s, %s" % (indent, name, v, l) for v, l in cases]
new += ["%sJT_END %s, %s, %s" % (indent, name, bound, default)] + extra
lines[line - 1:end] = new
open(path, "w").write("\n".join(lines))
print("converted %d cases, default %s; targets: %s" % (len(cases), default, " ".join(sorted(set(l for _, l in cases)))))
