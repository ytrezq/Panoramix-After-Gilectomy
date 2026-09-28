# Hash maps from 64-bit keys (node pointers or tagged ints, never 0) to
# 64-bit values (never 0), in the arena. Used for memoization: as tuples
# are hash-consed, a structure is its pointer.

.include "defs.inc"

        .text

# map_new() -> rax
FUNC map_new
        mov edi, 64
        jmp map_new_cap
ENDF map_new

# map_new_cap(cap) -> rax: a map of cap slots (a power of 2), for as many
# as cap/2 entries without growing
FUNC map_new_cap
        ENTER
        mov rbx, rdi
        shl rdi, 4
        add rdi, MAP_SIZEOF
        call arena_alloc
        lea rcx, [rax + MAP_SIZEOF]
        mov [rax + MAP_ENTRIES], rcx
        mov [rax + MAP_CAP], rbx
        mov qword ptr [rax + MAP_COUNT], 0
        LEAVE
ENDF map_new_cap

# map_get(map, key) -> rax: the value, or 0
FUNC map_get
        mov rax, rsi
        mov rcx, rax
        shr rcx, 33
        xor rax, rcx
        movabs rcx, 0xff51afd7ed558ccd
        imul rax, rcx
        mov rcx, rax
        shr rcx, 29
        xor rax, rcx
        mov rcx, [rdi + MAP_CAP]
        dec rcx
        and rax, rcx
        shl rax, 4                      # byte offset of the slot
        shl rcx, 4
        mov rdx, [rdi + MAP_ENTRIES]
1:      mov r8, [rdx + rax]
        test r8, r8
        jz 2f
        cmp r8, rsi
        je 3f
        add rax, 16
        and rax, rcx
        jmp 1b
2:      xor eax, eax
        ret
3:      mov rax, [rdx + rax + 8]
        ret
ENDF map_get

# map_put(map, key, value): insert or replace
FUNC map_put
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov rax, [rbx + MAP_COUNT]
        shl rax, 1
        cmp rax, [rbx + MAP_CAP]
        jb 1f
        mov rdi, rbx
        call map_grow
1:      mov rdi, rbx
        mov rsi, r12
        call map_slot
        mov rdx, [rbx + MAP_ENTRIES]
        cmp qword ptr [rdx + rax], 0
        jne 2f
        inc qword ptr [rbx + MAP_COUNT]
2:      mov [rdx + rax], r12
        mov [rdx + rax + 8], r13
        LEAVE
ENDF map_put

# map_slot(map, key) -> rax: the byte offset of the slot holding key, or of
# the empty one for it
FUNC map_slot
        mov rax, rsi
        mov rcx, rax
        shr rcx, 33
        xor rax, rcx
        movabs rcx, 0xff51afd7ed558ccd
        imul rax, rcx
        mov rcx, rax
        shr rcx, 29
        xor rax, rcx
        mov rcx, [rdi + MAP_CAP]
        dec rcx
        and rax, rcx
        shl rax, 4
        shl rcx, 4
        mov rdx, [rdi + MAP_ENTRIES]
1:      mov r8, [rdx + rax]
        test r8, r8
        jz 2f
        cmp r8, rsi
        je 2f
        add rax, 16
        and rax, rcx
        jmp 1b
2:      ret
ENDF map_slot

FUNC map_grow
        ENTER
        mov rbx, rdi
        mov r12, [rbx + MAP_ENTRIES]
        mov r13, [rbx + MAP_CAP]
        lea rdi, [r13*2]
        shl rdi, 4
        call arena_alloc                # (first: past the memory limit it
        mov [rbx + MAP_ENTRIES], rax    # throws, and the map must stay whole)
        lea rax, [r13*2]
        mov [rbx + MAP_CAP], rax
        xor r14d, r14d                  # byte offset into the old entries
        shl r13, 4
1:      cmp r14, r13
        jae 3f
        mov rsi, [r12 + r14]
        test rsi, rsi
        jz 2f
        mov rdi, rbx
        call map_slot
        mov rdx, [rbx + MAP_ENTRIES]
        mov rsi, [r12 + r14]
        mov [rdx + rax], rsi
        mov rsi, [r12 + r14 + 8]
        mov [rdx + rax + 8], rsi
