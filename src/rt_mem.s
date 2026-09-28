# Memory: thread contexts, arenas, GMP glue.
#
# All the nodes a thread creates while decompiling a function live in its
# arena (a list of mmap'ed chunks, bump-allocated) and are freed at once
# with arena_reset. GMP's allocations are routed there too, so the limbs
# of the big ints die with the nodes that own them.

.include "defs.inc"

        .section .bss
        .align 8
ctx_key:        .quad 0          # pthread_key_t
rt_initialized: .quad 0
        .globl global_ctx
        .hidden global_ctx
global_ctx:     .quad 0          # a context for process-wide constants (never reset)
chunk_pool:     .quad 0          # the chunks free for reuse (zeroed), a list
chunk_pool_count: .quad 0
chunk_pool_lock: .quad 0         # a spinlock
chunk_poison:   .quad 0          # PANORAMIX_POISON set: the released chunks filled with garbage

        .text

# rt_init(): process-wide initialization, idempotent.
FUNC rt_init
        ENTER
        cmp qword ptr [rip + rt_initialized], 0
        jne 9f
        mov qword ptr [rip + rt_initialized], 1
        lea rdi, [rip + ctx_key]
        xor esi, esi
        call pthread_key_create@PLT
        lea rdi, [rip + gmp_alloc]
        lea rsi, [rip + gmp_realloc]
        lea rdx, [rip + gmp_free]
        call __gmp_set_memory_functions@PLT
        lea rdi, [rip + .Ls_env_poison]
        call getenv@PLT
        test rax, rax
        setnz byte ptr [rip + chunk_poison]
        call simd_init
        call str_init
        call opcodes_init
        # the global context: bound while the constants get made, and left
        # bound for the calling thread if it had nothing (the CLI)
        call ctx_current
        mov rbx, rax
        call ctx_new
        mov [rip + global_ctx], rax
        push r15
        push r15
        mov r15, rax
        mov rdi, rax
        call ctx_bind
        call arith_init
        call alg_init
        call arith_module_init
        call vm_module_init
        call matcher_init
        call prettify_init
        call patterns_init
        pop r15
        pop r15
        test rbx, rbx
        jz 9f
        mov rdi, rbx
        call ctx_bind
9:      LEAVE
ENDF rt_init

# ctx_new() -> rax: a fresh thread context, not yet bound (see ctx_bind).
FUNC ctx_new
        ENTER
        mov edi, CTX_SIZE
        call xmalloc
        mov rbx, rax
        mov rdi, rbx
        xor esi, esi
        mov edx, CTX_SIZE
        call memset@PLT
        mov qword ptr [rbx + CTX_ARENA_CHUNKSZ], ARENA_CHUNK_DEFAULT
        # first chunk
        mov rdi, rbx
        mov esi, ARENA_CHUNK_DEFAULT
        xor edx, edx
        call arena_new_chunk
        # hash-cons table: 4096 entries to start with
        mov edi, 4096
        mov esi, 8
        call xcalloc
        mov [rbx + CTX_HC_TABLE], rax
        mov qword ptr [rbx + CTX_HC_CAP], 4096
        # scratch mpz
        lea rdi, [rbx + CTX_TMPZ]
        push r15
        push r15
        mov r15, rbx
        mov rdi, rbx
        call ctx_bind
        call ctx_init_mpz
        pop r15
        pop r15
        mov rax, rbx
        LEAVE
ENDF ctx_new

# ctx_bind(ctx): make ctx the current thread's context for the code that
# can't rely on r15 (GMP callbacks).
FUNC ctx_bind
        ENTER
        mov rsi, rdi
        mov rdi, [rip + ctx_key]
        call pthread_setspecific@PLT
        LEAVE
ENDF ctx_bind

# ctx_current() -> rax: the bound context (pthread key)
FUNC ctx_current
        ENTER
        mov rdi, [rip + ctx_key]
        call pthread_getspecific@PLT
        LEAVE
ENDF ctx_current

# ctx_free(ctx): release everything
FUNC ctx_free
        ENTER
        mov rbx, rdi
        mov rdi, [rbx + CTX_ARENA_CHUNKS]
        mov rsi, [rbx + CTX_ARENA_CUR]
        call chunks_release
        mov rdi, [rbx + CTX_HC_TABLE]
        call free@PLT
        mov rdi, rbx
        call free@PLT
        LEAVE
ENDF ctx_free

