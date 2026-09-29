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
        call xcalloc
        mov [rip + str_table], rax
        mov qword ptr [rip + str_cap], 4096
        LEAVE
ENDF str_init

# hash_bytes(ptr, len) -> rax: eight bytes at a time (a multiply and a
# rotation each), the last one to seven bytes as one more word, then
# mixed (Murmur3's finalizer). Every string made gets hashed - the
# printer's, whole lines, many times over: byte by byte, this was 1% of
# the instructions
FUNC hash_bytes
        movabs rax, 0xcbf29ce484222325
        xor rax, rsi                    # (the length in)
        movabs rcx, 0x9e3779b97f4a7c15
        mov rdx, rsi
        shr rdx, 3                      # the words
        jz 2f
1:      xor rax, [rdi]
        add rdi, 8
        imul rax, rcx
        rol rax, 29
        dec rdx
        jnz 1b
2:      and esi, 7
        jz 4f
        xor r8d, r8d                    # the tail, a byte at a time (no
3:      shl r8, 8                       # read past the end)
        movzx r9d, byte ptr [rdi + rsi - 1]
        or r8, r9
        dec esi
        jnz 3b
        xor rax, r8
        imul rax, rcx
        rol rax, 29
4:      mov rdi, rax
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
        mov rcx, HF_MASK
        not rcx
        and rax, rcx
        mov [rsp + 16], rax
        mov rdi, [rsp]
        mov rsi, [rsp + 8]
        call str_scan_flags
        or [rsp + 16], rdx              # the mention flags, in the hash
        mov [rsp + 24], rax             # STR_VOLATILE, in the aux
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
        call xmalloc
        mov r14, rax
        mov dword ptr [r14 + N_KIND], K_STR
        mov rax, [rsp + 24]
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

# str_scan_flags(ptr, len) -> eax: STR_VOLATILE if the string mentions one
# of the VOLATILE names (see arithmetic.py), else 0 (and HF_VOLATILE in
# rdx then); rdx: the HF_* mention
# flags ("mem", "msize", "storage" anywhere; HF_VAR: the string "var",
# HF_SETVAR: "setvar", HF_GOTO: "goto", HF_CONTINUE: "continue"). One
# pass over the text: a byte is
# looked up in a table of the names' first letters, and only a candidate
# is compared with the names.
FUNC str_scan_flags
        ENTER
        sub rsp, 48
        .set SF_HF, 0                   # the HF flags
        .set SF_VOLATILE, 8             # STR_VOLATILE or 0
        .set SF_CANDIDATES, 16          # the names still to try at this position
        .set SF_NAME, 24                # the entry of scan_names being tried
        .set SF_MASK, 32                # the vector loop: the candidates of a chunk
        .set SF_CHUNK, 40               # and its position
        mov r12, rdi                    # text
        mov r13, rsi                    # its length
        mov qword ptr [rsp + SF_HF], 0
        mov qword ptr [rsp + SF_VOLATILE], 0
        lea rbx, [rip + scan_first]
        xor r14d, r14d                  # position
        cmp qword ptr [rip + isa_level], 2
        jb .Lsf_sse2
        # AVX2: 32 positions at a time, the candidates those where the
        # name's first two bytes are (every name has 3 or more), both
        # loads inside the string
