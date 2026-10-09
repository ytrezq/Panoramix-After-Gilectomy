# The simplifier engine (port of simplify.py's simplify_trace): the
# rewrites applied to the trace in a loop until nothing changes, then the
# final postprocessing for readability.

.include "defs.inc"

        .section .rodata
.Ls_logname:    .asciz "panoramix.simplify"
.Ls_timed_out:  .asciz "simplify_trace timed out."
        # the stages, as --explain titles them
.Lx_simplify:   .asciz "simplify expressions"
.Lx_vars:       .asciz "cleanup variables"
.Lx_mems:       .asciz "cleanup mems"
.Lx_precompiled: .asciz "results of precompiled contracts"
.Lx_mins:       .asciz "minimums"
.Lx_split:      .asciz "split setmems & storages"
.Lx_vars2:      .asciz "cleanup vars"
.Lx_length:     .asciz "replace storage with length"
.Lx_ifs:        .asciz "cleanup unused ifs"
.Lx_loops:      .asciz "convert loops to setmems"
.Lx_indexes:    .asciz "move loop indexes outside of loops"
.Lx_heuristics: .asciz "using heuristics to clean up some things"
.Lx_final:      .asciz "final setmem/condition cleanup"
.Lx_storages:   .asciz "cleaning up storages slightly"
.Lx_names:      .asciz "adding nicer variable names"

        .text

.macro B reg, n
        mov \reg, [rsp + 8*(\n)]
.endm

# python's explain(title, trace) after a stage (explain.s: nothing without
# --explain), the trace in rbx
.macro EXPLAIN title
        lea rdi, [rip + \title]
        mov rsi, rbx
        call explain
.endm

# simplify_trace(trace, timeout_ns) -> list: python's simplify_trace - the
# trace, simplified. While it is, the comparisons know that a variable is
# one of the values it's set to (set_variables): a snapshot of the free
# memory pointer is at least 0x60. And which of the words the contract is
# given are small (small_words). Forgotten afterwards, whatever happens.
FUNC simplify_trace
        ENTER
        sub rsp, ERR_SIZEOF + 16
        mov rbx, rdi
        mov r12, rsi
        call variable_values
        mov r13, rax
        mov rdi, rbx
        mov rsi, rax
        call small_words
        mov rsi, rax
        mov rdi, r13
        call mk2                        # (vars, small)
        mov rdi, rax
        call set_variables
        mov rdi, rsp
        call err_catch
        test eax, eax
        jnz 1f
        mov rdi, rbx
        mov rsi, r12
        call simplify_trace_impl
        mov rbx, rax
        call err_end
        xor edi, edi
        call set_variables
        mov rax, rbx
        add rsp, ERR_SIZEOF + 16
        LEAVE
1:      mov [rsp + ERR_SIZEOF], eax
        xor edi, edi
        call set_variables
        mov edi, [rsp + ERR_SIZEOF]
        mov rsi, [r15 + CTX_ERR_MSG]
        call err_throw
ENDF simplify_trace

# simplify_trace_impl(trace, timeout_ns) -> list: python's _simplify_trace
FUNC simplify_trace_impl
        ENTER
        sub rsp, 48
        .set ST_TIMEOUT, 0
        .set ST_START, 8
        .set ST_OLD, 16
        .set ST_COUNT, 24
        mov rbx, rdi
        mov [rsp + ST_TIMEOUT], rsi
        call monotonic_ns
        mov [rsp + ST_START], rax
        mov qword ptr [rsp + ST_OLD], 0
        mov qword ptr [rsp + ST_COUNT], 0
