# Hash maps from 64-bit keys (node pointers or tagged ints, never 0) to
# 64-bit values (never 0), in the arena. Used for memoization: as tuples
# are hash-consed, a structure is its pointer.
#
# The entries are dense, in the order they came in (key and value, 16
# bytes; 32 for the maps of pairs and of triples), in chunks of 64, 128,
# 256... entries (MAP_CHUNKS: each one as big as all the ones before and
# 64 more, made when they are full - never moved), found through the
# slots (MAP_SLOTS: open addressing, linear probing, half full at most).
# A slot is a 32-bit word: 0 empty, else the top 6 bits of the key's hash
# above the entry's index + 1 (26 bits) - a probe reads the entry only
# when they match. Entry i is in chunk k = bsr(i + 64) - 6, at i + 64
# without its top bit. A map of pairs takes 32 bytes an entry (64 at
# most, a chunk just made) and 8 to 32 of slots, where slots holding the
# entries themselves took 66 to 264 - the tables of the big functions,
# hundreds of thousands of entries, were most of their arena. A growth
# rehashes the slots from the entries, read in order.

.include "defs.inc"

        .set MAP_TAGMASK, 0xfc000000
        .set MAP_IDXMASK, 0x03ffffff
        .set MAP_MAXCOUNT, 0x03fffffe   # the entries a map holds at most
        .set MAP_SEG_SHIFT, 6
        .set MAP_SEG, 1 << MAP_SEG_SHIFT        # the first chunk's entries

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

# MAP_SLOTTAG reg, reg32: the tag bits of a slot for the hash rax
.macro MAP_SLOTTAG reg, reg32
        mov \reg, rax
        shr \reg, 32
        and \reg32, MAP_TAGMASK
.endm

# MAP_ENTRY j, t, map, shift: j (an entry's index + MAP_SEG) becomes the
# entry's address; t clobbered
.macro MAP_ENTRY j, t, map, shift
        bsr \t, \j
        btr \j, \t
        mov \t, [\map + \t*8 + MAP_CHUNKS - MAP_SEG_SHIFT*8]
        shl \j, \shift
        add \j, \t
.endm

# MAP_NEWCAP reg: the slots a map of r13 slots grows to - twice as many,
# four times past MAP_GROW4 of them
        .set MAP_GROW4, 1 << 12
.macro MAP_NEWCAP reg
        lea \reg, [r13*2]
        cmp r13, MAP_GROW4
        jb 99f
        shl \reg, 1
99:
.endm

# map_alloc(cap, ecap, entry_shift) -> rax: a map of cap slots (zeroed),
# room for ecap entries of 2^shift bytes at least
FUNC map_alloc
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13d, edx
        mov edi, MAP_SEG
        mov ecx, edx
        shl rdi, cl
        add rdi, MAP_SIZEOF
        call arena_alloc_raw            # (the entries: written before read)
        mov r14, rax
        lea rcx, [rax + MAP_SIZEOF]
        mov [rax + MAP_CHUNKS], rcx     # the first chunk
        mov [rax + MAP_CAP], rbx
        mov qword ptr [rax + MAP_COUNT], 0
        mov qword ptr [rax + MAP_ECAP], MAP_SEG
        mov [rax + MAP_SHIFT], r13
        lea rdi, [rbx*4]
        call arena_alloc                # the slots, zeroed
        mov [r14 + MAP_SLOTS], rax
1:      cmp r12, [r14 + MAP_ECAP]       # (room asked for: the chunks now)
        jbe 2f
        mov rdi, r14
        call map_add_chunk
        jmp 1b
2:      mov rax, r14
        LEAVE
ENDF map_alloc

# map_add_chunk(map): the next chunk of entries
FUNC map_add_chunk
        ENTER
        mov rbx, rdi
        mov r12, [rbx + MAP_ECAP]
        add r12, MAP_SEG                # its entries: MAP_SEG << k
        mov rdi, r12
        mov rcx, [rbx + MAP_SHIFT]
        shl rdi, cl
        call arena_alloc_raw
        bsr rcx, r12
        mov [rbx + rcx*8 + MAP_CHUNKS - MAP_SEG_SHIFT*8], rax
        add [rbx + MAP_ECAP], r12
        LEAVE
ENDF map_add_chunk

