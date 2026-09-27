# Trace simplification (port of simplify.py) - in progress.

.include "defs.inc"

        .text

# simplify_trace(trace, timeout_ns) -> list
FUNC simplify_trace
        mov rax, rdi
        ret
ENDF simplify_trace

        .section .note.GNU-stack,"",@progbits