.Lst_round:
        cmp rbx, [rsp + ST_OLD]
        je .Lst_final
        cmp qword ptr [rsp + ST_COUNT], 40
        jae .Lst_final
        call .Lst_should_quit
        test eax, eax
        jnz .Lst_final
        inc qword ptr [rsp + ST_COUNT]
        mov [rsp + ST_OLD], rbx
        mov rdi, rbx
        lea rsi, [rip + simplify_exp_cb]
        xor edx, edx
        call replace_f_memo                  # simplify expressions
        mov rbx, rax
        EXPLAIN .Lx_simplify
        mov rdi, rbx
        xor esi, esi
        call cleanup_vars               # cleanup variables
        mov rbx, rax
        EXPLAIN .Lx_vars
        mov rdi, rbx
        xor esi, esi
        call cleanup_mems               # cleanup mems
        mov rbx, rax
        EXPLAIN .Lx_mems
        mov rdi, rbx
        xor esi, esi
        call precompiled_results        # results of precompiled contracts
        mov rbx, rax
        EXPLAIN .Lx_precompiled
        mov rdi, rbx
        call min_ifs                    # minimums
        mov rbx, rax
        EXPLAIN .Lx_mins
        mov rdi, rbx
        lea rsi, [rip + split_setmem]
        xor edx, edx
        call rewrite_trace              # split setmems & storages
        mov rbx, rax
        mov rdi, rbx
        lea rsi, [rip + split_store]
        xor edx, edx
        call rewrite_trace_full
        mov rbx, rax
        EXPLAIN .Lx_split
        mov rdi, rbx
        xor esi, esi
        call cleanup_vars               # cleanup vars
        mov rbx, rax
        EXPLAIN .Lx_vars2
        mov rdi, rbx
        lea rsi, [rip + simplify_exp_cb]
        xor edx, edx
        call replace_f_memo                  # simplify expressions
        mov rbx, rax
        EXPLAIN .Lx_simplify
        mov rdi, rbx
        call pp_cleanup_mul_1
        mov rbx, rax
        EXPLAIN .Lx_simplify
        mov rdi, rbx
        call replace_bytes_or_string_length     # replace storage with length
        mov rbx, rax
        EXPLAIN .Lx_length
        mov rdi, rbx
        call cleanup_conds              # cleanup unused ifs
        mov rbx, rax
        EXPLAIN .Lx_ifs
        mov rdi, rbx
        lea rsi, [rip + loop_to_setmem]
        xor edx, edx
        call rewrite_trace              # convert loops to setmems
        mov rbx, rax
        EXPLAIN .Lx_loops
        mov rdi, rbx
        xor esi, esi
        call propagate_storage_in_loops # move loop indexes outside of loops
        mov rbx, rax
        EXPLAIN .Lx_indexes
        # (there is a logic to this ordering, but it would take a long
        # time to explain)
        # the garbage of the round is dropped once the arena is big: the
        # trace is all that is live here (compared with the previous one
        # by pointer first, as it is copied)
        call compact_threshold
        cmp [r15 + CTX_ARENA_TOTAL], rax
        jb .Lst_round
        cmp r15, [rip + global_ctx]     # (never the process-wide context)
        je .Lst_round
        cmp rbx, [rsp + ST_OLD]
        je .Lst_final
        mov rdi, rbx
        call ctx_compact
        mov rbx, rax
        mov qword ptr [rsp + ST_OLD], 0
        jmp .Lst_round
.Lst_final:
        # final lightweight postprocessing: new variables, simplifications
        # for human readability, and other stuff that would break the loop
        mov rdi, rbx
        lea rsi, [rip + max_to_add_cb]
        xor edx, edx
        call replace_f_memo
        mov rbx, rax
        mov rdi, rbx
        lea rsi, [rip + postprocess_exp]
        xor edx, edx
        call replace_f_memo
        mov rbx, rax
        mov rdi, rbx
        lea rsi, [rip + postprocess_exp]
        xor edx, edx
        call replace_f_memo
        mov rbx, rax
        mov rdi, rbx
        lea rsi, [rip + postprocess_trace]
        xor edx, edx
        call rewrite_trace_ifs
        mov rbx, rax
        # (a string written to storage is left as the loops that copy it: no
        # notation says a store of all of its bytes, nor does storage.py
        # read it)
        EXPLAIN .Lx_heuristics
        call .Lst_should_quit
        test eax, eax
        jnz 2f
        # the most expensive pass, skipped if we're already out of time
        mov r12d, 3
1:      mov rdi, rbx
        xor esi, esi
        call cleanup_mems
        mov rbx, rax
        dec r12d
        jnz 1b