.Lsf_chunk:
        lea rax, [r14 + 33]
        cmp rax, r13
        ja 1f                           # the rest, byte by byte
        vmovdqu ymm0, [r12 + r14]       # the bytes at p
        vmovdqu ymm1, [r12 + r14 + 1]   # and after them
        vpcmpeqb ymm2, ymm0, [rip + .Lsv_s]
        vpcmpeqb ymm3, ymm1, [rip + .Lsv_t]
        vpand ymm4, ymm2, ymm3          # st
        vpcmpeqb ymm2, ymm0, [rip + .Lsv_b]
        vpcmpeqb ymm5, ymm1, [rip + .Lsv_a]
        vpand ymm2, ymm2, ymm5          # ba
        vpor ymm4, ymm4, ymm2
        vpcmpeqb ymm2, ymm0, [rip + .Lsv_g]
        vpand ymm2, ymm2, ymm5          # ga
        vpor ymm4, ymm4, ymm2
        vpcmpeqb ymm2, ymm0, [rip + .Lsv_e]
        vpcmpeqb ymm3, ymm1, [rip + .Lsv_x]
        vpand ymm2, ymm2, ymm3          # ex
        vpor ymm4, ymm4, ymm2
        vpcmpeqb ymm5, ymm1, [rip + .Lsv_e]
        vpcmpeqb ymm2, ymm0, [rip + .Lsv_r]
        vpand ymm2, ymm2, ymm5          # re
        vpor ymm4, ymm4, ymm2
        vpcmpeqb ymm2, ymm0, [rip + .Lsv_n]
        vpand ymm2, ymm2, ymm5          # ne
        vpor ymm4, ymm4, ymm2
        vpcmpeqb ymm3, ymm0, [rip + .Lsv_m]
        vpand ymm2, ymm3, ymm5          # me
        vpor ymm4, ymm4, ymm2
        vpcmpeqb ymm2, ymm1, [rip + .Lsv_s]
        vpand ymm2, ymm2, ymm3          # ms
        vpor ymm4, ymm4, ymm2
        vpcmpeqb ymm2, ymm0, [rip + .Lsv_dot]
        vpcmpeqb ymm3, ymm1, [rip + .Lsv_r]
        vpand ymm2, ymm2, ymm3          # .r
        vpor ymm4, ymm4, ymm2
        vpmovmskb eax, ymm4
        vzeroupper                      # (memcmp is SSE code)
        test eax, eax
        jz .Lsf_next_chunk
        mov [rsp + SF_MASK], rax
        mov [rsp + SF_CHUNK], r14
.Lsf_bit:
        mov rax, [rsp + SF_MASK]
        test eax, eax
        jz .Lsf_chunk_done
        tzcnt ecx, eax
        btr eax, ecx
        mov [rsp + SF_MASK], rax
        mov r14, [rsp + SF_CHUNK]
        add r14, rcx
        call .Lsf_check
        jmp .Lsf_bit
.Lsf_chunk_done:
        mov r14, [rsp + SF_CHUNK]
.Lsf_next_chunk:
        add r14, 32
        jmp .Lsf_chunk
        # SSE2: the same, 16 positions at a time
.Lsf_sse2:
        cmp qword ptr [rip + isa_level], 1
        jb 1f
.Lsf_chunk16:
        lea rax, [r14 + 17]
        cmp rax, r13
        ja 1f                           # the rest, byte by byte
        movdqu xmm0, [r12 + r14]        # the bytes at p
        movdqu xmm1, [r12 + r14 + 1]    # and after them
        movdqa xmm2, xmm0
        pcmpeqb xmm2, [rip + .Lsv_s]
        movdqa xmm3, xmm1
        pcmpeqb xmm3, [rip + .Lsv_t]
        pand xmm2, xmm3
        movdqa xmm4, xmm2               # st
        movdqa xmm5, xmm1
        pcmpeqb xmm5, [rip + .Lsv_a]    # (?a)
        movdqa xmm2, xmm0
        pcmpeqb xmm2, [rip + .Lsv_b]
        pand xmm2, xmm5
        por xmm4, xmm2                  # ba
        movdqa xmm2, xmm0
        pcmpeqb xmm2, [rip + .Lsv_g]
        pand xmm2, xmm5
        por xmm4, xmm2                  # ga
        movdqa xmm2, xmm0
        pcmpeqb xmm2, [rip + .Lsv_e]
        movdqa xmm3, xmm1
        pcmpeqb xmm3, [rip + .Lsv_x]
        pand xmm2, xmm3
        por xmm4, xmm2                  # ex
        movdqa xmm5, xmm1
        pcmpeqb xmm5, [rip + .Lsv_e]    # (?e)
        movdqa xmm2, xmm0
        pcmpeqb xmm2, [rip + .Lsv_r]
        pand xmm2, xmm5
        por xmm4, xmm2                  # re
        movdqa xmm2, xmm0
        pcmpeqb xmm2, [rip + .Lsv_n]
        pand xmm2, xmm5
        por xmm4, xmm2                  # ne
        movdqa xmm3, xmm0
        pcmpeqb xmm3, [rip + .Lsv_m]    # (m?)
        movdqa xmm2, xmm3
        pand xmm2, xmm5
        por xmm4, xmm2                  # me
        movdqa xmm2, xmm1
        pcmpeqb xmm2, [rip + .Lsv_s]
        pand xmm2, xmm3
        por xmm4, xmm2                  # ms
        movdqa xmm2, xmm0
        pcmpeqb xmm2, [rip + .Lsv_dot]
        movdqa xmm3, xmm1
        pcmpeqb xmm3, [rip + .Lsv_r]
        pand xmm2, xmm3
        por xmm4, xmm2                  # .r
        pmovmskb eax, xmm4
        test eax, eax
        jz .Lsf_next_chunk16
        mov [rsp + SF_MASK], rax
        mov [rsp + SF_CHUNK], r14
