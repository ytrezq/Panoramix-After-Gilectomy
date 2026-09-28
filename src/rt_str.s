# Strings: global interning (so that equal strings are the same pointer),
# the opcode table, string builders and number formatting.

.include "defs.inc"

        .section .bss
        .align 8
str_table:      .quad 0         # node* array
str_cap:        .quad 0
str_count:      .quad 0
str_lock:       .quad 0

        .text

FUNC str_init
        ENTER
        mov edi, 4096
        mov esi, 8
        call calloc@PLT
        mov [rip + str_table], rax
        mov qword ptr [rip + str_cap], 4096
        LEAVE
ENDF str_init

# hash_bytes(ptr, len) -> rax (FNV-1a, then mixed)
FUNC hash_bytes
        movabs rax, 0xcbf29ce484222325
        movabs rcx, 0x100000001b3
        xor edx, edx
1:      cmp rdx, rsi
        jae 2f
        movzx r8d, byte ptr [rdi + rdx]
        xor rax, r8
        imul rax, rcx
        inc rdx
        jmp 1b
2:      mov rdi, rax
        jmp hash_mix
ENDF hash_bytes

FUNC str_lock_acquire
1:      mov eax, 1
        xchg eax, dword ptr [rip + str_lock]
        test eax, eax
        jz 2f
        pause
        jmp 1b
2:      ret
ENDF str_lock_acquire

FUNC str_lock_release
        mov dword ptr [rip + str_lock], 0
        ret
ENDF str_lock_release

# str_intern(ptr, len) -> rax: the unique K_STR node with these bytes
FUNC str_intern
        ENTER
        sub rsp, 32
        mov [rsp], rdi
        mov [rsp + 8], rsi
        call hash_bytes
        mov [rsp + 16], rax
        call str_lock_acquire
        mov rax, [rip + str_count]
        shl rax, 1
        cmp rax, [rip + str_cap]
        jb 1f
        call str_grow
1:      mov rbx, [rip + str_table]
        mov r13, [rip + str_cap]
        dec r13
        mov r12, [rsp + 16]
        and r12, r13
2:      mov rdi, [rbx + r12*8]
        test rdi, rdi
        jz .Lstr_new
        mov rax, [rsp + 16]
        cmp [rdi + N_HASH], rax
        jne 3f
        mov eax, [rdi + N_DATA]
        cmp rax, [rsp + 8]
        jne 3f
        lea rdi, [rdi + N_DATA + 4]
        mov rsi, [rsp]
        mov rdx, [rsp + 8]
        call memcmp@PLT
        test eax, eax
        jnz 3f
        mov rax, [rbx + r12*8]
        mov [rsp + 24], rax
        call str_lock_release
        mov rax, [rsp + 24]
        add rsp, 32
        LEAVE
3:      inc r12
        and r12, r13
        jmp 2b
.Lstr_new:
        mov rdi, [rsp + 8]
        add rdi, N_DATA + 4 + 1 + 15
        and rdi, -16
        call malloc@PLT
        mov r14, rax
        mov dword ptr [r14 + N_KIND], K_STR
        mov rdi, [rsp]
        mov rsi, [rsp + 8]
        call str_volatile_flag
        mov [r14 + N_AUX], eax
        mov rax, [rsp + 16]
        mov [r14 + N_HASH], rax
        mov rax, [rsp + 8]
        mov [r14 + N_DATA], eax
        lea rdi, [r14 + N_DATA + 4]
        mov rsi, [rsp]
        mov rdx, [rsp + 8]
        call memcpy@PLT
        mov rax, [rsp + 8]
        mov byte ptr [r14 + N_DATA + 4 + rax], 0
        mov [rbx + r12*8], r14
        inc qword ptr [rip + str_count]
        call str_lock_release
        mov rax, r14
        add rsp, 32
        LEAVE
ENDF str_intern