# arena_new_chunk(ctx, size, check): map a chunk of at least `size`
# payload bytes and make it the current one. check: E_MEMORY if the arena
# would pass the context's limit (the context must be r15's then).
FUNC arena_new_chunk
        ENTER
        sub rsp, 16
        mov [rsp], rdx                  # check (for a failed mmap too)
        mov rbx, rdi
        mov r12, rsi
        add r12, CHUNK_DATA + 15
        and r12, -16
        mov rax, [rbx + CTX_ARENA_CHUNKSZ]
        cmp r12, rax
        cmovb r12, rax
        test edx, edx
        jz 1f
        mov rax, [rbx + CTX_MEM_LIMIT]
        test rax, rax
        jz 1f
        mov rcx, [rbx + CTX_HC_CAP]
        shl rcx, 3                      # (the hash-cons table counts too)
        add rcx, [rbx + CTX_ARENA_TOTAL]
        add rcx, r12
        cmp rcx, rax
        ja .Lchunk_limit
1:      cmp r12, ARENA_CHUNK_DEFAULT
        jne 3f
        call pool_pop                   # a chunk used before
        test rax, rax
        jnz 4f
        call chunk_map_huge             # a new one, on huge pages if it can
        test rax, rax
        jnz 4f
3:      xor edi, edi
        mov rsi, r12
        mov edx, 3                      # PROT_READ | PROT_WRITE
        mov ecx, 0x22                   # MAP_PRIVATE | MAP_ANONYMOUS
        mov r8, -1
        xor r9d, r9d
        call mmap@PLT
        cmp rax, -1
        je .Lchunk_fail
4:      mov rcx, [rbx + CTX_ARENA_CHUNKS]
        test rcx, rcx
        jz 5f
        mov rdx, [rbx + CTX_ARENA_CUR]  # what the current chunk got used for
        sub rdx, rcx
        sub rdx, CHUNK_DATA
        mov [rcx + CHUNK_USED], rdx
5:      mov [rax + CHUNK_NEXT], rcx
        mov [rax + CHUNK_SIZE], r12
        mov qword ptr [rax + CHUNK_USED], 0
        mov [rbx + CTX_ARENA_CHUNKS], rax
        lea rcx, [rax + CHUNK_DATA]
        mov [rbx + CTX_ARENA_CUR], rcx
        add rax, r12
        mov [rbx + CTX_ARENA_END], rax
        mov rax, [rbx + CTX_ARENA_TOTAL]
        add rax, r12
        mov [rbx + CTX_ARENA_TOTAL], rax
        cmp rax, [rbx + CTX_ARENA_PEAK]
        jbe 2f
        mov [rbx + CTX_ARENA_PEAK], rax
2:      add rsp, 16
        LEAVE
.Lchunk_limit:
        cmp rbx, r15
        jne 1b                          # (not the thread's own context: no handler to go to)
        mov edi, E_MEMORY
        lea rsi, [rip + .Lmsg_limit]
        call err_throw
.Lchunk_fail:
        # the system has no more (an address space limit, the machine's
        # memory): python's MemoryError where the context can take it -
        # its own, with a handler, and not in the middle of GMP's work
        cmp qword ptr [rsp], 0
        je 1f
        cmp rbx, r15
        jne 1f
        cmp qword ptr [r15 + CTX_ERR_BUF], 0
        je 1f
        mov edi, E_MEMORY
        lea rsi, [rip + .Lmsg_oom_throw]
        call err_throw
1:      lea rdi, [rip + .Lmsg_oom]
        call rt_fatal
ENDF arena_new_chunk

        .section .rodata
.Lmsg_oom: .asciz "panoramix-asm: out of memory (mmap failed)"
.Lmsg_oom_throw: .asciz "out of memory: the system gave no more (mmap failed)"
.Ls_env_poison: .asciz "PANORAMIX_POISON"
.Lmsg_limit: .asciz "out of memory: a function's memory limit was reached (PANORAMIX_MAX_MEMORY)"
.Lmsg_recursion: .asciz "maximum recursion depth exceeded"
        .text

# arena_alloc_ctx(ctx, size) -> rax: 16-byte aligned, zeroed memory
# (E_MEMORY past the context's limit)
FUNC arena_alloc_ctx
        mov edx, 1
        jmp arena_alloc_check
ENDF arena_alloc_ctx

# arena_alloc_nl(ctx, size) -> rax: 16-byte aligned, not zeroed, never
# past a limit (GMP's allocations: GMP can't be left in the middle of an
# operation)
FUNC arena_alloc_nl
        xor edx, edx
        jmp arena_alloc_check_raw
