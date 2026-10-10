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
.Ls_def_storage_vyper: .asciz "storage (vyper):"
.Ls_def_safemath: .asciz "SafeMath:"
.Ls_def_:       .asciz "def "
.Ls_regular:    .asciz "#\n#  Regular functions\n#"
.Ls_internal:   .asciz "#\n#  Internal functions\n#"
.Ls_fallback:   .asciz "_fallback"
.Ls_unknown:    .asciz "unknown"
.Ls_param_:     .asciz "_param"
.Ls_running:    .asciz "Running light execution to find functions."
.Ls_decompiling: .asciz "Decompiling %S..."
.Ls_interpreting: .asciz " -> Interpreting EVM on function..."
.Ls_cleaning:   .asciz " -> Cleaning up AST, identifying loops..."
.Ls_finished:   .asciz "Functions decompilation finished, now doing post-processing."
.Ls_problem:    .asciz "Problem with %S: %s"
.Ls_json_failed: .asciz "Failed json serialization. (%s)"
.Ls_no_ctx:     .asciz "out of memory: the system gave no more (mmap failed)"
.Ls_loader_issue: .asciz "Loader issue: %s"
.Ls_timed_out:  .asciz "the function took more than 3 minutes"
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
        # --explain (explain.s): what the job printed, and its first and
        # last traces explained (imported), for python's prev_trace
        .set JB_EXPLAIN, 72             # the builder (malloc'd), or 0
        .set JB_EXPLAIN_FIRST, 80       # the first trace explained, or 0
        .set JB_EXPLAIN_LAST, 88        # the last one, or 0
        .set JB_EXPLAIN_CUT, 96         # what the first one's text took
        # a recursive internal function's job (see vmrec.s): its record
        # (entry, n, m, frame) (main context), or 0 for a function of the abi
        .set JB_INTERNAL, 104
        # the recursive internal functions its VM found (vm_found_buffer's,
        # xmalloc'd), or 0
        .set JB_FOUND, 112
        .set JB_SIZEOF, 120

        # the shared state of the decompilation
        .set DC_LOADER, 0
        .set DC_JOBS, 8
        .set DC_NJOBS, 16
        .set DC_NEXT, 24                # the next job to take (atomic)
        .set DC_DONE, 32                # the jobs done (under the mutex)
        .set DC_MUTEX, 40               # pthread_mutex_t (40 bytes, zero-initialized)
        .set DC_COND, 80                # pthread_cond_t (48 bytes)
        .set DC_MEMLIMIT, 128           # CTX_MEM_LIMIT of the workers' contexts
        .set DC_VERBOSE, 136            # CTX_VERBOSE of the workers' contexts
        .set DC_EXPLAIN_SB, 144         # where the jobs' --explain goes, in order
        # the jobs run in batches: the functions of the abi, then the
        # recursive internal functions, wave after wave (see decompile)
        .set DC_BASE, 152               # the jobs of the batches before (their order)
        .set DC_EXPLAIN_PREV, 160       # --explain: the trace printed last (0: none yet)
        .set DC_SIZEOF, 168
        # the most threads a decompilation runs at once: the output is the
        # same at any count (the results go by the jobs' order), and the
        # arrays of a batch's threads are sized by it
        .set DC_MAX_THREADS, 1024

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

# (the abi of a function, signatures.make_abi: abi_of in sigs.s)

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
        call ctx_try_new
        test rax, rax
        jz .Ldw_no_ctx
        mov r15, rax
        mov [r12 + JB_CTX], rax
        mov rdi, rax
        call ctx_bind
        call ctx_set_stack
        mov rax, [rbx + DC_MEMLIMIT]
        mov [r15 + CTX_MEM_LIMIT], rax
        mov rax, [rbx + DC_VERBOSE]
        mov [r15 + CTX_VERBOSE], rax
        test rax, VB_EXPLAIN
        jz 1f
        mov edi, 255                    # (what the job explains - asked for
        call sb_try_new_cap             # without throwing: this is before the
        mov [r15 + CTX_EXPLAIN_SB], rax # handler below, so a system with no
        mov [r12 + JB_EXPLAIN], rax     # memory left went to rt_fatal, an
