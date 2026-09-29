# Nodes: tagged values, tuples/lists (hash-consed), big ints (GMP).

.include "defs.inc"

        .text

# hash_mix(rdi) -> rax. Murmur3's 64-bit finalizer. Clobbers rcx.
FUNC hash_mix
        mov rax, rdi
        mov rcx, rax
        shr rcx, 33
        xor rax, rcx
        movabs rcx, 0xff51afd7ed558ccd
        imul rax, rcx
        mov rcx, rax
        shr rcx, 33
        xor rax, rcx
        movabs rcx, 0xc4ceb9fe1a85ec53
        imul rax, rcx
        mov rcx, rax
        shr rcx, 33
        xor rax, rcx
        ret
ENDF hash_mix

# value_hash(rdi) -> rax. Clobbers rcx.
FUNC value_hash
        test dil, 1
        jz 1f
        jmp hash_mix
1:      test rdi, rdi
        jz 2f
        mov rax, [rdi + N_HASH]
        ret
2:      movabs rax, 0x9e3779b97f4a7c15
        ret
ENDF value_hash

# hash_seq(kind, count, elems) -> rax: the hash, its top byte the mention
# flags (HF_*) of the elements. A node's hash is read from it, a small
# int is mixed inline, and the chain is finalized once (Murmur3's
# finalizer): the elements are hashed in a few instructions each, which
# matters as every tuple and list goes through here. A long sequence
# goes to the vector loop of the machine (rt_simd.s), when it has one.
FUNC hash_seq
        cmp rsi, [rip + hash_seq_vec_min]
        jae 9f
        movabs rax, 0x9e3779b97f4a7c15
        imul rax, rdi
        xor rax, rsi                    # (kind, count)
        xor edi, edi                    # no flags yet
        xor ecx, ecx                    # from the first element
        jmp hash_seq_tail
9:      jmp [rip + hash_seq_vec]
ENDF hash_seq

# hash_seq_tail(rax: the hash so far, rdi: the flags so far, rcx: the
# first element left, rsi: count, rdx: elems) -> rax: the scalar loop
# over the elements left, then the finalizer
FUNC hash_seq_tail
        movabs r9, 0xc4ceb9fe1a85ec53
        mov r10, rdi                    # the flags
        mov r11, HF_MASK
1:      cmp rcx, rsi
        jae 4f
        mov rdi, [rdx + rcx*8]
        test dil, 1
        jz 2f
        movabs r8, 0xff51afd7ed558ccd
        imul rdi, r8                    # a small int: mixed inline
        jmp 3f
2:      test rdi, rdi
        jz 3f                           # NIL hashes as 0
        mov rdi, [rdi + N_HASH]
        mov r8, rdi
        and r8, r11
        or r10, r8                      # its flags
3:      xor rax, rdi
        imul rax, r9
        rol rax, 31
        inc rcx
        jmp 1b
4:      # the finalizer
        mov rcx, rax
        shr rcx, 33
        xor rax, rcx
        movabs r8, 0xff51afd7ed558ccd
        imul rax, r8
        mov rcx, rax
        shr rcx, 33
        xor rax, rcx
        imul rax, r9
        mov rcx, rax
        shr rcx, 33
        xor rax, rcx
        not r11
        and rax, r11
        or rax, r10
        ret
ENDF hash_seq_tail

# values_equal(a, b) -> eax 0/1. Pointer equality, except big ints which
# are compared by value.
FUNC values_equal
        cmp rdi, rsi
        je .Lveq_yes
        test dil, 1
        jnz .Lveq_no
        test sil, 1
        jnz .Lveq_no
        test rdi, rdi
        jz .Lveq_no
        test rsi, rsi
        jz .Lveq_no
        mov eax, [rdi + N_KIND]
        cmp eax, [rsi + N_KIND]
        jne .Lveq_no
        cmp eax, K_TUPLE
        je .Lveq_seq
        cmp eax, K_LIST
        je .Lveq_seq
        cmp eax, K_INT
        jne .Lveq_no
        mov rax, [rdi + N_HASH]
        cmp rax, [rsi + N_HASH]
        jne .Lveq_no
        ENTER
        add rdi, N_DATA
        add rsi, N_DATA
        call __gmpz_cmp@PLT
        test eax, eax
        sete al
        movzx eax, al
        LEAVE
.Lveq_yes:
        mov eax, 1
        ret
.Lveq_no:
        xor eax, eax
        ret
.Lveq_seq:
        cmp qword ptr [r15 + CTX_DEDUP], DEDUP_EAGER
        je .Lveq_no                     # (hash-consed: different pointers, different)
        mov rax, [rdi + N_HASH]
        cmp rax, [rsi + N_HASH]
        jne .Lveq_no
        mov eax, [rdi + N_AUX]
        cmp eax, [rsi + N_AUX]
        jne .Lveq_no
        push rbx
        call canon
        mov rbx, rax
        mov rdi, rsi
        call canon
        cmp rax, rbx
        pop rbx
        sete al
        movzx eax, al
        ret