ENDF arena_alloc_nl

# arena_alloc_check(ctx, size, check) -> rax: zeroed. The chunks aren't
# (the pool's are what their last user left): the block is zeroed here,
# while it is in the cache anyway - most of the allocations are of nodes
# and vectors that are all written at once, and take arena_alloc_raw.
FUNC arena_alloc_check
        add rsi, 15
        and rsi, -16
        mov rax, [rdi + CTX_ARENA_CUR]
        lea rcx, [rax + rsi]
        cmp rcx, [rdi + CTX_ARENA_END]
        ja .Laa_slow
        mov [rdi + CTX_ARENA_CUR], rcx
.Laa_zero:                              # rsi bytes at rax, a multiple of 16
        cmp rsi, 512
        ja .Laa_big
        test rsi, rsi
        jz 2f
        mov rcx, rax
        xor edx, edx
1:      mov [rcx], rdx
        mov [rcx + 8], rdx
        add rcx, 16
        sub rsi, 16
        jnz 1b
2:      ret
.Laa_big:
        push rax                        # (and the stack aligned for the call)
        mov rdi, rax
        mov rdx, rsi
        xor esi, esi
        call memset@PLT
        pop rax
        ret
.Laa_slow:
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call arena_new_chunk            # (rdi, rsi, edx: the same)
        mov rax, [rbx + CTX_ARENA_CUR]
        lea rcx, [rax + r12]
        mov [rbx + CTX_ARENA_CUR], rcx
        mov rsi, r12
        LEAVE_NORET
        jmp .Laa_zero
ENDF arena_alloc_check

# arena_alloc_check_raw(ctx, size, check) -> rax: the same, not zeroed
FUNC arena_alloc_check_raw
        add rsi, 15
        and rsi, -16
        mov rax, [rdi + CTX_ARENA_CUR]
        lea rcx, [rax + rsi]
        cmp rcx, [rdi + CTX_ARENA_END]
        ja 1f
        mov [rdi + CTX_ARENA_CUR], rcx
        ret
1:      ENTER
        mov rbx, rdi
        mov r12, rsi
        call arena_new_chunk
        mov rax, [rbx + CTX_ARENA_CUR]
        lea rcx, [rax + r12]
        mov [rbx + CTX_ARENA_CUR], rcx
        LEAVE
ENDF arena_alloc_check_raw

# mem_limit_for(threads) -> rax: the bytes a function's context may take
# (CTX_MEM_LIMIT): PANORAMIX_MAX_MEMORY (MiB, 0 for no limit), else the
# memory of the machine (or of its cgroup) shared by the threads and the
# main one, 1 GiB at least. The worst functions of the corpora take
# ~300 MiB; this is for the inputs that would take it all (python has no
# limit, the kernel's OOM killer has one).
FUNC mem_limit_for
        ENTER
        sub rsp, 80
        mov rbx, rdi
        lea rdi, [rip + .Ls_env_maxmem]
        call getenv@PLT
        test rax, rax
        jz 1f
        mov rdi, rax
        xor esi, esi
        mov edx, 10
        call strtoull@PLT
        shl rax, 20
        jmp 9f
1:      mov edi, 85                     # _SC_PHYS_PAGES
        call sysconf@PLT
        mov r12, rax
        mov edi, 30                     # _SC_PAGESIZE
        call sysconf@PLT
        imul r12, rax
        # cgroup v2: memory.max, "max" or a number of bytes
        lea rdi, [rip + .Ls_cgroup_max]
        xor esi, esi                    # O_RDONLY
        xor eax, eax
        call open@PLT
        test eax, eax
        js 3f
        mov r13d, eax
        mov edi, eax
        mov rsi, rsp
        mov edx, 63
        call read@PLT
        mov r14, rax
        mov edi, r13d
        call close@PLT
        test r14, r14
        jle 3f
        mov byte ptr [rsp + r14], 0
        movzx eax, byte ptr [rsp]
        sub eax, '0'
        cmp eax, 9
        ja 3f                           # "max"
        mov rdi, rsp
        xor esi, esi
        mov edx, 10
        call strtoull@PLT
        test rax, rax
        jz 3f
        cmp rax, r12
        cmovb r12, rax
3:      lea rcx, [rbx + 1]
        mov rax, r12
        xor edx, edx
        div rcx
        mov ecx, 1 << 30
        cmp rax, rcx
        cmovb rax, rcx