.Lsf_bit16:
        mov rax, [rsp + SF_MASK]
        test eax, eax
        jz .Lsf_chunk16_done
        bsf ecx, eax
        btr eax, ecx
        mov [rsp + SF_MASK], rax
        mov r14, [rsp + SF_CHUNK]
        add r14, rcx
        call .Lsf_check
        jmp .Lsf_bit16
.Lsf_chunk16_done:
        mov r14, [rsp + SF_CHUNK]
.Lsf_next_chunk16:
        add r14, 16
        jmp .Lsf_chunk16
        # byte by byte
1:      cmp r14, r13
        jae 9f
        movzx eax, byte ptr [r12 + r14]
        cmp word ptr [rbx + rax*2], 0
        je 11f                          # (no name starts with it)
        call .Lsf_check
11:     inc r14
        jmp 1b
9:      cmp r13, 3                      # "var" exactly: HF_VAR
        jne 12f
        movzx eax, word ptr [r12]
        cmp eax, 0x6176                 # "va"
        jne 10f
        cmp byte ptr [r12 + 2], 'r'
        jne 10f
        mov rax, HF_VAR
        or [rsp + SF_HF], rax
        jmp 10f
12:     cmp r13, 6                      # "setvar" exactly: HF_SETVAR
        jne 13f
        cmp dword ptr [r12], 0x76746573 # "setv"
        jne 10f
        cmp word ptr [r12 + 4], 0x7261  # "ar"
        jne 10f
        mov rax, HF_SETVAR
        or [rsp + SF_HF], rax
        jmp 10f
13:     cmp r13, 4                      # "goto" exactly: HF_GOTO
        jne 14f
        cmp dword ptr [r12], 0x6f746f67 # "goto"
        jne 10f
        mov rax, HF_GOTO
        or [rsp + SF_HF], rax
        jmp 10f
14:     cmp r13, 8                      # "continue" exactly: HF_CONTINUE
        jne 10f
        movabs rax, 0x65756e69746e6f63  # "continue"
        cmp [r12], rax
        jne 10f
        mov rax, HF_CONTINUE
        or [rsp + SF_HF], rax
10:     mov eax, [rsp + SF_VOLATILE]
        mov rdx, [rsp + SF_HF]
        test eax, eax
        jz 11f
        movabs rcx, HF_VOLATILE         # (the tuples above know it too)
        or rdx, rcx
11:     add rsp, 48
        LEAVE
# the names starting at position r14 (the frame is 16 bytes up: the
# return address, the alignment)
.Lsf_check:
        movzx eax, byte ptr [r12 + r14]
        movzx eax, word ptr [rbx + rax*2]  # the names starting with this byte
        test eax, eax
        jz 8f
        sub rsp, 8
        mov [rsp + 16 + SF_CANDIDATES], rax