ENDF values_equal

# seq_equal(node, kind, count, elems) -> eax: does the tuple/list node hold
# exactly these elements?
FUNC seq_equal
        cmp [rdi + N_KIND], esi
        jne .Lseq_no
        cmp [rdi + N_AUX], edx
        jne .Lseq_no
        xor eax, eax
1:      cmp rax, rdx
        jae .Lseq_yes
        mov r8, [rdi + N_DATA + rax*8]
        mov r9, [rcx + rax*8]
        inc rax
        cmp r8, r9
        je 1b
        # different pointers: equal as two big ints of the same value, or
        # (not hash-consed: DEDUP_KSM...) two tuples with the same
        # canonical node
        test r8b, 1
        jnz .Lseq_no
        test r9b, 1
        jnz .Lseq_no
        test r8, r8
        jz .Lseq_no
        test r9, r9
        jz .Lseq_no
        mov r10, [r8 + N_HASH]
        cmp r10, [r9 + N_HASH]
        jne .Lseq_no
        mov r10d, [r8 + N_KIND]
        cmp r10d, [r9 + N_KIND]
        jne .Lseq_no
        cmp r10d, K_INT
        je 3f
        cmp qword ptr [r15 + CTX_DEDUP], DEDUP_EAGER
        je .Lseq_no
3:      ENTER
        mov rbx, rdi
        mov r12, rdx
        mov r13, rcx
        mov r14, rax
        mov rdi, r8
        mov rsi, r9
        call values_equal
        test eax, eax
        jz 2f
        mov rdi, rbx
        mov rdx, r12
        mov rcx, r13
        mov rax, r14
        LEAVE_NORET
        jmp 1b
2:      LEAVE_NORET
.Lseq_no:
        xor eax, eax
        ret
.Lseq_yes:
        mov eax, 1
        ret
ENDF seq_equal

# mk_seq_like(orig, elems) -> rax: a sequence of orig's kind and count
# with these elements - orig itself when they are its own elements (the
# common case of a walk that changes nothing: no hashing, no lookup)
FUNC mk_seq_like
        mov ecx, [rdi + N_AUX]
        xor eax, eax
1:      cmp rax, rcx
        jae 2f
        mov rdx, [rsi + rax*8]
        cmp rdx, [rdi + N_DATA + rax*8]
        jne 3f
        inc rax
        jmp 1b
2:      mov rax, rdi
        ret
3:      mov rdx, rsi
        mov esi, ecx
        mov edi, [rdi + N_KIND]
        jmp mk_seq
ENDF mk_seq_like

# hc_grow(): double the hash-cons table (the new one allocated first:
# when the system has none, python's MemoryError for a context with a
# handler, the table as it was)
        .set HC_GROW4, 1 << 16
FUNC hc_grow
        ENTER
        sub rsp, 16
        mov r12, [r15 + CTX_HC_TABLE]
        mov r13, [r15 + CTX_HC_CAP]
        lea rdi, [r13 * 2]              # twice the slots, four times past
        cmp r13, HC_GROW4               # HC_GROW4 (see MAP_NEWCAP)
        jb 7f
        shl rdi, 1
7:      mov [rsp], rdi
        mov esi, 8
        call calloc@PLT
        test rax, rax
        jz .Lhc_no_table
        mov rcx, [rsp]
        mov [r15 + CTX_HC_CAP], rcx
        mov [r15 + CTX_HC_TABLE], rax
        mov rbx, rax
        xor r14d, r14d
        movabs r8, HC_PTR_MASK
1:      cmp r14, r13
        jae 3f
        lea rax, [r14 + 8]              # (the node eight slots on: read
        cmp rax, r13                    # ahead, the reads scattered)
        jae 6f
        mov rdi, [r12 + rax*8]
        and rdi, r8
        prefetcht0 [rdi]
6:      mov rdi, [r12 + r14*8]
        test rdi, rdi
        jz 2f
        # reinsert (the slot's word: the pointer, its tag above)
        mov rsi, rdi
        and rdi, r8
        mov rax, [rdi + N_HASH]
        mov rcx, [r15 + CTX_HC_CAP]
        dec rcx
        and rax, rcx
4:      cmp qword ptr [rbx + rax*8], 0
        je 5f
        inc rax
        and rax, rcx
        jmp 4b
5:      mov [rbx + rax*8], rsi
2:      inc r14
        jmp 1b
3:      mov rdi, r12
        call free@PLT
        add rsp, 16
        LEAVE