9:      add rsp, 80
        LEAVE
ENDF mem_limit_for

        .section .rodata
.Ls_env_maxmem:  .asciz "PANORAMIX_MAX_MEMORY"
.Ls_cgroup_max:  .asciz "/sys/fs/cgroup/memory.max"
        .text

# chunk_map_huge() -> rax: a new chunk of the default size, aligned on
# 2 MiB and advised to be backed by huge pages (transparent huge pages:
# a fault per 2 MiB instead of per 4 KiB - the arenas are touched
# linearly and mostly used); 0 if the mapping failed
FUNC chunk_map_huge
        ENTER
        xor edi, edi
        mov esi, ARENA_CHUNK_DEFAULT + HUGE_PAGE
        mov edx, 3                      # PROT_READ | PROT_WRITE
        mov ecx, 0x22                   # MAP_PRIVATE | MAP_ANONYMOUS
        mov r8, -1
        xor r9d, r9d
        call mmap@PLT
        cmp rax, -1
        je 8f
        mov rbx, rax                    # the mapping
        lea r12, [rax + HUGE_PAGE - 1]
        and r12, -HUGE_PAGE             # the chunk, aligned
        mov rsi, r12
        sub rsi, rbx                    # the head to give back
        jz 1f
        mov rdi, rbx
        call munmap@PLT
1:      lea rdi, [r12 + ARENA_CHUNK_DEFAULT]
        lea rsi, [rbx + ARENA_CHUNK_DEFAULT + HUGE_PAGE]
        sub rsi, rdi                    # and the tail
        jz 2f
        call munmap@PLT
2:      mov rdi, r12
        mov esi, ARENA_CHUNK_DEFAULT
        mov edx, 14                     # MADV_HUGEPAGE (a hint: its failure changes nothing)
        call madvise@PLT
        mov rax, r12
        LEAVE
8:      xor eax, eax
        LEAVE
ENDF chunk_map_huge

# chunks_release(head, cur) -> rax: the bytes released. A context's chunks
# (a list, `head` the current one, bump-allocated up to `cur`) go back:
# those of the default size to the pool (as they are: arena_alloc zeroes),
# the others (and those past the pool's size) to the system.
FUNC chunks_release
        ENTER
        xor r14d, r14d                  # the bytes
        mov rbx, rdi
        test rbx, rbx
        jz 9f
        mov rax, rsi
        sub rax, rbx
        sub rax, CHUNK_DATA
        mov [rbx + CHUNK_USED], rax
1:      test rbx, rbx
        jz 9f
        mov r12, [rbx + CHUNK_NEXT]
        mov r13, [rbx + CHUNK_SIZE]
        add r14, r13
        cmp r13, ARENA_CHUNK_DEFAULT
        jne 2f
        cmp qword ptr [rip + chunk_pool_count], CHUNK_POOL_MAX
        jae 2f
        cmp byte ptr [rip + chunk_poison], 0
        je 4f
        # PANORAMIX_POISON (tests): garbage where the chunk was used, for
        # what would read memory it didn't write
        lea rdi, [rbx + CHUNK_DATA]
        mov esi, 0xa5
        mov rdx, [rbx + CHUNK_USED]
        mov rax, ARENA_CHUNK_DEFAULT - CHUNK_DATA
        cmp rdx, rax
        cmova rdx, rax
        call memset@PLT
4:      mov rdi, rbx
        call pool_push
        jmp 3f
2:      mov rdi, rbx
        mov rsi, r13
        call munmap@PLT
3:      mov rbx, r12
        jmp 1b
9:      mov rax, r14
        LEAVE
ENDF chunks_release

# the pool's lock: a spinlock (held for a few instructions)
.macro POOL_LOCK
        mov eax, 1
.Lpl_spin\@:
        xchg eax, [rip + chunk_pool_lock]
        test eax, eax
        jz .Lpl_got\@
        pause
        mov eax, 1
        jmp .Lpl_spin\@
.Lpl_got\@:
.endm
.macro POOL_UNLOCK
        mov dword ptr [rip + chunk_pool_lock], 0
.endm

# pool_pop() -> rax: a chunk of the default size (not zeroed), or 0
FUNC pool_pop
        POOL_LOCK
        mov rax, [rip + chunk_pool]
        test rax, rax
        jz 1f
        mov rcx, [rax + CHUNK_NEXT]
        mov [rip + chunk_pool], rcx
        dec qword ptr [rip + chunk_pool_count]
