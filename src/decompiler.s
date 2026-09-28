# The decompiler (port of decompiler.py): the functions of the contract
# decompiled in parallel, one thread per function at a time, then the
# contract's postprocessing and its text.
#
# decompile(code, len, threads, only_func, out_sb): the text appended
# to the builder. The threads work on contexts of their own (one per
# function, freed once the result is imported) and share the loader,
# which is read-only by then.

.include "defs.inc"

        .section .rodata
.Ls_logname:    .asciz "panoramix.decompiler"
.Ls_no_code:    .asciz "# No code found for this contract."
.Ls_header:     .asciz "# Palkeoramix decompiler. "
.Ls_hash:       .asciz "#"
.Ls_failed_with: .asciz "#  I failed with these: "
.Ls_failed_item: .asciz "#  - "
.Ls_all_rest:   .asciz "#  All the rest is below."
.Ls_def_storage: .asciz "storage:"
.Ls_def_:       .asciz "def "
.Ls_regular:    .asciz "#\n#  Regular functions\n#"
.Ls_fallback:   .asciz "_fallback"
.Ls_unknown:    .asciz "unknown"
.Ls_param_:     .asciz "_param"
.Ls_running:    .asciz "Running light execution to find functions."
.Ls_decompiling: .asciz "Decompiling %S..."
.Ls_interpreting: .asciz " -> Interpreting EVM on function..."
.Ls_cleaning:   .asciz " -> Cleaning up AST, identifying loops..."
.Ls_finished:   .asciz "Functions decompilation finished, now doing post-processing."
.Ls_problem:    .asciz "Problem with %S: %s"
.Ls_loader_issue: .asciz "Loader issue: %s"
.Ls_timed_out:  .asciz "the function took more than 3 minutes"
.Ls_no_target:  .asciz "KeyError: its jump destination isn't an instruction"
.Ls_thread_failed: .asciz "pthread_create failed"
.Ls_peak:       .asciz "%S: the arena took %u MiB at most"
.Ls_peak_main:  .asciz "the contract: the arena took %u MiB at most"
.Ls_failed:     .asciz "decompilation failed: %s"
.Ls_failed_text: .asciz "decompilation failed: "
.Ls_0x:         .asciz "0x"

        # python's time limits (scaled by PANORAMIX_TIMEOUT, see scaled_ns)
        .set LOADER_TIMEOUT_NS, 60000000000
        .set VM_TIMEOUT_NS, 60000000000
        .set WHILES_TIMEOUT_NS, 60000000000
        .set FUNC_TIMEOUT_NS, 180000000000
        .set WORKER_STACK, 64 << 20     # the stack of a worker thread

        # a job: one function to decompile
        .set JB_HASH, 0                 # str (main context)
        .set JB_TARGET, 8               # tagged pc
        .set JB_STACK, 16               # tuple (main context)
        .set JB_KNOWN, 24               # tuple (main context)
        .set JB_CTX, 32                 # the context it ran on
        .set JB_TRACE, 40               # the trace, on JB_CTX
        .set JB_ERR, 48                 # an error code, or 0
        .set JB_ERRMSG, 56
        .set JB_STATE, 64               # 0 pending, 1 done, 2 imported
        .set JB_SIZEOF, 72

        # the shared state of the decompilation
        .set DC_LOADER, 0
        .set DC_JOBS, 8
        .set DC_NJOBS, 16
        .set DC_NEXT, 24                # the next job to take (atomic)
        .set DC_DONE, 32                # the jobs done (under the mutex)
        .set DC_MUTEX, 40               # pthread_mutex_t (40 bytes, zero-initialized)
        .set DC_COND, 80                # pthread_cond_t (48 bytes)
        .set DC_MEMLIMIT, 128           # CTX_MEM_LIMIT of the workers' contexts
        .set DC_SIZEOF, 144

        # the decompilation thread (decompile_run)
        .set DR_CODE, 0
        .set DR_LEN, 8
        .set DR_THREADS, 16
        .set DR_ONLY, 24
        .set DR_OUT, 32
        .set DR_CTX, 40                 # the main context
        .set DR_STATUS, 48              # 0, or the error code
        .set DR_MSG, 56                 # its message
        .set DR_ATTR, 64                # pthread_attr_t (56 bytes)
        .set DR_TID, 128
        .set DR_SIZEOF, 144

        .text

.macro B reg, n
        mov \reg, [rsp + 8*(\n)]
.endm

# --- the abi of a function ---

# abi_of(hash) -> (name, inputs): the signature database's entry for a
# selector, else "unknown<selector>" (or the name itself for "_fallback")
FUNC abi_of
        ENTER
        mov rbx, rdi
        lea rsi, [rip + .Ls_0x]
        call str_startswith_c
        test eax, eax
        jz .Lab_named                   # "_fallback", or an unknown selector
        lea rdi, [rbx + N_DATA + 4 + 2]
        call parse_hex_int
        mov rdi, rax
        call int_to_i64
        mov rdi, rax
        call sig_db_lookup
        test rax, rax
        jz 1f
        mov rdi, rax
        call fix_input_names
        LEAVE
