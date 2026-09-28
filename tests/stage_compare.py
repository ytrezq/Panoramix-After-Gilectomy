#!/usr/bin/env python3
"""Where does a function's simplification start to differ from python's?

    stage_compare.py contract.hex FUNCTION [OUT]

Runs python's simplify_trace on the function (0x12345678 or _fallback),
recording every stage it explains, then applies the port's version of
each stage to python's input of that stage, and reports the first one
whose output differs (and writes its input to OUT, for a closer look)."""
import sys, ast, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ["PANORAMIX_SIGDB"] = "/nonexistent"
from test_simplify import *
import panoramix.simplify

stages = []
panoramix.simplify.explain = lambda name, t: stages.append((name, t))

def asm(hook):
    return lambda t: A._test(hook, repr(t))

def seq(*hooks):
    def f(t):
        r = t
        for h in hooks:
            r = ast.literal_eval(A._test(h, repr(r)))
        return repr(r)
    return f

STAGES = {
    "split setmems & storages": seq("split_setmem_trace", "split_store_trace"),
    "convert loops to setmems": asm("loop_to_setmem_trace"),
    "using heuristics to clean up some things": asm("heuristics"),
    "final setmem/condition cleanup": seq("cleanup_mems", "cleanup_mems", "cleanup_mems", "cleanup_conds"),
    "cleaning up storages slightly": seq("fix_storages_trace", "cleanup_conds"),
    "cleanup variables": asm("cleanup_vars"),
    "cleanup vars": asm("cleanup_vars"),
    "cleanup mems": asm("cleanup_mems"),
    "calculate msize": asm("cleanup_msize"),
    "replace storage with length": asm("replace_bytes_or_string_length"),
    "cleanup unused ifs": asm("cleanup_conds"),
    "move loop indexes outside of loops": asm("propagate_storage_in_loops"),
    "adding nicer variable names": asm("readability"),
}

if __name__ == "__main__":
    code = open(sys.argv[1]).read().strip()
    target = sys.argv[2]
    out = sys.argv[3] if len(sys.argv) > 3 else None
    for fname, tgt, stack, known in functions_of(code):
        if fname != target:
            continue
        trace = py_run(code, tgt, False, stack, known)
        trace = whiles.make(trace)
        trace = rewrite_trace(trace, lambda line: [] if (isinstance(line, tuple) and line[0] == "jumpdest") else [line])
        stages.append(("input", trace))
        S.simplify_trace(trace)
        for i in range(1, len(stages)):
            name, t = stages[i]
            if name == "simplify expressions":
                # three stages have this name: replace_f(simplify_exp) twice,
                # then cleanup_mul_1 (after the second)
                after_second = stages[i - 1][0] == "simplify expressions" and stages[i - 2][0] == "cleanup vars"
                hook = asm("pp_cleanup_mul_1") if after_second else asm("simplify_exps")
            else:
                hook = STAGES.get(name)
            if hook is None:
                continue
            got, exp = hook(stages[i - 1][1]), repr(t)
            if got != exp:
                j = 0
                while j < min(len(got), len(exp)) and got[j] == exp[j]:
                    j += 1
                print("stage %d (%s) differs" % (i, name))
                print("  python: ...", exp[max(0, j - 250):j + 150])
                print("  asm:    ...", got[max(0, j - 250):j + 150])
                if out:
                    open(out, "w").write(repr(stages[i - 1][1]))
                break
        else:
            print("every stage is the same")
        break
    else:
        print("no function", target)