.Lhc_no_table:
        cmp qword ptr [r15 + CTX_ERR_BUF], 0
        je 6f
        mov edi, E_MEMORY
        lea rsi, [rip + .Ls_hc_nomem]
        call err_throw
6:      call xalloc_failed
ENDF hc_grow

        .section .rodata
.Ls_hc_nomem:   .asciz "out of memory: the system gave no more (malloc failed)"
        .text

# mk_seq(kind, count, elems) -> rax: the unique node for this sequence.
# The hottest function of all (every tuple and list made goes through it,
# most of them existing already): the comparison with a candidate, the
# allocation and the copy are done here, the calls only for a big int
# among the elements, a new chunk, a long copy.
FUNC mk_seq
        ENTER
        sub rsp, 32
        mov [rsp], rdi                  # kind
        mov [rsp + 8], rsi              # count
        mov [rsp + 16], rdx             # elems
        call hash_seq
        mov r14, rax                    # hash
        cmp qword ptr [r15 + CTX_DEDUP], DEDUP_EAGER
        jne .Lmk_provisional
        # grow if the table is half full
        mov rax, [r15 + CTX_HC_COUNT]
        shl rax, 1
        cmp rax, [r15 + CTX_HC_CAP]
        jb 1f
        call hc_grow
1:      mov rbx, [r15 + CTX_HC_TABLE]
        mov r13, [r15 + CTX_HC_CAP]
        dec r13                         # mask
        mov r12, r14
        and r12, r13                    # slot
        HC_TAG rax, r14
        mov [rsp + 24], rax             # the slot's tag
.Lmk_probe:
        mov rdi, [rbx + r12*8]
        test rdi, rdi
        jz .Lmk_new
        mov rax, rdi                    # another tag: another hash, the
        xor rax, [rsp + 24]             # node not read
        shr rax, 48
        jnz .Lmk_next
        shl rdi, 16
        shr rdi, 16                     # the node
        cmp [rdi + N_HASH], r14
        jne .Lmk_next
        mov eax, [rsp]
        cmp [rdi + N_KIND], eax
        jne .Lmk_next
        mov rcx, [rsp + 8]
        cmp [rdi + N_AUX], ecx
        jne .Lmk_next
        mov rdx, [rsp + 16]
        xor eax, eax
2:      cmp rax, rcx
        jae .Lmk_found
        mov r8, [rdi + N_DATA + rax*8]
        cmp r8, [rdx + rax*8]
        jne 3f
        inc rax
        jmp 2b
3:      # two different pointers: seq_equal decides (big ints by value)
        mov esi, [rsp]
        mov rdx, rcx
        mov rcx, [rsp + 16]
        call seq_equal
        test eax, eax
        jz .Lmk_next
        mov rdi, [rbx + r12*8]
        shl rdi, 16
        shr rdi, 16
.Lmk_found:
        mov rax, rdi
        add rsp, 32
        LEAVE
.Lmk_next:
        inc r12
        and r12, r13
        jmp .Lmk_probe
.Lmk_new:
        # arena_alloc_raw's bump, here (the canonical word before the node,
        # when some context doesn't hash-cons: hc_prefix)
        mov rsi, [rsp + 8]
        lea rsi, [rsi*8 + N_DATA + 15]
        add rsi, [rip + hc_prefix]
        and rsi, -16
        mov rax, [r15 + CTX_ARENA_CUR]
        lea rcx, [rax + rsi]
        cmp rcx, [r15 + CTX_ARENA_END]
        ja .Lmk_alloc_slow
        mov [r15 + CTX_ARENA_CUR], rcx
.Lmk_alloc_done:
        cmp qword ptr [rip + hc_prefix], 0
        je 1f
        add rax, 8
        mov [rax + N_CANON], rax        # (its own canonical node)
1:      mov rcx, [rsp]
        mov [rax + N_KIND], ecx
        mov rcx, [rsp + 8]
        mov [rax + N_AUX], ecx
        mov [rax + N_HASH], r14
        mov rdx, [rsp + 24]
        or rdx, rax
        mov [rbx + r12*8], rdx
        inc qword ptr [r15 + CTX_HC_COUNT]
        inc qword ptr [r15 + CTX_NODE_COUNT]
        mov rdx, [rsp + 16]
        cmp rcx, 16
        ja .Lmk_copy_long
        xor esi, esi
4:      cmp rsi, rcx
        jae 5f
        mov r8, [rdx + rsi*8]
        mov [rax + N_DATA + rsi*8], r8
        inc rsi
        jmp 4b
5:      add rsp, 32
        LEAVE
.Lmk_copy_long:
        mov r12, rax
        lea rdi, [rax + N_DATA]
        mov rsi, rdx
        shl rcx, 3
        mov rdx, rcx
        call memcpy@PLT
        mov rax, r12
        add rsp, 32
        LEAVE
