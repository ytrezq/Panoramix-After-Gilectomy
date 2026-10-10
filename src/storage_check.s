# The check of storage.py: what a printed access reads, on random values of
# what its slot is computed from - python's World, ev, evb, read, read_loc,
# access_value, checks. A world is its seed (0 to 3; python's WORLDS): the
# value of a symbol is the blake2b of "seed:repr(symbol)", the same for the
# same, small (16 bits) in the odd worlds. Values are words (32 bytes, the
# least significant limb first: runtrace.s's), made without a node; the
# bytes evb makes are a stack in the check's buffer (CK_BUF), which a sha3
# hashes from where its parts began.

.include "defs.inc"

.set E_UNKNOWN, 41
.set E_ZERO_DIV, 42

# a check's state
.set CK_SEED, 0                 # the world
.set CK_BUF, 8                  # the bytes being made (arena), their count,
.set CK_LEN, 16                 # the room
.set CK_CAP, 24
.set CK_SIZEOF, 32

# what read_loc gives
.set RL_SLOT, 0                 # the slot: a word
.set RL_BLEN, 32                # 1: ('blen', slot)
.set RL_BIT, 40                 # an int value
.set RL_WIDTH, 48               # an int value
.set RL_TYPE, 56                # a type, or 0 (None)
.set RL_SIZEOF, 64

        .section .rodata
.Ls_unknown:    .asciz "storage: a value the check can't compute (Unknown)"
.Ls_unpack:     .asciz "not enough values to unpack (expected 3)"
.Ls_tindex:     .asciz "tuple index out of range"
.Ls_key:        .asciz "storage: a variable without a definition"
.Ls_type_blen:  .asciz "unsupported operand type(s): a length's slot"
.Ls_type_mod:   .asciz "unsupported operand type(s) for %"
.Ls_zero_div:   .asciz "integer division or modulo by zero"
.Ls_unpack3:    .asciz "too many values to unpack (expected 3)"
.Ls_subscript:  .asciz "object is not subscriptable"
        .text

FUNC ck_unknown
        mov edi, E_UNKNOWN
        lea rsi, [rip + .Ls_unknown]
        jmp err_throw
ENDF ck_unknown

FUNC ck_index
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_tindex]
        jmp err_throw
ENDF ck_index

# ck_new(seed) -> ck
FUNC ck_new
        ENTER
        mov rbx, rdi
        mov edi, CK_SIZEOF
        call arena_alloc
        mov [rax + CK_SEED], rbx
        LEAVE
ENDF ck_new

# ck_reserve(ck, n) -> rax: the address of n more bytes at the end of the
# buffer (its length grown by n)
FUNC ck_reserve
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rax, [rbx + CK_LEN]
        add rax, r12
        cmp rax, [rbx + CK_CAP]
        jbe 2f
        mov r13, [rbx + CK_CAP]         # twice the room, or what's needed
        add r13, r13
        cmp r13, rax
        jae 1f
        mov r13, rax
1:      add r13, 64
        mov rdi, r13
        call arena_alloc_raw
        mov r14, rax
        mov rdi, rax
        mov rsi, [rbx + CK_BUF]
        mov rdx, [rbx + CK_LEN]
        test rdx, rdx
        jz 3f
        call memcpy@PLT
3:      mov [rbx + CK_BUF], r14
        mov [rbx + CK_CAP], r13
2:      mov rax, [rbx + CK_BUF]
        add rax, [rbx + CK_LEN]
        add [rbx + CK_LEN], r12
        LEAVE
ENDF ck_reserve

# ck_digest(ck, e, out, n): blake2b(f"{seed}:{e!r}", digest_size=n) at out
FUNC ck_digest
        ENTER
        sub rsp, ERR_SIZEOF + 16
        .set CD_SB, ERR_SIZEOF
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov r14, rcx
        call sb_new
        mov [rsp + CD_SB], rax
        # value_print has a STACK_CHECK: a symbol nested past the stack's
        # margin throws E_RECURSION mid-print, which the storage code's
        # handlers swallow and go on - the builder (xmalloc'd, outside the
        # arena) was lost each time. Freed, then the same error goes on.
        mov rdi, rsp
        call err_catch
        test eax, eax
        jnz .Lcd_throw
        mov rdi, [rsp + CD_SB]
        mov rsi, [rbx + CK_SEED]
        call sb_append_u64
        mov rdi, [rsp + CD_SB]
        mov esi, ':'
        call sb_append_char
        mov rdi, [rsp + CD_SB]
        mov rsi, r12
        call value_print
        mov rax, [rsp + CD_SB]
        mov rdi, r13
        mov rsi, r14
        mov rdx, [rax + SB_BUF]
        mov rcx, [rax + SB_LEN]
        call blake2b
        call err_end
        mov rdi, [rsp + CD_SB]
        call sb_free
        add rsp, ERR_SIZEOF + 16
        LEAVE
.Lcd_throw:                             # (the handler is unlinked already)
        mov r12d, eax                   # the error's code
        mov rdi, [rsp + CD_SB]
        call sb_free
        mov edi, r12d
        mov rsi, [r15 + CTX_ERR_MSG]
        call err_throw