1:      # ("unknown" + hash[2:], no inputs)
        call sb_new
        mov r12, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_unknown]
        call sb_append_c
        mov rdi, r12
        lea rsi, [rbx + N_DATA + 4 + 2]
        call sb_append_c
        mov rdi, r12
        call sb_finish_intern
        mov rdi, rax
        xor esi, esi
        call mk2
        LEAVE
.Lab_named:
        mov rdi, rbx
        xor esi, esi
        call mk2
        LEAVE
ENDF abi_of

# fix_input_names(abi) -> abi: the unnamed inputs called _param<n>
FUNC fix_input_names
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, [rbx + N_DATA + 8]
        test r12, r12
        jz .Lfi_asis
        call vec_new
        mov r13, rax
        xor r14d, r14d
1:      cmp r14d, [r12 + N_AUX]
        jae 3f
        mov rax, [r12 + N_DATA + r14*8]
        mov rcx, [rax + N_DATA + 8]
        cmp dword ptr [rcx + N_DATA], 0
        jne 2f
        call sb_new
        mov [rsp], rax
        mov rdi, rax
        lea rsi, [rip + .Ls_param_]
        call sb_append_c
        mov rdi, [rsp]
        lea rsi, [r14 + 1]
        call sb_append_u64
        mov rdi, [rsp]
        call sb_finish_intern
        mov rsi, rax
        mov rax, [r12 + N_DATA + r14*8]
        mov rdi, [rax + N_DATA]
        call mk2
2:      mov rdi, r13
        mov rsi, rax
        call vec_push
        inc r14d
        jmp 1b
3:      mov rdi, r13
        call vec_to_list
        mov rdi, [rbx + N_DATA]
        mov rsi, rax
        call mk2
        add rsp, 16
        LEAVE
.Lfi_asis:
        mov rax, rbx
        add rsp, 16
        LEAVE
ENDF fix_input_names

# --- the workers ---

# decompile_worker(dec) -> 0: takes jobs until there are none left. Each
# job runs on a context of its own, kept for the main thread to import
# the result from.
FUNC decompile_worker
        push r15
        ENTER
        sub rsp, ERR_SIZEOF + 40        # (with r15 pushed: 8 mod 16 keeps rsp aligned)
        .set DW_DEC, ERR_SIZEOF
        .set DW_JOB, ERR_SIZEOF + 8
        .set DW_START, ERR_SIZEOF + 16
        .set DW_TMP, ERR_SIZEOF + 24
        mov [rsp + DW_DEC], rdi
.Ldw_next:
        mov rbx, [rsp + DW_DEC]
        mov eax, 1
        lock xadd [rbx + DC_NEXT], rax
        cmp rax, [rbx + DC_NJOBS]
        jae .Ldw_done
        imul rax, rax, JB_SIZEOF
        add rax, [rbx + DC_JOBS]
        mov r12, rax                    # the job
        mov [rsp + DW_JOB], rax
        call ctx_new
        mov r15, rax
        mov [r12 + JB_CTX], rax
        mov rdi, rax
        call ctx_bind
        call ctx_set_stack
        mov rax, [rbx + DC_MEMLIMIT]
        mov [r15 + CTX_MEM_LIMIT], rax
        call monotonic_ns
        mov [rsp + DW_START], rax
        mov edi, LOG_INFO
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_decompiling]
        mov rcx, [r12 + JB_HASH]
        call log_fmt
        mov rdi, rsp
        call err_catch
        test eax, eax
        jnz .Ldw_failed
        cmp qword ptr [r12 + JB_TARGET], 0
        je .Ldw_no_target
        mov edi, LOG_INFO
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_interpreting]
        call log_fmt
        mov rdi, [rbx + DC_LOADER]
        xor esi, esi
        call vm_new
        mov rdi, [r12 + JB_STACK]
        call value_import_root
        mov r13, rax
        mov rdi, [r12 + JB_KNOWN]
        call value_import_root
        mov [rsp + DW_TMP], rax
        mov rdi, VM_TIMEOUT_NS
        call scaled_ns
        mov rcx, rax
        mov rdi, [r12 + JB_TARGET]
        mov rsi, r13
        mov rdx, [rsp + DW_TMP]
        call vm_run
        mov r13, rax
        call .Ldw_check_deadline
        mov edi, LOG_INFO
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_cleaning]
        call log_fmt
        mov rdi, WHILES_TIMEOUT_NS
        call scaled_ns
        mov rdi, r13
        mov rsi, rax
        call make_whiles
        mov [r12 + JB_TRACE], rax
        call .Ldw_check_deadline
        call err_end
        mov qword ptr [r12 + JB_ERR], 0
        jmp .Ldw_finish
.Ldw_failed:
        mov [r12 + JB_ERR], rax
        mov rax, [r15 + CTX_ERR_MSG]
        mov [r12 + JB_ERRMSG], rax