# map_entry_at(map, index) -> rax: the address of the entry
FUNC map_entry_at
        lea rax, [rsi + MAP_SEG]
        mov rcx, [rdi + MAP_SHIFT]
        bsr rdx, rax
        btr rax, rdx
        shl rax, cl
        add rax, [rdi + rdx*8 + MAP_CHUNKS - MAP_SEG_SHIFT*8]
        ret
ENDF map_entry_at

# map_new() -> rax
FUNC map_new
        mov edi, 256
        jmp map_new_cap
ENDF map_new

# map_new_cap(cap) -> rax: a map of cap slots (a power of 2), for as many
# as cap/2 entries without growing
FUNC map_new_cap
        xor esi, esi
        mov edx, 4
        jmp map_alloc
ENDF map_new_cap

# map_new_sized(cap, ecap) -> rax: a map of cap slots, room for ecap
# entries
FUNC map_new_sized
        mov edx, 4
        jmp map_alloc
ENDF map_new_sized

# map_get(map, key) -> rax: the value, or 0
FUNC map_get
        MAP_HASH
        MAP_SLOTTAG r8, r8d
        mov rcx, [rdi + MAP_CAP]
        dec rcx
        and rax, rcx                    # the slot
        mov r9, [rdi + MAP_SLOTS]
1:      mov r10d, [r9 + rax*4]
        test r10d, r10d
        jz 2f
        xor r10d, r8d                   # the index + 1 when the tags match
        cmp r10d, MAP_IDXMASK
        ja 3f
        add r10d, MAP_SEG - 1
        MAP_ENTRY r10, r11, rdi, 4
        cmp [r10], rsi
        je 4f
3:      inc rax
        and rax, rcx
        jmp 1b
2:      xor eax, eax
        ret
4:      mov rax, [r10 + 8]
        ret
ENDF map_get

# map_put(map, key, value): insert or replace
FUNC map_put
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov rax, [rbx + MAP_COUNT]
        shl rax, 1
        cmp rax, [rbx + MAP_CAP]
        jb 1f
        mov rdi, rbx
        call map_grow
1:      mov rsi, r12
        MAP_HASH
        MAP_SLOTTAG r8, r8d
        mov rcx, [rbx + MAP_CAP]
        dec rcx
        and rax, rcx
        mov r9, [rbx + MAP_SLOTS]
2:      mov r10d, [r9 + rax*4]
        test r10d, r10d
        jz 4f
        xor r10d, r8d
        cmp r10d, MAP_IDXMASK
        ja 3f
        add r10d, MAP_SEG - 1
        MAP_ENTRY r10, r11, rbx, 4
        cmp [r10], r12
        jne 3f
        mov [r10 + 8], r13              # there: replaced
        add rsp, 16
        LEAVE
3:      inc rax
        and rax, rcx
        jmp 2b
4:      mov r14, rax                    # a new entry, at the end
        mov [rsp], r8
        mov rax, [rbx + MAP_COUNT]
        cmp rax, MAP_MAXCOUNT
        jae map_full
        cmp rax, [rbx + MAP_ECAP]
        jb 5f
        mov rdi, rbx
        call map_add_chunk
        mov rax, [rbx + MAP_COUNT]
5:      lea r10, [rax + MAP_SEG]
        MAP_ENTRY r10, r11, rbx, 4
        mov [r10], r12
        mov [r10 + 8], r13
        inc rax
        mov [rbx + MAP_COUNT], rax
        or eax, [rsp]
        mov r9, [rbx + MAP_SLOTS]
        mov [r9 + r14*4], eax
        add rsp, 16
        LEAVE
ENDF map_put

# map_full: a map past MAP_MAXCOUNT entries (jumped to): E_MEMORY
map_full:
        mov edi, E_MEMORY
        lea rsi, [rip + .Lmsg_map_full]
        call err_throw

        .section .rodata
.Lmsg_map_full: .asciz "out of memory: a table of more than 2^26 entries"
        .text

