# DEDUP_KSM: the tuples and lists of a function's context made as they
# are, and their duplicates merged by a thread of its own - as UKSM merges
# the pages of a process behind its back, but object by object: the
# program knows where each one is, its kind, its size and its hash, where
# UKSM has to hash pages to find them.
#
# mk_seq puts each node it makes on its context's queue (a ring the
# context's thread writes and the merging thread reads; full, a node is
# left out: it is merged when it is first compared, see canon). The
# merging thread takes the nodes in the order they were made - the
# elements of a node before it - and gives each its canonical node
# (N_CANON): the one equal to it in the context's hash-cons table, or the
# node itself, put there. A node whose elements aren't all merged yet is
# left to canon. The table is shared without a lock - its slots are only
# ever filled, with a compare-and-swap - and grown by the context's
# thread alone, the merging one kept away meanwhile.
#
# A context is left alone while it is compacted or freed: its thread sets
# KQ_BLOCKED (a count) and waits for KQ_ACTIVE to go, and the merging
# thread sets KQ_ACTIVE, then looks at KQ_BLOCKED - Dekker's, the writes
# locked instructions (full barriers) both ways.

.include "defs.inc"

        .set KQ_SIZE, 1 << 16           # the nodes a queue holds
        .set KQ_HEAD, 0                 # the next to write (the context's thread)
        .set KQ_TAIL, 64                # the next to read (the merging thread)
        .set KQ_ACTIVE, 128             # the merging thread is at the context
        .set KQ_BLOCKED, 192            # the context's thread wants it left alone
        .set KQ_MERGED, 256             # (counts: nodes given their canonical one,
        .set KQ_LATER, 264              #   left to canon, lost to a full queue)
        .set KQ_DROPPED, 272
        .set KQ_BUF, 320
        .set KQ_SIZEOF, KQ_BUF + KQ_SIZE * 8
        .set KSM_MAX, 256               # the contexts registered at once
        .set KSM_BATCH, 1024            # the nodes taken from a queue at a time
        .set KSM_NAP, 500000            # ns: the pause when all queues are empty

        .section .bss
        .align 64
ksm_ctxs:       .skip KSM_MAX * 8
ksm_n:          .quad 0
ksm_started:    .quad 0
ksm_mutex:      .skip 64                # (PTHREAD_MUTEX_INITIALIZER: zeros)
ksm_tid:        .quad 0
        .section .data
ksm_lag:        .quad 0

        .section .rodata
.Ls_logname:    .asciz "panoramix.ksm"
.Ls_env_lag:    .asciz "PANORAMIX_KSM_LAG"
.Ls_stats:      .asciz "merged %u nodes by the thread, %u left to canon, %u not queued"
        .text

# ksm_register(ctx): the context's nodes merged by the thread from now on
# (DEDUP_LAZY instead when a queue can't be had)
FUNC ksm_register
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov rdi, rsp
        mov esi, 64
        mov edx, KQ_SIZEOF
        call posix_memalign@PLT
        test eax, eax
        jnz 8f
        mov r12, [rsp]
        mov rdi, r12
        xor esi, esi
        mov edx, KQ_BUF
        call memset@PLT
        lea rdi, [rip + ksm_mutex]
        call pthread_mutex_lock@PLT
        mov rax, [rip + ksm_n]
        cmp rax, KSM_MAX
        jae 7f
        lea rcx, [rip + ksm_ctxs]
        mov [rcx + rax*8], rbx
        inc rax
        mov [rip + ksm_n], rax
        mov [rbx + CTX_KSMQ], r12
        cmp qword ptr [rbx + CTX_DEDUP], DEDUP_DEFER
        je 1f                           # (merged by the context's thread)
        cmp qword ptr [rip + ksm_started], 0
        jne 1f
        lea rdi, [rip + .Ls_env_lag]    # (experiments)
        call getenv@PLT
        test rax, rax
        jz 5f
        mov rdi, rax
        call atol@PLT
        mov [rip + ksm_lag], rax
5:      lea rdi, [rip + ksm_tid]
        xor esi, esi
        lea rdx, [rip + ksm_main]
        xor ecx, ecx
        call pthread_create@PLT
        test eax, eax
        jnz 6f
        mov rdi, [rip + ksm_tid]
        call pthread_detach@PLT
        mov qword ptr [rip + ksm_started], 1
1:      lea rdi, [rip + ksm_mutex]
        call pthread_mutex_unlock@PLT
        add rsp, 16
        LEAVE
6:      # (no thread: undone, lazy)
        dec qword ptr [rip + ksm_n]
        mov qword ptr [rbx + CTX_KSMQ], 0