1:                                      # abort. 0 is "none", which `explain`
                                        # and the merge both take)
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
        # python's 3 minutes, as an alarm: the watchdog (rt_watch.s)
        mov rdi, FUNC_TIMEOUT_NS
        call scaled_ns
        add rax, [rsp + DW_START]
        mov rdi, r15
        mov rsi, rax
        call watch_start
        mov edi, LOG_INFO
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_interpreting]
        call log_fmt
        mov rdi, [rbx + DC_LOADER]
        xor esi, esi
        call vm_new
        cmp qword ptr [r12 + JB_INTERNAL], 0
        jne .Ldw_internal
        mov rdi, [r12 + JB_STACK]
        call value_import_root
        mov r13, rax
        mov rdi, VM_TIMEOUT_NS
        call scaled_ns
        # the VM run as python's decompiler makes it: what no selector
        # matched known where the default function is all of the
        # dispatcher, what runs before the function and the memory then
        # (vm_run_function: loader.entry, entry_memory)
        mov r8, rax
        mov rdi, [rbx + DC_LOADER]
        mov rsi, [r12 + JB_HASH]
        mov rdx, [r12 + JB_TARGET]
        mov rcx, r13
        call vm_run_function
        jmp .Ldw_ran
        # a recursive internal function's (vmrec.s): its VM knows it, starts
        # at its entry with its params where its calls push them, above the
        # address it returns to - nothing ran before, nothing is known
.Ldw_internal:
        mov rdi, [r12 + JB_INTERNAL]
        call value_import_root
        mov [rsp + DW_TMP], rax
        mov rdi, rax
        xor esi, esi
        call vm_internal_add
        mov rax, [r15 + CTX_VM]
        mov qword ptr [rax + VM_INSIDE], 1
        mov rdi, [rsp + DW_TMP]
        mov rdi, [rdi + N_DATA + 8]
        call vm_internal_stack
        mov r13, rax
        xor edi, edi
        xor esi, esi
        call mk_tuple
        mov r14, rax                    # ()
        mov rdi, VM_TIMEOUT_NS
        call scaled_ns
        mov rcx, rax
        mov rdi, [rsp + DW_TMP]
        mov rdi, [rdi + N_DATA]         # the entry
        mov rsi, r13
        mov rdx, r14
        xor r8d, r8d                    # (no entry: python's None)
        mov r9, r14
        call vm_run
.Ldw_ran:
        mov r13, rax
        # the recursive internal functions its VM found, for the decompiler
        # (python's vm.found)
        call vm_found_buffer
        mov [r12 + JB_FOUND], rax
        call .Ldw_check_deadline
        test qword ptr [r15 + CTX_VERBOSE], VB_EXPLAIN
        jz 1f
        lea rdi, [rip + explain_s_initial]      # (the whole trace: its entry
        mov rsi, r13                            # first, see vm_run)
        call explain
        mov rdi, r13                    # the lines of assembly dropped again
        lea rsi, [rip + explain_drop_asm]
        xor edx, edx
        call rewrite_trace
        mov r13, rax
        lea rdi, [rip + explain_s_no_asm]
        mov rsi, rax
        call explain
1:
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
        test qword ptr [r15 + CTX_VERBOSE], VB_EXPLAIN
        jz 1f
        lea rdi, [rip + explain_s_final]
        mov rsi, rax
        call explain
        mov rdi, [r12 + JB_TRACE]
        call fold_isolated
        lea rdi, [rip + explain_s_folded]
        mov rsi, rax
        call explain
1:      call .Ldw_check_deadline
        call err_end
        mov qword ptr [r12 + JB_ERR], 0
        jmp .Ldw_finish
.Ldw_failed:
        mov [r12 + JB_ERR], rax
        mov rax, [r15 + CTX_ERR_MSG]
        mov [r12 + JB_ERRMSG], rax
.Ldw_finish:
        mov rdi, r15
        call watch_stop
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
# no memory for the job's context: the function fails (python's
# MemoryError), the others go on
.Ldw_no_ctx:
        mov qword ptr [r12 + JB_CTX], 0
        mov qword ptr [r12 + JB_ERR], E_MEMORY
        lea rax, [rip + .Ls_no_ctx]
        mov [r12 + JB_ERRMSG], rax
        lea rdi, [rbx + DC_MUTEX]
        call pthread_mutex_lock@PLT
        mov qword ptr [r12 + JB_STATE], 1
        inc qword ptr [rbx + DC_DONE]
        lea rdi, [rbx + DC_COND]
        call pthread_cond_signal@PLT
        lea rdi, [rbx + DC_MUTEX]
        call pthread_mutex_unlock@PLT
        jmp .Ldw_next
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
#
# The jobs run in batches: the functions of the abi, then the recursive
# internal functions their VMs found (vmrec.s), decompiled apart - those
# they call, then those these call, and so on (python's waves), by entry.
FUNC decompile
        ENTER
        sub rsp, ERR_SIZEOF + 144
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
        .set DE_REQ, ERR_SIZEOF + 112   # the threads asked for (each batch's)
        .set DE_RECS, ERR_SIZEOF + 120  # the recursive internal functions found: records, as found
        .set DE_NEW, ERR_SIZEOF + 128   # those the last batch found first: the next wave
        .set DE_INTERNAL, ERR_SIZEOF + 136      # their functions (FN_INTERNAL)
        mov [rsp + DE_CODE], rdi
        mov [rsp + DE_LEN], rsi
        # the count of threads, settled here once and for all: 0 asks for
        # one, and a count past DC_MAX_THREADS is that maximum. Everything
        # below takes it as it is - mem_limit_for divides the memory by it
        # and the arrays of a batch's threads are sized by it, and neither
        # held for a count of (size_t)-1 from an API caller (the divisor
        # was 0: SIGFPE) or of 2^61 (times 8: a few bytes). The output is
        # the same at any count, so capping it changes nothing else.
        test rdx, rdx
        jnz 01f
        mov edx, 1
