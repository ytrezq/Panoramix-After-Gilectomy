# Hash maps from 64-bit keys (node pointers or tagged ints, never 0) to
# 64-bit values (never 0), in the arena. Used for memoization: as tuples
# are hash-consed, a structure is its pointer.
#
# Open addressing, linear probing, half full at most. A slot's state is
# its control byte (MAP_CTRL, one per slot): 0 empty, else 0x80 | the top
# 7 bits of the key's hash - a probe compares the key only when they
# match. Only the control bytes are zeroed when a table is made (the
# entries are written before they are read): a table of pairs grown to
# 2^18 slots zeroes 256 KiB instead of 8 MiB - the zeroing of the tables
# grown by doubling was 5 to 9% of the instructions.

.include "defs.inc"

        .text

# MAP_HASH: rax = the hash of rsi, rcx clobbered
.macro MAP_HASH
        mov rax, rsi
        mov rcx, rax
        shr rcx, 33
        xor rax, rcx
        movabs rcx, 0xff51afd7ed558ccd
        imul rax, rcx
        mov rcx, rax
        shr rcx, 29
        xor rax, rcx
.endm

# MAP_TAG reg32: the control byte of the hash rax (0x80..0xff)
.macro MAP_TAG reg, reg32
        mov \reg, rax
        shr \reg, 57
        or \reg32, 0x80
.endm

# MAP_NEWCAP reg: the capacity a map of r13 slots grows to - twice as
# many, four times past MAP_GROW4 of them (the rehashing of a doubling
# costs as much as the entries: a map grown to n entries has rehashed n
# of them by doublings, n/3 past there)
        .set MAP_GROW4, 1 << 12
.macro MAP_NEWCAP reg
        lea \reg, [r13*2]
        cmp r13, MAP_GROW4
        jb 99f
        shl \reg, 1
99:
.endm

# map_alloc(cap, entry_shift) -> rax: a table of cap slots of 2^shift
# bytes, its control bytes zeroed
FUNC map_alloc
        ENTER
        mov rbx, rdi
        mov ecx, esi
        shl rdi, cl
        add rdi, MAP_SIZEOF
        call arena_alloc_raw            # (the entries: written before read)
        mov r12, rax
        lea rcx, [rax + MAP_SIZEOF]
        mov [rax + MAP_ENTRIES], rcx
        mov [rax + MAP_CAP], rbx
        mov qword ptr [rax + MAP_COUNT], 0
        mov rdi, rbx
        call arena_alloc                # the control bytes, zeroed
        mov [r12 + MAP_CTRL], rax
        mov rax, r12
        LEAVE
ENDF map_alloc

# map_new() -> rax
FUNC map_new
        mov edi, 256
        jmp map_new_cap
ENDF map_new

# map_new_cap(cap) -> rax: a map of cap slots (a power of 2), for as many
# as cap/2 entries without growing
FUNC map_new_cap
        mov esi, 4
        jmp map_alloc
ENDF map_new_cap

# map_get(map, key) -> rax: the value, or 0
FUNC map_get
        MAP_HASH
        MAP_TAG r8, r8d
        mov rcx, [rdi + MAP_CAP]
        dec rcx
        and rax, rcx                    # the slot
        mov r9, [rdi + MAP_CTRL]
        mov rdx, [rdi + MAP_ENTRIES]
1:      movzx r10d, byte ptr [r9 + rax]
        test r10d, r10d
        jz 2f
        cmp r10d, r8d
        jne 3f
        mov r10, rax
        shl r10, 4
        cmp [rdx + r10], rsi
        je 4f
3:      inc rax
        and rax, rcx
        jmp 1b
2:      xor eax, eax
        ret
4:      mov rax, [rdx + r10 + 8]
        ret
ENDF map_get

# map_slot(map, key) -> rax: the slot holding key, or the empty one for
# it; edx: the key's control byte
FUNC map_slot
        MAP_HASH
        MAP_TAG rdx, edx
        mov rcx, [rdi + MAP_CAP]
        dec rcx
        and rax, rcx
        mov r9, [rdi + MAP_CTRL]
        mov r11, [rdi + MAP_ENTRIES]
1:      movzx r10d, byte ptr [r9 + rax]
        test r10d, r10d
        jz 2f
        cmp r10d, edx
        jne 3f
        mov r10, rax
        shl r10, 4
        cmp [r11 + r10], rsi
        je 2f
3:      inc rax
        and rax, rcx
        jmp 1b