ENDF ck_digest

# ck_be_to_word(dst, be32): the number of 32 big-endian bytes
FUNC ck_be_to_word
        .irp i, 0, 1, 2, 3
        mov rax, [rsi + 24 - 8*\i]
        bswap rax
        mov [rdi + 8*\i], rax
        .endr
        ret
ENDF ck_be_to_word

# ck_word_to_be(dst, n, w): the low n <= 32 bytes of the word w, big-endian
FUNC ck_word_to_be
        xor ecx, ecx                    # byte k of dst: byte n - 1 - k of w
1:      cmp rcx, rsi
        jae 2f
        mov rax, rsi
        sub rax, rcx
        dec rax
        movzx r8d, byte ptr [rdx + rax]
        mov [rdi + rcx], r8b
        inc rcx
        jmp 1b
2:      ret
ENDF ck_word_to_be

# ck_sym(dst, e, ck): python's World.sym - the value of a symbol in the
# world: its digest, 16 bits of it in the odd worlds
FUNC ck_sym
        ENTER
        sub rsp, 32
        mov rbx, rdi
        mov r12, rdx
        mov rdi, rdx
        mov rdx, rsp
        mov ecx, 32
        call ck_digest
        mov rdi, rbx
        mov rsi, rsp
        call ck_be_to_word
        test qword ptr [r12 + CK_SEED], 1
        jz 1f
        movzx eax, word ptr [rbx]
        mov [rbx], rax
        xor eax, eax
        mov [rbx + 8], rax
        mov [rbx + 16], rax
        mov [rbx + 24], rax
1:      add rsp, 32
        LEAVE
ENDF ck_sym

# ck_ev(dst, e, ck): python's ev - the value of e in the world
FUNC ck_ev
        STACK_CHECK
        ENTER
        sub rsp, 112
        .set EV_DST, 0
        .set EV_CK, 8
        .set EV_W, 16                   # a word
        .set EV_W2, 48                  # another
        .set EV_SIZE, 80                # a mask's size, off, shl
        .set EV_OFF, 88
        .set EV_SHL, 96
        mov [rsp + EV_DST], rdi
        mov [rsp + EV_CK], rdx
        mov rbx, rsi
        lea rax, [rip + sp_true]
        cmp rbx, rax
        je .Lev_one
        lea rax, [rip + sp_false]
        cmp rbx, rax
        je .Lev_zero
        mov rdi, rbx
        call is_int
        test eax, eax
        jz 1f
        mov rdi, [rsp + EV_DST]         # e % 2**256
        mov rsi, rbx
        call w_from_value
        jmp .Lev_ret
1:      mov rdi, rbx
        call is_tuple
        test eax, eax
        jz .Lev_sym
        cmp dword ptr [rbx + N_AUX], 0
        je .Lev_sym
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_BYTES
        je .Lev_bytes
        cmp eax, OP_ADD
        je .Lev_add
        cmp eax, OP_MUL
        je .Lev_mul
        cmp eax, OP_DIV
        je .Lev_div
        cmp eax, OP_MOD
        je .Lev_div
        cmp eax, OP_MASK_SHL
        je .Lev_mask
        cmp eax, OP_SHA3
        je .Lev_sha3
.Lev_sym:
        mov rdi, [rsp + EV_DST]
        mov rsi, rbx
        mov rdx, [rsp + EV_CK]
        call ck_sym
        jmp .Lev_ret
.Lev_one:
        mov rdi, [rsp + EV_DST]
        mov esi, 1
        call w_set_u64
        jmp .Lev_ret
.Lev_zero:
        mov rdi, [rsp + EV_DST]
        call w_zero
        jmp .Lev_ret
.Lev_bytes:
        cmp dword ptr [rbx + N_AUX], 2
        jb .Lev_index
        cmp qword ptr [rbx + N_DATA + 8], (32 << 1) | 1
        jne .Lev_sym
        cmp dword ptr [rbx + N_AUX], 3
        jb .Lev_index
        mov rdi, [rsp + EV_DST]
        mov rsi, [rbx + N_DATA + 16]
        mov rdx, [rsp + EV_CK]
        call ck_ev
        jmp .Lev_ret
.Lev_add:
        mov rdi, [rsp + EV_DST]
        call w_zero
        mov r12d, 1
1:      cmp r12d, [rbx + N_AUX]
        jae .Lev_ret
        lea rdi, [rsp + EV_W]
        mov rsi, [rbx + N_DATA + r12*8]
        mov rdx, [rsp + EV_CK]
        call ck_ev
        mov rdi, [rsp + EV_DST]
        mov rsi, rdi
        lea rdx, [rsp + EV_W]
        call w_add
        inc r12d
        jmp 1b
.Lev_mul:
        mov rdi, [rsp + EV_DST]
        mov esi, 1
        call w_set_u64
        mov r12d, 1