# map_grow(map): the slots of map_put's maps, grown (MAP_NEWCAP) and
# refilled from the entries (no comparison: the keys are all different)
FUNC map_grow
        ENTER
        mov rbx, rdi
        mov r13, [rbx + MAP_CAP]
        MAP_NEWCAP rdi
        mov r12, rdi
        shl rdi, 2
        call arena_alloc                # (first: past the memory limit it
        mov [rbx + MAP_SLOTS], rax      # throws, and the map must stay whole)
        mov [rbx + MAP_CAP], r12
        mov r9, rax
        lea r11, [r12 - 1]              # the new mask
        xor r14d, r14d                  # the entry
1:      cmp r14, [rbx + MAP_COUNT]
        jae 3f
        lea r10, [r14 + MAP_SEG]
        MAP_ENTRY r10, rdi, rbx, 4
        mov rsi, [r10]
        MAP_HASH
        MAP_SLOTTAG r8, r8d
        and rax, r11
4:      cmp dword ptr [r9 + rax*4], 0
        je 5f
        inc rax
        and rax, r11
        jmp 4b
5:      lea edx, [r14 + 1]
        or edx, r8d
        mov [r9 + rax*4], edx
        inc r14
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
        xor esi, esi
        mov edx, 5
        jmp map_alloc
ENDF map2_new_cap

# map2_new_sized(cap, ecap) -> rax: a map of pairs of cap slots, room for
# ecap entries
FUNC map2_new_sized
        mov edx, 5
        jmp map_alloc
ENDF map2_new_sized

# map2_get(map, k1, k2) -> rax: the value, or 0; rdx: the entry's fourth
# word when there is one (map2_put_w's; 0 for map2_put's)
FUNC map2_get
        MAP2_HASH
        MAP_SLOTTAG r8, r8d
        mov rcx, [rdi + MAP_CAP]
        dec rcx
        and rax, rcx
        mov r9, [rdi + MAP_SLOTS]
1:      mov r10d, [r9 + rax*4]
        test r10d, r10d
        jz 2f
        xor r10d, r8d
        cmp r10d, MAP_IDXMASK
        ja 3f
        add r10d, MAP_SEG - 1
        MAP_ENTRY r10, r11, rdi, 5
        cmp [r10], rsi
        jne 3f
        cmp [r10 + 8], rdx
        je 4f
3:      inc rax
        and rax, rcx
        jmp 1b
2:      xor eax, eax
        ret
4:      mov rax, [r10 + 16]
        mov rdx, [r10 + 24]
        ret
ENDF map2_get

# map2_put(map, k1, k2, value): insert or replace (the fourth word 0)
FUNC map2_put
        xor r8d, r8d
        jmp map2_put_w
ENDF map2_put

# map2_put_w(map, k1, k2, value, w): insert or replace, w the entry's
# fourth word (map2_get's rdx)
FUNC map2_put_w
        ENTER
        sub rsp, 32
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
1:      mov rsi, r12
        mov rdx, r13
        MAP2_HASH
        MAP_SLOTTAG r8, r8d
        mov rcx, [rbx + MAP_CAP]
        dec rcx
        and rax, rcx
        mov r9, [rbx + MAP_SLOTS]
2:      mov r10d, [r9 + rax*4]
        test r10d, r10d
        jz 4f
        xor r10d, r8d
        cmp r10d, MAP_IDXMASK
        ja 3f
        add r10d, MAP_SEG - 1
        MAP_ENTRY r10, r11, rbx, 5
        cmp [r10], r12
        jne 3f
        cmp [r10 + 8], r13
        jne 3f
        mov [r10 + 16], r14             # there: replaced
        mov rax, [rsp]
        mov [r10 + 24], rax
        add rsp, 32
        LEAVE
3:      inc rax
        and rax, rcx
        jmp 2b
4:      mov [rsp + 8], r8               # a new entry, at the end
        mov [rsp + 16], rax
        mov rax, [rbx + MAP_COUNT]
        cmp rax, MAP_MAXCOUNT
        jae map_full
        cmp rax, [rbx + MAP_ECAP]
        jb 5f
        mov rdi, rbx
        call map_add_chunk
        mov rax, [rbx + MAP_COUNT]
5:      lea r10, [rax + MAP_SEG]
        MAP_ENTRY r10, r11, rbx, 5
        mov [r10], r12
        mov [r10 + 8], r13
        mov [r10 + 16], r14
        mov rdx, [rsp]
        mov [r10 + 24], rdx
        inc rax
        mov [rbx + MAP_COUNT], rax
        or eax, [rsp + 8]
        mov r9, [rbx + MAP_SLOTS]
        mov rcx, [rsp + 16]
        mov [r9 + rcx*4], eax
        add rsp, 32
        LEAVE