.Ldw_finish:
        mov edi, LOG_DEBUG
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_peak]
        mov rcx, [r12 + JB_HASH]
        mov r8, [r15 + CTX_ARENA_PEAK]
        shr r8, 20
        call log_fmt
        # done: the main thread may import it
        lea rdi, [rbx + DC_MUTEX]
        call pthread_mutex_lock@PLT
        mov qword ptr [r12 + JB_STATE], 1
        inc qword ptr [rbx + DC_DONE]
        lea rdi, [rbx + DC_COND]
        call pthread_cond_signal@PLT
        lea rdi, [rbx + DC_MUTEX]
        call pthread_mutex_unlock@PLT
        jmp .Ldw_next
.Ldw_done:
        xor eax, eax
        add rsp, ERR_SIZEOF + 40
        LEAVE_NORET
        pop r15
        ret
# the function's target isn't an instruction (python: loader.lines[target])
.Ldw_no_target:
        mov edi, E_KEY
        lea rsi, [rip + .Ls_no_target]
        call err_throw
# the function's overall time limit (python's 3 minutes)
.Ldw_check_deadline:
        sub rsp, 8
        mov rdi, FUNC_TIMEOUT_NS
        call scaled_ns
        mov [rsp], rax
        call monotonic_ns
        sub rax, [rsp + 8 + 8 + DW_START]
        mov rcx, [rsp]
        cmp rax, rcx
        jg 1f
        add rsp, 8
        ret
1:      mov edi, E_TIMEOUT
        lea rsi, [rip + .Ls_timed_out]
        call err_throw
ENDF decompile_worker

# --- the decompilation ---

# decompile(code, len, threads, only_func, out): the text of the
# decompiled contract appended to the builder `out`. only_func (a C
# string or 0) keeps only the functions whose name starts with it.
FUNC decompile
        ENTER
        sub rsp, ERR_SIZEOF + 112
        .set DE_CODE, ERR_SIZEOF
        .set DE_LEN, ERR_SIZEOF + 8
        .set DE_THREADS, ERR_SIZEOF + 16
        .set DE_ONLY, ERR_SIZEOF + 24
        .set DE_OUT, ERR_SIZEOF + 32
        .set DE_LOADER, ERR_SIZEOF + 40
        .set DE_DEC, ERR_SIZEOF + 48
        .set DE_TIDS, ERR_SIZEOF + 56
        .set DE_FUNCS, ERR_SIZEOF + 64
        .set DE_PROBLEMS, ERR_SIZEOF + 72
        .set DE_I, ERR_SIZEOF + 80
        .set DE_CONTRACT, ERR_SIZEOF + 88
        .set DE_SHOWN, ERR_SIZEOF + 96
        .set DE_ATTR, ERR_SIZEOF + 104
        mov [rsp + DE_CODE], rdi
        mov [rsp + DE_LEN], rsi
        mov [rsp + DE_THREADS], rdx
        mov [rsp + DE_ONLY], rcx
        mov [rsp + DE_OUT], r8
        # the loader: the code disassembled, the functions found
        call loader_new
        mov rbx, rax
        mov [rsp + DE_LOADER], rax
        mov [r15 + CTX_LOADER], rax
        mov rdi, rax
        mov rsi, [rsp + DE_CODE]
        mov rdx, [rsp + DE_LEN]
        call loader_load
        mov edi, LOG_INFO
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_running]
        call log_fmt
        mov rdi, rsp
        call err_catch
        test eax, eax
        jnz .Lde_loader_issue
        mov rdi, LOADER_TIMEOUT_NS
        call scaled_ns
        mov rdi, rbx
        mov rsi, rax
        call loader_find_functions
        call err_end
        jmp 1f
.Lde_loader_issue:
        mov edi, LOG_ERROR
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_loader_issue]
        mov rcx, [r15 + CTX_ERR_MSG]
        call log_fmt
        # just the default function, at 0
        lea rdi, [rip + .Ls_fallback]
        call str_intern_c
        push rax
        push rax
        xor edi, edi
        xor esi, esi
        call mk_tuple                   # the empty stack
        pop rdi
        pop rdi                         # the name
        mov rsi, 1                      # the target: 0
        mov rdx, rax
        call mk3
        mov rdi, rax
        call mk_list1
        mov [rbx + LD_FUNCS], rax
        xor edi, edi
        xor esi, esi
        call mk_tuple
        mov [rbx + LD_FALLBACK_KNOWN], rax