1:      cmp r12d, [rbx + N_AUX]
        jae .Lev_ret
        lea rdi, [rsp + EV_W]
        mov rsi, [rbx + N_DATA + r12*8]
        mov rdx, [rsp + EV_CK]
        call ck_ev
        mov rdi, [rsp + EV_DST]
        mov rsi, rdi
        lea rdx, [rsp + EV_W]
        call w_mul
        inc r12d
        jmp 1b
.Lev_div:
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lev_sym
        mov r12d, eax                   # (the opcode)
        lea rdi, [rsp + EV_W2]          # b first, a only if b isn't 0
        mov rsi, [rbx + N_DATA + 16]
        mov rdx, [rsp + EV_CK]
        call ck_ev
        lea rdi, [rsp + EV_W2]
        call w_is_zero
        test eax, eax
        jnz .Lev_zero
        lea rdi, [rsp + EV_W]
        mov rsi, [rbx + N_DATA + 8]
        mov rdx, [rsp + EV_CK]
        call ck_ev
        cmp r12d, OP_DIV
        jne 2f
        mov rdi, [rsp + EV_DST]
        xor esi, esi
        jmp 3f
2:      xor edi, edi
        mov rsi, [rsp + EV_DST]
3:      lea rdx, [rsp + EV_W]
        lea rcx, [rsp + EV_W2]
        call w_divmod
        jmp .Lev_ret
.Lev_mask:
        # size, off, shl: signed(ev(x)) of e[1:4]
        mov r12d, 1
1:      cmp r12d, 4
        jae 2f
        cmp r12d, [rbx + N_AUX]
        jae .Lev_unpack
        lea rdi, [rsp + EV_W]
        mov rsi, [rbx + N_DATA + r12*8]
        mov rdx, [rsp + EV_CK]
        call ck_ev
        lea rdi, [rsp + EV_W]
        call w_small
        mov [rsp + EV_SIZE + r12*8 - 8], rax
        inc r12d
        jmp 1b
2:      mov rax, [rsp + EV_SIZE]
        cmp rax, 0
        jl .Lev_unknown
        cmp rax, 256
        jg .Lev_unknown
        mov rax, [rsp + EV_OFF]
        cmp rax, -256
        jl .Lev_unknown
        cmp rax, 256
        jg .Lev_unknown
        mov rax, [rsp + EV_SHL]
        cmp rax, -512
        jl .Lev_unknown
        cmp rax, 512
        jg .Lev_unknown
        cmp dword ptr [rbx + N_AUX], 5
        jb .Lev_index
        lea rdi, [rsp + EV_W]
        mov rsi, [rbx + N_DATA + 32]
        mov rdx, [rsp + EV_CK]
        call ck_ev
        mov rax, [rsp + EV_OFF]
        test rax, rax
        js 4f
        # v &= ((1 << size) - 1) << off: the bits [off, off + size)
        lea rdi, [rsp + EV_W]
        lea rsi, [rsp + EV_W]
        mov rdx, rax
        call w_shr
        lea rdi, [rsp + EV_W]
        lea rsi, [rsp + EV_W]
        mov rdx, [rsp + EV_SIZE]
        call w_lowbits
        lea rdi, [rsp + EV_W]
        lea rsi, [rsp + EV_W]
        mov rdx, [rsp + EV_OFF]
        call w_shl
        jmp 5f
4:      # v &= (1 << max(size + off, 0)) - 1
        add rax, [rsp + EV_SIZE]
        jns 41f
        xor eax, eax
41:     lea rdi, [rsp + EV_W]
        lea rsi, [rsp + EV_W]
        mov rdx, rax
        call w_lowbits
5:      mov rax, [rsp + EV_SHL]
        test rax, rax
        js 6f
        mov rdi, [rsp + EV_DST]
        lea rsi, [rsp + EV_W]
        mov rdx, rax
        call w_shl
        jmp .Lev_ret
6:      neg rax
        mov rdi, [rsp + EV_DST]
        lea rsi, [rsp + EV_W]
        mov rdx, rax
        call w_shr
        jmp .Lev_ret
.Lev_sha3:
        # keccak of the bytes of its parts
        mov rdi, rbx
        call st_sha3_parts
        mov r12, rax
        mov r13, rdx
        mov rax, [rsp + EV_CK]
        mov r14, [rax + CK_LEN]         # where they begin
1:      test r13, r13
        jz 2f
        mov rdi, [r12]
        mov rsi, [rsp + EV_CK]
        call ck_evb
        add r12, 8
        dec r13
        jmp 1b
2:      mov rax, [rsp + EV_CK]
        mov rdi, [rax + CK_BUF]
        add rdi, r14
        mov rsi, [rax + CK_LEN]
        sub rsi, r14
        lea rdx, [rsp + EV_W]
        call keccak256
        mov rax, [rsp + EV_CK]
        mov [rax + CK_LEN], r14
        mov rdi, [rsp + EV_DST]
        lea rsi, [rsp + EV_W]
        call ck_be_to_word
.Lev_ret:
        add rsp, 112
        LEAVE
.Lev_unknown:
        call ck_unknown
.Lev_index:
        call ck_index