01:     cmp rdx, DC_MAX_THREADS
        jbe 02f
        mov edx, DC_MAX_THREADS
02:     mov [rsp + DE_THREADS], rdx
        mov [rsp + DE_ONLY], rcx
        mov [rsp + DE_OUT], r8
        # the contract phase - the loader's light run to find the
        # functions, then (below) the import of the workers' results, the
        # post-processing and the printing - runs on this context (the main
        # one). It is bounded like a function's: a memory limit and the
        # watchdog's deadline, so a small input that makes the function
        # discovery, a post-processing walk or the printer spend gigabytes
        # or minutes is cut here too (it was not: the limit and the
        # watchdog were a worker's only).
        #
        # The discovery gets half of it, and the phases after it the rest:
        # what an arena has taken is never given back (CTX_ARENA_TOTAL
        # only grows, and nothing compacts this context), so a discovery
        # that ran to the limit before it threw left the import of the
        # results, the post-processing and the printing with nothing, and
        # a contract that is merely expensive to discover came out with no
        # text at all rather than with the problem reported. Half is a
        # bound either way: the phase as a whole stays under the limit.
        mov rdi, [rsp + DE_THREADS]
        call mem_limit_for
        shr rax, 1
        mov [r15 + CTX_MEM_LIMIT], rax
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
        mov r12, rax
        call monotonic_ns
        add rax, r12                    # the deadline: now + the limit
        mov rdi, r15
        mov rsi, rax
        call watch_start
        mov rdi, rbx
        mov rsi, r12
        call loader_find_functions
        mov rdi, r15
        call watch_stop
        call err_end
        jmp 1f
.Lde_loader_issue:
        # (watched above: the deadline has to go, or a STACK_CHECK of the
        # phases below would throw for a limit that is past)
        mov rdi, r15
        call watch_stop
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
        mov rdi, [r15 + CTX_DATA_SB]    # (python's json: {})
        test rdi, rdi
        jz .Lde_ret
        mov esi, [r15 + CTX_DATA_MODE]
        call data_empty_dict
        jmp .Lde_ret
2:      # the jobs: (hash, target, stack) -> the functions asked for
        mov r12, [rbx + LD_FUNCS]
        mov edi, DC_SIZEOF
        call arena_alloc
        mov r13, rax
        mov [rsp + DE_DEC], rax
        mov [r13 + DC_LOADER], rbx
        mov rax, [r15 + CTX_VERBOSE]
        and eax, VB_ASM | VB_EXPLAIN    # (what the jobs do with it)
        mov [r13 + DC_VERBOSE], rax
        # (--explain: the context's builder is each job's in turn, while
        # its function is made - see .Lde_import_job)
        mov rax, [r15 + CTX_EXPLAIN_SB]
        mov [r13 + DC_EXPLAIN_SB], rax
        mov qword ptr [r15 + CTX_EXPLAIN_SB], 0
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
        # (what's known holds for the default function where it's all of
        # the dispatcher, at 0 - not where it starts: what's known there is
        # what its entries, each of the paths to it, have in common - see
        # loader.entry)
        cmp qword ptr [rcx + JB_TARGET], 1      # target == 0
        jne 3b
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
        mov rdi, [rsp + DE_THREADS]     # (1 to DC_MAX_THREADS: settled at the
        mov [rsp + DE_REQ], rdi         # entry, so the array below is sized by
                                        # a count that times 8 cannot wrap)
        cmp rdi, [r13 + DC_NJOBS]
        jbe 6f
        mov rdi, [r13 + DC_NJOBS]
6:      test rdi, rdi
        jnz 7f
        mov edi, 1