ENDF map2_put_w

# map2_grow(map): map_grow's, for the pairs
FUNC map2_grow
        ENTER
        mov rbx, rdi
        mov r13, [rbx + MAP_CAP]
        MAP_NEWCAP rdi
        mov r12, rdi
        shl rdi, 2
        call arena_alloc                # (first: see map_grow)
        mov [rbx + MAP_SLOTS], rax
        mov [rbx + MAP_CAP], r12
        mov r9, rax
        lea r11, [r12 - 1]
        xor r14d, r14d                  # the entry
1:      cmp r14, [rbx + MAP_COUNT]
        jae 3f
        lea r10, [r14 + MAP_SEG]
        MAP_ENTRY r10, rdi, rbx, 5
        mov rsi, [r10]
        mov rdx, [r10 + 8]
        MAP2_HASH
        MAP_SLOTTAG r8, r8d
        and rax, r11
4:      cmp dword ptr [r9 + rax*4], 0
        je 5f
        inc rax
        and rax, r11
        jmp 4b
5:      lea edx, [r14 + 1]
        or edx, r8d
        mov [r9 + rax*4], edx
        inc r14
        jmp 1b
3:      LEAVE
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
        xor r8d, r8d
        jmp memo2_put_w
ENDF memo2_put

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
        MAP_SLOTTAG r8, r8d
        mov r9, [rdi + MAP_CAP]
        dec r9
        and rax, r9
        push rbx
        mov rbx, [rdi + MAP_SLOTS]
1:      mov r10d, [rbx + rax*4]
        test r10d, r10d
        jz 2f
        xor r10d, r8d
        cmp r10d, MAP_IDXMASK
        ja 3f
        add r10d, MAP_SEG - 1
        MAP_ENTRY r10, r11, rdi, 5
        cmp [r10], rsi
        jne 3f
        cmp [r10 + 8], rdx
        jne 3f
        cmp [r10 + 16], rcx
        je 4f
3:      inc rax
        and rax, r9
        jmp 1b
2:      pop rbx
        xor eax, eax
        ret
4:      pop rbx
        mov rax, [r10 + 24]
        ret
ENDF map3_get

# map3_put(map, k1, k2, k3, value): insert or replace
FUNC map3_put
        ENTER
        sub rsp, 32
        mov [rsp], r8                   # value
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov r14, rcx
        mov rax, [rbx + MAP_COUNT]
        shl rax, 1
        cmp rax, [rbx + MAP_CAP]
        jb 1f
        mov rdi, rbx
        call map3_grow
1:      mov rsi, r12
        mov rdx, r13
        mov rcx, r14
        MAP3_HASH
        MAP_SLOTTAG r8, r8d
        mov r9, [rbx + MAP_CAP]
        dec r9
        and rax, r9
        mov rdi, [rbx + MAP_SLOTS]
2:      mov r10d, [rdi + rax*4]
        test r10d, r10d
        jz 4f
        xor r10d, r8d
        cmp r10d, MAP_IDXMASK
        ja 3f
        add r10d, MAP_SEG - 1
        MAP_ENTRY r10, r11, rbx, 5
        cmp [r10], r12
        jne 3f
        cmp [r10 + 8], r13
        jne 3f
        cmp [r10 + 16], r14
        jne 3f
        mov rax, [rsp]
        mov [r10 + 24], rax             # there: replaced
        add rsp, 32
        LEAVE
3:      inc rax
        and rax, r9
        jmp 2b
4:      mov [rsp + 8], r8               # a new entry, at the end
        mov [rsp + 16], rax
        mov rax, [rbx + MAP_COUNT]
        cmp rax, MAP_MAXCOUNT
        jae map_full
        cmp rax, [rbx + MAP_ECAP]
        jb 5f
        mov rdi, rbx
        call map_add_chunk
        mov rax, [rbx + MAP_COUNT]