.Lev_unpack:
        mov edi, E_VALUE
        lea rsi, [rip + .Ls_unpack]
        call err_throw
ENDF ck_ev

# ck_put_word(ck, n, w): the low n bytes of the word w, big-endian, at the
# end of the buffer
FUNC ck_put_word
        ENTER
        mov rbx, rsi
        mov r12, rdx
        call ck_reserve
        mov rdi, rax
        mov rsi, rbx
        mov rdx, r12
        call ck_word_to_be
        LEAVE
ENDF ck_put_word

# ck_evb(e, ck): python's evb - the bytes of e as an element of a data,
# appended to the buffer
FUNC ck_evb
        STACK_CHECK
        ENTER
        sub rsp, 48
        .set EB_W, 0
        mov rbx, rdi
        mov r12, rsi
        call opcode_of
        cmp eax, OP_BYTES
        jne 2f
        cmp dword ptr [rbx + N_AUX], 2
        jb .Leb_index
        mov r13, [rbx + N_DATA + 8]     # an int n, 0 < n <= 32
        test r13b, 1
        jz 3f
        cmp r13, 1
        jle 3f
        cmp r13, (32 << 1) | 1
        jg 3f
        cmp dword ptr [rbx + N_AUX], 3
        jb .Leb_index
        lea rdi, [rsp + EB_W]
        mov rsi, [rbx + N_DATA + 16]
        mov rdx, r12
        call ck_ev
        sar r13, 1
        mov rdi, r12
        mov rsi, r13
        lea rdx, [rsp + EB_W]
        call ck_put_word
        jmp 9f
2:      cmp eax, OP_DATA
        jne 3f
        mov r13d, 1
1:      cmp r13d, [rbx + N_AUX]
        jae 9f
        mov rdi, [rbx + N_DATA + r13*8]
        mov rsi, r12
        call ck_evb
        inc r13d
        jmp 1b
3:      mov rdi, rbx
        call sized
        test eax, eax
        jz 4f
        # a range: its bytes, whatever they are, the same for the same
        mov rdi, r12
        mov esi, 40
        call ck_reserve
        mov rdi, r12
        mov rsi, rbx
        mov rdx, rax
        mov ecx, 40
        call ck_digest
        jmp 9f
4:      mov rdi, rbx
        call sizeof
        mov r13, rax
        mov rdi, rax                    # an int, a multiple of 8, in (0, 256]
        call is_int
        test eax, eax
        jz .Leb_unknown
        test r13b, 1
        jz .Leb_unknown
        sar r13, 1
        jle .Leb_unknown
        cmp r13, 256
        jg .Leb_unknown
        test r13, 7
        jnz .Leb_unknown
        lea rdi, [rsp + EB_W]
        mov rsi, rbx
        mov rdx, r12
        call ck_ev
        shr r13, 3
        mov rdi, r12
        mov rsi, r13
        lea rdx, [rsp + EB_W]
        call ck_put_word
9:      add rsp, 48
        LEAVE
.Leb_unknown:
        call ck_unknown
.Leb_index:
        call ck_index
ENDF ck_evb

# ck_w32_put(ck, w): w32(w) at the end of the buffer
FUNC ck_w32_put
        mov rdx, rsi
        mov esi, 32
        jmp ck_put_word
ENDF ck_w32_put

# ck_keccak_from(dst, ck, start): dst := keccak of the buffer's bytes from
# start, then the buffer cut back to start
FUNC ck_keccak_from
        ENTER
        sub rsp, 32
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov rdi, [r12 + CK_BUF]
        add rdi, r13
        mov rsi, [r12 + CK_LEN]
        sub rsi, r13
        mov rdx, rsp
        call keccak256
        mov [r12 + CK_LEN], r13
        mov rdi, rbx
        mov rsi, rsp
        call ck_be_to_word
        add rsp, 32
        LEAVE
ENDF ck_keccak_from

# ck_read_loc(out, loc, defs, lang, ck): python's read_loc - (slot, bit,
# width, type) of a loc in the world, at out (RL_*; defs: an od, name ->
# (slot, off, type))
FUNC ck_read_loc
        STACK_CHECK
        ENTER
        sub rsp, 176
        .set RLx_OUT, 0
        .set RLx_DEFS, 8
        .set RLx_LANG, 16
        .set RLx_CK, 24
        .set RLx_START, 32
        .set RLx_PER, 40
        .set RLx_W, 48                  # words
        .set RLx_B, 80
        .set RLx_Q, 112
        .set RLx_R, 144
        mov [rsp + RLx_OUT], rdi
        mov rbx, rsi
        mov [rsp + RLx_DEFS], rdx
        mov [rsp + RLx_LANG], rcx
        mov [rsp + RLx_CK], r8
        mov rdi, rbx                    # loc[0]: a TypeError for a number
        call ck_head_check
        mov rdi, rbx
        call opcode_of
        mov r12d, eax
        cmp eax, OP_SV
        je .Lrl_sv
        cmp eax, OP_SR
        je .Lrl_sr
        cmp eax, OP_SF
        je .Lrl_sf
        cmp eax, OP_SL
        je .Lrl_sl
        cmp eax, OP_SBL
        je .Lrl_sl
        cmp eax, OP_SI
        je .Lrl_si
        call ck_unknown