7:      mov [rsp + DE_THREADS], rdi
        mov [r15 + CTX_FOLD_THREADS], rdi       # (the folds of the postprocessing too)
        call mem_limit_for
        mov [r13 + DC_MEMLIMIT], rax
        mov [r15 + CTX_CHILD_LIMIT], rax        # (the folder's contexts)
        mov [r15 + CTX_MEM_LIMIT], rax          # (this context: the import of
                                                # the results, the
                                                # post-processing, the text -
                                                # see the loader above)
        mov rdi, [rsp + DE_REQ]         # (as many as a batch may have)
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
        # the results, imported as they come (the contexts they are on
        # are freed then), the functions made from them
        call vec_new
        mov [rsp + DE_FUNCS], rax
        call vec_new
        mov [rsp + DE_PROBLEMS], rax
        call vec_new
        mov [rsp + DE_RECS], rax
        call vec_new
        mov [rsp + DE_NEW], rax
        call vec_new
        mov [rsp + DE_INTERNAL], rax
.Lde_batch:
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
9:      mov qword ptr [rsp + DE_I], 0   # imported so far
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
        test rdi, rdi                   # (0: it had none)
        jz .Lde_wait
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
13:     test qword ptr [r15 + CTX_VERBOSE], VB_EXPLAIN
        jz 16f
        call .Lde_explain_merge
16:     # the recursive internal functions the batch's VMs found (python's
        # internal.setdefault, then new), then the next wave: those new, by
        # entry - a job each
        mov rdi, [r13 + DC_JOBS]
        mov rsi, [r13 + DC_NJOBS]
        mov rdx, [rsp + DE_RECS]
        mov rcx, [rsp + DE_NEW]
        call dc_merge_found
        mov rdi, [rsp + DE_NEW]
        cmp qword ptr [rdi + VEC_LEN], 0
        je .Lde_batches_done
        lea rsi, [rip + record_entry_lt]
        xor edx, edx
        call py_sort
        mov rax, [r13 + DC_NJOBS]
        add [r13 + DC_BASE], rax
        mov rax, [rsp + DE_NEW]
        mov rax, [rax + VEC_LEN]
        mov [r13 + DC_NJOBS], rax
        mov qword ptr [r13 + DC_NEXT], 0
        mov qword ptr [r13 + DC_DONE], 0
        imul rdi, rax, JB_SIZEOF
        call arena_alloc
        mov [r13 + DC_JOBS], rax
        mov r12, rax
        xor r14d, r14d
17:     mov rax, [rsp + DE_NEW]
        cmp r14, [rax + VEC_LEN]
        jae 18f
        mov rax, [rax + VEC_DATA]
        mov rax, [rax + r14*8]          # (entry, n, m, frame)
        mov [r12 + JB_INTERNAL], rax
        mov rdi, [rax + N_DATA]
        mov [r12 + JB_TARGET], rdi
        call internal_name              # (its name: the logs', the problems')
        mov [r12 + JB_HASH], rax
        add r12, JB_SIZEOF
        inc r14
        jmp 17b
18:     mov rax, [rsp + DE_NEW]
        mov qword ptr [rax + VEC_LEN], 0
        mov rdi, [rsp + DE_REQ]
        cmp rdi, [r13 + DC_NJOBS]
        jbe 19f
        mov rdi, [r13 + DC_NJOBS]
19:     mov [rsp + DE_THREADS], rdi
        jmp .Lde_batch
.Lde_batches_done:
        mov rdi, [rsp + DE_ATTR]
        call pthread_attr_destroy@PLT
        mov edi, LOG_INFO
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_finished]
        call log_fmt
        # the functions in the order of the jobs (python's dict), then
        # the contract
        mov rdi, [rsp + DE_FUNCS]
        call .Lde_functions_in_order
        mov [rsp + DE_FUNCS], rax
        mov rdi, [rsp + DE_PROBLEMS]
        call .Lde_functions_in_order    # (the (hash, name), in the order of the jobs)
        mov rdi, rax
        call vec_to_list
        mov rsi, rax
        mov rdi, [rsp + DE_FUNCS]
        call contract_new
        mov [rsp + DE_CONTRACT], rax
        mov rdi, [rsp + DE_INTERNAL]    # (the internal ones by entry)
        lea rsi, [rip + internal_entry_lt]
        xor edx, edx
        call py_sort
        mov rax, [rsp + DE_CONTRACT]
        mov rcx, [rsp + DE_INTERNAL]
        mov [rax + CT_INTERNAL], rcx
        mov rdi, rax
        call contract_postprocess
        # every function printed now, on threads (the json and the text
        # take them as they are then)
        mov rdi, [rsp + DE_CONTRACT]
        mov rdi, [rdi + CT_FUNCS]
        mov rsi, [r15 + CTX_FOLD_THREADS]
        call print_many
        mov rdi, [rsp + DE_CONTRACT]
        mov rdi, [rdi + CT_INTERNAL]
        mov rsi, [r15 + CTX_FOLD_THREADS]
        call print_many
        # python's decompilation.json, when asked for (before the text,
        # as python makes it)
        cmp qword ptr [r15 + CTX_DATA_SB], 0
        je 14f
        mov rdi, rsp
        call err_catch
        test eax, eax
        jnz 15f
        mov rdi, [rsp + DE_CONTRACT]
        mov rsi, [r15 + CTX_DATA_SB]
        mov edx, [r15 + CTX_DATA_MODE]
        call contract_data
        call err_end
        jmp 14f