7:      lea rdi, [rip + ksm_mutex]
        call pthread_mutex_unlock@PLT
        mov rdi, r12
        call free@PLT
8:      mov qword ptr [rbx + CTX_DEDUP], DEDUP_LAZY
        add rsp, 16
        LEAVE
ENDF ksm_register

# ksm_unregister(ctx): the thread done with the context (before it is
# freed); its counts logged (DEBUG)
FUNC ksm_unregister
        ENTER
        mov rbx, rdi
        mov r12, [rbx + CTX_KSMQ]
        test r12, r12
        jz 9f
        call ksm_block
        lea rdi, [rip + ksm_mutex]
        call pthread_mutex_lock@PLT
        lea rcx, [rip + ksm_ctxs]
        mov rdx, [rip + ksm_n]
        xor eax, eax
1:      cmp rax, rdx
        jae 3f
        cmp [rcx + rax*8], rbx
        je 2f
        inc rax
        jmp 1b
2:      mov rsi, [rcx + rdx*8 - 8]      # (the last one in its place)
        mov [rcx + rax*8], rsi
        dec qword ptr [rip + ksm_n]
3:      lea rdi, [rip + ksm_mutex]
        call pthread_mutex_unlock@PLT
        mov edi, LOG_DEBUG
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_stats]
        mov rcx, [r12 + KQ_MERGED]
        mov r8, [r12 + KQ_LATER]
        mov r9, [r12 + KQ_DROPPED]
        call log_fmt
        mov qword ptr [rbx + CTX_KSMQ], 0
        mov rdi, r12
        call free@PLT
9:      LEAVE
ENDF ksm_unregister

# ksm_block(ctx): the merging thread kept away from the context (it
# finishes the node it is at) - a count: a table grown during a
# compaction keeps it away until the compaction is done; ksm_unblock(ctx):
# back, the queue emptied (its nodes may be gone: a compaction - and
# those made meanwhile are of the new arena, a table they'd go in being
# the new one or, rolled back, the old one)
FUNC ksm_block
        mov rcx, [rdi + CTX_KSMQ]
        test rcx, rcx
        jz 2f
        lock inc qword ptr [rcx + KQ_BLOCKED]
1:      cmp qword ptr [rcx + KQ_ACTIVE], 0
        je 2f
        pause
        jmp 1b
2:      ret
ENDF ksm_block

# ksm_resume(ctx): back, the queue kept (the table grown)
FUNC ksm_resume
        mov rcx, [rdi + CTX_KSMQ]
        test rcx, rcx
        jz 1f
        lock dec qword ptr [rcx + KQ_BLOCKED]
1:      ret
ENDF ksm_resume

# hc_grow_shared(): hc_grow, the merging thread kept away meanwhile (it
# reads the table and puts nodes there: see hc_find_or_insert)
FUNC hc_grow_shared
        cmp qword ptr [r15 + CTX_KSMQ], 0
        jne 1f
        jmp hc_grow
1:      ENTER
        mov rdi, r15
        call ksm_block
        call hc_grow                    # (if it throws, the thread stays
        mov rdi, r15                    # away: canon merges them)
        call ksm_resume
        LEAVE
ENDF hc_grow_shared

FUNC ksm_unblock
        mov rcx, [rdi + CTX_KSMQ]
        test rcx, rcx
        jz 1f
        mov rax, [rcx + KQ_HEAD]
        mov rdx, rax
        sub rdx, [rcx + KQ_TAIL]
        add [rcx + KQ_DROPPED], rdx
        mov [rcx + KQ_TAIL], rax
        lock dec qword ptr [rcx + KQ_BLOCKED]
1:      ret
ENDF ksm_unblock

# ksm_main(): the merging thread - the queues in turn, a batch each; a
# pause when they are all empty
FUNC ksm_main
        push rbp
        mov rbp, rsp
        push rbx
        push r12
        push r13
        push r14
        push r15
        sub rsp, 24
        .set KM_I, 0
        .set KM_WORKED, 8
.Lkm_round:
        mov qword ptr [rsp + KM_WORKED], 0
        mov qword ptr [rsp + KM_I], 0
.Lkm_next:
        lea rdi, [rip + ksm_mutex]
        call pthread_mutex_lock@PLT
        mov rax, [rsp + KM_I]
        cmp rax, [rip + ksm_n]
        jae .Lkm_end
        lea rcx, [rip + ksm_ctxs]
        mov r15, [rcx + rax*8]          # the context
        mov rbx, [r15 + CTX_KSMQ]
        mov eax, 1
        xchg [rbx + KQ_ACTIVE], rax
        cmp qword ptr [rbx + KQ_BLOCKED], 0
        je 1f
        mov qword ptr [rbx + KQ_ACTIVE], 0
        lea rdi, [rip + ksm_mutex]
        call pthread_mutex_unlock@PLT
        jmp .Lkm_skip