.Lrl_sv:
        cmp dword ptr [rbx + N_AUX], 2  # (as .Lrl_inner)
        jb ck_index
        mov rdi, [rsp + RLx_DEFS]
        mov rsi, [rbx + N_DATA + 8]
        call od_get
        test rax, rax
        jz .Lrl_key
        mov r12, rax                    # (slot, off, type)
        mov rdi, [rsp + RLx_OUT]
        mov rsi, [r12 + N_DATA]
        call w_from_value
        mov rdi, [rsp + RLx_OUT]
        mov qword ptr [rdi + RL_BLEN], 0
        mov rax, [r12 + N_DATA + 8]
        mov [rdi + RL_BIT], rax
        mov rax, [r12 + N_DATA + 16]
        mov [rdi + RL_TYPE], rax
        mov rdi, rax
        call st_value_width
        mov rdi, [rsp + RLx_OUT]
        mov [rdi + RL_WIDTH], rax
        jmp .Lrl_ret
.Lrl_sr:
        mov rdi, [rsp + RLx_OUT]        # (ev(slot), 0, 256, None)
        mov rsi, [rbx + N_DATA + 8]
        mov rdx, [rsp + RLx_CK]
        call ck_ev
        mov rdi, [rsp + RLx_OUT]
        mov qword ptr [rdi + RL_BLEN], 0
        jmp .Lrl_whole
.Lrl_sf:
        call .Lrl_inner
        mov rdi, [rsp + RLx_OUT]
        cmp qword ptr [rdi + RL_BLEN], 0
        jne .Lrl_type
        cmp dword ptr [rbx + N_AUX], 3  # (as .Lrl_inner)
        jb ck_index
        mov r12, [rbx + N_DATA + 16]    # n: (slot + n // 256, n % 256,
        mov rdi, r12                    # 256 - n % 256, None)
        call is_int
        test eax, eax
        jz .Lrl_type_mod
        mov rdi, r12
        mov esi, (256 << 1) | 1
        call int_floordiv
        lea rdi, [rsp + RLx_W]
        mov rsi, rax
        call w_from_value
        mov rdi, [rsp + RLx_OUT]
        mov rsi, rdi
        lea rdx, [rsp + RLx_W]
        call w_add
        mov rdi, r12
        mov esi, 8
        call int_mod_2exp
        mov r13, rax
        mov rdi, [rsp + RLx_OUT]
        mov [rdi + RL_BIT], rax
        mov edi, (256 << 1) | 1
        mov rsi, r13
        call int_sub
        mov rdi, [rsp + RLx_OUT]
        mov [rdi + RL_WIDTH], rax
        mov qword ptr [rdi + RL_TYPE], 0
        jmp .Lrl_ret
.Lrl_sl:
        call .Lrl_inner                 # (slot, 0, 256, None) - the slot
        mov rdi, [rsp + RLx_OUT]        # of a length: ('blen', slot)
        cmp r12d, OP_SBL
        jne .Lrl_whole
        mov qword ptr [rdi + RL_BLEN], 1
.Lrl_whole:
        mov qword ptr [rdi + RL_BIT], 1
        mov qword ptr [rdi + RL_WIDTH], (256 << 1) | 1
        mov qword ptr [rdi + RL_TYPE], 0
        jmp .Lrl_ret
.Lrl_si:
        call .Lrl_inner
        mov rdi, [rsp + RLx_OUT]
        mov r12, [rdi + RL_TYPE]
        test r12, r12
        jz .Lrl_unknown
        cmp dword ptr [rbx + N_AUX], 3  # (as .Lrl_inner)
        jb ck_index
        mov r13, [rbx + N_DATA + 16]    # key
        mov rdi, r12
        call opcode_of
        mov r14d, eax
        cmp eax, OP_MAPPING
        je .Lrl_mapping
        cmp eax, OP_BYTES
        je .Lrl_bytes
        cmp eax, OP_ARRAY
        je .Lrl_array
        cmp eax, OP_FIXED
        je .Lrl_array
        jmp .Lrl_unknown
.Lrl_mapping:
        # keccak(key . slot) - vyper: slot . key
        mov rdi, [rsp + RLx_OUT]
        cmp qword ptr [rdi + RL_BLEN], 0
        jne .Lrl_type
        mov rax, [rsp + RLx_CK]
        mov rax, [rax + CK_LEN]
        mov [rsp + RLx_START], rax
        cmp qword ptr [rsp + RLx_LANG], 0
        je 1f
        mov rdi, [rsp + RLx_CK]
        mov rsi, [rsp + RLx_OUT]
        call ck_w32_put
1:      mov rdi, r13
        call opcode_of
        cmp eax, OP_DATA
        jne 2f
        mov rdi, r13
        mov rsi, [rsp + RLx_CK]
        call ck_evb
        jmp 3f