2:      add r14, 16
        jmp 1b
3:      LEAVE
ENDF map_grow

# memo_table(which) -> rax: the context's memo map `which`, made on demand
FUNC memo_table
        mov rax, [r15 + CTX_MEMO + rdi*8]
        test rax, rax
        jz 1f
        ret
1:      ENTER
        mov rbx, rdi
        call map_new
        mov [r15 + CTX_MEMO + rbx*8], rax
        LEAVE
ENDF memo_table

# memo_get(which, key) -> rax (0 if absent; a table not made yet: absent)
FUNC memo_get
        mov rax, [r15 + CTX_MEMO + rdi*8]
        test rax, rax
        jz 1f
        mov rdi, rax
        jmp map_get
1:      xor eax, eax
        ret
ENDF memo_get

# memo_put(which, key, value)
FUNC memo_put
        ENTER
        mov rbx, rsi
        mov r12, rdx
        call memo_table
        mov rdi, rax
        mov rsi, rbx
        mov rdx, r12
        call map_put
        LEAVE
ENDF memo_put

# --- maps from pairs of keys: memoization of the functions of two
# expressions (lt_op, le_op, range_overlaps, try_add) without making the
# tuple of the two (a hash-cons lookup) for every question. Entries of 32
# bytes: k1 (never 0), k2, the value (never 0), unused. Same header.

# MAP2_HASH: rax = the hash of (rsi, rdx), rcx clobbered
.macro MAP2_HASH
        movabs rax, 0x9e3779b97f4a7c15
        imul rax, rsi
        rol rax, 29
        xor rax, rdx
        mov rcx, rax
        shr rcx, 33
        xor rax, rcx
        movabs rcx, 0xff51afd7ed558ccd
        imul rax, rcx
        mov rcx, rax
        shr rcx, 29
        xor rax, rcx
.endm

# map2_new() -> rax
FUNC map2_new
        mov edi, 64
        jmp map2_new_cap
ENDF map2_new

# map2_new_cap(cap) -> rax: a map of pairs of cap slots (a power of 2)
FUNC map2_new_cap
        ENTER
        mov rbx, rdi
        shl rdi, 5
        add rdi, MAP_SIZEOF
        call arena_alloc
        lea rcx, [rax + MAP_SIZEOF]
        mov [rax + MAP_ENTRIES], rcx
        mov [rax + MAP_CAP], rbx
        mov qword ptr [rax + MAP_COUNT], 0
        LEAVE
ENDF map2_new_cap

# map2_get(map, k1, k2) -> rax: the value, or 0
FUNC map2_get
        MAP2_HASH
        mov rcx, [rdi + MAP_CAP]
        dec rcx
        and rax, rcx
        shl rax, 5                      # byte offset of the slot
        shl rcx, 5
        mov rdi, [rdi + MAP_ENTRIES]
1:      mov r8, [rdi + rax]
        test r8, r8
        jz 2f
        cmp r8, rsi
        jne 3f
        cmp [rdi + rax + 8], rdx
        je 4f
3:      add rax, 32
        and rax, rcx
        jmp 1b
2:      xor eax, eax
        ret
4:      mov rax, [rdi + rax + 16]
        ret
ENDF map2_get

# map2_slot(map, k1, k2) -> rax: the byte offset of the slot holding the
# pair, or of the empty one for it
FUNC map2_slot
        MAP2_HASH
        mov rcx, [rdi + MAP_CAP]
        dec rcx
        and rax, rcx
        shl rax, 5
        shl rcx, 5
        mov r9, [rdi + MAP_ENTRIES]
1:      mov r8, [r9 + rax]
        test r8, r8
        jz 2f
        cmp r8, rsi
        jne 3f
        cmp [r9 + rax + 8], rdx
        je 2f
3:      add rax, 32
        and rax, rcx
        jmp 1b
2:      ret
ENDF map2_slot

# map2_put(map, k1, k2, value): insert or replace
FUNC map2_put
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov r14, rcx
        mov rax, [rbx + MAP_COUNT]
        shl rax, 1
        cmp rax, [rbx + MAP_CAP]
        jb 1f
        mov rdi, rbx
        call map2_grow