15:     mov edi, LOG_ERROR
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_json_failed]
        mov rcx, [r15 + CTX_ERR_MSG]
        call log_fmt
        mov rdi, [r15 + CTX_DATA_SB]
        call sb_reset
        mov rdi, [r15 + CTX_DATA_SB]
        mov esi, [r15 + CTX_DATA_MODE]
        call data_empty_dict
14:     mov rdi, [rsp + DE_CONTRACT]
        mov rsi, [rsp + DE_OUT]
        call contract_text
.Lde_ret:
        mov edi, LOG_DEBUG
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_peak_main]
        mov rcx, [r15 + CTX_ARENA_PEAK]
        shr rcx, 20
        call log_fmt
        add rsp, ERR_SIZEOF + 144
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
# a target on a jumpdest moves past it (python: lines.get(target, (None,
# None))[1] == "jumpdest" and target > 1 -> target += 1); one that isn't an
# instruction stays (the VM's run from it is an invalid jump, or a stop
# past the last instruction)
.Lde_past_jumpdest:
        mov rax, rdi
        test dil, 1
        jz 1f                           # (not a small int: no instruction)
        cmp rdi, 3                      # tagged 1
        jle 1f
        mov rcx, rdi
        UNTAG rcx
        cmp rcx, [rbx + LD_CODELEN]
        jae 1f
        mov rdx, [rbx + LD_PC2IDX]
        mov edx, [rdx + rcx*4]
        cmp edx, -1
        je 1f
        imul rdx, rdx, IN_SIZEOF
        add rdx, [rbx + LD_INSTRS]
        cmp byte ptr [rdx + IN_OP], 0x5b
        jne 1f
        add rax, 2                      # pc + 1
1:      ret
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
        test qword ptr [r15 + CTX_VERBOSE], VB_EXPLAIN
        jz 1f
        call .Lde_import_explain
        mov rdi, [rsp + ERR_SIZEOF]
        mov rax, [rdi + JB_EXPLAIN]     # (the traits of its function, there)
        mov [r15 + CTX_EXPLAIN_SB], rax
1:      cmp qword ptr [rdi + JB_ERR], 0
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
        mov rdi, [rdi + JB_INTERNAL]
        test rdi, rdi
        jnz 5f
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
        mov qword ptr [r15 + CTX_EXPLAIN_SB], 0
        # (fn, job index) - the order is restored later
        mov rdi, [rsp + ERR_SIZEOF]
        call .Lde_job_index
        mov rsi, rax
        mov rdi, [rsp + ERR_SIZEOF + 16]
        call mk2
        mov rdi, [rsp + ERR_SIZEOF + 24 + 8 + DE_FUNCS]
        mov rsi, rax
        call vec_push
        add rsp, ERR_SIZEOF + 24
        ret
5:      # a recursive internal function (vmrec.s), its record in rdi - put
        # in the order of the entries later
        mov rsi, [rsp + ERR_SIZEOF + 8]
        call internal_function_new
        mov [rsp + ERR_SIZEOF + 16], rax
        call err_end
        mov qword ptr [r15 + CTX_EXPLAIN_SB], 0
        mov rdi, [rsp + ERR_SIZEOF + 24 + 8 + DE_INTERNAL]
        mov rsi, [rsp + ERR_SIZEOF + 16]
        call vec_push
        add rsp, ERR_SIZEOF + 24
        ret
3:      mov rdi, [rsp + ERR_SIZEOF]
        mov rsi, [r15 + CTX_ERR_MSG]
        mov [rdi + JB_ERRMSG], rsi
        mov [rdi + JB_ERR], rax