1:      POOL_UNLOCK
        ret
ENDF pool_pop

# pool_push(chunk): into the pool
FUNC pool_push
        POOL_LOCK
        mov rax, [rip + chunk_pool]
        mov [rdi + CHUNK_NEXT], rax
        mov [rip + chunk_pool], rdi
        inc qword ptr [rip + chunk_pool_count]
        POOL_UNLOCK
        ret
ENDF pool_push

# chunk_pool_trim(keep): the pool's chunks past `keep` back to the system
FUNC chunk_pool_trim
        ENTER
        mov rbx, rdi
1:      cmp [rip + chunk_pool_count], rbx
        jbe 2f
        call pool_pop
        test rax, rax
        jz 2f
        mov rdi, rax
        mov esi, ARENA_CHUNK_DEFAULT
        call munmap@PLT
        jmp 1b
2:      LEAVE
ENDF chunk_pool_trim

# stack_overflow(): where STACK_CHECK goes (python's RecursionError, or
# the watchdog's timeout: see rt_watch.s)
FUNC stack_overflow
        call watch_expired
        mov edi, E_RECURSION
        lea rsi, [rip + .Lmsg_recursion]
        jmp err_throw
ENDF stack_overflow

# ctx_set_stack(): CTX_STACK_LOW of r15 from the calling thread's stack
# (the recursions throw E_RECURSION a margin above its end)
FUNC ctx_set_stack
        ENTER
        sub rsp, 80                     # a pthread_attr_t (56 bytes), the stack's address and size
        call pthread_self@PLT
        mov rdi, rax
        mov rsi, rsp
        call pthread_getattr_np@PLT
        test eax, eax
        jnz 9f
        mov rdi, rsp
        lea rsi, [rsp + 64]
        lea rdx, [rsp + 72]
        call pthread_attr_getstack@PLT
        mov ebx, eax
        mov rdi, rsp
        call pthread_attr_destroy@PLT
        test ebx, ebx
        jnz 9f
        mov rax, [rsp + 64]             # the lowest address
        mov rcx, [rsp + 72]
        cmp rcx, 4 * STACK_MARGIN
        jb 9f                           # (a small stack: no check rather than a wrong one)
        add rax, STACK_MARGIN
        mov [r15 + CTX_STACK_LOW], rax
9:      add rsp, 80
        LEAVE
ENDF ctx_set_stack

# arena_alloc(size) -> rax, on the r15 context: zeroed memory
FUNC arena_alloc
        mov rsi, rdi
        mov rdi, r15
        jmp arena_alloc_ctx
ENDF arena_alloc

# arena_alloc_raw(size) -> rax, on the r15 context: memory the caller
# writes all of (not zeroed)
FUNC arena_alloc_raw
        mov rsi, rdi
        mov rdi, r15
        mov edx, 1
        jmp arena_alloc_check_raw
ENDF arena_alloc_raw