1:      mov rdi, rbx
        mov rsi, r12
        mov rdx, r13
        call map2_slot
        mov rdx, [rbx + MAP_ENTRIES]
        cmp qword ptr [rdx + rax], 0
        jne 2f
        inc qword ptr [rbx + MAP_COUNT]
2:      mov [rdx + rax], r12
        mov [rdx + rax + 8], r13
        mov [rdx + rax + 16], r14
        LEAVE
ENDF map2_put

FUNC map2_grow
        ENTER
        mov rbx, rdi
        mov r12, [rbx + MAP_ENTRIES]
        mov r13, [rbx + MAP_CAP]
        lea rdi, [r13*2]
        shl rdi, 5
        call arena_alloc                # (first: see map_grow)
        mov [rbx + MAP_ENTRIES], rax
        lea rax, [r13*2]
        mov [rbx + MAP_CAP], rax
        xor r14d, r14d                  # byte offset into the old entries
        shl r13, 5
1:      cmp r14, r13
        jae 3f
        mov rsi, [r12 + r14]
        test rsi, rsi
        jz 2f
        mov rdi, rbx
        mov rdx, [r12 + r14 + 8]
        call map2_slot
        mov rdx, [rbx + MAP_ENTRIES]
        mov rsi, [r12 + r14]
        mov [rdx + rax], rsi
        mov rsi, [r12 + r14 + 8]
        mov [rdx + rax + 8], rsi
        mov rsi, [r12 + r14 + 16]
        mov [rdx + rax + 16], rsi
2:      add r14, 32
        jmp 1b
3:      LEAVE
ENDF map2_grow

# memo2_get(which, k1, k2) -> rax (0 if absent): a pair memo (MEMO_LT...)
FUNC memo2_get
        test rsi, rsi
        jz 1f                           # (k1 0: never stored)
        mov rax, [r15 + CTX_MEMO + rdi*8]
        test rax, rax
        jz 1f
        mov rdi, rax
        jmp map2_get
1:      xor eax, eax
        ret
ENDF memo2_get

# memo2_put(which, k1, k2, value)
FUNC memo2_put
        test rsi, rsi
        jnz 2f
        ret
2:      ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov r14, rcx
        mov rax, [r15 + CTX_MEMO + rbx*8]
        test rax, rax
        jnz 1f
        call map2_new
        mov [r15 + CTX_MEMO + rbx*8], rax
1:      mov rdi, rax
        mov rsi, r12
        mov rdx, r13
        mov rcx, r14
        call map2_put
        LEAVE
ENDF memo2_put

# --- maps from triples of keys (replace_mem_exp's (exp, mem_idx,
# mem_val)), for the same reason: entries of 32 bytes, k1 (never 0), k2,
# k3, the value (never 0). Same header.

# MAP3_HASH: rax = the hash of (rsi, rdx, rcx), r8 clobbered
.macro MAP3_HASH
        movabs rax, 0x9e3779b97f4a7c15
        imul rax, rsi
        rol rax, 29
        xor rax, rdx
        movabs r8, 0xc4ceb9fe1a85ec53
        imul rax, r8
        rol rax, 31
        xor rax, rcx
        mov r8, rax
        shr r8, 33
        xor rax, r8
        movabs r8, 0xff51afd7ed558ccd
        imul rax, r8
        mov r8, rax
        shr r8, 29
        xor rax, r8
.endm

# map3_get(map, k1, k2, k3) -> rax: the value, or 0
FUNC map3_get
        MAP3_HASH
        mov r9, [rdi + MAP_CAP]
        dec r9
        and rax, r9
        shl rax, 5
        shl r9, 5
        mov rdi, [rdi + MAP_ENTRIES]
1:      mov r8, [rdi + rax]
        test r8, r8
        jz 2f
        cmp r8, rsi
        jne 3f
        cmp [rdi + rax + 8], rdx
        jne 3f
        cmp [rdi + rax + 16], rcx
        je 4f
3:      add rax, 32
        and rax, r9
        jmp 1b
2:      xor eax, eax
        ret
4:      mov rax, [rdi + rax + 24]
        ret
ENDF map3_get