2:      mov qword ptr [r15 + CTX_EXPLAIN_SB], 0
        mov rdi, [rsp + ERR_SIZEOF]
        mov r8, [rdi + JB_ERRMSG]
        mov rcx, [rdi + JB_HASH]
        mov edi, LOG_ERROR
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_problem]
        call log_fmt
        # the name, as python's problems hold it - the hash itself where the
        # system has no memory left for it (a job that failed for want of
        # it: interning the name may fail too)
        mov rdi, [rsp + ERR_SIZEOF]
        mov rax, [rdi + JB_HASH]
        mov [rsp + ERR_SIZEOF + 16], rax
        cmp qword ptr [rdi + JB_INTERNAL], 0    # (a recursive internal function:
        jne 4f                                  # its name, problems[name] = name)
        lea rdi, [rsp]
        call err_catch
        test eax, eax
        jnz 4f
        mov rdi, [rsp + ERR_SIZEOF]
        mov rdi, [rdi + JB_HASH]
        call abi_of
        mov rdi, rax
        xor esi, esi
        call abi_func_name
        mov [rsp + ERR_SIZEOF + 16], rax
        call err_end
4:      mov rdi, [rsp + ERR_SIZEOF + 24 + 8 + DE_PROBLEMS]
        push rdi
        push rdi
        mov rsi, [rsp + 16 + ERR_SIZEOF + 16]   # (hash, name): problems[hash] = fname
        mov rdi, [rsp + 16 + ERR_SIZEOF]
        mov rdi, [rdi + JB_HASH]
        call mk2
        mov [rsp + 16 + ERR_SIZEOF + 8], rax
        # ((hash, name), job index): python's dict has them in the loader's order
        # (then the recursive internal functions', in the order of the
        # waves), the jobs finish in any order
        mov rdi, [rsp + 16 + ERR_SIZEOF]
        call .Lde_job_index
        mov rsi, rax
        mov rdi, [rsp + 16 + ERR_SIZEOF + 8]
        call mk2
        pop rdi
        pop rdi
        mov rsi, rax
        call vec_push
        add rsp, ERR_SIZEOF + 24
        ret
# rax: the index of the job rdi among the jobs of all the batches (tagged)
.Lde_job_index:
        mov rax, rdi
        sub rax, [r13 + DC_JOBS]
        xor edx, edx
        mov ecx, JB_SIZEOF
        div rcx
        add rax, [r13 + DC_BASE]
        TAG rax
        ret
# --explain: the first and last traces the job (rdi) explained, imported
# (its context is freed next), and what the first one's text took
.Lde_import_explain:
        push rbx
        mov rbx, rdi
        mov rcx, [rbx + JB_CTX]
        test rcx, rcx
        jz 1f
        mov rax, [rcx + CTX_EXPLAIN_CUT]
        mov [rbx + JB_EXPLAIN_CUT], rax
        mov rdi, [rcx + CTX_EXPLAIN_FIRST]
        test rdi, rdi
        jz 2f
        call value_import_root
        mov [rbx + JB_EXPLAIN_FIRST], rax
2:      mov rcx, [rbx + JB_CTX]
        mov rdi, [rcx + CTX_EXPLAIN_PREV]
        test rdi, rdi
        jz 1f
        call value_import_root
        mov [rbx + JB_EXPLAIN_LAST], rax
1:      pop rbx
        ret
# --explain: what the jobs printed, one after the other into
# DC_EXPLAIN_SB (the context's builder again) - python's prev_trace, the
# trace printed last, carried from each job to the next (and from a batch
# to the next): a job's first trace equal to it wasn't printed. Their
# builders freed.
.Lde_explain_merge:
        push rbx
        push r12
        push r14
        mov rax, [r13 + DC_EXPLAIN_SB]
        mov [r15 + CTX_EXPLAIN_SB], rax
        mov r14, [r13 + DC_EXPLAIN_PREV]        # the trace printed last (0: none yet)
        mov rbx, [r13 + DC_JOBS]
        mov r12, [r13 + DC_NJOBS]
1:      test r12, r12
        jz 5f
        cmp qword ptr [rbx + JB_EXPLAIN], 0
        je 4f
        xor ecx, ecx                    # from where
        mov rdi, [rbx + JB_EXPLAIN_FIRST]
        test rdi, rdi
        jz 2f
        test r14, r14
        jz 2f
        mov rsi, r14
        call values_equal
        xor ecx, ecx
        test eax, eax
        jz 2f
        mov rcx, [rbx + JB_EXPLAIN_CUT]