2:      ret
ENDF map_slot

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
        mov r9, [rbx + MAP_CTRL]
        cmp byte ptr [r9 + rax], 0
        jne 2f
        inc qword ptr [rbx + MAP_COUNT]
        mov [r9 + rax], dl
2:      mov rcx, [rbx + MAP_ENTRIES]
        shl rax, 4
        mov [rcx + rax], r12
        mov [rcx + rax + 8], r13
        LEAVE
ENDF map_put

FUNC map_grow
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, [rbx + MAP_ENTRIES]
        mov r13, [rbx + MAP_CAP]
        mov rax, [rbx + MAP_CTRL]
        mov [rsp], rax                  # the old control bytes
        MAP_NEWCAP rdi
        mov esi, 4
        call map_alloc                  # (first: past the memory limit it
        mov rcx, [rax + MAP_ENTRIES]    # throws, and the map must stay whole)
        mov [rbx + MAP_ENTRIES], rcx
        mov rcx, [rax + MAP_CTRL]
        mov [rbx + MAP_CTRL], rcx
        MAP_NEWCAP rax
        mov [rbx + MAP_CAP], rax
        # each entry to the first empty slot from its key's in the new
        # table (no comparison: the keys are all different), its control
        # byte as it was
        mov r8, [rsp]
        mov r9, [rbx + MAP_CTRL]
        mov r10, [rbx + MAP_ENTRIES]
        mov r11, [rbx + MAP_CAP]
        dec r11            # the new mask
        xor r14d, r14d                  # the old slot
1:      cmp r14, r13
        jae 3f
        movzx edx, byte ptr [r8 + r14]
        test edx, edx
        jz 2f
        mov rdi, r14
        shl rdi, 4
        mov rsi, [r12 + rdi]
        MAP_HASH
        and rax, r11
4:      cmp byte ptr [r9 + rax], 0
        je 5f
        inc rax
        and rax, r11
        jmp 4b
5:      mov [r9 + rax], dl
        shl rax, 4
        movups xmm0, [r12 + rdi]
        movups [r10 + rax], xmm0
2:      inc r14
        jmp 1b
3:      add rsp, 16
        LEAVE
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
# bytes: k1 (never 0), k2, the value (never 0), a word of map2_put_w's
# (MEMO_ADD2: whether add_op reduced its sum). Same header.

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
        mov edi, 256
        jmp map2_new_cap
ENDF map2_new

# map2_new_cap(cap) -> rax: a map of pairs of cap slots (a power of 2)
FUNC map2_new_cap
        mov esi, 5
        jmp map_alloc
ENDF map2_new_cap

# map2_get(map, k1, k2) -> rax: the value, or 0; rdx: the entry's fourth
# word when there is one (map2_put_w's; garbage for map2_put's)
FUNC map2_get
        MAP2_HASH
        MAP_TAG r8, r8d
        mov rcx, [rdi + MAP_CAP]
        dec rcx
        and rax, rcx
        mov r9, [rdi + MAP_CTRL]
        mov rdi, [rdi + MAP_ENTRIES]
1:      movzx r10d, byte ptr [r9 + rax]
        test r10d, r10d
        jz 2f
        cmp r10d, r8d
        jne 3f
        mov r10, rax
        shl r10, 5
        cmp [rdi + r10], rsi
        jne 3f
        cmp [rdi + r10 + 8], rdx
        je 4f
3:      inc rax
        and rax, rcx
        jmp 1b
2:      xor eax, eax
        ret
4:      mov rax, [rdi + r10 + 16]
        mov rdx, [rdi + r10 + 24]
        ret
ENDF map2_get

# map2_slot(map, k1, k2) -> rax: the slot holding the pair, or the empty
# one for it; r8d: its control byte
FUNC map2_slot
        MAP2_HASH
        MAP_TAG r8, r8d
        mov rcx, [rdi + MAP_CAP]
        dec rcx
        and rax, rcx
        mov r9, [rdi + MAP_CTRL]
        mov r11, [rdi + MAP_ENTRIES]
1:      movzx r10d, byte ptr [r9 + rax]
        test r10d, r10d
        jz 2f
        cmp r10d, r8d
        jne 3f
        mov r10, rax
        shl r10, 5
        cmp [r11 + r10], rsi
        jne 3f
        cmp [r11 + r10 + 8], rdx
        je 2f