# map3_slot(map, k1, k2, k3) -> rax: the byte offset of the slot holding
# the triple, or of the empty one for it (r10: the entries)
FUNC map3_slot
        MAP3_HASH
        mov r9, [rdi + MAP_CAP]
        dec r9
        and rax, r9
        shl rax, 5
        shl r9, 5
        mov r10, [rdi + MAP_ENTRIES]
1:      mov r8, [r10 + rax]
        test r8, r8
        jz 2f
        cmp r8, rsi
        jne 3f
        cmp [r10 + rax + 8], rdx
        jne 3f
        cmp [r10 + rax + 16], rcx
        je 2f
3:      add rax, 32
        and rax, r9
        jmp 1b
2:      ret
ENDF map3_slot

# map3_put(map, k1, k2, k3, value): insert or replace
FUNC map3_put
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov r14, rcx
        mov [rsp], r8
        mov rax, [rbx + MAP_COUNT]
        shl rax, 1
        cmp rax, [rbx + MAP_CAP]
        jb 1f
        mov rdi, rbx
        call map3_grow
1:      mov rdi, rbx
        mov rsi, r12
        mov rdx, r13
        mov rcx, r14
        call map3_slot
        cmp qword ptr [r10 + rax], 0
        jne 2f
        inc qword ptr [rbx + MAP_COUNT]
2:      mov [r10 + rax], r12
        mov [r10 + rax + 8], r13
        mov [r10 + rax + 16], r14
        mov rcx, [rsp]
        mov [r10 + rax + 24], rcx
        add rsp, 16
        LEAVE
ENDF map3_put

FUNC map3_grow
        ENTER
        mov rbx, rdi
        mov r12, [rbx + MAP_ENTRIES]
        mov r13, [rbx + MAP_CAP]
        lea rdi, [r13*2]
        shl rdi, 5
        call arena_alloc                # (first: see map_grow)
        mov [rbx + MAP_ENTRIES], rax
        lea rax, [r13*2]
        mov [rbx + MAP_CAP], rax
        xor r14d, r14d                  # byte offset into the old entries
        shl r13, 5
1:      cmp r14, r13
        jae 3f
        mov rsi, [r12 + r14]
        test rsi, rsi
        jz 2f
        mov rdi, rbx
        mov rdx, [r12 + r14 + 8]
        mov rcx, [r12 + r14 + 16]
        call map3_slot
        mov rsi, [r12 + r14]
        mov [r10 + rax], rsi
        mov rsi, [r12 + r14 + 8]
        mov [r10 + rax + 8], rsi
        mov rsi, [r12 + r14 + 16]
        mov [r10 + rax + 16], rsi
        mov rsi, [r12 + r14 + 24]
        mov [r10 + rax + 24], rsi
2:      add r14, 32
        jmp 1b
3:      LEAVE
ENDF map3_grow

# memo3_get(which, k1, k2, k3) -> rax (0 if absent): a triple memo
FUNC memo3_get
        mov rax, [r15 + CTX_MEMO + rdi*8]
        test rax, rax
        jz 1f
        mov rdi, rax
        jmp map3_get
1:      xor eax, eax
        ret
ENDF memo3_get

# memo3_put(which, k1, k2, k3, value)
FUNC memo3_put
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov r14, rcx
        mov [rsp], r8
        mov rax, [r15 + CTX_MEMO + rbx*8]
        test rax, rax
        jnz 1f
        mov edi, 64                     # (32 bytes an entry, as map2's)
        call map2_new_cap
        mov [r15 + CTX_MEMO + rbx*8], rax
1:      mov rdi, rax
        mov rsi, r12
        mov rdx, r13
        mov rcx, r14
        mov r8, [rsp]
        call map3_put
        add rsp, 16
        LEAVE
ENDF memo3_put

# --- emaps: maps whose entries belong to an epoch (32 bytes: key, value,
# epoch, -), emptied at once by starting a new epoch - the entries of
# the ones before are as good as empty (a new key takes their slot; the
# probes stop at them). For replace_f_memo, which asks for a fresh map at
# every walk of the trace: growing one from nothing, rehashing and zeroing
# at every doubling, cost more than the walk it saved.