# ctx_compact(root) -> rax: the root copied into a fresh arena and
# hash-cons table, and everything else of the context's arena freed - the
# garbage of the rewrites, when the root (the trace being simplified) is
# all that is live. The memo tables go with the arena (they are caches),
# the scratch mpz are made again.
FUNC ctx_compact
        ENTER
        .set CC_MEMOS, 16               # the old memo tables
        .set CC_OLD, CC_MEMOS + MEMO_COUNT * 8  # the old arena's end, total, table's cap, count, nodes
        .set CC_ERR, CC_OLD + 48        # a handler: an error midway puts the old arena back
        .set CC_FRAME, (CC_ERR + ERR_SIZEOF + 15) & -16
        sub rsp, CC_FRAME
        .set CC_FREED, 0
        .set CC_SLOT, 8
        mov rbx, rdi
        mov r12, [r15 + CTX_ARENA_CHUNKS]      # the old chunks
        mov r13, [r15 + CTX_HC_TABLE]          # the old table
        mov r14, [r15 + CTX_ARENA_CUR]         # (how much of the current one got used)
        mov rax, [r15 + CTX_ARENA_END]
        mov [rsp + CC_OLD], rax
        mov rax, [r15 + CTX_ARENA_TOTAL]
        mov [rsp + CC_OLD + 8], rax
        mov rax, [r15 + CTX_HC_CAP]
        mov [rsp + CC_OLD + 16], rax
        mov rax, [r15 + CTX_HC_COUNT]
        mov [rsp + CC_OLD + 24], rax
        mov rax, [r15 + CTX_NODE_COUNT]
        mov [rsp + CC_OLD + 32], rax
        mov rax, [r15 + CTX_RFM_MAP]
        mov [rsp + CC_OLD + 40], rax
        mov qword ptr [r15 + CTX_ARENA_CHUNKS], 0
        mov qword ptr [r15 + CTX_ARENA_CUR], 0
        mov qword ptr [r15 + CTX_ARENA_END], 0
        mov qword ptr [r15 + CTX_ARENA_TOTAL], 0
        mov edi, 4096
        mov esi, 8
        call xcalloc
        mov [r15 + CTX_HC_TABLE], rax
        mov qword ptr [r15 + CTX_HC_CAP], 4096
        mov qword ptr [r15 + CTX_HC_COUNT], 0
        mov qword ptr [r15 + CTX_NODE_COUNT], 0
        call memo_sizes_log
        lea rdi, [rsp + CC_MEMOS]
        lea rsi, [r15 + CTX_MEMO]
        mov edx, MEMO_COUNT * 8
        call memcpy@PLT
        lea rdi, [r15 + CTX_MEMO]
        xor esi, esi
        mov edx, MEMO_COUNT * 8
        call memset@PLT
        call ctx_init_mpz
        # the imports can throw (the recursion, the memory limit, the
        # watchdog's timeout): then the new arena goes, the old one stays
        lea rdi, [rsp + CC_ERR]
        call err_catch
        test eax, eax
        jnz .Lcc_rollback
        mov rdi, rbx
        call value_import
        mov rbx, rax
        # the memo tables worth keeping (see memo_kinds) are imported too:
        # what they remember is recomputed dearly (the comparisons)
        mov qword ptr [rsp + CC_SLOT], 0
1:      mov rcx, [rsp + CC_SLOT]
        cmp rcx, MEMO_COUNT
        jae 2f
        lea rax, [rip + memo_kinds]
        movzx esi, byte ptr [rax + rcx]
        mov rdx, [rsp + CC_MEMOS + rcx*8]
        mov rdi, rcx
        call memo_import
        inc qword ptr [rsp + CC_SLOT]
        jmp 1b
2:      call err_end
        # (the import's memo holds the old addresses: gone with them;
        # replace_f_memo's map was in the old arena)
        mov qword ptr [r15 + CTX_MEMO + MEMO_IMPORT * 8], 0
        mov qword ptr [r15 + CTX_RFM_MAP], 0
        mov rdi, r12
        mov rsi, r14
        call chunks_release
        mov [rsp + CC_FREED], rax
        mov rdi, r13
        call free@PLT
        mov edi, LOG_DEBUG
        lea rsi, [rip + .Ls_mem_logname]
        lea rdx, [rip + .Ls_compacted]
        mov rcx, [rsp + CC_FREED]
        shr rcx, 20
        mov r8, [r15 + CTX_ARENA_TOTAL]
        shr r8, 20
        call log_fmt
        mov rax, rbx
        add rsp, CC_FRAME
        LEAVE
.Lcc_rollback:
        mov [rsp + CC_FREED], rax       # the error's code
        mov rdi, [r15 + CTX_ARENA_CHUNKS]
        mov rsi, [r15 + CTX_ARENA_CUR]
        call chunks_release
        mov rdi, [r15 + CTX_HC_TABLE]
        call free@PLT
        mov [r15 + CTX_ARENA_CHUNKS], r12      # (r12, r13, r14: as they were
        mov [r15 + CTX_HC_TABLE], r13          # at err_catch)
        mov [r15 + CTX_ARENA_CUR], r14
        mov rax, [rsp + CC_OLD]
        mov [r15 + CTX_ARENA_END], rax
        mov rax, [rsp + CC_OLD + 8]
        mov [r15 + CTX_ARENA_TOTAL], rax
        mov rax, [rsp + CC_OLD + 16]
        mov [r15 + CTX_HC_CAP], rax
        mov rax, [rsp + CC_OLD + 24]
        mov [r15 + CTX_HC_COUNT], rax
        mov rax, [rsp + CC_OLD + 32]
        mov [r15 + CTX_NODE_COUNT], rax
        mov rax, [rsp + CC_OLD + 40]
        mov [r15 + CTX_RFM_MAP], rax
        lea rdi, [r15 + CTX_MEMO]
        lea rsi, [rsp + CC_MEMOS]
        mov edx, MEMO_COUNT * 8
        call memcpy@PLT
        call ctx_init_mpz               # (the scratches were made in the new arena)
        mov edi, LOG_DEBUG
        lea rsi, [rip + .Ls_mem_logname]
        lea rdx, [rip + .Ls_compact_undone]
        call log_fmt
        mov rdi, [rsp + CC_FREED]
        mov rsi, [r15 + CTX_ERR_MSG]
        call err_throw
