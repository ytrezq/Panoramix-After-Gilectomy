# Stubs of what the branch bp-function ports (function.py's
# Function.rename_params, postprocess.py's short_circuits), for this
# branch to link: contract.s calls them. DELETE THIS FILE when merging
# bp-function, whose function.s and postprocess.s have the real ones
# (fn_rename_params(fn, storage_names), short_circuits(trace) -> list).

.include "defs.inc"

# fn_rename_params(fn, storage_names): (stub) nothing renamed
FUNC fn_rename_params
        ret
ENDF fn_rename_params

# short_circuits(trace) -> list: (stub) the trace as it is
FUNC short_circuits
        mov rax, rdi
        ret
ENDF short_circuits

        .section .note.GNU-stack,"",@progbits
