#!/usr/bin/env python3
"""Generate src/core/ops_gen.hpp from spec/evm.def and spec/ops.def.

    gen_ops.py --evm ../spec/evm.def --ops ../spec/ops.def -o OUT

Writes: enum class Op : u16 (EVM bytes, the decompiler's ops 0x100.., NONE =
0xffff), Sort, the property bits, the content flags, struct OpInfo and the
dense kOpInfo[0x200], and the EVM decoder tables indexed by the byte (kImm,
kStackIn, kStackOut, kClass, kSince). Fails (exit 1) on: an unknown EVM name,
a duplicate number or name, a decompiler op < 0x100 (or > 0x1ff), an unknown
property word, a malformed line. The output is deterministic.
"""
import argparse
import os
import sys

FORKS = ["frontier", "homestead", "byzantium", "constantinople", "istanbul",
         "london", "shanghai", "cancun", "osaka"]

SORTS = ["none", "word", "bool", "bytes", "range", "loc", "line"]

# property word -> (C++ name, bit)
PROPS = [
    ("comm", "COMM"), ("assoc", "ASSOC"),
    ("r_mem", "R_MEM"), ("r_msize", "R_MSIZE"), ("r_storage", "R_STORAGE"),
    ("r_transient", "R_TRANSIENT"), ("r_calldata", "R_CALLDATA"),
    ("r_account", "R_ACCOUNT"), ("r_callres", "R_CALLRES"), ("r_gas", "R_GAS"),
    ("r_ctx", "R_CTX"),
    ("w_mem", "W_MEM"), ("w_storage", "W_STORAGE"), ("w_transient", "W_TRANSIENT"),
    ("w_log", "W_LOG"), ("w_call", "W_CALL"),
    ("halt", "HALT"), ("control", "CONTROL"), ("loopctl", "LOOPCTL"),
    ("line", "LINE"), ("numbered", "NUMBERED"), ("print_only", "PRINT_ONLY"),
]
PROP_BIT = {w: 1 << i for i, (w, _) in enumerate(PROPS)}

# content flags (value.hpp §2.3), derived from the properties
CONTENT = [("F_MEM", 0x01), ("F_MSIZE", 0x02), ("F_STORAGE", 0x04), ("F_STATE", 0x08),
           ("F_VAR", 0x10), ("F_CALLDATA", 0x20), ("F_LOOPCTL", 0x40), ("F_WRITES", 0x80)]
CF = dict(CONTENT)
CONTENT_OF = {
    "r_mem": CF["F_MEM"], "r_msize": CF["F_MSIZE"], "r_storage": CF["F_STORAGE"],
    "r_transient": CF["F_STATE"], "r_account": CF["F_STATE"], "r_callres": CF["F_STATE"],
    "r_gas": CF["F_STATE"], "r_calldata": CF["F_CALLDATA"], "loopctl": CF["F_LOOPCTL"],
    "w_mem": CF["F_WRITES"], "w_storage": CF["F_WRITES"], "w_transient": CF["F_WRITES"],
    "w_log": CF["F_WRITES"], "w_call": CF["F_WRITES"],
}

CLASSES = ["Plain", "Push", "Dup", "Swap", "Jump", "JumpI", "JumpDest", "Halt", "Unknown"]


class SpecError(Exception):
    pass


def fail(path, n, msg):
    raise SpecError(f"{path}:{n}: {msg}")


def read_evm(path):
    """{byte: (name, imm, in, out, since, flags)} of evm.def"""
    ops, names = {}, {}
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            w = line.split("#", 1)[0].split()
            if not w:
                continue
            if len(w) < 6:
                fail(path, n, "expected: opcode name imm in out since [flags]")
            try:
                code, imm, pin, pout = int(w[0], 16), int(w[2]), int(w[3]), int(w[4])
            except ValueError:
                fail(path, n, "bad number")
            name, since, flags = w[1], w[5], frozenset(w[6:])
            if not 0 <= code < 256:
                fail(path, n, f"opcode {w[0]} out of a byte")
            if code in ops:
                fail(path, n, f"duplicate opcode {code:#04x}")
            if name in names:
                fail(path, n, f"duplicate name {name}")
            if since not in FORKS:
                fail(path, n, f"unknown fork {since}")
            bad = flags - {"halt", "jump", "jumpdest", "dup", "swap"}
            if bad:
                fail(path, n, f"unknown flag {sorted(bad)[0]}")
            ops[code] = (name, imm, pin, pout, since, flags)
            names[name] = code
    return ops, names