2:      mov rax, [rbx + JB_EXPLAIN]
        mov rsi, [rax + SB_BUF]
        mov rdx, [rax + SB_LEN]
        add rsi, rcx
        sub rdx, rcx
        mov rdi, [r13 + DC_EXPLAIN_SB]
        test rdi, rdi
        jz 3f
        call sb_append
3:      mov rdi, [rbx + JB_EXPLAIN]
        call sb_free
        mov qword ptr [rbx + JB_EXPLAIN], 0
        mov rax, [rbx + JB_EXPLAIN_LAST]
        test rax, rax
        jz 4f
        mov r14, rax
4:      add rbx, JB_SIZEOF
        dec r12
        jmp 1b
5:      mov [r13 + DC_EXPLAIN_PREV], r14
        pop r14
        pop r12
        pop rbx
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

# record_entry_lt(rec, rec2, arg) -> eax: the records (entry, n, m, frame)
# of recursive internal functions by entry (a number: tagged small ints
# keep their order)
FUNC record_entry_lt
        mov rax, [rdi + N_DATA]
        cmp rax, [rsi + N_DATA]
        setl al
        movzx eax, al
        ret
ENDF record_entry_lt

# internal_entry_lt(fn, fn2, arg) -> eax: recursive internal functions by
# entry
FUNC internal_entry_lt
        mov rdi, [rdi + FN_INTERNAL]
        mov rsi, [rsi + FN_INTERNAL]
        jmp record_entry_lt
ENDF internal_entry_lt

# dc_merge_found(jobs, njobs, recs, new): python's merge of the recursive
# internal functions the VMs of a batch of jobs found (decompiler.py:
# internal.setdefault, new.append) - in the order of the jobs, those whose
# function was made (JB_ERR 0): each record (entry, n, m, frame) whose
# entry isn't one of recs' yet goes there, and to new. The jobs' buffers
# (JB_FOUND, vm_found_buffer's) freed.
FUNC dc_merge_found
        ENTER
        sub rsp, 32 + ERR_SIZEOF
        .set MF_RECS, 0
        .set MF_NEW, 8
        .set MF_REC, 16
        .set MF_ERR, 32
        mov rbx, rdi                    # the job
        mov r12, rsi                    # the jobs left
        mov [rsp + MF_RECS], rdx
        mov [rsp + MF_NEW], rcx
        # the buffers are malloc'd (vm_found_buffer), outside any arena,
        # and mk_tuple and vec_push below allocate on this context, which
        # has a memory limit of its own now: a throw there left the
        # current job's buffer and every later one behind, for the life of
        # the process. rbx and r12 come back as they are here, so the
        # handler walks every job of the batch (one already freed is 0).
        lea rdi, [rsp + MF_ERR]
        call err_catch
        test eax, eax
        jnz .Lmf_threw
1:      test r12, r12
        jz 9f
        mov r13, [rbx + JB_FOUND]
        test r13, r13
        jz 5f
        cmp qword ptr [rbx + JB_ERR], 0
        jne 4f
        xor r14d, r14d
2:      cmp r14, [r13]
        jae 4f
        mov rsi, r14
        shl rsi, 5
        lea rsi, [r13 + 8 + rsi]        # the record's numbers
        inc r14
        mov rdx, [rsi]                  # its entry: known?
        mov rdi, [rsp + MF_RECS]
        mov rcx, [rdi + VEC_LEN]
        mov r8, [rdi + VEC_DATA]
3:      test rcx, rcx
        jz 31f
        mov rax, [r8]
        cmp [rax + N_DATA], rdx
        je 2b
        add r8, 8
        dec rcx
        jmp 3b
31:     mov edi, 4
        call mk_tuple
        mov [rsp + MF_REC], rax
        mov rdi, [rsp + MF_RECS]
        mov rsi, rax
        call vec_push
        mov rdi, [rsp + MF_NEW]
        mov rsi, [rsp + MF_REC]
        call vec_push
        jmp 2b
4:      mov rdi, r13
        call free@PLT
        mov qword ptr [rbx + JB_FOUND], 0
5:      add rbx, JB_SIZEOF
        dec r12
        jmp 1b
9:      call err_end
        add rsp, 32 + ERR_SIZEOF
        LEAVE
.Lmf_threw:                             # (the handler is unlinked already)
        mov r13d, eax                   # the error's code
6:      test r12, r12
        jz 8f
        mov rdi, [rbx + JB_FOUND]
        test rdi, rdi
        jz 7f
        mov qword ptr [rbx + JB_FOUND], 0
        call free@PLT
7:      add rbx, JB_SIZEOF
        dec r12
        jmp 6b