1:      lea rdi, [rip + ksm_mutex]
        call pthread_mutex_unlock@PLT
        # a batch
        mov r12, [rbx + KQ_TAIL]
        mov r13, [rbx + KQ_HEAD]
        sub r13, [rip + ksm_lag]        # (the nodes the thread is still at left alone)
        lea rax, [r12 + KSM_BATCH]
        cmp r13, rax
        cmovg r13, rax
2:      cmp r12, r13
        jge 3f
        cmp qword ptr [rbx + KQ_BLOCKED], 0     # (wanted away: the batch cut short)
        jne 3f
        mov qword ptr [rsp + KM_WORKED], 1
        mov rax, r12
        and eax, KQ_SIZE - 1
        mov rdi, [rbx + KQ_BUF + rax*8]
        call ksm_merge
        add [rbx + KQ_MERGED], rax
        xor eax, 1
        add [rbx + KQ_LATER], rax
        inc r12
        mov [rbx + KQ_TAIL], r12
        jmp 2b
3:      mov qword ptr [rbx + KQ_ACTIVE], 0
.Lkm_skip:
        inc qword ptr [rsp + KM_I]
        jmp .Lkm_next
.Lkm_end:
        lea rdi, [rip + ksm_mutex]
        call pthread_mutex_unlock@PLT
        cmp qword ptr [rsp + KM_WORKED], 0
        jne .Lkm_round
        # nothing to do: a pause
        sub rsp, 16
        mov qword ptr [rsp], 0
        mov qword ptr [rsp + 8], KSM_NAP
        mov rdi, rsp
        xor esi, esi
        call nanosleep@PLT
        add rsp, 16
        jmp .Lkm_round
ENDF ksm_main

# ksm_drain(n): (DEDUP_DEFER) the n oldest nodes of r15's queue merged
# here, as the thread would - a deterministic stand-in for it, the nodes
# merged after they are made and used
FUNC ksm_drain
        ENTER
        mov rbx, [r15 + CTX_KSMQ]
        cmp qword ptr [rbx + KQ_BLOCKED], 0     # (as the thread: not while
        jne 2f                                  # the table is replaced)
        mov r12, [rbx + KQ_TAIL]
        lea r13, [r12 + rdi]
        cmp r13, [rbx + KQ_HEAD]
        cmova r13, [rbx + KQ_HEAD]
1:      cmp r12, r13
        jae 2f
        mov rax, r12
        and eax, KQ_SIZE - 1
        mov rdi, [rbx + KQ_BUF + rax*8]
        call ksm_merge
        inc r12
        mov [rbx + KQ_TAIL], r12
        jmp 1b
2:      LEAVE
ENDF ksm_drain

# ksm_merge(v) -> eax: 1 when the node v (r15: its context) has its
# canonical node now, 0 when it is left to canon (an element not merged
# yet, a table to grow first)
FUNC ksm_merge
        ENTER
        sub rsp, 16
        mov rbx, rdi
        cmp qword ptr [rbx + N_CANON], 0
        jne .Lkx_yes
        # its elements merged already? (their canonical nodes put in it)
        mov r12d, [rbx + N_AUX]
        xor r13d, r13d
1:      cmp r13, r12
        jae 3f
        mov rdi, [rbx + N_DATA + r13*8]
        inc r13
        test dil, 1
        jnz 1b
        test rdi, rdi
        jz 1b
        mov eax, [rdi + N_KIND]
        cmp eax, K_TUPLE
        je 2f
        cmp eax, K_LIST
        jne 1b
2:      mov rax, [rdi + N_CANON]
        test rax, rax
        jz .Lkx_no
        cmp rax, rdi                    # (written only when it changes:
        je 1b                           # the line the other thread reads)
        mov [rbx + N_DATA + r13*8 - 8], rax
        jmp 1b
3:      mov rax, [r15 + CTX_HC_COUNT]
        shl rax, 1
        cmp rax, [r15 + CTX_HC_CAP]
        jae .Lkx_no                     # (the table to grow: canon's)
        mov rdi, rbx
        call hc_find_or_insert
        mov [rbx + N_CANON], rax
.Lkx_yes:
        mov eax, 1
        add rsp, 16
        LEAVE
.Lkx_no:
        xor eax, eax
        add rsp, 16
        LEAVE
ENDF ksm_merge

        .section .note.GNU-stack,"",@progbits