2:      lea rdi, [rsp + RLx_W]
        mov rsi, r13
        mov rdx, [rsp + RLx_CK]
        call ck_ev
        mov rdi, [rsp + RLx_CK]
        lea rsi, [rsp + RLx_W]
        call ck_w32_put
3:      cmp qword ptr [rsp + RLx_LANG], 0
        jne 4f
        mov rdi, [rsp + RLx_CK]
        mov rsi, [rsp + RLx_OUT]
        call ck_w32_put
4:      mov rdi, [rsp + RLx_OUT]
        mov rsi, [rsp + RLx_CK]
        mov rdx, [rsp + RLx_START]
        call ck_keccak_from
        mov rdi, [rsp + RLx_OUT]        # (keccak(data), 0, value_width(t[1]), t[1])
        mov qword ptr [rdi + RL_BIT], 1
        mov r12, [r12 + N_DATA + 8]
        mov [rdi + RL_TYPE], r12
        mov rdi, r12
        call st_value_width
        mov rdi, [rsp + RLx_OUT]
        mov [rdi + RL_WIDTH], rax
        jmp .Lrl_ret
.Lrl_bytes:
        # ((keccak(w32(slot)) + ev(key)) % 2**256, 0, 256, None)
        call .Lrl_keccak_slot
        lea rdi, [rsp + RLx_W]
        mov rsi, r13
        mov rdx, [rsp + RLx_CK]
        call ck_ev
        mov rdi, [rsp + RLx_OUT]
        mov rsi, rdi
        lea rdx, [rsp + RLx_W]
        call w_add
        mov rdi, [rsp + RLx_OUT]
        jmp .Lrl_whole
.Lrl_array:
        cmp dword ptr [r12 + N_AUX], 3  # _, et, stride = t
        jne .Lrl_unpack
        cmp r14d, OP_ARRAY              # the start of the elements
        jne 1f
        call .Lrl_keccak_slot
1:      lea rdi, [rsp + RLx_W]          # i = ev(key)
        mov rsi, r13
        mov rdx, [rsp + RLx_CK]
        call ck_ev
        mov rdi, [r12 + N_DATA + 8]     # width = elem_width(et)
        call st_elem_width
        mov r13, rax
        cmp rax, (256 << 1) | 1
        jge 3f
        # packed: (start + i // per, width * (i % per), width, et)
        mov rcx, r13
        sar rcx, 1
        mov eax, 256
        xor edx, edx
        div ecx
        mov [rsp + RLx_PER], rax
        lea rdi, [rsp + RLx_B]
        mov rsi, rax
        call w_set_u64
        lea rdi, [rsp + RLx_Q]
        lea rsi, [rsp + RLx_R]
        lea rdx, [rsp + RLx_W]
        lea rcx, [rsp + RLx_B]
        call w_divmod
        mov rdi, [rsp + RLx_OUT]
        mov rsi, rdi
        lea rdx, [rsp + RLx_Q]
        call w_add
        mov rax, [rsp + RLx_R]          # (below per: its first limb)
        mov rcx, r13
        sar rcx, 1
        imul rax, rcx
        TAG rax
        mov rdi, [rsp + RLx_OUT]
        mov [rdi + RL_BIT], rax
        mov [rdi + RL_WIDTH], r13
        mov rax, [r12 + N_DATA + 8]
        mov [rdi + RL_TYPE], rax
        jmp .Lrl_ret
3:      # (start + i * stride, 0, value_width(et), et)
        lea rdi, [rsp + RLx_B]
        mov rsi, [r12 + N_DATA + 16]
        call w_from_value
        lea rdi, [rsp + RLx_W]
        lea rsi, [rsp + RLx_W]
        lea rdx, [rsp + RLx_B]
        call w_mul
        mov rdi, [rsp + RLx_OUT]
        mov rsi, rdi
        lea rdx, [rsp + RLx_W]
        call w_add
        mov rdi, [rsp + RLx_OUT]
        mov qword ptr [rdi + RL_BIT], 1
        mov rax, [r12 + N_DATA + 8]
        mov [rdi + RL_TYPE], rax
        mov rdi, rax
        call st_value_width
        mov rdi, [rsp + RLx_OUT]
        mov [rdi + RL_WIDTH], rax
.Lrl_ret:
        add rsp, 176
        LEAVE
# read_loc(loc[1]) into out
.Lrl_inner:
        cmp dword ptr [rbx + N_AUX], 2  # python's IndexError for a shape
        jb ck_index                     # shorter than the opcode's (the VM
                                        # builds them whole; opcode_of has
                                        # made this a non-empty tuple)
        mov rdi, [rsp + RLx_OUT + 8]
        mov rsi, [rbx + N_DATA + 8]
        mov rdx, [rsp + RLx_DEFS + 8]
        mov rcx, [rsp + RLx_LANG + 8]
        mov r8, [rsp + RLx_CK + 8]
        jmp ck_read_loc