8:      mov edi, r13d
        mov rsi, [r15 + CTX_ERR_MSG]
        call err_throw
ENDF dc_merge_found

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
        mov rsi, [rsi + N_DATA + 8]     # (hash, name)
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
5:      # the storage: `def storage:` (`def storage (vyper):` for a Vyper
        # contract), each definition as storage.pretty_def prints it
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
        cmp qword ptr [rbx + CT_LANG], 0
        je 51f
        lea rsi, [rip + .Ls_def_storage_vyper]
51:     call sb_append_c
        call .Lct_newline
        xor r14d, r14d
6:      cmp r14d, [r13 + N_AUX]
        jae 61f
        mov rdi, [r13 + N_DATA + r14*8]
        call st_pretty_def
        mov rdi, r12
        mov rsi, rax
        call sb_append_str
        call .Lct_newline
        inc r14d
        jmp 6b
61:     call .Lct_newline
7:      # the functions of the contract's SafeMath (safemath.s)
        mov r13, [rbx + CT_SAFEMATH]
        cmp dword ptr [r13 + N_AUX], 0
        je 72f
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
        lea rsi, [rip + .Ls_def_safemath]
        call sb_append_c
        call .Lct_newline
        mov rdi, r13
        call safemath_pretty
        mov r13, rax
        xor r14d, r14d
71:     cmp r14d, [r13 + N_AUX]
        jae 711f
        mov rdi, r12
        mov rsi, [r13 + N_DATA + r14*8]
        call sb_append_str
        call .Lct_newline
        inc r14d
        jmp 71b
711:    call .Lct_newline
72:     # the getters
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
        test qword ptr [r15 + CTX_VERBOSE], VB_REPR
        jz 81f
        call .Lct_newline               # --repr: print(), pprint_repr(func.trace)
        mov rax, [r13 + VEC_DATA]
        mov rax, [rax + r14*8 - 8]
        mov rsi, [rax + FN_TRACE]
        mov rdi, r12
        xor edx, edx
        call pprint_repr
81:     call .Lct_newline
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
        test qword ptr [r15 + CTX_VERBOSE], VB_RETURNS
        jz 132f
        call .Lct_returns               # --returns: print(r) for each
132:    test qword ptr [r15 + CTX_VERBOSE], VB_REPR
        jz 133f
        mov rax, [r13 + VEC_DATA]       # --repr: pprint_repr(func.orig_trace)
        mov rax, [rax + r14*8]
        mov rsi, [rax + FN_ORIG_TRACE]
        mov rdi, r12
        xor edx, edx
        call pprint_repr
133:    call .Lct_newline
131:    inc r14
        jmp 13b
14:     # the recursive internal functions, by entry (vmrec.s)
        mov r13, [rbx + CT_INTERNAL]
        cmp qword ptr [r13 + VEC_LEN], 0
        je 16f
        mov rdi, r12
        lea rsi, [rip + C_GRAY]
        call sb_append_c
        mov rdi, r12
        lea rsi, [rip + .Ls_internal]
        call sb_append_c
        mov rdi, r12
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        call .Lct_newline
        call .Lct_newline
        xor r14d, r14d
15:     cmp r14, [r13 + VEC_LEN]
        jae 16f
        mov rax, [r13 + VEC_DATA]
        mov rdi, [rax + r14*8]
        call .Lct_print_function
        test qword ptr [r15 + CTX_VERBOSE], VB_REPR
        jz 151f
        mov rax, [r13 + VEC_DATA]       # --repr: pprint_repr(func.orig_trace)
        mov rax, [rax + r14*8]
        mov rsi, [rax + FN_ORIG_TRACE]
        mov rdi, r12
        xor edx, edx
        call pprint_repr
151:    call .Lct_newline
        inc r14
        jmp 15b
16:     add rsp, 32
        LEAVE
# locals
.Lct_newline:
        sub rsp, 8
        mov rdi, r12
        mov esi, 10
        call sb_append_char
        add rsp, 8
        ret
# --returns: the returns of the function r13[r14], a line each (str())
.Lct_returns:
        push rbx
        push r12
        push r14
        mov rax, [r13 + VEC_DATA]
        mov rax, [rax + r14*8]
        mov rbx, [rax + FN_RETURNS]
        xor r14d, r14d
1:      cmp r14d, [rbx + N_AUX]
        jae 2f
        mov rdi, r12
        mov rsi, [rbx + N_DATA + r14*8]
        call value_print
        mov rdi, r12
        mov esi, 10
        call sb_append_char
        inc r14d
        jmp 1b
2:      pop r14
        pop r12
        pop rbx
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