2:      mov rdi, rbx
        xor esi, esi
        call precompiled_results
        mov rbx, rax
        mov rdi, rbx
        call cleanup_conds              # final setmem/condition cleanup
        mov rbx, rax
        EXPLAIN .Lx_final
        mov rdi, rbx
        lea rsi, [rip + fix_storages]
        xor edx, edx
        call replace_f_memo
        mov rbx, rax
        mov rdi, rbx
        call cleanup_conds              # cleaning up storages slightly
        mov rbx, rax
        EXPLAIN .Lx_storages
        mov rdi, rbx
        xor esi, esi
        call readability                # adding nicer variable names
        mov rbx, rax
        EXPLAIN .Lx_names
        mov rdi, rbx
        call pp_cleanup_mul_1
        # the conditions readability turned around may be known now: `if
        # not (1 | x)` is `if 0`
        mov rdi, rax
        call cleanup_conds
        add rsp, 48
        LEAVE

# local: eax = out of time (logged)
.Lst_should_quit:
        sub rsp, 8
        cmp qword ptr [rsp + 16 + ST_TIMEOUT], 0
        je 3f
        call monotonic_ns
        sub rax, [rsp + 16 + ST_START]
        cmp rax, [rsp + 16 + ST_TIMEOUT]
        jle 3f
        mov edi, LOG_WARNING
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_timed_out]
        call log_fmt
        mov eax, 1
        add rsp, 8
        ret
3:      xor eax, eax
        add rsp, 8
        ret
ENDF simplify_trace_impl

FUNC max_to_add_cb
        jmp alg_max_to_add
ENDF max_to_add_cb

# fix_storages(exp, arg): a field moved left (see
# algebra.apply_mask_to_storage): the field, shifted
FUNC fix_storages
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        PAT rsi, "('storage', ':size', ':int:off', ':loc')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        B rdi, 1
        call int_sign
        cmp eax, -1
        jne 1f
        # ('mask_shl', size, 0, -off, ('storage', size, 0, loc))
        B rcx, 2
        B rsi, 0
        LOADS rdi, STORAGE
        mov edx, 1
        call mk4
        mov r12, rax
        B rdi, 1
        call int_neg
        mov rcx, rax
        mov r8, r12
        B rsi, 0
        LOADS rdi, MASK_SHL
        mov edx, 1
        call mk5
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
1:      mov rax, rbx
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
ENDF fix_storages

# compact_threshold() -> rax: the arena's size past which simplify_trace
# compacts - COMPACT_THRESHOLD, or a quarter of the context's memory
# limit when that is less (a small machine, many threads: compacted
# rather than past the limit), or PANORAMIX_COMPACT_MIB (the tests: a
# compaction at every round)
FUNC compact_threshold
        mov rax, [rip + compact_bytes]
        test rax, rax
        jz 1f
.Lct_have:
        cmp byte ptr [rip + compact_env], 0
        jne 3f                          # (set by the variable: as it is)
        mov rcx, [r15 + CTX_MEM_LIMIT]
        shr rcx, 2
        jz 3f                           # (no limit)
        cmp rcx, rax
        cmovb rax, rcx
3:      ret
1:      push rbx
        lea rdi, [rip + .Ls_env_compact]
        call getenv@PLT
        mov rbx, COMPACT_THRESHOLD
        test rax, rax
        jz 2f
        mov rdi, rax
        xor esi, esi
        mov edx, 10
        call strtoull@PLT
        shl rax, 20
        test rax, rax
        jz 2f
        mov rbx, rax
        mov byte ptr [rip + compact_env], 1
2:      mov [rip + compact_bytes], rbx
        mov rax, rbx
        pop rbx
        jmp .Lct_have
ENDF compact_threshold

        .section .data
        .align 8
compact_bytes:  .quad 0
compact_env:    .quad 0             # set by PANORAMIX_COMPACT_MIB
        .section .rodata
.Ls_env_compact: .asciz "PANORAMIX_COMPACT_MIB"
        .text

        .section .note.GNU-stack,"",@progbits