1:      cmp qword ptr [rbx + LD_NINSTR], 0
        jne 2f
        # No code.
        mov rdi, [rsp + DE_OUT]
        lea rsi, [rip + C_GRAY]
        call sb_append_c
        mov rdi, [rsp + DE_OUT]
        lea rsi, [rip + .Ls_no_code]
        call sb_append_c
        mov rdi, [rsp + DE_OUT]
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        jmp .Lde_ret
2:      # the jobs: (hash, target, stack) -> the functions asked for
        mov r12, [rbx + LD_FUNCS]
        mov edi, DC_SIZEOF
        call arena_alloc
        mov r13, rax
        mov [rsp + DE_DEC], rax
        mov [r13 + DC_LOADER], rbx
        mov edi, [r12 + N_AUX]
        imul rdi, rdi, JB_SIZEOF
        call arena_alloc
        mov [r13 + DC_JOBS], rax
        mov qword ptr [r13 + DC_NJOBS], 0
        xor r14d, r14d
3:      cmp r14d, [r12 + N_AUX]
        jae 5f
        mov rax, [r12 + N_DATA + r14*8] # (hash, target, stack)
        inc r14d
        mov rdi, [rax + N_DATA]
        call .Lde_wanted
        test eax, eax
        jz 3b
        mov rax, [r12 + N_DATA + r14*8 - 8]
        mov rcx, [r13 + DC_NJOBS]
        imul rcx, rcx, JB_SIZEOF
        add rcx, [r13 + DC_JOBS]
        inc qword ptr [r13 + DC_NJOBS]
        mov rdi, [rax + N_DATA]
        mov [rcx + JB_HASH], rdi
        mov rdi, [rax + N_DATA + 16]
        mov [rcx + JB_STACK], rdi
        mov rdi, [rax + N_DATA + 8]
        push rcx
        push rcx
        call .Lde_past_jumpdest
        pop rcx
        pop rcx
        mov [rcx + JB_TARGET], rax
        xor edi, edi
        xor esi, esi
        push rcx
        push rcx
        call mk_tuple
        pop rcx
        pop rcx
        mov [rcx + JB_KNOWN], rax
        mov rdi, [rcx + JB_HASH]
        push rcx
        push rcx
        lea rsi, [rip + .Ls_fallback]
        call str_eq_c
        pop rcx
        pop rcx
        test eax, eax
        jz 3b
        mov rax, [rbx + LD_FALLBACK_KNOWN]
        mov [rcx + JB_KNOWN], rax
        jmp 3b
5:      # the workers
        mov rdi, [rsp + DE_THREADS]
        cmp rdi, [r13 + DC_NJOBS]
        jbe 6f
        mov rdi, [r13 + DC_NJOBS]
6:      test rdi, rdi
        jnz 7f
        mov edi, 1
7:      mov [rsp + DE_THREADS], rdi
        call mem_limit_for
        mov [r13 + DC_MEMLIMIT], rax
        mov [r15 + CTX_CHILD_LIMIT], rax        # (the folder's contexts)
        mov rdi, [rsp + DE_THREADS]
        shl rdi, 3
        call arena_alloc
        mov [rsp + DE_TIDS], rax
        # the workers' stacks: 64 MiB (reserved, not committed) - the
        # recursions follow the nesting of the traces, and python's
        # RecursionError has no equivalent here
        mov edi, 64                     # (a pthread_attr_t is 56 bytes)
        call arena_alloc
        mov [rsp + DE_ATTR], rax
        mov rdi, rax
        call pthread_attr_init@PLT
        mov rdi, [rsp + DE_ATTR]
        mov esi, WORKER_STACK
        call pthread_attr_setstacksize@PLT
        mov qword ptr [rsp + DE_I], 0
8:      mov rax, [rsp + DE_I]
        cmp rax, [rsp + DE_THREADS]
        jae 9f
        mov rdi, [rsp + DE_TIDS]
        lea rdi, [rdi + rax*8]
        mov rsi, [rsp + DE_ATTR]
        lea rdx, [rip + decompile_worker]
        mov rcx, r13
        call pthread_create@PLT
        test eax, eax
        jnz .Lde_thread_failed
        inc qword ptr [rsp + DE_I]
        jmp 8b
.Lde_thread_failed:
        # (no more threads: the ones there are do the work, or this one)
        mov rax, [rsp + DE_I]
        mov [rsp + DE_THREADS], rax
        mov edi, LOG_WARNING
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_thread_failed]
        call log_fmt
        cmp qword ptr [rsp + DE_THREADS], 0
        jne 9f
        mov rdi, r13
        call decompile_worker
        mov rdi, r15
        call ctx_bind                   # (the worker bound its contexts to this thread)
9:      mov rdi, [rsp + DE_ATTR]
        call pthread_attr_destroy@PLT
        # the results, imported as they come (the contexts they are on
        # are freed then), the functions made from them
        call vec_new
        mov [rsp + DE_FUNCS], rax
        call vec_new
        mov [rsp + DE_PROBLEMS], rax
        mov qword ptr [rsp + DE_I], 0   # imported so far
.Lde_wait:
        mov rax, [rsp + DE_I]
        cmp rax, [r13 + DC_NJOBS]
        jae .Lde_joined
        lea rdi, [r13 + DC_MUTEX]
        call pthread_mutex_lock@PLT