2:      mov eax, [rsp + 16 + SF_CANDIDATES]
        test eax, eax
        jz 7f
        tzcnt ecx, eax                  # the name's index
        btr eax, ecx
        mov [rsp + 16 + SF_CANDIDATES], rax
        lea rax, [rcx + rcx*2]          # 24 bytes per entry
        lea rdx, [rip + scan_names]
        lea rax, [rdx + rax*8]
        mov [rsp + 16 + SF_NAME], rax
        mov rdx, [rax + 8]              # the name's length
        lea rcx, [r14 + rdx]
        cmp rcx, r13
        ja 2b                           # too close to the end
        lea rdi, [r12 + r14]
        mov rsi, [rax]
        call memcmp@PLT
        test eax, eax
        jnz 2b
        mov rax, [rsp + 16 + SF_NAME]
        mov rax, [rax + 16]             # the name's HF flags
        or [rsp + 16 + SF_HF], rax
        mov dword ptr [rsp + 16 + SF_VOLATILE], STR_VOLATILE
        jmp 2b
7:      add rsp, 8
8:      ret
ENDF str_scan_flags

        .section .rodata
        .align 32
.Lsv_s:   .fill 32, 1, 's'
.Lsv_t:   .fill 32, 1, 't'
.Lsv_b:   .fill 32, 1, 'b'
.Lsv_a:   .fill 32, 1, 'a'
.Lsv_g:   .fill 32, 1, 'g'
.Lsv_e:   .fill 32, 1, 'e'
.Lsv_x:   .fill 32, 1, 'x'
.Lsv_r:   .fill 32, 1, 'r'
.Lsv_n:   .fill 32, 1, 'n'
.Lsv_m:   .fill 32, 1, 'm'
.Lsv_dot: .fill 32, 1, '.'
        .text

        .section .data.rel.ro
        .align 8
scan_names:                             # (text, length, HF flags), in the order of scan_first's bits
        .quad .Lv0, 7, HF_STORAGE       # storage
        .quad .Lv1, 7, 0                # balance
        .quad .Lv2, 8, 0                # ext_call
        .quad .Lv3, 14, 0               # returndatasize
        .quad .Lv4, 11, 0               # return_code
        .quad .Lv5, 11, 0               # new_address
        .quad .Lv6, 7, HF_MEM           # memcopy (contains "mem")
        .quad .Lv7, 7, 0                # .result
        .quad .Lv8, 3, 0                # gas
        .quad .Lv9, 11, 0               # extcodesize
        .quad .Lv10, 11, 0              # extcodehash
        .quad .Lv11, 3, HF_MEM          # mem
        .quad .Lv12, 5, HF_MSIZE        # msize
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
        # scan_first[byte]: the names (bits of scan_names' order) starting with it
        .align 2
scan_first:
        .fill '.', 2, 0
        .short 1 << 7                   # '.': .result
        .fill 'b' - '.' - 1, 2, 0
        .short 1 << 1                   # 'b': balance
        .fill 'e' - 'b' - 1, 2, 0
        .short (1 << 2) | (1 << 9) | (1 << 10)   # 'e': ext_call, extcodesize, extcodehash
        .fill 'g' - 'e' - 1, 2, 0
        .short 1 << 8                   # 'g': gas
        .fill 'm' - 'g' - 1, 2, 0
        .short (1 << 6) | (1 << 11) | (1 << 12)  # 'm': memcopy, mem, msize
        .short 1 << 5                   # 'n': new_address
        .fill 'r' - 'n' - 1, 2, 0
        .short (1 << 3) | (1 << 4)      # 'r': returndatasize, return_code
        .short 1 << 0                   # 's': storage
        .fill 255 - 's', 2, 0
        .text


# str_grow(): double the intern table (lock held)
FUNC str_grow
        ENTER
        mov r12, [rip + str_table]
        mov r13, [rip + str_cap]
        lea rdi, [r13 * 2]
        mov [rip + str_cap], rdi
        mov esi, 8
        call xcalloc
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
        call xmalloc
        mov rbx, rax
        mov edi, 256
        call xmalloc
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
        call xrealloc
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