# str_volatile_flag(ptr, len) -> eax: STR_VOLATILE if the string mentions
# one of the VOLATILE names (see arithmetic.py), else 0
FUNC str_volatile_flag
        ENTER
        mov r12, rdi
        mov r13, rsi
        lea rbx, [rip + volatile_names]
1:      mov rdi, [rbx]
        test rdi, rdi
        jz 3f
        call strlen@PLT
        mov r14, rax                    # name length
        cmp r14, r13
        ja 2f
        # naive substring search
        xor ecx, ecx
4:      lea rax, [rcx + r14]
        cmp rax, r13
        ja 2f
        push rcx
        push rcx
        lea rdi, [r12 + rcx]
        mov rsi, [rbx]
        mov rdx, r14
        call memcmp@PLT
        pop rcx
        pop rcx
        test eax, eax
        jz 5f
        inc rcx
        jmp 4b
2:      add rbx, 8
        jmp 1b
5:      mov eax, STR_VOLATILE
        LEAVE
3:      xor eax, eax
        LEAVE
ENDF str_volatile_flag

        .section .data.rel.ro
        .align 8
volatile_names:
        .quad .Lv0, .Lv1, .Lv2, .Lv3, .Lv4, .Lv5, .Lv6, .Lv7, .Lv8, .Lv9, .Lv10, .Lv11, .Lv12, 0
        .section .rodata
.Lv0:  .asciz "storage"
.Lv1:  .asciz "balance"
.Lv2:  .asciz "ext_call"
.Lv3:  .asciz "returndatasize"
.Lv4:  .asciz "return_code"
.Lv5:  .asciz "new_address"
.Lv6:  .asciz "memcopy"
.Lv7:  .asciz ".result"
.Lv8:  .asciz "gas"
.Lv9:  .asciz "extcodesize"
.Lv10: .asciz "extcodehash"
.Lv11: .asciz "mem"
.Lv12: .asciz "msize"
        .text

# str_grow(): double the intern table (lock held)
FUNC str_grow
        ENTER
        mov r12, [rip + str_table]
        mov r13, [rip + str_cap]
        lea rdi, [r13 * 2]
        mov [rip + str_cap], rdi
        mov esi, 8
        call calloc@PLT
        mov [rip + str_table], rax
        mov rbx, rax
        xor r14d, r14d
1:      cmp r14, r13
        jae 3f
        mov rdi, [r12 + r14*8]
        test rdi, rdi
        jz 2f
        mov rax, [rdi + N_HASH]
        mov rcx, [rip + str_cap]
        dec rcx
        and rax, rcx
4:      cmp qword ptr [rbx + rax*8], 0
        je 5f
        inc rax
        and rax, rcx
        jmp 4b
5:      mov [rbx + rax*8], rdi
2:      inc r14
        jmp 1b
3:      mov rdi, r12
        call free@PLT
        LEAVE
ENDF str_grow

# str_intern_c(cstr) -> rax
FUNC str_intern_c
        ENTER
        mov rbx, rdi
        call strlen@PLT
        mov rdi, rbx
        mov rsi, rax
        call str_intern
        LEAVE
ENDF str_intern_c

# opcodes_init(): intern the opcode names with their ids
FUNC opcodes_init
        ENTER
        xor ebx, ebx
1:      cmp rbx, [rip + opcode_names_count]
        jae 2f
        lea rax, [rip + opcode_names]
        mov rdi, [rax + rbx*8]
        call str_intern_c
        lea ecx, [rbx + 1]
        or [rax + N_AUX], ecx
        lea rdx, [rip + opcode_nodes]
        mov [rdx + rcx*8], rax
        inc rbx
        jmp 1b
2:      LEAVE
ENDF opcodes_init

# --- string builder ---

# sb_new() -> rax (malloc'ed; the buffer is malloc'ed too, so that the
# result can be handed to the caller and freed with free())
FUNC sb_new
        ENTER
        mov edi, SB_SIZEOF
        call malloc@PLT
        mov rbx, rax
        mov edi, 256
        call malloc@PLT
        mov [rbx + SB_BUF], rax
        mov qword ptr [rbx + SB_LEN], 0
        mov qword ptr [rbx + SB_CAP], 256
        mov byte ptr [rax], 0
        mov rax, rbx
        LEAVE