5:      lea r10, [rax + MAP_SEG]
        MAP_ENTRY r10, r11, rbx, 5
        mov [r10], r12
        mov [r10 + 8], r13
        mov [r10 + 16], r14
        mov rdx, [rsp]
        mov [r10 + 24], rdx
        inc rax
        mov [rbx + MAP_COUNT], rax
        or eax, [rsp + 8]
        mov r9, [rbx + MAP_SLOTS]
        mov rcx, [rsp + 16]
        mov [r9 + rcx*4], eax
        add rsp, 32
        LEAVE
ENDF map3_put

# map3_grow(map): map_grow's, for the triples
FUNC map3_grow
        ENTER
        mov rbx, rdi
        mov r13, [rbx + MAP_CAP]
        MAP_NEWCAP rdi
        mov r12, rdi
        shl rdi, 2
        call arena_alloc                # (first: see map_grow)
        mov [rbx + MAP_SLOTS], rax
        mov [rbx + MAP_CAP], r12
        mov r9, rax
        lea r11, [r12 - 1]
        xor r14d, r14d                  # the entry
1:      cmp r14, [rbx + MAP_COUNT]
        jae 3f
        lea r10, [r14 + MAP_SEG]
        MAP_ENTRY r10, rdi, rbx, 5
        mov rsi, [r10]
        mov rdx, [r10 + 8]
        mov rcx, [r10 + 16]
        MAP3_HASH
        MAP_SLOTTAG r8, r8d
        and rax, r11
4:      cmp dword ptr [r9 + rax*4], 0
        je 5f
        inc rax
        and rax, r11
        jmp 4b
5:      lea edx, [r14 + 1]
        or edx, r8d
        mov [r9 + rax*4], edx
        inc r14
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
        mov rcx, [rdi + EMAP_CAP]
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
        mov [rax + EMAP_ENTRIES], rcx
        mov qword ptr [rax + EMAP_CAP], 1024
        mov qword ptr [rax + EMAP_COUNT], 0
        mov qword ptr [rax + EMAP_EPOCH], 1
        LEAVE
ENDF emap_new

# emap_begin(map): empty (a new epoch)
FUNC emap_begin
        inc qword ptr [rdi + EMAP_EPOCH]
        mov qword ptr [rdi + EMAP_COUNT], 0
        ret
ENDF emap_begin

# emap_get(map, key) -> rax: the value, or 0
FUNC emap_get
        EMAP_SLOT
        mov r8, [rdi + EMAP_EPOCH]
        mov rdx, [rdi + EMAP_ENTRIES]
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
        mov rax, [rbx + EMAP_COUNT]
        inc rax
        shl rax, 1
        cmp rax, [rbx + EMAP_CAP]
        jbe 1f
        mov rdi, rbx
        call emap_grow
1:      mov rdi, rbx
        mov rsi, r12
        EMAP_SLOT
        mov r8, [rbx + EMAP_EPOCH]
        mov rdx, [rbx + EMAP_ENTRIES]
2:      cmp [rdx + rax + 16], r8
        jne 3f
        cmp [rdx + rax], r12
        je 4f
        add rax, 32
        and rax, rcx
        jmp 2b
3:      inc qword ptr [rbx + EMAP_COUNT] # a slot taken
        mov [rdx + rax], r12
        mov [rdx + rax + 16], r8
4:      mov [rdx + rax + 8], r13
        LEAVE
ENDF emap_put

# emap_add(map, key) -> eax: 1 when the key is added (value 1), 0 when it
# was there already - a set's insertion, one probe
FUNC emap_add
        mov rax, [rdi + EMAP_COUNT]
        inc rax
        shl rax, 1
        cmp rax, [rdi + EMAP_CAP]
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
        mov rdx, [rdi + EMAP_ENTRIES]
2:      cmp [rdx + rax + 16], r8
        jne 3f
        cmp [rdx + rax], rsi
        je 4f
        add rax, 32
        and rax, rcx
        jmp 2b
3:      inc qword ptr [rdi + EMAP_COUNT] # a slot taken
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
        mov r12, [rbx + EMAP_ENTRIES]
        mov r13, [rbx + EMAP_CAP]
        lea rdi, [r13*2]
        shl rdi, 5
        call arena_alloc                # (zeroed: epoch 0, empty; first: see map_grow)
        mov [rbx + EMAP_ENTRIES], rax
        lea rax, [r13*2]
        mov [rbx + EMAP_CAP], rax
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
        mov rdx, [rbx + EMAP_ENTRIES]
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