ENDF ctx_compact

        .section .rodata
.Ls_compact_undone: .asciz "compaction interrupted: the old arena kept"
        .text

# memo_import(slot, kind, old_map): the entries of a memo table of the old
# arena put into the context's new table, keys and values imported
# (kind 1), or the keys imported and the values kept as they are (kind 2:
# codes, MEMO_TRUE and the like; kind 3: the same for a table of pairs,
# see memo2_get); kind 0: dropped
FUNC memo_import
        ENTER
        sub rsp, 16
        test esi, esi
        jz 3f
        test rdx, rdx
        jz 3f
        cmp esi, 3
        je memo_import_pairs
        mov rbx, rdi                    # slot
        mov r12d, esi                   # kind
        mov r13, rdx                    # the old map
        xor r14d, r14d                  # the entry
1:      cmp r14, [r13 + MAP_CAP]
        jae 3f
        mov rax, [r13 + MAP_ENTRIES]
        mov rcx, r14
        shl rcx, 4                      # 16 bytes per entry
        mov rdi, [rax + rcx]            # key
        test rdi, rdi
        jz 2f
        mov rsi, [rax + rcx + 8]        # value
        mov [rsp], rsi
        call value_import
        mov [rsp + 8], rax              # the key, imported
        mov rdi, [rsp]
        cmp r12d, 2
        je 4f
        cmp rdi, 16
        jb 4f                           # (a code in a table of values: MEMO_NONE)
        call value_import
        mov rdi, rax
4:      mov rdx, rdi
        mov rdi, rbx
        mov rsi, [rsp + 8]
        call memo_put
2:      inc r14
        jmp 1b
3:      add rsp, 16
        LEAVE
ENDF memo_import

# memo_import_pairs: memo_import's kind 3 (jumped to, its frame as it is)
FUNC memo_import_pairs
        mov rbx, rdi                    # slot
        mov r13, rdx                    # the old map
        xor r14d, r14d                  # the entry
1:      cmp r14, [r13 + MAP_CAP]
        jae 3f
        mov rax, [r13 + MAP_ENTRIES]
        mov rcx, r14
        shl rcx, 5                      # 32 bytes per entry
        mov rdi, [rax + rcx]            # k1
        test rdi, rdi
        jz 2f
        call value_import
        mov [rsp], rax
        mov rax, [r13 + MAP_ENTRIES]
        mov rcx, r14
        shl rcx, 5
        mov rdi, [rax + rcx + 8]        # k2
        call value_import
        mov [rsp + 8], rax
        mov rax, [r13 + MAP_ENTRIES]
        mov rcx, r14
        shl rcx, 5
        mov rcx, [rax + rcx + 16]       # the value, a code
        mov rdi, rbx
        mov rsi, [rsp]
        mov rdx, [rsp + 8]
        call memo2_put
2:      inc r14
        jmp 1b
3:      add rsp, 16
        LEAVE
ENDF memo_import_pairs

        .section .rodata
        # what ctx_compact does with each memo table (MEMO_* order)
memo_kinds:
        .byte 0                         # SIMPLIFY: values
        .byte 2                         # GE_ZERO: codes
        .byte 3                         # LT (pairs)
        .byte 3                         # LE (pairs)
        .byte 0                         # MASK
        .byte 0                         # ADD
        .byte 0                         # TO_MASK (values, or MEMO_NONE)
        .byte 2                         # ADD_GE_ZERO
        .byte 0                         # STACK_SIMPLIFY: the VM is over
        .byte 0                         # TEST_NODES
        .byte 0                         # SIMPLIFY_EXP
        .byte 0                         # FIND_MEMS
        .byte 0                         # REPLACE_MEM_EXP
        .byte 3                         # RANGE_OVERLAPS (pairs)
        .byte 0                         # SIGDB
        .byte 0                         # IMPORT: the import's own
        .byte 0                         # LINE_VARS
        .byte 0                         # TRY_ADD (pairs)
        .byte 0                         # MUL2 (pairs)
        .text

# memo_sizes_log(): DEBUG: the number of entries of every memo table
FUNC memo_sizes_log
        ENTER
        xor ebx, ebx