.Lmk_alloc_slow:
        mov rdi, [rsp + 8]              # (a new chunk: arena_alloc_raw)
        shl rdi, 3
        add rdi, N_DATA
        add rdi, [rip + hc_prefix]
        call arena_alloc_raw
        jmp .Lmk_alloc_done
.Lmk_provisional:
        # made as it is, its canonical node not known yet (DEDUP_KSM: the
        # merging thread is told)
        mov rsi, [rsp + 8]
        lea rdi, [rsi*8 + N_DATA + 8]
        call arena_alloc_raw
        add rax, 8
        mov qword ptr [rax + N_CANON], 0
        mov rcx, [rsp]
        mov [rax + N_KIND], ecx
        mov rcx, [rsp + 8]
        mov [rax + N_AUX], ecx
        mov [rax + N_HASH], r14
        inc qword ptr [r15 + CTX_NODE_COUNT]
        mov rdx, [rsp + 16]
        mov r12, rax
        lea rdi, [rax + N_DATA]
        mov rsi, rdx
        shl rcx, 3
        mov rdx, rcx
        call memcpy@PLT
        mov rax, r12
        cmp qword ptr [r15 + CTX_DEDUP], DEDUP_SYNC
        jne 7f
        mov rdi, rax
        call ksm_merge
        mov rax, r12
        add rsp, 32
        LEAVE
7:      mov rcx, [r15 + CTX_KSMQ]       # (DEDUP_KSM: the merging thread's queue)
        test rcx, rcx
        jz 9f
        mov rdx, [rcx + 0]              # KQ_HEAD
        mov rsi, rdx
        sub rsi, [rcx + 64]             # - KQ_TAIL
        cmp rsi, 1 << 16                # KQ_SIZE: full, the node left out
        jae 8f
        mov rsi, rdx
        and esi, (1 << 16) - 1
        mov [rcx + 320 + rsi*8], rax    # KQ_BUF
        inc rdx
        mov [rcx + 0], rdx
        cmp qword ptr [r15 + CTX_DEDUP], DEDUP_DEFER
        jne 9f
        test edx, 63
        jnz 9f
        mov [rsp + 24], rax
        mov edi, 48
        call ksm_drain
        mov rax, [rsp + 24]
9:      add rsp, 32
        LEAVE
8:      inc qword ptr [rcx + 272]       # KQ_DROPPED
        add rsp, 32
        LEAVE
ENDF mk_seq

# dedup_mode() -> rax: DEDUP_* of the contexts of the functions, from
# $PANORAMIX_DEDUP (eager, ksm, lazy; read once)
# dedup_init(): the mode read, before any node is made: the tuples of
# every context get the canonical word before them (hc_prefix) unless
# they all hash-cons
FUNC dedup_init
        ENTER
        call dedup_mode
        test rax, rax
        jz 1f
        mov qword ptr [rip + hc_prefix], 8
1:      LEAVE
ENDF dedup_init

FUNC dedup_mode
        mov rax, [rip + dedup_mode_word]
        test rax, rax
        js 1f
        ret
1:      ENTER
        lea rdi, [rip + .Ls_env_dedup]
        call getenv@PLT
        xor ebx, ebx                    # DEDUP_EAGER
        test rax, rax
        jz 2f
        mov r12, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_dedup_ksm]
        call strcmp@PLT
        mov ecx, DEDUP_KSM
        test eax, eax
        cmovz ebx, ecx
        mov rdi, r12
        lea rsi, [rip + .Ls_dedup_lazy]
        call strcmp@PLT
        mov ecx, DEDUP_LAZY
        test eax, eax
        cmovz ebx, ecx
        mov rdi, r12
        lea rsi, [rip + .Ls_dedup_sync]
        call strcmp@PLT
        mov ecx, DEDUP_SYNC
        test eax, eax
        cmovz ebx, ecx
        mov rdi, r12
        lea rsi, [rip + .Ls_dedup_defer]
        call strcmp@PLT
        mov ecx, DEDUP_DEFER
        test eax, eax
        cmovz ebx, ecx
2:      mov [rip + dedup_mode_word], rbx
        mov rax, rbx
        LEAVE
ENDF dedup_mode

        .section .data
        .align 8
dedup_mode_word: .quad -1
hc_prefix:      .quad 0                 # 8: the tuples have their N_CANON word
        .section .rodata
.Ls_env_dedup:  .asciz "PANORAMIX_DEDUP"
.Ls_dedup_ksm:  .asciz "ksm"
.Ls_dedup_lazy: .asciz "lazy"
.Ls_dedup_sync: .asciz "sync"
.Ls_dedup_defer: .asciz "defer"
        .text