3:      inc rax
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
        mov r9, [rbx + MAP_CTRL]
        cmp byte ptr [r9 + rax], 0
        jne 2f
        inc qword ptr [rbx + MAP_COUNT]
        mov [r9 + rax], r8b
2:      mov rdx, [rbx + MAP_ENTRIES]
        shl rax, 5
        mov [rdx + rax], r12
        mov [rdx + rax + 8], r13
        mov [rdx + rax + 16], r14
        LEAVE
ENDF map2_put

FUNC map2_grow
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, [rbx + MAP_ENTRIES]
        mov r13, [rbx + MAP_CAP]
        mov rax, [rbx + MAP_CTRL]
        mov [rsp], rax                  # the old control bytes
        MAP_NEWCAP rdi
        mov esi, 5
        call map_alloc                  # (first: see map_grow)
        mov rcx, [rax + MAP_ENTRIES]
        mov [rbx + MAP_ENTRIES], rcx
        mov rcx, [rax + MAP_CTRL]
        mov [rbx + MAP_CTRL], rcx
        MAP_NEWCAP rax
        mov [rbx + MAP_CAP], rax
        # (as map_grow does)
        mov r8, [rsp]
        mov r9, [rbx + MAP_CTRL]
        mov r10, [rbx + MAP_ENTRIES]
        mov r11, [rbx + MAP_CAP]
        dec r11
        xor r14d, r14d                  # the old slot
1:      cmp r14, r13
        jae 3f
        movzx edi, byte ptr [r8 + r14]
        test edi, edi
        jz 2f
        mov rax, r14
        shl rax, 5
        mov rsi, [r12 + rax]
        mov rdx, [r12 + rax + 8]
        MAP2_HASH
        and rax, r11
4:      cmp byte ptr [r9 + rax], 0
        je 5f
        inc rax
        and rax, r11
        jmp 4b
5:      mov [r9 + rax], dil
        shl rax, 5
        mov rcx, r14
        shl rcx, 5
        movups xmm0, [r12 + rcx]
        movups xmm1, [r12 + rcx + 16]
        movups [r10 + rax], xmm0
        movups [r10 + rax + 16], xmm1
2:      inc r14
        jmp 1b
3:      add rsp, 16
        LEAVE
ENDF map2_grow

# memo2_get(which, k1, k2) -> rax (0 if absent): a pair memo (MEMO_LE...);
# rdx: the entry's fourth word (map2_get)
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

# map2_put_w(map, k1, k2, value, w): map2_put, and w the entry's fourth
# word (map2_get's rdx)
FUNC map2_put_w
        ENTER
        sub rsp, 16
        mov [rsp], r8                   # w
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
        mov r9, [rbx + MAP_CTRL]
        cmp byte ptr [r9 + rax], 0
        jne 2f
        inc qword ptr [rbx + MAP_COUNT]
        mov [r9 + rax], r8b
2:      mov rdx, [rbx + MAP_ENTRIES]
        shl rax, 5
        mov [rdx + rax], r12
        mov [rdx + rax + 8], r13
        mov [rdx + rax + 16], r14
        mov rcx, [rsp]
        mov [rdx + rax + 24], rcx
        add rsp, 16
        LEAVE
ENDF map2_put_w

# memo2_put_w(which, k1, k2, value, w): memo2_put, w in the entry
FUNC memo2_put_w
        test rsi, rsi
        jnz 2f
        ret
2:      ENTER
        sub rsp, 16
        mov [rsp], r8
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
        mov r8, [rsp]
        call map2_put_w
        add rsp, 16
        LEAVE
ENDF memo2_put_w

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
        MAP_TAG r8, r8d
        mov r9, [rdi + MAP_CAP]
        dec r9
        and rax, r9
        mov r11, [rdi + MAP_CTRL]
        mov rdi, [rdi + MAP_ENTRIES]
1:      movzx r10d, byte ptr [r11 + rax]
        test r10d, r10d
        jz 2f
        cmp r10d, r8d
        jne 3f
        mov r10, rax
        shl r10, 5
        cmp [rdi + r10], rsi
        jne 3f
        cmp [rdi + r10 + 8], rdx
        jne 3f
        cmp [rdi + r10 + 16], rcx
        je 4f
3:      inc rax
        and rax, r9
        jmp 1b
2:      xor eax, eax
        ret
4:      mov rax, [rdi + r10 + 24]
        ret
ENDF map3_get