1:      cmp ebx, MEMO_COUNT
        jae 2f
        mov rax, [r15 + CTX_MEMO + rbx*8]
        test rax, rax
        jz 3f
        mov edi, LOG_DEBUG
        lea rsi, [rip + .Ls_mem_logname]
        lea rdx, [rip + .Ls_memo_size]
        mov rcx, rbx
        mov r8, [rax + MAP_COUNT]
        call log_fmt
3:      inc ebx
        jmp 1b
2:      LEAVE
ENDF memo_sizes_log

        .section .rodata
.Ls_memo_size:   .asciz "memo %u: %u entries"
        .text

        .section .rodata
.Ls_mem_logname: .asciz "panoramix.memory"
.Ls_compacted:   .asciz "arena compacted: %u MiB freed, %u MiB live"
        .text

# ctx_init_mpz(): the context's scratch mpz (r15), their limbs in its arena
FUNC ctx_init_mpz
        ENTER
        lea rdi, [r15 + CTX_MPZ_A]
        call __gmpz_init@PLT
        lea rdi, [r15 + CTX_MPZ_B]
        call __gmpz_init@PLT
        lea rdi, [r15 + CTX_MPZ_R]
        call __gmpz_init@PLT
        lea rdi, [r15 + CTX_MPZ_T]
        call __gmpz_init@PLT
        xor r12d, r12d
1:      cmp r12d, EVAL_POOL_DEPTH
        jae 2f
        mov rax, r12
        shl rax, 4
        lea rdi, [r15 + CTX_EVAL_POOL + rax]
        mov esi, 512                    # bits: the variants' numbers, mostly
        call __gmpz_init2@PLT
        inc r12d
        jmp 1b
2:      xor r12d, r12d
3:      cmp r12d, 8
        jae 4f
        mov rax, r12
        shl rax, 4
        lea rdi, [r15 + CTX_AGZ + rax]
        mov esi, 512
        call __gmpz_init2@PLT
        inc r12d
        jmp 3b
4:      LEAVE
ENDF ctx_init_mpz

# --- GMP memory callbacks (C ABI, context from the pthread key) ---

FUNC gmp_alloc
        ENTER
        mov rbx, rdi
        call ctx_current
        mov rdi, rax
        mov rsi, rbx
        call arena_alloc_nl
        LEAVE
ENDF gmp_alloc

# gmp_realloc(ptr, old_size, new_size)
FUNC gmp_realloc
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        call ctx_current
        mov rdi, rax
        mov rsi, r13
        call arena_alloc_nl
        mov r14, rax
        mov rdi, rax
        mov rsi, rbx
        mov rdx, r12
        cmp r12, r13
        cmova rdx, r13
        call memcpy@PLT
        mov rax, r14
        LEAVE
ENDF gmp_realloc

FUNC gmp_free
        ret
ENDF gmp_free

# xmalloc(size) / xcalloc(n, size) / xrealloc(ptr, size): the C
# allocator's, a fatal "out of memory" instead of a NULL (for what lives
# outside the arenas: the contexts, the hash-cons and string tables, the
# loader, the signature database)
FUNC xmalloc
        push rdi
        call malloc@PLT
        pop rdi
        test rax, rax
        jz xalloc_failed
        ret
ENDF xmalloc

FUNC xcalloc
        push rdi
        call calloc@PLT
        pop rdi
        test rax, rax
        jz xalloc_failed
        ret
ENDF xcalloc

FUNC xrealloc
        push rdi
        call realloc@PLT
        pop rdi
        test rax, rax
        jz xalloc_failed
        ret
ENDF xrealloc

FUNC xalloc_failed
        sub rsp, 8
        lea rdi, [rip + .Lmsg_xalloc]
        call rt_fatal
ENDF xalloc_failed

        .section .rodata
.Lmsg_xalloc: .asciz "panoramix-asm: out of memory (malloc failed)"
        .text

# rt_fatal(msg): print and abort
FUNC rt_fatal
        ENTER
        mov rbx, rdi
        mov rdi, [rip + stderr@GOTPCREL]
        mov rdi, [rdi]
        lea rsi, [rip + .Lfatal_fmt]
        mov rdx, rbx
        xor eax, eax
        call fprintf@PLT
        call abort@PLT
ENDF rt_fatal

        .section .rodata
.Lfatal_fmt: .asciz "%s\n"
        .section .note.GNU-stack,"",@progbits