# veq_stack: VEQ's slow part, the two values at [rsp + 8] and [rsp + 16]
# (different pointers): ZF set when their canonical nodes are the same.
# Every register kept.
FUNC veq_stack
        cmp qword ptr [r15 + CTX_DEDUP], DEDUP_EAGER
        jne 1f
        test rsp, rsp                   # (ZF clear: different)
        ret
1:      push rax
        push rdi
        push rdx
        mov rdi, [rsp + 32]
        call canon
        mov rdx, rax
        mov rdi, [rsp + 40]
        call canon
        cmp rdx, rax
        pop rdx
        pop rdi
        pop rax
        ret
ENDF veq_stack

# canon(v) -> rax: the canonical node equal to v - v itself when v isn't
# a tuple or a list (ints, strings, specials, VM nodes...). Every
# register but rax kept.
FUNC canon
        mov rax, rdi
        test dil, 1
        jnz 1f
        test rdi, rdi
        jz 1f
        cmp dword ptr [rdi + N_KIND], K_TUPLE
        je 2f
        cmp dword ptr [rdi + N_KIND], K_LIST
        jne 1f
2:      mov rax, [rdi + N_CANON]
        test rax, rax
        jz 3f
1:      ret
3:      push rbp
        mov rbp, rsp
        and rsp, -16
        push rcx
        push rdx
        push rsi
        push rdi
        push r8
        push r9
        push r10
        push r11
        call canonicalize
        pop r11
        pop r10
        pop r9
        pop r8
        pop rdi
        pop rsi
        pop rdx
        pop rcx
        mov rsp, rbp
        pop rbp
        ret
ENDF canon

# canonicalize(v) -> rax: the canonical node of a tuple or list not known
# yet: its elements made canonical (in place: the same values), then the
# node equal to it in the hash-cons table, or v itself put there (under
# the table's lock: DEDUP_KSM's thread merges nodes too, see ksm.s)
FUNC canonicalize
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12d, [rbx + N_AUX]
        xor r13d, r13d
1:      cmp r13, r12
        jae 2f
        mov rdi, [rbx + N_DATA + r13*8]
        call canon
        mov [rbx + N_DATA + r13*8], rax
        inc r13
        jmp 1b
2:      mov rax, [rbx + N_CANON]
        test rax, rax
        jnz 3f                          # (the merging thread's, meanwhile)
        mov rax, [r15 + CTX_HC_COUNT]
        shl rax, 1
        cmp rax, [r15 + CTX_HC_CAP]
        jb 4f
        call hc_grow_shared
4:      mov rdi, rbx
        call hc_find_or_insert
        mov [rbx + N_CANON], rax
3:      LEAVE
ENDF canonicalize

# hc_find_or_insert(v) -> rax: the node of the hash-cons table equal to
# the tuple or list v (its elements canonical), or v itself, put there
# (the table has room; its lock held when shared)
FUNC hc_find_or_insert
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r14, [rbx + N_HASH]
        mov r12, [r15 + CTX_HC_TABLE]
        mov r13, [r15 + CTX_HC_CAP]
        dec r13
        mov rcx, r14
        and rcx, r13
        mov [rsp], rcx                  # the slot
        HC_TAG rax, r14
        mov [rsp + 8], rax
4:      mov rcx, [rsp]
        mov rdi, [r12 + rcx*8]
        test rdi, rdi
        jz 7f
3:      mov rax, rdi
        xor rax, [rsp + 8]
        shr rax, 48
        jnz 6f
        shl rdi, 16
        shr rdi, 16
        cmp [rdi + N_HASH], r14
        jne 6f
        mov esi, [rbx + N_KIND]
        mov edx, [rbx + N_AUX]
        lea rcx, [rbx + N_DATA]
        push rdi
        push rdi
        call seq_equal
        pop rdi
        pop rdi
        test eax, eax
        jz 6f
        cmp qword ptr [rdi + N_CANON], 0 # found (its canonical node itself:
        jne 1f                          # the one that put it there may not
        mov [rdi + N_CANON], rdi        # have said so yet - it will, the same)
1:      mov rax, rdi
        add rsp, 16
        LEAVE
6:      mov rcx, [rsp]
        inc rcx
        and rcx, r13
        mov [rsp], rcx
        jmp 4b
7:      mov rdx, [rsp + 8]              # not there: v is the one - unless
        or rdx, rbx                     # the other thread put one there
        xor eax, eax                    # meanwhile (DEDUP_KSM: the table
        lock cmpxchg [r12 + rcx*8], rdx # shared without a lock, slots
        jne 5f                          # only ever filled)
        lock inc qword ptr [r15 + CTX_HC_COUNT]
        mov rax, rbx
        add rsp, 16
        LEAVE
5:      mov rdi, rax                    # (what it put there)
        jmp 3b
ENDF hc_find_or_insert

# mk_tuple(count, elems) / mk_list(count, elems)
FUNC mk_tuple
        mov rdx, rsi
        mov rsi, rdi
        mov edi, K_TUPLE
        jmp mk_seq