# out's slot := keccak(w32(slot)) (a length's slot: python's TypeError)
.Lrl_keccak_slot:
        sub rsp, 8
        mov rdi, [rsp + 16 + RLx_OUT]
        cmp qword ptr [rdi + RL_BLEN], 0
        jne .Lrl_type
        mov rax, [rsp + 16 + RLx_CK]
        mov rax, [rax + CK_LEN]
        mov [rsp], rax
        mov rdi, [rsp + 16 + RLx_CK]
        mov rsi, [rsp + 16 + RLx_OUT]
        call ck_w32_put
        mov rdi, [rsp + 16 + RLx_OUT]
        mov rsi, [rsp + 16 + RLx_CK]
        mov rdx, [rsp]
        call ck_keccak_from
        add rsp, 8
        ret
.Lrl_unknown:
        call ck_unknown
.Lrl_key:
        mov edi, E_KEY
        lea rsi, [rip + .Ls_key]
        call err_throw
.Lrl_type:
        mov edi, E_TYPE
        lea rsi, [rip + .Ls_type_blen]
        call err_throw
.Lrl_type_mod:
        mov edi, E_TYPE
        lea rsi, [rip + .Ls_type_mod]
        call err_throw
.Lrl_unpack:
        mov edi, E_VALUE
        lea rsi, [rip + .Ls_unpack3]
        call err_throw
ENDF ck_read_loc

# ck_head_check(v): python's TypeError of v[0] for what isn't a sequence
# or a string, IndexError for an empty one
FUNC ck_head_check
        test dil, 1
        jnz 1f
        test rdi, rdi
        jz 1f
        mov eax, [rdi + N_KIND]
        cmp eax, K_STR
        je 2f
        cmp eax, K_TUPLE
        je 3f
        cmp eax, K_LIST
        je 3f
1:      mov edi, E_TYPE
        lea rsi, [rip + .Ls_subscript]
        jmp err_throw
2:      cmp dword ptr [rdi + N_DATA], 0
        je ck_index
        ret
3:      cmp dword ptr [rdi + N_AUX], 0
        je ck_index
        ret
ENDF ck_head_check

# ck_read(out, f, defs, lang, ck) -> rax: python's read - (slot, off, size)
# the printed access f reads in the world: the slot at out (RL_SLOT,
# RL_BLEN), rax the off (an int value), rdx the size (a value)
FUNC ck_read
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 48
        .set RD_OUT, MATCH_BINDINGS_SIZE
        .set RD_DEFS, MATCH_BINDINGS_SIZE + 8
        .set RD_LANG, MATCH_BINDINGS_SIZE + 16
        .set RD_CK, MATCH_BINDINGS_SIZE + 24
        mov [rsp + RD_OUT], rdi
        mov rbx, rsi
        mov [rsp + RD_DEFS], rdx
        mov [rsp + RD_LANG], rcx
        mov [rsp + RD_CK], r8
        PAT rsi, "('mask_shl', ':int:size', ':int:d', ':int:shl', ('st', 'Any', ':loc', 'Any'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        mov rdi, [rsp + RD_OUT]
        mov rsi, [rsp + 24]
        mov rdx, [rsp + RD_DEFS]
        mov rcx, [rsp + RD_LANG]
        mov r8, [rsp + RD_CK]
        call ck_read_loc
        mov rax, [rsp + RD_OUT]         # (slot, off + d, size)
        mov rdi, [rax + RL_BIT]
        mov rsi, [rsp + 8]
        call int_add
        mov rdx, [rsp]
        jmp 9f
1:      PAT rsi, "('st', ':size', ':loc', 'Any')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        mov rdi, [rsp + RD_OUT]
        mov rsi, [rsp + 8]
        mov rdx, [rsp + RD_DEFS]
        mov rcx, [rsp + RD_LANG]
        mov r8, [rsp + RD_CK]
        call ck_read_loc
        mov rax, [rsp + RD_OUT]         # (slot, off, size)
        mov rax, [rax + RL_BIT]
        mov rdx, [rsp]
9:      add rsp, MATCH_BINDINGS_SIZE + 48
        LEAVE
2:      call ck_unknown
ENDF ck_read

# ck_mod_word(dst, v): v % 2**256 of an int value (python's TypeError for
# anything else)
FUNC ck_mod_word
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rsi
        call is_int
        test eax, eax
        jz 1f
        mov rdi, rbx
        mov rsi, r12
        call w_from_value
        LEAVE
1:      mov edi, E_TYPE
        lea rsi, [rip + .Ls_type_mod]
        call err_throw
ENDF ck_mod_word

# ck_words_eq(a, b) -> eax
FUNC ck_words_eq
        mov rax, [rdi]
        xor rax, [rsi]
        mov rcx, [rdi + 8]
        xor rcx, [rsi + 8]
        or rax, rcx
        mov rcx, [rdi + 16]
        xor rcx, [rsi + 16]
        or rax, rcx
        mov rcx, [rdi + 24]
        xor rcx, [rsi + 24]
        or rax, rcx
        sete al
        movzx eax, al
        ret
ENDF ck_words_eq