10:     mov rdi, r13
        call .Lde_find_done
        test rax, rax
        jnz 11f
        lea rdi, [r13 + DC_COND]
        lea rsi, [r13 + DC_MUTEX]
        call pthread_cond_wait@PLT
        jmp 10b
11:     mov r12, rax
        mov qword ptr [r12 + JB_STATE], 2
        lea rdi, [r13 + DC_MUTEX]
        call pthread_mutex_unlock@PLT
        inc qword ptr [rsp + DE_I]
        mov rdi, r12
        call .Lde_import_job
        mov rdi, [r12 + JB_CTX]
        call ctx_free
        jmp .Lde_wait
.Lde_joined:
        mov qword ptr [rsp + DE_I], 0
12:     mov rax, [rsp + DE_I]
        cmp rax, [rsp + DE_THREADS]
        jae 13f
        mov rdi, [rsp + DE_TIDS]
        mov rdi, [rdi + rax*8]
        xor esi, esi
        call pthread_join@PLT
        inc qword ptr [rsp + DE_I]
        jmp 12b
13:     mov edi, LOG_INFO
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_finished]
        call log_fmt
        # the functions in the order of the jobs (python's dict), then
        # the contract
        mov rdi, [rsp + DE_FUNCS]
        call .Lde_functions_in_order
        mov [rsp + DE_FUNCS], rax
        mov rdi, [rsp + DE_PROBLEMS]
        call .Lde_functions_in_order    # (the names, in the order of the jobs)
        mov rdi, rax
        call vec_to_list
        mov rsi, rax
        mov rdi, [rsp + DE_FUNCS]
        call contract_new
        mov [rsp + DE_CONTRACT], rax
        mov rdi, rax
        call contract_postprocess
        mov rdi, [rsp + DE_CONTRACT]
        mov rsi, [rsp + DE_OUT]
        call contract_text
.Lde_ret:
        mov edi, LOG_DEBUG
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_peak_main]
        mov rcx, [r15 + CTX_ARENA_PEAK]
        shr rcx, 20
        call log_fmt
        add rsp, ERR_SIZEOF + 112
        LEAVE

# locals of decompile
# eax: the function's name starts with only_func (or there's none)
.Lde_wanted:
        sub rsp, 8
        mov rsi, [rsp + 8 + 8 + DE_ONLY]
        test rsi, rsi
        jz 1f
        call abi_of
        mov rdi, rax
        xor esi, esi
        call abi_func_name
        mov rdi, rax
        mov rsi, [rsp + 8 + 8 + DE_ONLY]
        call str_startswith_c
        add rsp, 8
        ret
1:      mov eax, 1
        add rsp, 8
        ret
# a target on a jumpdest moves past it (python: lines[target][1] ==
# "jumpdest" -> target += 1), for targets above 1; one that isn't an
# instruction is 0 (python's KeyError there fails the function)
.Lde_past_jumpdest:
        mov rax, rdi
        cmp rdi, 3                      # tagged 1
        jle 1f
        test dil, 1
        jz 2f                           # (not even a small int)
        mov rcx, rdi
        UNTAG rcx
        cmp rcx, [rbx + LD_CODELEN]
        jae 2f
        mov rdx, [rbx + LD_PC2IDX]
        mov edx, [rdx + rcx*4]
        cmp edx, -1
        je 2f
        imul rdx, rdx, IN_SIZEOF
        add rdx, [rbx + LD_INSTRS]
        cmp byte ptr [rdx + IN_OP], 0x5b
        jne 1f
        add rax, 2                      # pc + 1
1:      ret
2:      xor eax, eax
        ret
# a job done and not imported yet, or 0 (under the mutex)
.Lde_find_done:
        mov rcx, [rdi + DC_NJOBS]
        mov rax, [rdi + DC_JOBS]
1:      test rcx, rcx
        jz 2f
        cmp qword ptr [rax + JB_STATE], 1
        je 3f
        add rax, JB_SIZEOF
        dec rcx
        jmp 1b
2:      xor eax, eax
3:      ret
# the job's result made into a function of the main context (or a problem)
.Lde_import_job:
        sub rsp, ERR_SIZEOF + 24
        mov [rsp + ERR_SIZEOF], rdi
        cmp qword ptr [rdi + JB_ERR], 0
        jne 2f
        lea rdi, [rsp]
        call err_catch
        test eax, eax
        jnz 3f
        mov rdi, [rsp + ERR_SIZEOF]
        mov rdi, [rdi + JB_TRACE]
        call value_import_root
        mov [rsp + ERR_SIZEOF + 8], rax
        mov rdi, [rsp + ERR_SIZEOF]
        mov rdi, [rdi + JB_HASH]
        call abi_of
        mov rdx, rax
        mov rdi, [rsp + ERR_SIZEOF]
        mov rdi, [rdi + JB_HASH]
        mov rsi, [rsp + ERR_SIZEOF + 8]
        call function_new
        mov [rsp + ERR_SIZEOF + 16], rax
        call err_end
        # (fn, job index) - the order is restored later
        mov rsi, [rsp + ERR_SIZEOF]
        sub rsi, [r13 + DC_JOBS]
        mov rax, rsi
        xor edx, edx
        mov ecx, JB_SIZEOF
        div rcx
        mov rsi, rax
        TAG rsi
        mov rdi, [rsp + ERR_SIZEOF + 16]
        call mk2
        mov rdi, [rsp + ERR_SIZEOF + 24 + 8 + DE_FUNCS]
        mov rsi, rax
        call vec_push
        add rsp, ERR_SIZEOF + 24
        ret