ENDF mk_tuple

FUNC mk_list
        mov rdx, rsi
        mov rsi, rdi
        mov edi, K_LIST
        jmp mk_seq
ENDF mk_list

# mk1(a) ... mk6(a, b, c, d, e, f): tuples from registers
FUNC mk1
        ENTER
        sub rsp, 16
        mov [rsp], rdi
        mov edi, 1
        mov rsi, rsp
        call mk_tuple
        add rsp, 16
        LEAVE
ENDF mk1

FUNC mk2
        ENTER
        sub rsp, 16
        mov [rsp], rdi
        mov [rsp + 8], rsi
        mov edi, 2
        mov rsi, rsp
        call mk_tuple
        add rsp, 16
        LEAVE
ENDF mk2

FUNC mk3
        ENTER
        sub rsp, 32
        mov [rsp], rdi
        mov [rsp + 8], rsi
        mov [rsp + 16], rdx
        mov edi, 3
        mov rsi, rsp
        call mk_tuple
        add rsp, 32
        LEAVE
ENDF mk3

FUNC mk4
        ENTER
        sub rsp, 32
        mov [rsp], rdi
        mov [rsp + 8], rsi
        mov [rsp + 16], rdx
        mov [rsp + 24], rcx
        mov edi, 4
        mov rsi, rsp
        call mk_tuple
        add rsp, 32
        LEAVE
ENDF mk4

FUNC mk5
        ENTER
        sub rsp, 48
        mov [rsp], rdi
        mov [rsp + 8], rsi
        mov [rsp + 16], rdx
        mov [rsp + 24], rcx
        mov [rsp + 32], r8
        mov edi, 5
        mov rsi, rsp
        call mk_tuple
        add rsp, 48
        LEAVE
ENDF mk5

FUNC mk6
        ENTER
        sub rsp, 48
        mov [rsp], rdi
        mov [rsp + 8], rsi
        mov [rsp + 16], rdx
        mov [rsp + 24], rcx
        mov [rsp + 32], r8
        mov [rsp + 40], r9
        mov edi, 6
        mov rsi, rsp
        call mk_tuple
        add rsp, 48
        LEAVE
ENDF mk6

# --- integers ---

# int_hash_mpz(mpz) -> rax: hash of the value from its limbs
FUNC int_hash_mpz
        ENTER
        mov rbx, rdi
        movsxd r12, dword ptr [rbx + MPZ_SIZE]
        mov rdi, r12
        movabs rax, 0x9e3779b97f4a7c15
        xor rdi, rax
        call hash_mix
        mov r13, rax
        mov r14, r12
        test r14, r14
        jns 1f
        neg r14
1:      mov rbx, [rbx + MPZ_D]
2:      test r14, r14
        jz 3f
        dec r14
        mov rdi, [rbx + r14*8]
        xor rdi, r13
        call hash_mix
        mov r13, rax
        jmp 2b
3:      mov rax, r13
        mov rcx, HF_MASK                # (no mention flags in a number)
        not rcx
        and rax, rcx
        LEAVE
ENDF int_hash_mpz

# mk_int_mpz(mpz) -> rax: a value for this integer (small if it fits)
FUNC mk_int_mpz
        ENTER
        mov rbx, rdi
        call __gmpz_fits_slong_p@PLT
        test eax, eax
        jz 1f
        mov rdi, rbx
        call __gmpz_get_si@PLT
        mov rcx, SMALL_MAX
        cmp rax, rcx
        jg 1f
        mov rcx, SMALL_MIN
        cmp rax, rcx
        jl 1f
        TAG rax
        LEAVE
1:      # interned: one node per value on a context (in the hash-cons
        # table, with the tuples), so that equal ints are one pointer as
        # everything else is
        mov rdi, rbx
        call int_hash_mpz
        mov r13, rax                    # the hash
        mov rax, [r15 + CTX_HC_COUNT]
        shl rax, 1
        cmp rax, [r15 + CTX_HC_CAP]
        jb 2f
        call hc_grow_shared
2:      mov r14, [r15 + CTX_HC_CAP]
        dec r14                         # the mask
        mov r12, r13
        and r12, r14                    # the slot
3:      mov rax, [r15 + CTX_HC_TABLE]
        mov rdi, [rax + r12*8]
        test rdi, rdi
        jz 5f
        shl rdi, 16                     # (the slot's tag above)
        shr rdi, 16
        cmp [rdi + N_HASH], r13
        jne 4f
        cmp dword ptr [rdi + N_KIND], K_INT
        jne 4f
        push rdi
        push rdi
        lea rdi, [rdi + N_DATA]
        mov rsi, rbx
        call __gmpz_cmp@PLT
        pop rdi
        pop rdi
        test eax, eax
        jnz 4f
        mov rax, rdi                    # that value, already
        LEAVE