# map3_slot(map, k1, k2, k3) -> rax: the slot holding the triple, or the
# empty one for it; r8d: its control byte (r10: the entries, r11: the
# control bytes)
FUNC map3_slot
        MAP3_HASH
        MAP_TAG r8, r8d
        mov r9, [rdi + MAP_CAP]
        dec r9
        and rax, r9
        mov r11, [rdi + MAP_CTRL]
        mov r10, [rdi + MAP_ENTRIES]
        push rbx
1:      movzx ebx, byte ptr [r11 + rax]
        test ebx, ebx
        jz 2f
        cmp ebx, r8d
        jne 3f
        mov rbx, rax
        shl rbx, 5
        cmp [r10 + rbx], rsi
        jne 3f
        cmp [r10 + rbx + 8], rdx
        jne 3f
        cmp [r10 + rbx + 16], rcx
        je 2f
3:      inc rax
        and rax, r9
        jmp 1b
2:      pop rbx
        ret
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
        cmp byte ptr [r11 + rax], 0
        jne 2f
        inc qword ptr [rbx + MAP_COUNT]
        mov [r11 + rax], r8b
2:      shl rax, 5
        mov [r10 + rax], r12
        mov [r10 + rax + 8], r13
        mov [r10 + rax + 16], r14
        mov rcx, [rsp]
        mov [r10 + rax + 24], rcx
        add rsp, 16
        LEAVE
ENDF map3_put

FUNC map3_grow
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, [rbx + MAP_ENTRIES]
        mov r13, [rbx + MAP_CAP]
        mov rax, [rbx + MAP_CTRL]
        mov [rsp], rax                  # the old control bytes
        MAP_NEWCAP rdi
        mov esi, 5
        call map_alloc                  # (first: see map_grow)
        mov rcx, [rax + MAP_ENTRIES]
        mov [rbx + MAP_ENTRIES], rcx
        mov rcx, [rax + MAP_CTRL]
        mov [rbx + MAP_CTRL], rcx
        MAP_NEWCAP rax
        mov [rbx + MAP_CAP], rax
        # (as map_grow does; MAP3_HASH takes r8)
        mov r9, [rbx + MAP_CTRL]
        mov r10, [rbx + MAP_ENTRIES]
        mov r11, [rbx + MAP_CAP]
        dec r11
        xor r14d, r14d                  # the old slot
1:      cmp r14, r13
        jae 3f
        mov rax, [rsp]
        movzx edi, byte ptr [rax + r14]
        test edi, edi
        jz 2f
        mov rax, r14
        shl rax, 5
        mov rsi, [r12 + rax]
        mov rdx, [r12 + rax + 8]
        mov rcx, [r12 + rax + 16]
        MAP3_HASH
        and rax, r11
4:      cmp byte ptr [r9 + rax], 0
        je 5f
        inc rax
        and rax, r11
        jmp 4b
5:      mov [r9 + rax], dil
        shl rax, 5
        mov rcx, r14
        shl rcx, 5
        movups xmm0, [r12 + rcx]
        movups xmm1, [r12 + rcx + 16]
        movups [r10 + rax], xmm0
        movups [r10 + rax + 16], xmm1
2:      inc r14
        jmp 1b
3:      add rsp, 16
        LEAVE
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
# probes stop at them). For rename_var (cleanup.s), which asks for a fresh
# map at every walk of the trace, and the sets of line_vars and
# vec_extend_unique: growing one from nothing, rehashing and zeroing at
# every doubling, cost more than the walk it saved.

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

# emap_add(map, key) -> eax: 1 when the key is added (value 1), 0 when it
# was there already - a set's insertion, one probe
FUNC emap_add
        mov rax, [rdi + MAP_COUNT]
        inc rax
        shl rax, 1
        cmp rax, [rdi + MAP_CAP]
        jbe 1f
        push rdi
        push rsi
        sub rsp, 8
        call emap_grow
        add rsp, 8
        pop rsi
        pop rdi
1:      EMAP_SLOT
        mov r8, [rdi + EMAP_EPOCH]
        mov rdx, [rdi + MAP_ENTRIES]
2:      cmp [rdx + rax + 16], r8
        jne 3f
        cmp [rdx + rax], rsi
        je 4f
        add rax, 32
        and rax, rcx
        jmp 2b
3:      inc qword ptr [rdi + MAP_COUNT] # a slot taken
        mov [rdx + rax], rsi
        mov qword ptr [rdx + rax + 8], 1
        mov [rdx + rax + 16], r8
        mov eax, 1
        ret
4:      xor eax, eax
        ret
ENDF emap_add

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
