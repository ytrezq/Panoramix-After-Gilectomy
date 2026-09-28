# Hash maps from 64-bit keys (node pointers or tagged ints, never 0) to
# 64-bit values (never 0), in the arena. Used for memoization: as tuples
# are hash-consed, a structure is its pointer.

.include "defs.inc"

        .text

# map_new() -> rax
FUNC map_new
        ENTER
        mov edi, MAP_SIZEOF + 64*16
        call arena_alloc
        lea rcx, [rax + MAP_SIZEOF]
        mov [rax + MAP_ENTRIES], rcx
        mov qword ptr [rax + MAP_CAP], 64
        mov qword ptr [rax + MAP_COUNT], 0
        LEAVE
ENDF map_new

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
        lea rax, [r13*2]
        mov [rbx + MAP_CAP], rax
        shl rax, 4
        mov rdi, rax
        call arena_alloc
        mov [rbx + MAP_ENTRIES], rax
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

# memo_get(which, key) -> rax (0 if absent)
FUNC memo_get
        ENTER
        mov rbx, rsi
        call memo_table
        mov rdi, rax
        mov rsi, rbx
        call map_get
        LEAVE
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
        ENTER
        mov edi, MAP_SIZEOF + 64*32
        call arena_alloc
        lea rcx, [rax + MAP_SIZEOF]
        mov [rax + MAP_ENTRIES], rcx
        mov qword ptr [rax + MAP_CAP], 64
        mov qword ptr [rax + MAP_COUNT], 0
        LEAVE
ENDF map2_new

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
        lea rax, [r13*2]
        mov [rbx + MAP_CAP], rax
        shl rax, 5
        mov rdi, rax
        call arena_alloc
        mov [rbx + MAP_ENTRIES], rax
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

        .section .note.GNU-stack,"",@progbits