# sb_append_clean(sb, ptr, len): the bytes appended, everything that
# isn't printable ASCII as \xNN (the backslash too). For text that comes
# from outside and ends up on a terminal - what a node answers: an error
# object, a result that isn't code, an HTTP reason. The contract's own
# strings go through pretty_bignum, which takes only printable bytes.
FUNC sb_append_clean
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        xor r14d, r14d
1:      cmp r14, r13
        jae 9f
        mov [rsp], r14                  # a run of bytes that can go as they are
2:      cmp r14, r13
        jae 3f
        movzx eax, byte ptr [r12 + r14]
        cmp al, ' '
        jb 3f
        cmp al, 0x7e
        ja 3f
        cmp al, '\\'
        je 3f
        inc r14
        jmp 2b
3:      mov rdx, r14
        sub rdx, [rsp]
        jz 4f
        mov rdi, rbx
        mov rsi, r12
        add rsi, [rsp]
        call sb_append
4:      cmp r14, r13
        jae 9f
        movzx esi, byte ptr [r12 + r14]
        mov rdi, rbx
        call sb_append_byte_hex
        inc r14
        jmp 1b
9:      add rsp, 16
        LEAVE
ENDF sb_append_clean

# sb_append_clean_c(sb, cstr): sb_append_clean of a NUL-terminated string
FUNC sb_append_clean_c
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rsi
        call strlen@PLT
        mov rdi, rbx
        mov rsi, r12
        mov rdx, rax
        call sb_append_clean
        LEAVE
ENDF sb_append_clean_c

# sb_append_byte_hex(sb, byte): \xNN
FUNC sb_append_byte_hex
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov eax, esi
        mov byte ptr [rsp], '\\'
        mov byte ptr [rsp + 1], 'x'
        lea rcx, [rip + .Lhexdigits]
        mov edx, eax
        shr edx, 4
        and edx, 15
        mov dl, [rcx + rdx]
        mov [rsp + 2], dl
        mov edx, eax
        and edx, 15
        mov dl, [rcx + rdx]
        mov [rsp + 3], dl
        mov rdi, rbx
        mov rsi, rsp
        mov edx, 4
        call sb_append
        add rsp, 16
        LEAVE
ENDF sb_append_byte_hex

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
        call arena_alloc_raw
        mov r12, rax
        mov dword ptr [r12 + N_KIND], K_STR
        mov rdi, [rsp]
        mov rsi, [rsp + 8]
        call hash_bytes
        mov rcx, HF_MASK
        not rcx
        and rax, rcx
        mov [r12 + N_HASH], rax
        mov rdi, [rsp]
        mov rsi, [rsp + 8]
        call str_scan_flags
        mov [r12 + N_AUX], eax
        or [r12 + N_HASH], rdx
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


# str_charlen(str) -> eax: python's len() - the characters (code points)
# of the UTF-8 text, not its bytes
FUNC str_charlen
        mov ecx, [rdi + N_DATA]
        add rdi, N_DATA + 4
        xor eax, eax
1:      test ecx, ecx
        jz 2f
        movzx edx, byte ptr [rdi]
        and edx, 0xc0
        cmp edx, 0x80                   # a continuation byte
        je 3f
        inc eax
3:      inc rdi
        dec ecx
        jmp 1b
2:      ret
ENDF str_charlen

# sb_finish_intern(sb) -> rax: like sb_finish, interned (for text that
# goes into expressions, where equal strings must be the same node)
FUNC sb_finish_intern
        ENTER
        mov rbx, rdi
        mov rdi, [rbx + SB_BUF]
        mov rsi, [rbx + SB_LEN]
        call str_intern
        mov r12, rax
        mov rdi, rbx
        call sb_free
        mov rax, r12
        LEAVE
ENDF sb_finish_intern

# str_interned(str) -> rax: the interned node of a string's text
FUNC str_interned
        mov esi, [rdi + N_DATA]
        add rdi, N_DATA + 4
        jmp str_intern
ENDF str_interned

        .section .note.GNU-stack,"",@progbits