4:      inc r12
        and r12, r14
        jmp 3b
5:      # the node made, then put in the table (DEDUP_KSM: the merging
        # thread putting tuples there meanwhile - the slot taken perhaps,
        # the next free one then; it puts no ints)
        push r12
        push r12
        mov edi, NODE_INT_SIZE
        call arena_alloc_raw
        mov r12, rax
        mov dword ptr [r12 + N_KIND], K_INT
        mov dword ptr [r12 + N_AUX], 0
        mov [r12 + N_HASH], r13
        lea rdi, [r12 + N_DATA]
        mov rsi, rbx
        call __gmpz_init_set@PLT
        inc qword ptr [r15 + CTX_NODE_COUNT]
        pop rbx                         # the slot
        pop rbx
        mov rsi, [r15 + CTX_HC_TABLE]
        HC_TAG rdx, r13
        or rdx, r12
8:      xor eax, eax
        lock cmpxchg [rsi + rbx*8], rdx
        je 9f
        inc rbx
        and rbx, r14
        jmp 8b
9:      lock inc qword ptr [r15 + CTX_HC_COUNT]
        mov rax, r12
        LEAVE
ENDF mk_int_mpz

# mk_int_i64(x) -> rax
FUNC mk_int_i64
        mov rcx, SMALL_MAX
        cmp rdi, rcx
        jg 1f
        mov rcx, SMALL_MIN
        cmp rdi, rcx
        jl 1f
        lea rax, [rdi + rdi + 1]
        ret
1:      ENTER
        mov rbx, rdi
        lea rdi, [r15 + CTX_TMPZ]
        mov rsi, rbx
        call __gmpz_set_si@PLT
        lea rdi, [r15 + CTX_TMPZ]
        call mk_int_mpz
        LEAVE
ENDF mk_int_i64

# mk_int_u64(x) -> rax
FUNC mk_int_u64
        mov rcx, SMALL_MAX
        cmp rdi, rcx
        ja 1f
        lea rax, [rdi + rdi + 1]
        ret
1:      ENTER
        mov rbx, rdi
        lea rdi, [r15 + CTX_TMPZ]
        mov rsi, rbx
        call __gmpz_set_ui@PLT
        lea rdi, [r15 + CTX_TMPZ]
        call mk_int_mpz
        LEAVE
ENDF mk_int_u64

# mk_int_bytes_be(ptr, len) -> rax: big-endian unsigned integer
FUNC mk_int_bytes_be
        ENTER
        cmp rsi, 8
        ja 1f
        # fits in u64
        xor eax, eax
        xor ecx, ecx
2:      cmp rcx, rsi
        jae 3f
        shl rax, 8
        movzx edx, byte ptr [rdi + rcx]
        or rax, rdx
        inc rcx
        jmp 2b
3:      mov rdi, rax
        call mk_int_u64
        LEAVE
1:      # mpz_import(rop, count=len, order=1, size=1, endian=0, nails=0, op)
        mov r8, rdi                     # op (the bytes)
        sub rsp, 16
        mov [rsp], r8                   # 7th argument, on the stack
        lea rdi, [r15 + CTX_TMPZ]       # rop
        mov edx, 1                      # order: most significant first
        mov ecx, 1                      # size: 1-byte words
        xor r8d, r8d                    # endian
        xor r9d, r9d                    # nails
        call __gmpz_import@PLT
        add rsp, 16
        lea rdi, [r15 + CTX_TMPZ]
        call mk_int_mpz
        LEAVE
ENDF mk_int_bytes_be

# value_set_mpz(mpz_dst, v): mpz_dst := integer value v (small or K_INT)
FUNC value_set_mpz
        test sil, 1
        jz 1f
        UNTAG rsi
        jmp __gmpz_set_si@PLT
1:      add rsi, N_DATA
        jmp __gmpz_set@PLT
ENDF value_set_mpz

# value_mpz(v) -> rax: a read-only mpz_t pointer for the integer value v.
# For small ints it is the context's scratch CTX_TMPZ2 (only one at a time!).
FUNC value_mpz
        test dil, 1
        jz 1f
        ENTER
        mov rsi, rdi
        UNTAG rsi
        lea rdi, [r15 + CTX_TMPZ2]
        call __gmpz_set_si@PLT
        lea rax, [r15 + CTX_TMPZ2]
        LEAVE
1:      lea rax, [rdi + N_DATA]
        ret
ENDF value_mpz

# is_int(v) -> eax: 1 if v is a small int or a K_INT node
FUNC is_int
        test dil, 1
        jnz 1f
        test rdi, rdi
        jz 2f
        cmp dword ptr [rdi + N_KIND], K_INT
        jne 2f