3:      mov rdi, [rsp + ERR_SIZEOF]
        mov rsi, [r15 + CTX_ERR_MSG]
        mov [rdi + JB_ERRMSG], rsi
        mov [rdi + JB_ERR], rax
2:      mov rdi, [rsp + ERR_SIZEOF]
        mov r8, [rdi + JB_ERRMSG]
        mov rcx, [rdi + JB_HASH]
        mov edi, LOG_ERROR
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_problem]
        call log_fmt
        mov rdi, [rsp + ERR_SIZEOF]
        mov rsi, [rdi + JB_HASH]
        mov rdi, [rsp + ERR_SIZEOF + 24 + 8 + DE_PROBLEMS]
        push rdi
        push rdi
        mov rdi, rsi
        call abi_of
        mov rdi, rax
        xor esi, esi
        call abi_func_name              # the name, as python's problems hold it
        mov [rsp + 16 + ERR_SIZEOF + 8], rax
        # (name, job index): python's dict has them in the loader's order,
        # the jobs finish in any order
        mov rsi, [rsp + 16 + ERR_SIZEOF]
        sub rsi, [r13 + DC_JOBS]
        mov rax, rsi
        xor edx, edx
        mov ecx, JB_SIZEOF
        div rcx
        mov rsi, rax
        TAG rsi
        mov rdi, [rsp + 16 + ERR_SIZEOF + 8]
        call mk2
        pop rdi
        pop rdi
        mov rsi, rax
        call vec_push
        add rsp, ERR_SIZEOF + 24
        ret
# the (fn, job) pairs sorted by job (the functions in the loader's order)
.Lde_functions_in_order:
        sub rsp, 24
        mov [rsp], rdi
        lea rsi, [rip + job_order_lt]
        xor edx, edx
        call py_sort
        mov rdi, [rsp]
        mov qword ptr [rsp + 8], 0
1:      mov rdi, [rsp]
        mov rcx, [rsp + 8]
        cmp rcx, [rdi + VEC_LEN]
        jae 2f
        mov rax, [rdi + VEC_DATA]
        mov rdx, [rax + rcx*8]
        mov rdx, [rdx + N_DATA]
        mov [rax + rcx*8], rdx
        inc qword ptr [rsp + 8]
        jmp 1b
2:      mov rax, [rsp]
        add rsp, 24
        ret
ENDF decompile

# job_order_lt((fn, job), (fn2, job2), arg) -> eax: by job address
FUNC job_order_lt
        mov rax, [rdi + N_DATA + 8]
        cmp rax, [rsi + N_DATA + 8]
        setb al
        movzx eax, al
        ret
ENDF job_order_lt

# decompile_run(code, len, threads, only_func, out) -> eax: decompile()
# on a thread of its own, with a stack as big as the workers' (the folder
# and the printer recurse as deep as the traces nest), under a handler
# for what python lets through (an error in the postprocessing, where it
# prints a traceback): 0, or the error code with the message in `out`
# instead of the text. r15: the main context.
FUNC decompile_run
        ENTER
        sub rsp, DR_SIZEOF
        mov [rsp + DR_CODE], rdi
        mov [rsp + DR_LEN], rsi
        mov [rsp + DR_THREADS], rdx
        mov [rsp + DR_ONLY], rcx
        mov [rsp + DR_OUT], r8
        mov [rsp + DR_CTX], r15
        mov qword ptr [rsp + DR_STATUS], 0
        lea rdi, [rsp + DR_ATTR]
        call pthread_attr_init@PLT
        lea rdi, [rsp + DR_ATTR]
        mov esi, WORKER_STACK
        call pthread_attr_setstacksize@PLT
        lea rdi, [rsp + DR_TID]
        lea rsi, [rsp + DR_ATTR]
        lea rdx, [rip + decompile_thread]
        mov rcx, rsp
        call pthread_create@PLT
        mov ebx, eax
        lea rdi, [rsp + DR_ATTR]
        call pthread_attr_destroy@PLT
        test ebx, ebx
        jnz 1f
        mov rdi, [rsp + DR_TID]
        xor esi, esi
        call pthread_join@PLT
        jmp 2f
1:      mov rdi, rsp                    # (no thread: on this one)
        call decompile_thread
        mov rdi, r15
        call ctx_bind