ENDF sb_new

# sb_reserve(sb, extra): make room for `extra` more bytes plus a NUL
FUNC sb_reserve
        ENTER
        mov rbx, rdi
        mov rax, [rbx + SB_LEN]
        add rax, rsi
        inc rax
        cmp rax, [rbx + SB_CAP]
        jbe 1f
        mov rcx, [rbx + SB_CAP]
2:      shl rcx, 1
        cmp rax, rcx
        ja 2b
        mov [rbx + SB_CAP], rcx
        mov rdi, [rbx + SB_BUF]
        mov rsi, rcx
        call realloc@PLT
        mov [rbx + SB_BUF], rax
1:      LEAVE
ENDF sb_reserve

# sb_append(sb, ptr, len)
FUNC sb_append
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov rsi, rdx
        call sb_reserve
        mov rdi, [rbx + SB_BUF]
        add rdi, [rbx + SB_LEN]
        mov rsi, r12
        mov rdx, r13
        call memcpy@PLT
        add [rbx + SB_LEN], r13
        mov rax, [rbx + SB_BUF]
        add rax, [rbx + SB_LEN]
        mov byte ptr [rax], 0
        LEAVE
ENDF sb_append

# sb_append_c(sb, cstr)
FUNC sb_append_c
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rsi
        call strlen@PLT
        mov rdi, rbx
        mov rsi, r12
        mov rdx, rax
        call sb_append
        LEAVE
ENDF sb_append_c

# sb_append_str(sb, strnode)
FUNC sb_append_str
        mov edx, [rsi + N_DATA]
        add rsi, N_DATA + 4
        jmp sb_append
ENDF sb_append_str

# sb_append_char(sb, c)
FUNC sb_append_char
        ENTER
        sub rsp, 16
        mov [rsp], sil
        mov rsi, rsp
        mov edx, 1
        call sb_append
        add rsp, 16
        LEAVE
ENDF sb_append_char

# sb_append_u64(sb, x): decimal
FUNC sb_append_u64
        ENTER
        sub rsp, 32
        mov rbx, rdi
        lea rdi, [rsp + 31]
        mov byte ptr [rdi], 0
        mov rax, rsi
        mov ecx, 10
1:      dec rdi
        xor edx, edx
        div rcx
        add dl, '0'
        mov [rdi], dl
        test rax, rax
        jnz 1b
        mov rsi, rdi
        mov rdi, rbx
        call sb_append_c
        add rsp, 32
        LEAVE
ENDF sb_append_u64

# sb_append_i64(sb, x): decimal, signed
FUNC sb_append_i64
        test rsi, rsi
        jns sb_append_u64
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov esi, '-'
        call sb_append_char
        mov rdi, rbx
        mov rsi, r12
        neg rsi
        call sb_append_u64
        LEAVE
ENDF sb_append_i64

# sb_append_hex(sb, x): 0x..., lowercase, no padding (like python's hex())
FUNC sb_append_hex
        ENTER
        sub rsp, 32
        mov rbx, rdi
        lea rdi, [rsp + 31]
        mov byte ptr [rdi], 0
        mov rax, rsi
1:      dec rdi
        mov edx, eax
        and edx, 15
        lea rcx, [rip + .Lhexdigits]
        mov dl, [rcx + rdx]
        mov [rdi], dl
        shr rax, 4
        jnz 1b
        dec rdi
        mov byte ptr [rdi], 'x'
        dec rdi
        mov byte ptr [rdi], '0'
        mov rsi, rdi
        mov rdi, rbx
        call sb_append_c
        add rsp, 32
        LEAVE
ENDF sb_append_hex

        .section .rodata
.Lhexdigits: .ascii "0123456789abcdef"
        .text