1:      mov eax, 1
        ret
2:      xor eax, eax
        ret
ENDF is_int

# --- specials ---
        .section .data
        .align 16
        .globl sp_none, sp_true, sp_false
        .hidden sp_none, sp_true, sp_false
sp_none:  .long K_SPECIAL, SP_NONE
          .quad 0x0011111111111111     # (the top byte: no mention flags)
sp_true:  .long K_SPECIAL, SP_TRUE
          .quad 0x0022222222222222
sp_false: .long K_SPECIAL, SP_FALSE
          .quad 0x0033333333333333
        .text

# opcode_of(v) -> eax: the opcode id of a tuple/list whose first element is
# an opcode string, else 0
FUNC opcode_of
        test dil, 1
        jnz 1f
        test rdi, rdi
        jz 1f
        cmp dword ptr [rdi + N_KIND], K_TUPLE   # (not lists, like python's opcode())
        jne 1f
        cmp dword ptr [rdi + N_AUX], 0
        je 1f
        mov rax, [rdi + N_DATA]
        test al, 1
        jnz 1f
        test rax, rax
        jz 1f
        cmp dword ptr [rax + N_KIND], K_STR
        jne 1f
        mov eax, [rax + N_AUX]
        and eax, STR_ID_MASK
        ret
1:      xor eax, eax
        ret
ENDF opcode_of

# str_id(strnode) -> eax: the opcode id of a string node
FUNC str_id
        mov eax, [rdi + N_AUX]
        and eax, STR_ID_MASK
        ret
ENDF str_id

# value_import_root(v) -> rax: value_import of a whole value from another
# context (a worker's trace, a fold's result). The VM nodes' copies are
# remembered by address for the length of one import only: the other
# context's memory is freed afterwards, and its addresses come back.
FUNC value_import_root
        ENTER
        mov qword ptr [r15 + CTX_MEMO + MEMO_IMPORT * 8], 0
        call value_import
        mov qword ptr [r15 + CTX_MEMO + MEMO_IMPORT * 8], 0
        LEAVE
ENDF value_import_root


# value_import(v) -> rax: the value rebuilt on this context. Tuples and
# lists are consed per thread, so a structure made by another thread (a
# function's trace, the loader's values) is imported before being
# compared by pointer with this thread's - and before that thread's
# arena is freed, which also holds its big integers (copied here).
# Strings are global: kept.
FUNC value_import
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        test dil, 1
        jnz 3f
        test rdi, rdi
        jz 3f
        cmp dword ptr [rdi + N_KIND], K_INT
        jne 4f
        lea rdi, [rdi + N_DATA]
        call mk_int_mpz
        add rsp, 16
        LEAVE
4:      call is_seq
        test eax, eax
        jz 5f
        # remembered by address for the length of one import: a subtree
        # shared by many (a DAG, hash-consed) is imported once
        mov edi, MEMO_IMPORT
        mov rsi, rbx
        call memo_get
        test rax, rax
        jnz 6f
        mov edi, [rbx + N_AUX]
        shl rdi, 3
        call arena_alloc_raw
        mov [rsp], rax
        xor r12d, r12d
1:      cmp r12d, [rbx + N_AUX]
        jae 2f
        mov rdi, [rbx + N_DATA + r12*8]
        call value_import
        mov rcx, [rsp]
        mov [rcx + r12*8], rax
        inc r12d
        jmp 1b
2:      mov edi, [rbx + N_KIND]
        mov esi, [rbx + N_AUX]
        mov rdx, [rsp]
        call mk_seq
        mov [rsp + 8], rax
        mov edi, MEMO_IMPORT
        mov rsi, rbx
        mov rdx, rax
        call memo_put
        mov rax, [rsp + 8]
        add rsp, 16
        LEAVE
5:      cmp dword ptr [rbx + N_KIND], K_VMNODE
        jne 3f
        # a node of the VM (the label of a loop, in a while's jds and its
        # continues): a stub with the same identity - the same copy for
        # the same node - and its jd, the only field read after the VM
        mov edi, MEMO_IMPORT
        mov rsi, rbx
        call memo_get
        test rax, rax
        jnz 6f
        mov edi, ND_SIZEOF
        call arena_alloc
        mov r12, rax
        mov dword ptr [r12 + N_KIND], K_VMNODE
        mov rax, [rbx + N_HASH]
        mov [r12 + N_HASH], rax
        mov edi, MEMO_IMPORT
        mov rsi, rbx
        mov rdx, r12
        call memo_put
        mov rdi, [rbx + ND_JD]
        call value_import
        mov [r12 + ND_JD], rax
        mov rax, r12
6:      add rsp, 16
        LEAVE
3:      mov rax, rbx
        add rsp, 16
        LEAVE
ENDF value_import

        .section .note.GNU-stack,"",@progbits