2:      mov qword ptr [r15 + CTX_STACK_LOW], 0  # (that stack is gone)
        mov eax, [rsp + DR_STATUS]
        test eax, eax
        jz 3f
        mov rdi, [rsp + DR_OUT]         # the message instead of the text
        call sb_reset
        mov rdi, [rsp + DR_OUT]
        lea rsi, [rip + .Ls_failed_text]
        call sb_append_c
        mov rdi, [rsp + DR_OUT]
        mov rsi, [rsp + DR_MSG]
        call sb_append_c
        mov eax, [rsp + DR_STATUS]
3:      add rsp, DR_SIZEOF
        LEAVE
ENDF decompile_run

# decompile_thread(args) -> 0: the body of decompile_run's thread
FUNC decompile_thread
        push r15
        ENTER
        sub rsp, ERR_SIZEOF + 8         # (with r15 pushed: 8 mod 16 keeps rsp aligned)
        mov rbx, rdi
        mov r15, [rbx + DR_CTX]
        mov rdi, r15
        call ctx_bind
        call ctx_set_stack
        mov rdi, rsp
        call err_catch
        test eax, eax
        jnz 1f
        mov rdi, [rbx + DR_CODE]
        mov rsi, [rbx + DR_LEN]
        mov rdx, [rbx + DR_THREADS]
        mov rcx, [rbx + DR_ONLY]
        mov r8, [rbx + DR_OUT]
        call decompile
        call err_end
        jmp 2f
1:      mov [rbx + DR_STATUS], rax
        mov rcx, [r15 + CTX_ERR_MSG]
        mov [rbx + DR_MSG], rcx
        mov edi, LOG_ERROR
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_failed]
        call log_fmt
2:      xor eax, eax
        add rsp, ERR_SIZEOF + 8
        LEAVE_NORET
        pop r15
        ret
ENDF decompile_thread

# --- the text ---

# contract_text(contract, out): the decompilation as python prints it
FUNC contract_text
        ENTER
        sub rsp, 32
        .set CT_OUT, 0
        .set CT_SHOWN, 8                # a vec of the functions printed
        .set CT_LIST, 16
        mov rbx, rdi
        mov [rsp + CT_OUT], rsi
        mov r12, rsi
        # the header, and the problems
        mov rdi, r12
        lea rsi, [rip + C_GRAY]
        call sb_append_c
        mov rdi, r12
        lea rsi, [rip + .Ls_header]
        call sb_append_c
        mov rdi, r12
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        call .Lct_newline
        mov r13, [rbx + CT_PROBLEMS]
        cmp dword ptr [r13 + N_AUX], 0
        je 2f
        mov rdi, r12
        lea rsi, [rip + C_GRAY]
        call sb_append_c
        mov rdi, r12
        lea rsi, [rip + .Ls_hash]
        call sb_append_c
        call .Lct_newline
        mov rdi, r12
        lea rsi, [rip + .Ls_failed_with]
        call sb_append_c
        call .Lct_newline
        xor r14d, r14d
1:      cmp r14d, [r13 + N_AUX]
        jae 11f
        mov rdi, r12
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        mov rdi, r12
        lea rsi, [rip + C_GRAY]
        call sb_append_c
        mov rdi, r12
        lea rsi, [rip + .Ls_failed_item]
        call sb_append_c
        mov rdi, r12
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        mov rdi, r12
        lea rsi, [rip + C_FAIL]
        call sb_append_c
        mov rdi, r12
        mov rsi, [r13 + N_DATA + r14*8]
        call sb_append_str
        mov rdi, r12
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        mov rdi, r12
        lea rsi, [rip + C_GRAY]
        call sb_append_c
        call .Lct_newline
        inc r14d
        jmp 1b
11:     mov rdi, r12
        lea rsi, [rip + .Ls_all_rest]
        call sb_append_c
        call .Lct_newline
        mov rdi, r12
        lea rsi, [rip + .Ls_hash]
        call sb_append_c
        mov rdi, r12
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        call .Lct_newline
2:      call .Lct_newline
        # the constants
        call vec_new
        mov [rsp + CT_SHOWN], rax
        mov r13, [rbx + CT_CONSTS]
        xor r14d, r14d
3:      cmp r14, [r13 + VEC_LEN]
        jae 4f
        mov rax, [r13 + VEC_DATA]
        mov rdi, [rax + r14*8]
        call .Lct_print_function
        inc r14
        jmp 3b
4:      mov rax, [rsp + CT_SHOWN]
        cmp qword ptr [rax + VEC_LEN], 0
        je 5f
        call .Lct_newline
5:      # the storage
        mov r13, [rbx + CT_STOR_DEFS]
        cmp dword ptr [r13 + N_AUX], 0
        je 7f
        mov rdi, r12
        lea rsi, [rip + C_GREEN]
        call sb_append_c
        mov rdi, r12
        lea rsi, [rip + .Ls_def_]
        call sb_append_c
        mov rdi, r12
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        mov rdi, r12
        lea rsi, [rip + .Ls_def_storage]
        call sb_append_c
        call .Lct_newline
        xor r14d, r14d