# sb_append_int(sb, v, base): an integer value (small or big), base 10 or 16
# (16 gives 0x..., negative numbers get a leading '-')
FUNC sb_append_int
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        test sil, 1
        jz .Lbig
        UNTAG rsi
        cmp r13, 16
        je 1f
        call sb_append_i64
        LEAVE
1:      test rsi, rsi
        jns 2f
        mov r12, rsi
        mov esi, '-'
        call sb_append_char
        mov rdi, rbx
        mov rsi, r12
        neg rsi
2:      call sb_append_hex
        LEAVE
.Lbig:  # mpz_get_str(NULL, base, mpz) -> allocated via our arena
        lea rdx, [r12 + N_DATA]
        xor edi, edi
        mov rsi, r13
        call __gmpz_get_str@PLT
        mov r14, rax
        cmp r13, 16
        jne 3f
        cmp byte ptr [r14], '-'
        jne 4f
        mov rdi, rbx
        mov esi, '-'
        call sb_append_char
        inc r14
4:      mov rdi, rbx
        lea rsi, [rip + .Lhexprefix]
        call sb_append_c
3:      mov rdi, rbx
        mov rsi, r14
        call sb_append_c
        LEAVE
ENDF sb_append_int

        .section .rodata
.Lhexprefix: .asciz "0x"
        .text

# --- arena strings: for text that is built and printed, not compared by
# pointer (the interned strings live for the whole process, these are
# freed with the thread's arena). Same layout as the interned ones, so
# everything that reads a string works on both.

# str_new(ptr, len) -> rax
FUNC str_new
        ENTER
        sub rsp, 16
        mov [rsp], rdi
        mov [rsp + 8], rsi
        lea rdi, [rsi + N_DATA + 4 + 1]
        call arena_alloc
        mov r12, rax
        mov dword ptr [r12 + N_KIND], K_STR
        mov rdi, [rsp]
        mov rsi, [rsp + 8]
        call str_volatile_flag
        mov [r12 + N_AUX], eax
        mov rdi, [rsp]
        mov rsi, [rsp + 8]
        call hash_bytes
        mov [r12 + N_HASH], rax
        mov rax, [rsp + 8]
        mov [r12 + N_DATA], eax
        lea rdi, [r12 + N_DATA + 4]
        mov rsi, [rsp]
        mov rdx, [rsp + 8]
        call memcpy@PLT
        mov rax, [rsp + 8]
        mov byte ptr [r12 + N_DATA + 4 + rax], 0
        mov rax, r12
        add rsp, 16
        LEAVE
ENDF str_new

# str_new_c(cstr) -> rax
FUNC str_new_c
        ENTER
        mov rbx, rdi
        call strlen@PLT
        mov rdi, rbx
        mov rsi, rax
        call str_new
        LEAVE
ENDF str_new_c

# sb_to_str(sb) -> rax: the builder's text as an arena string
FUNC sb_to_str
        mov rsi, [rdi + SB_LEN]
        mov rdi, [rdi + SB_BUF]
        jmp str_new
ENDF sb_to_str

# sb_finish(sb) -> rax: sb_to_str, and the builder is freed
FUNC sb_finish
        ENTER
        mov rbx, rdi
        call sb_to_str
        mov r12, rax
        mov rdi, rbx
        call sb_free
        mov rax, r12
        LEAVE
ENDF sb_finish

# sb_reset(sb): empty
FUNC sb_reset
        mov qword ptr [rdi + SB_LEN], 0
        mov rax, [rdi + SB_BUF]
        mov byte ptr [rax], 0
        ret
ENDF sb_reset

# str_eq(a, b) -> eax: same text (for strings that may not be interned)
FUNC str_eq
        cmp rdi, rsi
        je 2f
        mov eax, [rdi + N_DATA]
        cmp eax, [rsi + N_DATA]
        jne 3f
        ENTER
        mov edx, eax
        add rdi, N_DATA + 4
        add rsi, N_DATA + 4
        call memcmp@PLT
        test eax, eax
        sete al
        movzx eax, al
        LEAVE