def parse_arity(path, n, s):
    """(min, max, leaf)"""
    if s == "leaf":
        return 0, 0, True
    try:
        if s.endswith("+"):
            return int(s[:-1]), 255, False
        if "-" in s:
            a, b = s.split("-", 1)
            a, b = int(a), int(b)
            if not 0 <= a <= b < 255:
                raise ValueError
            return a, b, False
        a = int(s)
        if not 0 <= a < 255:
            raise ValueError
        return a, a, False
    except ValueError:
        fail(path, n, f"bad arity {s!r}")


def read_ops(path, evm, evm_names):
    """{op: dict} of ops.def"""
    ops, names = {}, {}
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            w = line.split("#", 1)[0].split()
            if not w:
                continue
            if len(w) < 3:
                fail(path, n, "expected: op name arity props... [prec=N]")
            try:
                code = int(w[0], 0)
            except ValueError:
                fail(path, n, f"bad op number {w[0]!r}")
            name = w[1]
            if not name.replace("_", "").isalnum() or not name[0].isalpha() or name != name.lower():
                fail(path, n, f"bad name {name!r} (lowercase identifier)")
            if code in ops:
                fail(path, n, f"duplicate op number {code:#x}")
            if name in names:
                fail(path, n, f"duplicate name {name}")
            if code < 0x100:
                if code not in evm:
                    if name in evm_names:
                        fail(path, n, f"{name} is EVM byte {evm_names[name]:#04x}, not {code:#04x}")
                    fail(path, n, f"{code:#04x} {name}: unknown EVM instruction "
                                  "(the decompiler's ops start at 0x100)")
                if evm[code][0] != name:
                    fail(path, n, f"unknown EVM name {name} for {code:#04x} "
                                  f"(evm.def: {evm[code][0]})")
            else:
                if code > 0x1ff:
                    fail(path, n, f"op {code:#x} past 0x1ff")
                if name in evm_names:
                    fail(path, n, f"duplicate name {name} (EVM byte {evm_names[name]:#04x})")
            amin, amax, leaf = parse_arity(path, n, w[2])
            sort, props, prec = None, [], 0
            for word in w[3:]:
                if word.startswith("prec="):
                    try:
                        prec = int(word[5:])
                    except ValueError:
                        fail(path, n, f"bad precedence {word!r}")
                    if not 0 <= prec < 256:
                        fail(path, n, f"precedence {prec} out of a byte")
                elif word in SORTS[1:]:
                    if sort is not None:
                        fail(path, n, f"two sorts: {sort}, {word}")
                    sort = word
                    if word == "line":
                        props.append("line")
                elif word in PROP_BIT and word != "line":
                    if word in props:
                        fail(path, n, f"duplicate property {word}")
                    props.append(word)
                else:
                    fail(path, n, f"unknown property word {word!r}")
            ops[code] = dict(name=name, amin=amin, amax=amax, leaf=leaf,
                             sort=sort or "none", props=props, prec=prec)
            names[name] = code
    return ops


def evm_class(name, imm, pin, flags):
    if "dup" in flags:
        return "Dup"
    if "swap" in flags:
        return "Swap"
    if "jumpdest" in flags:
        return "JumpDest"
    if "jump" in flags:
        return "Jump" if pin == 1 else "JumpI"
    if "halt" in flags:
        return "Halt"
    if imm > 0 or name.startswith("push"):
        return "Push"
    return "Plain"


def cstr(s):
    return '"' + s + '"'