6:      cmp r14d, [r13 + N_AUX]
        jae 61f
        mov rdi, [r13 + N_DATA + r14*8]
        call pretty_type
        mov rdi, r12
        mov rsi, rax
        call sb_append_str
        call .Lct_newline
        inc r14d
        jmp 6b
61:     call .Lct_newline
7:      # the getters
        mov r13, [rbx + CT_FUNCS]
        xor r14d, r14d
8:      cmp r14, [r13 + VEC_LEN]
        jae 9f
        mov rax, [r13 + VEC_DATA]
        mov rdi, [rax + r14*8]
        inc r14
        cmp qword ptr [rdi + FN_GETTER], 0
        je 8b
        call .Lct_print_function
        call .Lct_newline
        jmp 8b
9:      # the regular functions, by priority
        call vec_new
        mov [rsp + CT_LIST], rax
        mov rdi, rax
        mov rsi, [r13 + VEC_DATA]
        mov rdx, [r13 + VEC_LEN]
        call vec_extend
        mov rdi, [rsp + CT_LIST]
        lea rsi, [rip + priority_lt]
        xor edx, edx
        call py_sort
        mov rax, [rsp + CT_SHOWN]
        cmp qword ptr [rax + VEC_LEN], 0
        je 12f
        # a title, when some functions were shown already and others remain
        mov r13, [rsp + CT_LIST]
        xor r14d, r14d
10:     cmp r14, [r13 + VEC_LEN]
        jae 12f
        mov rax, [r13 + VEC_DATA]
        mov rdi, [rsp + CT_SHOWN]
        mov rsi, [rax + r14*8]
        call set_has
        inc r14
        test eax, eax
        jnz 10b
        mov rdi, r12
        lea rsi, [rip + C_GRAY]
        call sb_append_c
        mov rdi, r12
        lea rsi, [rip + .Ls_regular]
        call sb_append_c
        mov rdi, r12
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        call .Lct_newline
        call .Lct_newline
12:     mov r13, [rsp + CT_LIST]
        xor r14d, r14d
13:     cmp r14, [r13 + VEC_LEN]
        jae 14f
        mov rax, [r13 + VEC_DATA]
        mov rdi, [rsp + CT_SHOWN]
        mov rsi, [rax + r14*8]
        call set_has
        test eax, eax
        jnz 131f
        mov rax, [r13 + VEC_DATA]
        mov rdi, [rax + r14*8]
        call .Lct_print_function
        call .Lct_newline
131:    inc r14
        jmp 13b
14:     add rsp, 32
        LEAVE
# locals
.Lct_newline:
        sub rsp, 8
        mov rdi, r12
        mov esi, 10
        call sb_append_char
        add rsp, 8
        ret
# the function rdi printed (its text, a newline), and noted as shown
.Lct_print_function:
        sub rsp, 24
        mov [rsp], rdi
        mov rdi, [rsp + 24 + 8 + CT_SHOWN]
        mov rsi, [rsp]
        call set_add
        mov rdi, [rsp]
        call fn_print
        mov rdi, r12
        mov rsi, rax
        call sb_append_str
        call .Lct_newline
        add rsp, 24
        ret
ENDF contract_text

# priority_lt(fn, fn2, arg) -> eax
FUNC priority_lt
        ENTER
        mov rbx, rsi
        call fn_priority
        mov r12, rax
        mov rdi, rbx
        call fn_priority
        xor ecx, ecx
        cmp r12, rax
        setl cl
        mov eax, ecx
        LEAVE
ENDF priority_lt

# scaled_ns(ns) -> rax: a time limit of python's, scaled by
# PANORAMIX_TIMEOUT as python scales its own (10 for a slow machine, or
# under valgrind); 0 or less: no limit.
FUNC scaled_ns
        cmp byte ptr [rip + timeout_read], 0
        jne 1f
        push rdi
        lea rdi, [rip + .Ls_env_timeout]
        call getenv@PLT
        test rax, rax
        jz 2f
        mov rdi, rax
        xor esi, esi
        call strtod@PLT
        movsd [rip + timeout_scale], xmm0
2:      mov byte ptr [rip + timeout_read], 1
        pop rdi
1:      movsd xmm1, [rip + timeout_scale]
        xorpd xmm0, xmm0
        comisd xmm1, xmm0
        jbe 3f
        cvtsi2sd xmm0, rdi
        mulsd xmm0, xmm1
        minsd xmm0, [rip + .Lk_max_ns]
        cvttsd2si rax, xmm0
        ret
3:      movabs rax, 0x3fffffffffffffff
        ret
ENDF scaled_ns

        .section .data
        .align 8
timeout_scale:  .double 1.0
timeout_read:   .quad 0             # (a race between the first two threads reads it twice: harmless)
        .section .rodata
        .align 8
.Lk_max_ns:     .double 4.0e18
.Ls_env_timeout: .asciz "PANORAMIX_TIMEOUT"
        .text

        .section .note.GNU-stack,"",@progbits