2:      mov eax, 1
        ret
3:      xor eax, eax
        ret
ENDF str_eq

# str_eq_c(str, cstr) -> eax
FUNC str_eq_c
        ENTER
        lea rdi, [rdi + N_DATA + 4]
        call strcmp@PLT
        test eax, eax
        sete al
        movzx eax, al
        LEAVE
ENDF str_eq_c

# str_contains_c(str, cstr) -> eax: python's `cstr in str`
FUNC str_contains_c
        ENTER
        lea rdi, [rdi + N_DATA + 4]
        call strstr@PLT
        test rax, rax
        setne al
        movzx eax, al
        LEAVE
ENDF str_contains_c

# str_startswith_c(str, cstr) -> eax
FUNC str_startswith_c
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rsi
        call strlen@PLT
        cmp eax, [rbx + N_DATA]
        ja 1f
        lea rdi, [rbx + N_DATA + 4]
        mov rsi, r12
        mov rdx, rax
        call memcmp@PLT
        test eax, eax
        sete al
        movzx eax, al
        LEAVE
1:      xor eax, eax
        LEAVE
ENDF str_startswith_c

# str_count_char(str, c) -> eax
FUNC str_count_char
        mov ecx, [rdi + N_DATA]
        add rdi, N_DATA + 4
        xor eax, eax
1:      test ecx, ecx
        jz 2f
        cmp [rdi], sil
        jne 3f
        inc eax
3:      inc rdi
        dec ecx
        jmp 1b
2:      ret
ENDF str_count_char

# str_cat2(a, b) / str_cat3(a, b, c) -> rax: concatenations (arena)
FUNC str_cat2
        xor edx, edx
        jmp str_cat3
ENDF str_cat2

FUNC str_cat3
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        call sb_new
        mov r14, rax
        mov rdi, rax
        mov rsi, rbx
        call sb_append_str
        mov rdi, r14
        mov rsi, r12
        call sb_append_str
        test r13, r13
        jz 1f
        mov rdi, r14
        mov rsi, r13
        call sb_append_str
1:      mov rdi, r14
        call sb_finish
        LEAVE
ENDF str_cat3

# str_slice(str, start, stop) -> rax: str[start:stop] (arena; the bounds
# are clamped like python's)
FUNC str_slice
        mov eax, [rdi + N_DATA]
        cmp rdx, rax
        cmova rdx, rax                  # stop = min(stop, len)
        cmp rsi, rdx
        cmova rsi, rdx                  # start = min(start, stop)
        sub rdx, rsi
        lea rdi, [rdi + N_DATA + 4 + rsi]
        mov rsi, rdx
        jmp str_new
ENDF str_slice

# str_join(sep_cstr, list) -> rax: the strings of the list joined
FUNC str_join
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call sb_new
        mov r13, rax
        xor r14d, r14d
1:      cmp r14d, [r12 + N_AUX]
        jae 2f
        test r14d, r14d
        jz 3f
        mov rdi, r13
        mov rsi, rbx
        call sb_append_c
3:      mov rdi, r13
        mov rsi, [r12 + N_DATA + r14*8]
        call sb_append_str
        inc r14d
        jmp 1b
2:      mov rdi, r13
        call sb_finish
        LEAVE
ENDF str_join

# str_chars(str) -> rax: the list of its one-character strings (python
# iterating over a string where a tuple of strings was expected)
FUNC str_chars
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        xor r13d, r13d
1:      cmp r13d, [rbx + N_DATA]
        jae 2f
        lea rdi, [rbx + N_DATA + 4 + r13]
        mov esi, 1
        call str_new
        mov rdi, r12
        mov rsi, rax
        call vec_push
        inc r13d
        jmp 1b
2:      mov rdi, r12
        call vec_to_list
        LEAVE
ENDF str_chars

        .section .note.GNU-stack,"",@progbits