def generate(evm, irops):
    # every defined op: EVM bytes (all of evm.def), then the decompiler's
    table = {}
    for code, (name, imm, pin, pout, since, flags) in sorted(evm.items()):
        if code in irops:
            table[code] = irops[code]
        else:  # consumed by the VM, never in the IR
            table[code] = dict(name=name, amin=pin, amax=pin, leaf=False,
                               sort="none", props=[], prec=0)
    for code, d in sorted(irops.items()):
        if code >= 0x100:
            table[code] = d
    enum_names = {}
    for code, d in sorted(table.items()):
        e = d["name"].upper()
        if e in enum_names or e == "NONE":
            raise SpecError(f"duplicate enumerator {e} ({code:#x})")
        enum_names[e] = code

    out = []
    p = out.append
    p("// GENERATED by cxx/tools/gen_ops.py from spec/evm.def and spec/ops.def.")
    p("// Do not edit: change the .def files.")
    p("#pragma once")
    p("")
    p('#include "core/base.hpp"')
    p("")
    p("namespace pan {")
    p("")
    p("// The operations: an EVM instruction is its byte, the decompiler's own")
    p("// operations are 0x100..0x1ff. NONE: not an operation.")
    p("enum class Op : u16 {")
    for code, d in sorted(table.items()):
        p(f"  {d['name'].upper()} = {code:#04x},")
    p("  NONE = 0xffff,")
    p("};")
    p("")
    p("inline constexpr u32 kOpCount = 0x200;  // kOpInfo's size: ops are < kOpCount")
    p("")
    p("enum class Sort : u8 { None, Word, Bool, Bytes, Range, Loc, Line };")
    p("")
    p("// property bits (OpInfo::props)")
    for (w, cname) in PROPS:
        p(f"inline constexpr u32 {cname} = {PROP_BIT[w]:#x}u;")
    p("inline constexpr u32 R_ANY = R_MEM | R_MSIZE | R_STORAGE | R_TRANSIENT | R_CALLDATA |")
    p("                            R_ACCOUNT | R_CALLRES | R_GAS | R_CTX;")
    p("inline constexpr u32 W_ANY = W_MEM | W_STORAGE | W_TRANSIENT | W_LOG | W_CALL;")
    p("")
    p("// content flags (a Value's flags; OpInfo::content is what the op adds)")
    for cname, v in CONTENT:
        p(f"inline constexpr u8 {cname} = {v:#04x};")
    p("inline constexpr u8 F_VOLATILE = F_MEM | F_MSIZE | F_STORAGE | F_STATE;")
    p("")
    p("struct OpInfo {")
    p("  const char* name;     // for dumps and the printer only (nullptr: undefined)")
    p("  u8 arity_min, arity_max;  // IR operands; arity_max 255 = n-ary; leaf: 0, 0")
    p("  bool leaf;")
    p("  Sort sort;")
    p("  u8 prec;              // printer precedence")
    p("  u32 props;")
    p("  u8 content;           // the content flags this op adds")
    p("  bool defined;")
    p("};")
    p("")
    p("inline constexpr OpInfo kOpInfo[kOpCount] = {")
    for code in range(0x200):
        d = table.get(code)
        if d is None:
            p(f"  /* {code:#05x} */ {{nullptr, 0, 0, false, Sort::None, 0, 0u, 0, false}},")
            continue
        bits = [cname for (w, cname) in PROPS if w in d["props"]]
        content = 0
        for w in d["props"]:
            content |= CONTENT_OF.get(w, 0)
        cflags = [cname for cname, v in CONTENT if content & v]
        p(f"  /* {code:#05x} */ {{{cstr(d['name'])}, {d['amin']}, {d['amax']}, "
          f"{'true' if d['leaf'] else 'false'}, Sort::{d['sort'].capitalize()}, {d['prec']}, "
          f"{' | '.join(bits) if bits else '0u'}, "
          f"{' | '.join(cflags) if cflags else '0'}, true}},")
    p("};")
    p("")
    p("// The EVM decoder's tables, indexed by the byte.")
    p("enum class InsnClass : u8 { " + ", ".join(CLASSES) + " };")
    p("enum class Fork : u8 { " + ", ".join(f.capitalize() for f in FORKS) + ", Never = 0xff };")
    p("")

    def table256(ctype, cname, f):
        p(f"inline constexpr {ctype} {cname}[256] = {{")
        for row in range(0, 256, 8):
            p("  " + " ".join(f(b) + "," for b in range(row, row + 8)) + f"  // {row:#04x}")
        p("};")
        p("")

    table256("u8", "kImm", lambda b: str(evm[b][1]) if b in evm else "0")
    table256("u8", "kStackIn", lambda b: str(evm[b][2]) if b in evm else "0")
    table256("u8", "kStackOut", lambda b: str(evm[b][3]) if b in evm else "0")
    table256("InsnClass", "kClass", lambda b: "InsnClass::" + (
        evm_class(evm[b][0], evm[b][1], evm[b][2], evm[b][5]) if b in evm else "Unknown"))
    table256("u8", "kSince", lambda b: (
        f"u8(Fork::{evm[b][4].capitalize()})" if b in evm else "u8(Fork::Never)"))
    p("}  // namespace pan")
    return "\n".join(out) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--evm", required=True)
    ap.add_argument("--ops", required=True)
    ap.add_argument("-o", "--out", required=True)
    a = ap.parse_args(argv)
    try:
        evm, evm_names = read_evm(a.evm)
        irops = read_ops(a.ops, evm, evm_names)
        text = generate(evm, irops)
    except (SpecError, OSError) as e:
        print(f"gen_ops.py: error: {e}", file=sys.stderr)
        return 1
    d = os.path.dirname(a.out)
    if d:
        os.makedirs(d, exist_ok=True)
    tmp = a.out + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    os.replace(tmp, a.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