# EMAP_HASH: rax = the slot's byte offset of rsi in the emap rdi, rcx =
# the mask of the byte offsets
.macro EMAP_SLOT
        mov rax, rsi
        mov rcx, rax
        shr rcx, 33
        xor rax, rcx
        movabs rcx, 0xff51afd7ed558ccd
        imul rax, rcx
        mov rcx, rax
        shr rcx, 29
        xor rax, rcx
        mov rcx, [rdi + MAP_CAP]
        dec rcx
        and rax, rcx
        shl rax, 5
        shl rcx, 5
.endm

# emap_new() -> rax: an emap of 1024 slots, epoch 1 (the slots' 0: empty)
FUNC emap_new
        ENTER
        mov edi, EMAP_SIZEOF + 1024*32
        call arena_alloc
        lea rcx, [rax + EMAP_SIZEOF]
        mov [rax + MAP_ENTRIES], rcx
        mov qword ptr [rax + MAP_CAP], 1024
        mov qword ptr [rax + MAP_COUNT], 0
        mov qword ptr [rax + EMAP_EPOCH], 1
        LEAVE
ENDF emap_new

# emap_begin(map): empty (a new epoch)
FUNC emap_begin
        inc qword ptr [rdi + EMAP_EPOCH]
        mov qword ptr [rdi + MAP_COUNT], 0
        ret
ENDF emap_begin

# emap_get(map, key) -> rax: the value, or 0
FUNC emap_get
        EMAP_SLOT
        mov r8, [rdi + EMAP_EPOCH]
        mov rdx, [rdi + MAP_ENTRIES]
1:      cmp [rdx + rax + 16], r8
        jne 2f                          # empty, or of an epoch before
        cmp [rdx + rax], rsi
        je 3f
        add rax, 32
        and rax, rcx
        jmp 1b
2:      xor eax, eax
        ret
3:      mov rax, [rdx + rax + 8]
        ret
ENDF emap_get

# emap_put(map, key, value): insert or replace
FUNC emap_put
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov rax, [rbx + MAP_COUNT]
        inc rax
        shl rax, 1
        cmp rax, [rbx + MAP_CAP]
        jbe 1f
        mov rdi, rbx
        call emap_grow
1:      mov rdi, rbx
        mov rsi, r12
        EMAP_SLOT
        mov r8, [rbx + EMAP_EPOCH]
        mov rdx, [rbx + MAP_ENTRIES]
2:      cmp [rdx + rax + 16], r8
        jne 3f
        cmp [rdx + rax], r12
        je 4f
        add rax, 32
        and rax, rcx
        jmp 2b
3:      inc qword ptr [rbx + MAP_COUNT] # a slot taken
        mov [rdx + rax], r12
        mov [rdx + rax + 16], r8
4:      mov [rdx + rax + 8], r13
        LEAVE
ENDF emap_put

# emap_grow(map): twice the slots, the current epoch's entries moved
FUNC emap_grow
        ENTER
        mov rbx, rdi
        mov r12, [rbx + MAP_ENTRIES]
        mov r13, [rbx + MAP_CAP]
        lea rdi, [r13*2]
        shl rdi, 5
        call arena_alloc                # (zeroed: epoch 0, empty; first: see map_grow)
        mov [rbx + MAP_ENTRIES], rax
        lea rax, [r13*2]
        mov [rbx + MAP_CAP], rax
        mov r14, [rbx + EMAP_EPOCH]
        shl r13, 5
        xor r8d, r8d                    # byte offset into the old entries
1:      cmp r8, r13
        jae 4f
        cmp [r12 + r8 + 16], r14
        jne 3f
        mov rdi, rbx
        mov rsi, [r12 + r8]
        push r8
        push r8
        EMAP_SLOT
        pop r8
        pop r8
        mov rdx, [rbx + MAP_ENTRIES]
2:      cmp qword ptr [rdx + rax + 16], 0
        je 21f
        add rax, 32
        and rax, rcx
        jmp 2b
21:     mov rsi, [r12 + r8]
        mov [rdx + rax], rsi
        mov rsi, [r12 + r8 + 8]
        mov [rdx + rax + 8], rsi
        mov [rdx + rax + 16], r14
3:      add r8, 32
        jmp 1b
4:      LEAVE
ENDF emap_grow

        .section .note.GNU-stack,"",@progbits