# ck_checks(f, size, off, idx, defs, lang) -> eax: python's checks - f
# reads as the access (size, off, idx) in every world (the exceptions it
# catches: False; the others go through)
FUNC ck_checks
        ENTER
        sub rsp, 384
        .set CC_F, 0
        .set CC_SIZE, 8
        .set CC_OFF, 16
        .set CC_IDX, 24
        .set CC_DEFS, 32
        .set CC_LANG, 40
        .set CC_SEED, 48
        .set CC_CK, 56
        .set CC_ERR, 64                 # the handler (64 bytes)
        .set CC_GOT, 128                # read's slot (RL_SIZEOF)
        .set CC_GOFF, 192               # got's off and size: words
        .set CC_GSIZE, 224
        .set CC_WANT, 256               # what access_value gives: words
        .set CC_WOFF, 288
        .set CC_WSIZE, 320
        .set CC_WBLEN, 352
        .set CC_GOFFV, 360              # read's off and size, values
        .set CC_GSIZEV, 368
        mov [rsp + CC_F], rdi
        mov [rsp + CC_SIZE], rsi
        mov [rsp + CC_OFF], rdx
        mov [rsp + CC_IDX], rcx
        mov [rsp + CC_DEFS], r8
        mov [rsp + CC_LANG], r9
        lea rdi, [rsp + CC_ERR]
        call err_catch
        test eax, eax
        jnz .Lcc_caught
        xor edi, edi
        call ck_new
        mov [rsp + CC_CK], rax
        mov qword ptr [rsp + CC_SEED], 0
.Lcc_world:
        mov rax, [rsp + CC_CK]
        mov rcx, [rsp + CC_SEED]
        mov [rax + CK_SEED], rcx
        mov qword ptr [rax + CK_LEN], 0
        # got = read(f)
        lea rdi, [rsp + CC_GOT]
        mov rsi, [rsp + CC_F]
        mov rdx, [rsp + CC_DEFS]
        mov rcx, [rsp + CC_LANG]
        mov r8, [rsp + CC_CK]
        call ck_read
        mov [rsp + CC_GOFFV], rax
        mov [rsp + CC_GSIZEV], rdx
        # want = access_value(size, off, idx)
        mov qword ptr [rsp + CC_WBLEN], 0
        mov rbx, [rsp + CC_IDX]
        mov rdi, rbx
        OP_N_CHECK OP_LENGTH, 2, 2f
        mov rbx, [rbx + N_DATA + 8]     # the key, ('loc', n): n
        mov qword ptr [rsp + CC_WBLEN], 1
        mov rdi, rbx
        OP_N_CHECK OP_LOC, 2, 2f
        mov rdi, [rbx + N_DATA + 8]
        call is_int
        test eax, eax
        jz 2f
        mov rbx, [rbx + N_DATA + 8]
2:      lea rdi, [rsp + CC_WANT]
        mov rsi, rbx
        mov rdx, [rsp + CC_CK]
        call ck_ev
        lea rdi, [rsp + CC_WOFF]
        mov rsi, [rsp + CC_OFF]
        mov rdx, [rsp + CC_CK]
        call ck_ev
        lea rdi, [rsp + CC_WSIZE]
        mov rsi, [rsp + CC_SIZE]
        mov rdx, [rsp + CC_CK]
        call ck_ev
        # (slot, off % 2**256, size % 2**256)
        lea rdi, [rsp + CC_GOFF]
        mov rsi, [rsp + CC_GOFFV]
        call ck_mod_word
        lea rdi, [rsp + CC_GSIZE]
        mov rsi, [rsp + CC_GSIZEV]
        call ck_mod_word
        # got == want
        mov rax, [rsp + CC_GOT + RL_BLEN]
        cmp rax, [rsp + CC_WBLEN]
        jne .Lcc_false
        lea rdi, [rsp + CC_GOT + RL_SLOT]
        lea rsi, [rsp + CC_WANT]
        call ck_words_eq
        test eax, eax
        jz .Lcc_false
        lea rdi, [rsp + CC_GOFF]
        lea rsi, [rsp + CC_WOFF]
        call ck_words_eq
        test eax, eax
        jz .Lcc_false
        lea rdi, [rsp + CC_GSIZE]
        lea rsi, [rsp + CC_WSIZE]
        call ck_words_eq
        test eax, eax
        jz .Lcc_false
        inc qword ptr [rsp + CC_SEED]
        cmp qword ptr [rsp + CC_SEED], 4
        jb .Lcc_world
        call err_end
        mov eax, 1
        jmp .Lcc_ret
.Lcc_false:
        call err_end
        xor eax, eax
.Lcc_ret:
        add rsp, 384
        LEAVE
.Lcc_caught:
        cmp eax, E_UNKNOWN
        je 1f
        cmp eax, E_KEY
        je 1f
        cmp eax, E_VALUE
        je 1f
        cmp eax, E_ASSERT
        je 1f
        cmp eax, E_OVERFLOW
        je 1f
        mov edi, eax
        mov rsi, [r15 + CTX_ERR_MSG]
        call err_throw
1:      xor eax, eax
        add rsp, 384
        LEAVE
ENDF ck_checks


        .section .note.GNU-stack,"",@progbits
