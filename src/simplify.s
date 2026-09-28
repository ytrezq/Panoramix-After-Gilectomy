# The simplifier engine (port of simplify.py's simplify_trace): the
# rewrites applied to the trace in a loop until nothing changes, then the
# final postprocessing for readability.

.include "defs.inc"

        .section .rodata
.Ls_logname:    .asciz "panoramix.simplify"
.Ls_timed_out:  .asciz "simplify_trace timed out."

        .text

.macro B reg, n
        mov \reg, [rsp + 8*(\n)]
.endm

# simplify_trace(trace, timeout_ns) -> list
FUNC simplify_trace
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
        call replace_f                  # simplify expressions
        mov rbx, rax
        mov rdi, rbx
        xor esi, esi
        call cleanup_vars               # cleanup variables
        mov rbx, rax
        mov rdi, rbx
        xor esi, esi
        call cleanup_mems               # cleanup mems
        mov rbx, rax
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
        mov rdi, rbx
        xor esi, esi
        call cleanup_vars               # cleanup vars
        mov rbx, rax
        mov rdi, rbx
        lea rsi, [rip + simplify_exp_cb]
        xor edx, edx
        call replace_f                  # simplify expressions
        mov rbx, rax
        mov rdi, rbx
        call pp_cleanup_mul_1
        mov rbx, rax
        mov rdi, rbx
        call cleanup_msize              # calculate msize
        mov rbx, rax
        mov rdi, rbx
        call replace_bytes_or_string_length     # replace storage with length
        mov rbx, rax
        mov rdi, rbx
        call cleanup_conds              # cleanup unused ifs
        mov rbx, rax
        mov rdi, rbx
        lea rsi, [rip + loop_to_setmem]
        xor edx, edx
        call rewrite_trace              # convert loops to setmems
        mov rbx, rax
        mov rdi, rbx
        call propagate_storage_in_loops # move loop indexes outside of loops
        mov rbx, rax
        # (there is a logic to this ordering, but it would take a long
        # time to explain)
        # the garbage of the round is dropped once the arena is big: the
        # trace is all that is live here (compared with the previous one
        # by pointer first, as it is copied)
        cmp qword ptr [r15 + CTX_ARENA_TOTAL], COMPACT_THRESHOLD
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
        call replace_f
        mov rbx, rax
        mov rdi, rbx
        lea rsi, [rip + postprocess_exp]
        xor edx, edx
        call replace_f
        mov rbx, rax
        mov rdi, rbx
        lea rsi, [rip + postprocess_exp]
        xor edx, edx
        call replace_f
        mov rbx, rax
        mov rdi, rbx
        lea rsi, [rip + postprocess_trace]
        xor edx, edx
        call rewrite_trace_ifs
        mov rbx, rax
        xor edi, edi
        xor esi, esi
        call mk_list
        mov rdi, rbx
        mov rsi, rax
        call rewrite_string_stores      # using heuristics to clean up some things
        mov rbx, rax
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
        call cleanup_conds              # final setmem/condition cleanup
        mov rbx, rax
        mov rdi, rbx
        lea rsi, [rip + fix_storages]
        xor edx, edx
        call replace_f
        mov rbx, rax
        mov rdi, rbx
        call cleanup_conds              # cleaning up storages slightly
        mov rbx, rax
        mov rdi, rbx
        call readability                # adding nicer variable names
        mov rbx, rax
        mov rdi, rbx
        call pp_cleanup_mul_1
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
ENDF simplify_trace

FUNC max_to_add_cb
        jmp alg_max_to_add
ENDF max_to_add_cb

# fix_storages(exp, arg): a storage with a negative offset gets 0
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
        B rcx, 2
        B rsi, 0
        LOADS rdi, STORAGE
        mov edx, 1
        call mk4
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
1:      mov rax, rbx
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
ENDF fix_storages

        .section .note.GNU-stack,"",@progbits
