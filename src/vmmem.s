# What the symbolic VM knows on a path (port of vm.py's memory model and
# path helpers): the facts of `known` - the conditions holding there,
# ('memory', start, size, value) for what the path wrote at a known place
# (value None for what isn't kept), ('memory_fresh',) while the memory is
# known to be of zeroes elsewhere, ('returndatasize_zero',) while no call
# was made, ('var_bits', var, bits) for a read of a few bits (a size)
# given a name - and what they say: the bounds of what is compared with a
# number, the word read at an address, where a write may go.
#
# The starts and the sizes of the memory facts are python's integers,
# handled with the int_* functions (a big one is possible: an mstore at
# 2^200).

.include "defs.inc"

        .text

# py_falsy(v) -> eax: python's `not v` for the values a memory fact holds
# (None, 0, False, an empty tuple or string)
FUNC py_falsy
        mov eax, 1
        cmp rdi, 1                      # 0
        je 1f
        test dil, 1
        jnz 2f                          # another small int
        test rdi, rdi
        jz 1f                           # (NIL)
        lea rcx, [rip + sp_none]
        cmp rdi, rcx
        je 1f
        lea rcx, [rip + sp_false]
        cmp rdi, rcx
        je 1f
        mov ecx, [rdi + N_KIND]
        cmp ecx, K_TUPLE
        je 3f
        cmp ecx, K_LIST
        je 3f
        cmp ecx, K_STR
        jne 2f
        cmp dword ptr [rdi + N_DATA], 0
        je 1f
        jmp 2f
3:      cmp dword ptr [rdi + N_AUX], 0
        je 1f
2:      xor eax, eax
1:      ret
ENDF py_falsy

# fact_op(fact) -> eax: the opcode id of a fact (opcode_of), kept in a
# register by the callers
FUNC fact_op
        OPCODE_OF_RDI
        ret
ENDF fact_op

# mask_value(value, size, offset, shl) -> rax: python's mask_value - mask_op
# that also computes a number, and leaves a word as it is (size, offset,
# shl: integer values)
FUNC mask_value
        cmp rsi, (256 << 1) | 1
        jne 1f
        cmp rdx, 1
        jne 1f
        cmp rcx, 1
        jne 1f
        mov rax, rdi
        ret
1:      ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov r14, rcx
        call is_int
        test eax, eax
        jz 2f
        mov rdi, rbx
        mov rsi, r12
        mov rdx, r13
        mov rcx, r14
        call alg_apply_mask
        LEAVE
2:      mov rdi, rbx
        mov rsi, r12
        mov rdx, r13
        mov rcx, r14
        mov r8d, 1
        call alg_mask_op
        LEAVE
ENDF mask_value

# has_memory_facts(known) -> eax: a ('memory', ...) or ('memory_fresh',)
# among the facts
FUNC has_memory_facts
        xor ecx, ecx
1:      cmp ecx, [rdi + N_AUX]
        jae 2f
        mov rax, [rdi + N_DATA + rcx*8]
        inc ecx
        push rdi
        mov rdi, rax
        OPCODE_OF_RDI
        pop rdi
        cmp eax, OP_MEMORY
        je 3f
        cmp eax, OP_MEMORY_FRESH
        jne 1b
3:      mov eax, 1
        ret
2:      xor eax, eax
        ret
ENDF has_memory_facts

# is_fresh(known) -> eax: ('memory_fresh',) is known
FUNC is_fresh
        xor ecx, ecx
1:      cmp ecx, [rdi + N_AUX]
        jae 2f
        mov rax, [rdi + N_DATA + rcx*8]
        inc ecx
        test al, 1
        jnz 1b
        test rax, rax
        jz 1b
        cmp dword ptr [rax + N_KIND], K_TUPLE
        jne 1b
        cmp dword ptr [rax + N_AUX], 1
        jne 1b
        push rdi
        mov rdi, rax
        OPCODE_OF_RDI
        pop rdi
        cmp eax, OP_MEMORY_FRESH
        jne 1b
        mov eax, 1
        ret
2:      xor eax, eax
        ret
ENDF is_fresh

# read_memory(known, addr) -> rax: python's read_memory - the word at addr
# (an or of the masks of what was written there) if what's there is
# known, else NIL (python's None)
FUNC read_memory
        ENTER
        sub rsp, 64
        .set RM_KNOWN, 0
        .set RM_ADDR, 8
        .set RM_END, 16
        .set RM_RES, 24
        .set RM_COVERED, 32
        .set RM_LO, 40
        .set RM_HI, 48
        .set RM_FEND, 56
        mov [rsp + RM_KNOWN], rdi
        mov [rsp + RM_ADDR], rsi
        mov rdi, rsi
        call is_int
        test eax, eax
        jz .Lrdm_none
        mov rdi, [rsp + RM_KNOWN]
        call has_memory_facts
        test eax, eax
        jz .Lrdm_none
        mov rdi, [rsp + RM_ADDR]
        mov esi, (32 << 1) | 1
        call int_add
        mov [rsp + RM_END], rax
        mov qword ptr [rsp + RM_RES], 1         # 0
        mov qword ptr [rsp + RM_COVERED], 1     # 0
        xor r12d, r12d
.Lrdm_fact:
        mov rax, [rsp + RM_KNOWN]
        cmp r12d, [rax + N_AUX]
        jae .Lrdm_done
        mov rbx, [rax + N_DATA + r12*8]
        inc r12d
        mov rdi, rbx
        OPCODE_OF_RDI
        cmp eax, OP_MEMORY
        jne .Lrdm_fact
        # lo, hi = max(start, addr), min(start + size, end)
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rsp + RM_ADDR]
        call int_max
        mov [rsp + RM_LO], rax
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rbx + N_DATA + 16]
        call int_add
        mov [rsp + RM_FEND], rax        # start + size
        mov rdi, rax
        mov rsi, [rsp + RM_END]
        call int_min
        mov [rsp + RM_HI], rax
        mov rdi, [rsp + RM_LO]
        mov rsi, rax
        call int_cmp
        cmp eax, 0
        jge .Lrdm_fact                  # lo >= hi: not there
        mov r13, [rbx + N_DATA + 24]    # the value
        lea rax, [rip + sp_none]
        cmp r13, rax
        je .Lrdm_none
        # the bytes lo..hi of the value of the bytes start..start + size, to
        # their place in the word: off = 8 * (start + size - hi)
        mov rdi, [rsp + RM_FEND]
        mov rsi, [rsp + RM_HI]
        call int_sub
        mov rdi, rax
        mov esi, (8 << 1) | 1
        call int_mul
        mov r14, rax                    # off
        mov rdi, [rsp + RM_END]         # 8 * (end - hi) - off
        mov rsi, [rsp + RM_HI]
        call int_sub
        mov rdi, rax
        mov esi, (8 << 1) | 1
        call int_mul
        mov rdi, rax
        mov rsi, r14
        call int_sub
        mov [rsp + RM_FEND], rax        # (the shl)
        mov rdi, [rsp + RM_HI]          # 8 * (hi - lo)
        mov rsi, [rsp + RM_LO]
        call int_sub
        mov rdi, rax
        mov esi, (8 << 1) | 1
        call int_mul
        mov rsi, rax
        mov rdi, r13
        mov rdx, r14
        mov rcx, [rsp + RM_FEND]
        call mask_value
        mov rsi, rax
        mov rdi, [rsp + RM_RES]
        call alg_or2
        mov [rsp + RM_RES], rax
        # covered += hi - lo
        mov rdi, [rsp + RM_HI]
        mov rsi, [rsp + RM_LO]
        call int_sub
        mov rdi, [rsp + RM_COVERED]
        mov rsi, rax
        call int_add
        mov [rsp + RM_COVERED], rax
        jmp .Lrdm_fact
.Lrdm_done:
        mov rdi, [rsp + RM_COVERED]
        mov esi, (32 << 1) | 1
        call int_cmp
        cmp eax, 0
        jge 1f
        mov rdi, [rsp + RM_KNOWN]
        call is_fresh
        test eax, eax
        jz .Lrdm_none
1:      mov rax, [rsp + RM_RES]
        add rsp, 64
        LEAVE
.Lrdm_none:
        xor eax, eax
        add rsp, 64
        LEAVE
ENDF read_memory

# known_zeroes(known, start, size) -> eax: python's known_zeroes - the
# memory start..start + size is known to be zeroes: each word of it reads
# 0 (python reads them one by one; a word that touches no fact reads 0 in
# a fresh memory, nothing otherwise - the run of them up to the next fact
# is skipped at once)
FUNC known_zeroes
        ENTER
        sub rsp, 48
        .set KZ_KNOWN, 0
        .set KZ_START, 8
        .set KZ_END, 16
        .set KZ_A, 24
        .set KZ_NEXT, 32
        mov [rsp + KZ_KNOWN], rdi
        mov [rsp + KZ_START], rsi
        mov rbx, rdx                    # size
        mov rdi, rsi
        call is_int
        test eax, eax
        jz .Lkz_no
        mov rdi, rbx
        call is_int
        test eax, eax
        jz .Lkz_no
        mov rdi, rbx
        call int_sign
        cmp eax, 0
        jle .Lkz_no
        mov rdi, [rsp + KZ_START]
        mov rsi, rbx
        call int_add
        mov [rsp + KZ_END], rax
        mov rax, [rsp + KZ_START]
        mov [rsp + KZ_A], rax
.Lkz_word:
        mov rdi, [rsp + KZ_A]           # past the end: all of them were 0
        mov rsi, [rsp + KZ_END]
        call int_cmp
        cmp eax, 0
        jge .Lkz_yes
        # does a fact touch a..a + 32? (and the first start of one past it)
        mov rdi, [rsp + KZ_A]
        mov esi, (32 << 1) | 1
        call int_add
        mov r13, rax                    # a + 32
        mov qword ptr [rsp + KZ_NEXT], 0
        xor r12d, r12d
        xor r14d, r14d                  # touched
1:      mov rax, [rsp + KZ_KNOWN]
        cmp r12d, [rax + N_AUX]
        jae 4f
        mov rbx, [rax + N_DATA + r12*8]
        inc r12d
        mov rdi, rbx
        OPCODE_OF_RDI
        cmp eax, OP_MEMORY
        jne 1b
        mov rdi, [rbx + N_DATA + 8]     # starts at a + 32 or after: the next
        mov rsi, r13
        call int_cmp
        cmp eax, 0
        jl 2f
        mov rax, [rsp + KZ_NEXT]
        test rax, rax
        jz 3f
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, rax
        call int_cmp
        cmp eax, 0
        jge 1b
3:      mov rax, [rbx + N_DATA + 8]
        mov [rsp + KZ_NEXT], rax
        jmp 1b
2:      mov rdi, [rbx + N_DATA + 8]     # ends after a?
        mov rsi, [rbx + N_DATA + 16]
        call int_add
        mov rdi, rax
        mov rsi, [rsp + KZ_A]
        call int_cmp
        cmp eax, 0
        jle 1b
        mov r14d, 1
        jmp 1b
4:      test r14d, r14d
        jnz 5f
        # touches nothing: 0 in a fresh memory (if there's a memory fact at
        # all), nothing otherwise
        mov rdi, [rsp + KZ_KNOWN]
        call is_fresh
        test eax, eax
        jz .Lkz_no
        mov rax, [rsp + KZ_NEXT]
        test rax, rax
        jz .Lkz_yes                     # no fact further on: zeroes all along
        # the first word past a that touches the next fact: a + 32 * (1 +
        # (next - a - 32) // 32)
        mov rdi, rax
        mov rsi, r13
        call int_sub
        mov rdi, rax
        mov esi, (32 << 1) | 1
        call int_floordiv
        mov rdi, rax
        mov esi, 3
        call int_add
        mov rdi, rax
        mov esi, (32 << 1) | 1
        call int_mul
        mov rdi, [rsp + KZ_A]
        mov rsi, rax
        call int_add
        mov [rsp + KZ_A], rax
        jmp .Lkz_word
5:      mov rdi, [rsp + KZ_KNOWN]
        mov rsi, [rsp + KZ_A]
        call read_memory
        cmp rax, 1                      # == 0 (python's False too)
        je 6f
        lea rcx, [rip + sp_false]
        cmp rax, rcx
        jne .Lkz_no
6:      mov rdi, [rsp + KZ_A]
        mov esi, (32 << 1) | 1
        call int_add
        mov [rsp + KZ_A], rax
        jmp .Lkz_word
.Lkz_yes:
        mov eax, 1
        add rsp, 48
        LEAVE
.Lkz_no:
        xor eax, eax
        add rsp, 48
        LEAVE
ENDF known_zeroes

# has_mem_op(exp) -> eax: python's get_op(exp, "mem") is not None - a
# ('mem', ...) in exp, itself or below (the first element of a sequence
# isn't looked into); only where a string mentions "mem" (HF_MEM)
FUNC has_mem_op
        STACK_CHECK
        test dil, 1
        jnz 8f
        test rdi, rdi
        jz 8f
        mov eax, [rdi + N_KIND]
        cmp eax, K_TUPLE
        je 1f
        cmp eax, K_LIST
        jne 8f
1:      mov rax, HF_MEM
        test [rdi + N_HASH], rax
        jz 8f
        ENTER
        mov rbx, rdi
        cmp dword ptr [rbx + N_KIND], K_TUPLE
        jne 2f
        OPCODE_OF_RDI
        cmp eax, OP_MEM
        je 7f
2:      mov r12d, 1
3:      cmp r12d, [rbx + N_AUX]
        jae 6f
        mov rdi, [rbx + N_DATA + r12*8]
        inc r12d
        call has_mem_op
        test eax, eax
        jz 3b
7:      mov eax, 1
        LEAVE
6:      xor eax, eax
        LEAVE
8:      xor eax, eax
        ret
ENDF has_mem_op

# write_memory(known, rng, value) -> rax: python's write_memory - what's
# known once value is written to the memory range rng
FUNC write_memory
        STACK_CHECK
        ENTER
        sub rsp, 80
        .set WM_KNOWN, 0
        .set WM_START, 8
        .set WM_SIZE, 16
        .set WM_VALUE, 24
        .set WM_END, 32
        .set WM_RES, 40
        .set WM_FSTART, 48
        .set WM_FEND, 56
        .set WM_N, 64
        mov [rsp + WM_KNOWN], rdi
        mov rax, [rsi + N_DATA + 8]
        mov [rsp + WM_START], rax
        mov rax, [rsi + N_DATA + 16]
        mov [rsp + WM_SIZE], rax
        mov [rsp + WM_VALUE], rdx
        mov rdi, [rsp + WM_START]
        call is_int
        test eax, eax
        jz .Lwm_symbolic
        mov rdi, [rsp + WM_SIZE]
        call is_int
        test eax, eax
        jz .Lwm_symbolic
        cmp qword ptr [rsp + WM_SIZE], 1
        je .Lwm_asis                    # size 0: nothing written
        # a word, a byte, or a number of fewer bytes (codecopy's) is kept
        cmp qword ptr [rsp + WM_SIZE], (1 << 1) | 1
        je 2f
        cmp qword ptr [rsp + WM_SIZE], (32 << 1) | 1
        je 2f
        mov rdi, [rsp + WM_VALUE]
        call is_int
        test eax, eax
        jz 1f
        mov rdi, [rsp + WM_SIZE]
        mov esi, (32 << 1) | 1
        call int_cmp
        cmp eax, 0
        jl 2f
1:      lea rax, [rip + sp_none]
        mov [rsp + WM_VALUE], rax
2:      # a read of memory (mcopy's), done before the write: what the memory
        # has there then - the write may change it - not the read
        mov rdi, [rsp + WM_VALUE]
        lea rax, [rip + sp_none]
        cmp rdi, rax
        je 4f
        call has_mem_op
        test eax, eax
        jz 4f
        mov rbx, [rsp + WM_VALUE]
        lea rax, [rip + sp_none]
        mov [rsp + WM_VALUE], rax
        cmp qword ptr [rsp + WM_SIZE], (32 << 1) | 1
        jne 4f
        mov rdi, rbx                    # ('mem', ('range', src, 32))
        mov esi, OP_MEM
        mov edx, 2
        call is_op_n
        test eax, eax
        jz 4f
        mov rbx, [rbx + N_DATA + 8]
        mov rdi, rbx
        mov esi, OP_RANGE
        mov edx, 3
        call is_op_n
        test eax, eax
        jz 4f
        cmp qword ptr [rbx + N_DATA + 16], (32 << 1) | 1
        jne 4f
        mov rdi, [rbx + N_DATA + 8]
        call is_int
        test eax, eax
        jz 4f
        mov rdi, [rsp + WM_KNOWN]
        mov rsi, [rbx + N_DATA + 8]
        call read_memory
        test rax, rax
        jz 4f
        mov [rsp + WM_VALUE], rax
4:      mov rdi, [rsp + WM_START]
        mov rsi, [rsp + WM_SIZE]
        call int_add
        mov [rsp + WM_END], rax
        call vec_new
        mov [rsp + WM_RES], rax
        xor r12d, r12d
.Lwm_fact:
        mov rax, [rsp + WM_KNOWN]
        cmp r12d, [rax + N_AUX]
        jae .Lwm_new
        mov rbx, [rax + N_DATA + r12*8]
        inc r12d
        mov rdi, rbx
        OPCODE_OF_RDI
        cmp eax, OP_MEMORY
        jne .Lwm_keep
        mov rdi, [rbx + N_DATA + 8]
        mov [rsp + WM_FSTART], rdi
        mov rsi, [rbx + N_DATA + 16]
        call int_add
        mov [rsp + WM_FEND], rax
        mov rdi, rax                    # fact[1] + fact[2] <= start
        mov rsi, [rsp + WM_START]
        call int_cmp
        cmp eax, 0
        jle .Lwm_keep
        mov rdi, [rsp + WM_END]         # end <= fact[1]
        mov rsi, [rsp + WM_FSTART]
        call int_cmp
        cmp eax, 0
        jle .Lwm_keep
        # what the write leaves of a value written before, on each side
        mov r13, [rbx + N_DATA + 24]    # f_value
        mov rdi, [rsp + WM_FSTART]
        mov rsi, [rsp + WM_START]
        call int_cmp
        cmp eax, 0
        jge 5f
        mov rdi, [rsp + WM_START]       # n = start - f_start
        mov rsi, [rsp + WM_FSTART]
        call int_sub
        mov [rsp + WM_N], rax
        mov r14, r13
        mov rdi, r13
        call py_falsy
        test eax, eax
        jnz 6f
        mov rdi, [rsp + WM_FEND]        # off = 8 * (f_end - start)
        mov rsi, [rsp + WM_START]
        call int_sub
        mov rdi, rax
        mov esi, (8 << 1) | 1
        call int_mul
        mov r14, rax
        mov rdi, rax
        call int_neg
        mov [rsp + WM_END + 40], rax    # (-off, a free slot)
        mov rdi, [rsp + WM_N]
        mov esi, (8 << 1) | 1
        call int_mul
        mov rsi, rax
        mov rdi, r13
        mov rdx, r14
        mov rcx, [rsp + WM_END + 40]
        call mask_value
        mov r14, rax
6:      LOADS rdi, MEMORY
        mov rsi, [rsp + WM_FSTART]
        mov rdx, [rsp + WM_N]
        mov rcx, r14
        call mk4
        mov rdi, [rsp + WM_RES]
        mov rsi, rax
        call vec_push
5:      mov rdi, [rsp + WM_END]         # end < f_end
        mov rsi, [rsp + WM_FEND]
        call int_cmp
        cmp eax, 0
        jge .Lwm_fact
        mov rdi, [rsp + WM_FEND]        # n = f_end - end
        mov rsi, [rsp + WM_END]
        call int_sub
        mov [rsp + WM_N], rax
        mov r14, r13
        mov rdi, r13
        call py_falsy
        test eax, eax
        jnz 7f
        mov rdi, [rsp + WM_N]
        mov esi, (8 << 1) | 1
        call int_mul
        mov rsi, rax
        mov rdi, r13
        mov edx, 1
        mov ecx, 1
        call mask_value
        mov r14, rax
7:      LOADS rdi, MEMORY
        mov rsi, [rsp + WM_END]
        mov rdx, [rsp + WM_N]
        mov rcx, r14
        call mk4
        mov rdi, [rsp + WM_RES]
        mov rsi, rax
        call vec_push
        jmp .Lwm_fact
.Lwm_keep:
        mov rdi, [rsp + WM_RES]
        mov rsi, rbx
        call vec_push
        jmp .Lwm_fact
.Lwm_new:
        LOADS rdi, MEMORY
        mov rsi, [rsp + WM_START]
        mov rdx, [rsp + WM_SIZE]
        mov rcx, [rsp + WM_VALUE]
        call mk4
        mov rdi, [rsp + WM_RES]
        mov rsi, rax
        call vec_push
        mov rdi, [rsp + WM_RES]
        call vec_to_tuple
        add rsp, 80
        LEAVE
.Lwm_asis:
        mov rax, [rsp + WM_KNOWN]
        add rsp, 80
        LEAVE
.Lwm_symbolic:
        # where it may go: somewhere there, or anywhere
        mov rdi, [rsp + WM_KNOWN]
        mov rsi, [rsp + WM_START]
        mov rdx, [rsp + WM_SIZE]
        call write_range
        test rax, rax
        jz .Lwm_anywhere
        js .Lwm_anywhere                # (python's float: see write_range)
        mov [rsp + WM_START], rax
        mov rdi, rdx
        mov rsi, rax
        call int_sub
        mov rdx, rax
        mov rsi, [rsp + WM_START]
        LOADS rdi, RANGE
        call mk3
        mov rdi, [rsp + WM_KNOWN]
        mov rsi, rax
        lea rdx, [rip + sp_none]
        call write_memory
        add rsp, 80
        LEAVE
.Lwm_anywhere:
        mov rdi, [rsp + WM_KNOWN]
        call without_memory_facts
        add rsp, 80
        LEAVE
ENDF write_memory

# without_memory_facts(known) -> tuple: the facts but the memory's
# ('memory', ...) and ('memory_fresh',)
FUNC without_memory_facts
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 3f
        mov r14, [rbx + N_DATA + r13*8]
        inc r13d
        mov rdi, r14
        OPCODE_OF_RDI
        cmp eax, OP_MEMORY
        je 1b
        cmp eax, OP_MEMORY_FRESH
        je 1b
        mov rdi, r12
        mov rsi, r14
        call vec_push
        jmp 1b
3:      mov rdi, r12
        call vec_to_tuple
        LEAVE
ENDF without_memory_facts


# int_or_bool(v) -> rax: the integer of an int or of a bool (python's
# isinstance(v, int): the matcher's ':int:'), NIL for anything else (leaf)
FUNC int_or_bool
        mov rax, rdi
        test dil, 1
        jnz 1f
        test rdi, rdi
        jz 2f
        cmp dword ptr [rdi + N_KIND], K_INT
        je 1f
        lea rcx, [rip + sp_true]
        mov eax, 3
        cmp rdi, rcx
        je 1f
        lea rcx, [rip + sp_false]
        mov eax, 1
        cmp rdi, rcx
        je 1f
2:      xor eax, eax
1:      ret
ENDF int_or_bool

# cmp_op_of(fact, eq_ok) -> eax: the opcode id of fact when it is one of
# lt, le, gt, ge (and eq when eq_ok), else 0 (leaf)
FUNC cmp_op_id
        OPCODE_OF_RDI
        cmp eax, OP_LT
        je 1f
        cmp eax, OP_LE
        je 1f
        cmp eax, OP_GT
        je 1f
        cmp eax, OP_GE
        je 1f
        test esi, esi
        jz 2f
        cmp eax, OP_EQ
        je 1f
2:      xor eax, eax
1:      ret
ENDF cmp_op_id

# upper_bound(v, known) -> rax: python's upper_bound - the highest value v
# can have by the known conditions (x < n, x <= n, n > x, n >= x, and the
# iszero of x > n, x >= n, n < x, n <= x), NIL if none says
FUNC upper_bound
        ENTER
        sub rsp, 32
        mov [rsp], rdi                  # v
        mov [rsp + 8], rsi              # known
        mov qword ptr [rsp + 16], 0     # res
        xor r12d, r12d
.Lub_fact:
        mov rax, [rsp + 8]
        cmp r12d, [rax + N_AUX]
        jae .Lub_done
        mov rbx, [rax + N_DATA + r12*8]
        inc r12d
        xor r13d, r13d                  # 1: under an iszero
        # (":op", v, ":int:n") / (":op", ":int:n", v)
        mov rdi, rbx
        call ub_match
        cmp eax, -1
        jne .Lub_found
        # ("iszero", (":op", v, ":int:n")) / ("iszero", (":op", ":int:n", v))
        mov rdi, rbx
        mov esi, OP_ISZERO
        mov edx, 2
        call is_op_n
        test eax, eax
        jz .Lub_fact
        mov r13d, 1
        mov rdi, [rbx + N_DATA + 8]
        call ub_match
        cmp eax, -1
        je .Lub_fact
.Lub_found:
        # eax: 0 for (op, v, n), 1 for (op, n, v), 2: a match without an n;
        # rdx: the op's id, rcx: n
        cmp eax, 2
        je .Lub_fact
        mov r14, rcx                    # n
        # the table: (op, v, n): lt n-1, le n; (op, n, v): gt n-1, ge n;
        # iszero of (op, v, n): gt n, ge n-1; of (op, n, v): lt n, le n-1
        xor ecx, ecx                    # 0: n, 1: n - 1, -1: none
        test r13d, r13d
        jnz 3f
        test eax, eax
        jnz 2f
        mov ecx, 1
        cmp edx, OP_LT
        je 5f
        xor ecx, ecx
        cmp edx, OP_LE
        je 5f
        jmp .Lub_fact
2:      mov ecx, 1
        cmp edx, OP_GT
        je 5f
        xor ecx, ecx
        cmp edx, OP_GE
        je 5f
        jmp .Lub_fact
3:      test eax, eax
        jnz 4f
        xor ecx, ecx
        cmp edx, OP_GT
        je 5f
        mov ecx, 1
        cmp edx, OP_GE
        je 5f
        jmp .Lub_fact
4:      xor ecx, ecx
        cmp edx, OP_LT
        je 5f
        mov ecx, 1
        cmp edx, OP_LE
        je 5f
        jmp .Lub_fact
5:      test ecx, ecx
        jz 6f
        mov rdi, r14
        mov rsi, -1
        call int_add
        mov r14, rax
6:      mov rax, [rsp + 16]
        test rax, rax
        jz 7f
        mov rdi, r14
        mov rsi, rax
        call int_cmp
        cmp eax, 0
        jge .Lub_fact
7:      mov [rsp + 16], r14
        jmp .Lub_fact
.Lub_done:
        mov rax, [rsp + 16]
        add rsp, 32
        LEAVE

# ub_match(fact) -> eax: the fact against (":op", v, ":int:n") (0) and
# (":op", ":int:n", v) (1) - v at [rsp + 8] of the caller's frame (its
# [rsp]) -, -1 for neither; 2 when (":op", v, ...) matched but with no n
# (python's elif chain stops there); rdx: the op's id (0 for a non-string),
# rcx: n
ub_match:
        push rbx
        push r12
        sub rsp, 8
        mov rbx, rdi
        mov eax, -1
        test bl, 1
        jnz 9f
        test rbx, rbx
        jz 9f
        mov ecx, [rbx + N_KIND]
        cmp ecx, K_TUPLE
        je 1f
        cmp ecx, K_LIST
        jne 9f
1:      cmp dword ptr [rbx + N_AUX], 3
        jne 9f
        mov r12, [rsp + 24 + 8 + 0]     # v (the caller's [rsp]: its frame
                                        # starts past our 3 pushes and the
                                        # return address)
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, r12
        call py_equal
        test eax, eax
        jz 2f
        mov rdi, [rbx + N_DATA + 16]
        call int_or_bool
        test rax, rax
        jz 2f
        mov rcx, rax
        xor eax, eax
        jmp 8f
2:      mov rdi, [rbx + N_DATA + 8]
        call int_or_bool
        test rax, rax
        jz 3f
        mov [rsp], rax
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, r12
        call py_equal
        test eax, eax
        jz 3f
        mov rcx, [rsp]
        mov eax, 1
        jmp 8f
3:      mov eax, -1
        jmp 9f
8:      # the op's id (a string's), in rdx
        mov rdx, [rbx + N_DATA]
        push rax
        push rcx
        mov rdi, rdx
        call str_id
        mov edx, eax
        pop rcx
        pop rax
9:      add rsp, 8
        pop r12
        pop rbx
        ret
ENDF upper_bound

# known_bounds(known) -> rax: python's known_bounds - an emap {x: (lowest,
# highest)} of what the known conditions say of what they compare with a
# number (see value_range), and of the variables of a few bits
# ('var_bits'); 0 when they say nothing
FUNC known_bounds
        ENTER
        sub rsp, 48
        .set KB_KNOWN, 0
        .set KB_RES, 8
        .set KB_V, 16
        .set KB_LO, 24
        .set KB_HI, 32
        mov [rsp + KB_KNOWN], rdi
        mov qword ptr [rsp + KB_RES], 0
        xor r12d, r12d
.Lkb_fact:
        mov rax, [rsp + KB_KNOWN]
        cmp r12d, [rax + N_AUX]
        jae .Lkb_done
        mov rbx, [rax + N_DATA + r12*8]
        inc r12d
        xor r13d, r13d                  # neg
1:      mov rdi, rbx
        OPCODE_OF_RDI
        cmp eax, OP_ISZERO
        jne 2f
        cmp dword ptr [rbx + N_AUX], 2
        jb .Lkb_fact                    # (python's IndexError)
        xor r13d, 1
        mov rbx, [rbx + N_DATA + 8]
        jmp 1b
2:      cmp eax, OP_VAR_BITS
        jne 3f
        test r13d, r13d
        jnz .Lkb_fact
        cmp dword ptr [rbx + N_AUX], 3
        jb .Lkb_fact
        mov rdi, [rbx + N_DATA + 16]
        call is_int
        test eax, eax
        jz .Lkb_fact
        mov rax, [rbx + N_DATA + 8]
        mov [rsp + KB_V], rax
        mov qword ptr [rsp + KB_LO], 1  # 0
        mov rdi, [rbx + N_DATA + 16]    # 2 ** bits - 1
        call kb_pow2_minus_1
        mov [rsp + KB_HI], rax
        jmp .Lkb_merge
3:      mov rdi, rbx
        mov esi, 1
        call cmp_op_id
        test eax, eax
        jz .Lkb_fact
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lkb_fact
        mov r14d, eax                   # op
        mov rax, [rbx + N_DATA + 8]     # a
        mov rcx, [rbx + N_DATA + 16]    # b
        mov [rsp + KB_V], rax
        mov [rsp + KB_LO], rcx
        mov rdi, rax
        call is_int
        test eax, eax
        jz 4f
        mov rdi, [rsp + KB_LO]
        call is_int
        test eax, eax
        jnz 4f
        mov rax, [rsp + KB_V]           # a number first: flipped
        mov rcx, [rsp + KB_LO]
        mov [rsp + KB_V], rcx
        mov [rsp + KB_LO], rax
        mov edi, r14d
        call kb_flip
        mov r14d, eax
4:      mov rdi, [rsp + KB_V]
        call is_int
        test eax, eax
        jnz .Lkb_fact
        mov rdi, [rsp + KB_LO]
        call is_int
        test eax, eax
        jz .Lkb_fact
        mov rdi, [rsp + KB_LO]          # 0 <= b <= top
        call int_sign
        test eax, eax
        js .Lkb_fact
        mov rdi, [rsp + KB_LO]
        mov rsi, [rip + vr_word_top_v]
        call int_cmp
        cmp eax, 0
        jg .Lkb_fact
        test r13d, r13d
        jz 5f
        cmp r14d, OP_EQ
        je .Lkb_fact
        mov edi, r14d
        call kb_negate
        mov r14d, eax
5:      mov rbx, [rsp + KB_LO]          # b: the bounds of op
        cmp r14d, OP_LT
        jne 6f
        mov qword ptr [rsp + KB_LO], 1
        mov rdi, rbx
        mov rsi, -1
        call int_add
        mov [rsp + KB_HI], rax
        jmp .Lkb_merge
6:      cmp r14d, OP_LE
        jne 7f
        mov qword ptr [rsp + KB_LO], 1
        mov [rsp + KB_HI], rbx
        jmp .Lkb_merge
7:      cmp r14d, OP_GT
        jne 8f
        mov rdi, rbx
        mov esi, 3
        call int_add
        mov [rsp + KB_LO], rax
        mov rax, [rip + vr_word_top_v]
        mov [rsp + KB_HI], rax
        jmp .Lkb_merge
8:      cmp r14d, OP_GE
        jne 9f
        mov [rsp + KB_LO], rbx
        mov rax, [rip + vr_word_top_v]
        mov [rsp + KB_HI], rax
        jmp .Lkb_merge
9:      mov [rsp + KB_LO], rbx          # eq
        mov [rsp + KB_HI], rbx
.Lkb_merge:
        # lo, hi = max(lo, old_lo), min(hi, old_hi); kept if lo <= hi
        mov rdi, [rsp + KB_RES]
        test rdi, rdi
        jnz 10f
        call emap_new
        mov [rsp + KB_RES], rax
        mov rdi, rax
10:     mov rsi, [rsp + KB_V]
        call emap_get
        test rax, rax
        jz 11f
        mov rbx, rax                    # (old_lo, old_hi)
        mov rdi, [rsp + KB_LO]
        mov rsi, [rbx + N_DATA]
        call int_max
        mov [rsp + KB_LO], rax
        mov rdi, [rsp + KB_HI]
        mov rsi, [rbx + N_DATA + 8]
        call int_min
        mov [rsp + KB_HI], rax
        jmp 12f
11:     mov rdi, [rsp + KB_LO]          # (0, top)
        mov esi, 1
        call int_max
        mov [rsp + KB_LO], rax
        mov rdi, [rsp + KB_HI]
        mov rsi, [rip + vr_word_top_v]
        call int_min
        mov [rsp + KB_HI], rax
12:     mov rdi, [rsp + KB_LO]
        mov rsi, [rsp + KB_HI]
        call int_cmp
        cmp eax, 0
        jg .Lkb_fact
        mov rdi, [rsp + KB_LO]
        mov rsi, [rsp + KB_HI]
        call mk2
        mov rdi, [rsp + KB_RES]
        mov rsi, [rsp + KB_V]
        mov rdx, rax
        call emap_put
        jmp .Lkb_fact
.Lkb_done:
        mov rax, [rsp + KB_RES]
        add rsp, 48
        LEAVE
ENDF known_bounds

# kb_flip(op) / kb_negate(op) -> eax: known_bounds' flip and negate
FUNC kb_flip
        mov eax, edi
        cmp edi, OP_LT
        jne 1f
        mov eax, OP_GT
        ret
1:      cmp edi, OP_GT
        jne 2f
        mov eax, OP_LT
        ret
2:      cmp edi, OP_LE
        jne 3f
        mov eax, OP_GE
        ret
3:      cmp edi, OP_GE
        jne 4f
        mov eax, OP_LE
4:      ret
ENDF kb_flip

FUNC kb_negate
        mov eax, edi
        cmp edi, OP_LT
        jne 1f
        mov eax, OP_GE
        ret
1:      cmp edi, OP_GE
        jne 2f
        mov eax, OP_LT
        ret
2:      cmp edi, OP_GT
        jne 3f
        mov eax, OP_LE
        ret
3:      cmp edi, OP_LE
        jne 4f
        mov eax, OP_GT
4:      ret
ENDF kb_negate

# kb_pow2_minus_1(bits) -> rax: 2 ** bits - 1 (bits a small int, at most
# a few hundred: what max_value_bits gives)
FUNC kb_pow2_minus_1
        ENTER
        sar rdi, 1
        call pow2
        mov rdi, rax
        mov rsi, -1
        call int_add
        LEAVE
ENDF kb_pow2_minus_1

# var_bits_bounds(known) -> rax: {fact[1]: fact[2]} of the ('var_bits',
# var, bits) facts (an emap), 0 when there's none (python's {}: the same)
FUNC var_bits_bounds
        ENTER
        mov rbx, rdi
        xor r12d, r12d                  # the emap
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 3f
        mov r14, [rbx + N_DATA + r13*8]
        inc r13d
        mov rdi, r14
        OPCODE_OF_RDI
        cmp eax, OP_VAR_BITS
        jne 1b
        test r12, r12
        jnz 2f
        call emap_new
        mov r12, rax
2:      mov rdi, r12
        mov rsi, [r14 + N_DATA + 8]
        mov rdx, [r14 + N_DATA + 16]
        call emap_put
        jmp 1b
3:      mov rax, r12
        LEAVE
ENDF var_bits_bounds

# below_2_128(v) -> eax: v is an int, 0 <= v < 2^128
FUNC below_2_128
        ENTER
        mov rbx, rdi
        call is_int
        test eax, eax
        jz 1f
        mov rdi, rbx
        call int_sign
        test eax, eax
        js 1f
        mov rdi, rbx
        call int_bit_length
        cmp rax, 128
        ja 1f
        mov eax, 1
        LEAVE
1:      xor eax, eax
        LEAVE
ENDF below_2_128

# bound(v, known) -> rax: python's bound - the highest value v can have,
# below 2^128: by the known conditions (upper_bound), or by what it's made
# of (max_value_bits, with what the 'var_bits' facts say), the least of
# those of the terms of a min; NIL if there's none
FUNC bound
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov esi, OP_MIN
        call is_op_head
        test eax, eax
        jz .Lbd_plain
        # (the size of what a call wrote, see output_write)
        mov qword ptr [rsp], 0          # min(tops)
        mov r13d, 1
1:      cmp r13d, [rbx + N_AUX]
        jae 4f
        mov r14, [rbx + N_DATA + r13*8]
        inc r13d
        mov rdi, r14
        call is_int
        test eax, eax
        jnz 2f
        mov rdi, r14
        mov rsi, r12
        call bound
        test rax, rax
        jz 1b
        mov r14, rax
2:      mov rax, [rsp]
        test rax, rax
        jz 3f
        mov rdi, r14
        mov rsi, rax
        call int_cmp
        cmp eax, 0
        jge 1b
3:      mov [rsp], r14
        jmp 1b
4:      mov rdi, [rsp]
        test rdi, rdi
        jz 9f
        call below_2_128
        test eax, eax
        jz 9f
        mov rax, [rsp]
        add rsp, 16
        LEAVE
.Lbd_plain:
        mov rdi, rbx
        mov rsi, r12
        call upper_bound
        test rax, rax
        jnz 5f
        # the bounds of what it's made of (see VM.snapshot)
        mov rdi, r12
        call var_bits_bounds
        mov rsi, rax
        mov rdi, rbx
        call max_value_bits
        cmp rax, (128 << 1) | 1
        jg 9f
        mov rdi, rax
        call kb_pow2_minus_1
5:      mov [rsp], rax
        mov rdi, rax
        call below_2_128
        test eax, eax
        jz 9f
        mov rax, [rsp]
        add rsp, 16
        LEAVE
9:      xor eax, eax
        add rsp, 16
        LEAVE
ENDF bound

# is_op_head(exp, op) -> eax: exp is a tuple headed by op (leaf)
FUNC is_op_head
        mov edx, esi
        OPCODE_OF_RDI
        cmp eax, edx
        sete al
        movzx eax, al
        ret
ENDF is_op_head

# write_range(known, start, size) -> rax: lo, rdx: hi - python's
# write_range: the range of memory a write at a place or of a size
# computed at runtime may touch, base + k * i with i below a bound, as many
# bytes as size can be. rax 0 when it isn't known; -1 when python's is a
# float (2 ** shl for a negative shl), which python's write_memory then
# takes for a size it knows nothing of: anywhere.
FUNC write_range
        ENTER
        sub rsp, 48
        .set WR_KNOWN, 0
        .set WR_START, 8
        .set WR_STOP, 16
        .set WR_BASE, 24
        .set WR_K, 32
        mov [rsp + WR_KNOWN], rdi
        mov [rsp + WR_START], rsi
        mov rbx, rdx                    # size
        mov rdi, rdx
        call is_int
        test eax, eax
        jnz 1f
        mov rdi, rbx
        mov rsi, [rsp + WR_KNOWN]
        call bound
        test rax, rax
        jz .Lwr_none
        mov rbx, rax
1:      mov [rsp + WR_STOP], rbx        # size_top
        mov rdi, [rsp + WR_START]
        call is_int
        test eax, eax
        jz 2f
        mov rdi, [rsp + WR_START]
        mov rsi, rbx
        call int_add
        mov rdx, rax
        mov rax, [rsp + WR_START]
        add rsp, 48
        LEAVE
2:      mov rdi, [rsp + WR_START]
        mov esi, OP_ADD
        call is_op_head
        test eax, eax
        jz .Lwr_none
        # bases: the numbers among the terms (one), rest: the others
        mov rbx, [rsp + WR_START]
        call vec_new
        mov r12, rax                    # rest
        mov qword ptr [rsp + WR_BASE], 0
        xor r14d, r14d                  # the number of bases
        mov r13d, 1
3:      cmp r13d, [rbx + N_AUX]
        jae 4f
        mov rdi, [rbx + N_DATA + r13*8]
        inc r13d
        mov [rsp + WR_K], rdi
        call is_int
        test eax, eax
        jz 31f
        inc r14d
        mov rax, [rsp + WR_K]
        cmp qword ptr [rsp + WR_BASE], 0
        jne 3b
        mov [rsp + WR_BASE], rax
        jmp 3b
31:     mov rdi, r12
        mov rsi, [rsp + WR_K]
        call vec_push
        jmp 3b
4:      cmp r14d, 1
        jne .Lwr_none
        cmp qword ptr [r12 + VEC_LEN], 0
        je .Lwr_none
        mov rdi, [rsp + WR_BASE]
        call below_2_128
        test eax, eax
        jz .Lwr_none
        # offset = rest[0], or the add of the rest
        mov rax, [r12 + VEC_DATA]
        mov rbx, [rax]
        cmp qword ptr [r12 + VEC_LEN], 1
        je 5f
        mov rdi, r12                    # ('add',) + rest
        call vec_new
        mov r13, rax
        mov rdi, rax
        LOADS rsi, ADD
        call vec_push
        mov rdi, r13
        mov rsi, [r12 + VEC_DATA]
        mov rdx, [r12 + VEC_LEN]
        call vec_extend
        mov rdi, r13
        call vec_to_tuple
        mov rbx, rax
5:      # ('mul', :int:k, :i), ('mask_shl', :int:size, 0, :int:shl, :i): (i &
        # mask) << shl, at most i << shl; else k = 1, i = offset
        mov qword ptr [rsp + WR_K], 3   # k = 1
        mov r13, rbx                    # i
        mov rdi, rbx
        mov esi, OP_MUL
        mov edx, 3
        call is_op_n
        test eax, eax
        jz 6f
        mov rdi, [rbx + N_DATA + 8]
        call int_or_bool
        test rax, rax
        jz 6f
        mov [rsp + WR_K], rax
        mov r13, [rbx + N_DATA + 16]
        jmp 7f
6:      mov rdi, rbx
        mov esi, OP_MASK_SHL
        mov edx, 5
        call is_op_n
        test eax, eax
        jz 7f
        mov rdi, [rbx + N_DATA + 8]
        call int_or_bool
        test rax, rax
        jz 7f
        mov rax, [rbx + N_DATA + 16]    # == 0
        cmp rax, 1
        je 61f
        lea rcx, [rip + sp_false]
        cmp rax, rcx
        jne 7f
61:     mov rdi, [rbx + N_DATA + 24]
        call int_or_bool
        test rax, rax
        jz 7f
        mov r13, [rbx + N_DATA + 32]    # i
        mov r14, rax                    # shl
        mov rdi, rax
        call int_sign
        test eax, eax
        js 8f                           # a float
        mov rdi, r14
        mov esi, (64 << 1) | 1
        call int_cmp
        cmp eax, 0
        jge .Lwr_none                   # k >= 2^64
        mov rdi, r14
        sar rdi, 1
        call pow2
        mov [rsp + WR_K], rax
        jmp 7f
8:      # 2 ** shl, a float in (0, 1): the range python makes is of a size
        # that's a float, if i is bounded
        mov rdi, r13
        mov rsi, [rsp + WR_KNOWN]
        call bound
        test rax, rax
        jz .Lwr_none
        mov rax, -1
        add rsp, 48
        LEAVE
7:      mov rdi, r13                    # top = bound(i, known)
        mov rsi, [rsp + WR_KNOWN]
        call bound
        test rax, rax
        jz .Lwr_none
        mov r13, rax
        mov rdi, [rsp + WR_K]           # 0 < k < 2^64
        call int_sign
        cmp eax, 0
        jle .Lwr_none
        mov rdi, [rsp + WR_K]
        call int_bit_length
        cmp rax, 64
        ja .Lwr_none
        mov rdi, [rsp + WR_K]           # base + k * top + size_top
        mov rsi, r13
        call int_mul
        mov rdi, [rsp + WR_BASE]
        mov rsi, rax
        call int_add
        mov rdi, rax
        mov rsi, [rsp + WR_STOP]
        call int_add
        mov rdx, rax
        mov rax, [rsp + WR_BASE]
        add rsp, 48
        LEAVE
.Lwr_none:
        xor eax, eax
        add rsp, 48
        LEAVE
ENDF write_range

# and_op(left, right, known) -> rax: python's vm.and_op - left & right, a
# mask when one of them is one (see Stack.simplify), which for a 256 ** e -
# 1 is when the conditions known say what e is (see masks.to_mask)
FUNC and_op
        ENTER
        sub rsp, 16
        mov rbx, rdx                    # known
        mov rdx, rsi
        mov rsi, rdi
        LOADS rdi, AND
        call mk3
        mov rdi, rax
        call arith_eval
        mov r12, rax                    # exp
        mov rdi, rax
        mov esi, OP_AND
        mov edx, 3
        call is_op_n
        test eax, eax
        jz .Lao_exp
        xor r13d, r13d                  # bounds
        mov rdi, r12
        LOADS rsi, EXP
        call contains
        test eax, eax
        jz 1f
        mov rdi, rbx
        call known_bounds
        mov r13, rax
1:      mov rdi, [r12 + N_DATA + 8]
        mov rsi, r13
        call to_mask
        test rax, rax
        jz 2f
        mov rsi, rax
        mov rdi, [r12 + N_DATA + 16]
        mov ecx, 1
        mov r8d, 1
        call alg_mask_op
        jmp .Lao_ret
2:      mov rdi, [r12 + N_DATA + 16]
        mov rsi, r13
        call to_mask
        test rax, rax
        jz 3f
        mov rsi, rax
        mov rdi, [r12 + N_DATA + 8]
        mov ecx, 1
        mov r8d, 1
        call alg_mask_op
        jmp .Lao_ret
3:      mov rdi, [r12 + N_DATA + 8]
        mov rsi, r13
        call to_neg_mask
        test rax, rax
        jz 4f
        mov rsi, rax
        mov rdi, [r12 + N_DATA + 16]
        call alg_neg_mask_op
        jmp .Lao_ret
4:      mov rdi, [r12 + N_DATA + 16]
        mov rsi, r13
        call to_neg_mask
        test rax, rax
        jz .Lao_exp
        mov rsi, rax
        mov rdi, [r12 + N_DATA + 8]
        call alg_neg_mask_op
        jmp .Lao_ret
.Lao_exp:
        mov rax, r12
.Lao_ret:
        add rsp, 16
        LEAVE
ENDF and_op

# decided(value, known) -> rax: python's decided - value as the number it
# is where the known conditions decide it: 0 if they say it's false, 1 if
# they say it's true and it's a truth value, else value
FUNC decided
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call is_int
        test eax, eax
        jnz 9f
        mov rdi, rbx
        mov rsi, r12
        call is_known
        cmp eax, TRI_FALSE
        jne 1f
        mov eax, 1                      # 0
        LEAVE
1:      cmp eax, TRI_TRUE
        jne 9f
        mov rdi, rbx
        call is_bool
        test eax, eax
        jz 9f
        mov eax, 3                      # 1
        LEAVE
9:      mov rax, rbx
        LEAVE
ENDF decided

# switch_values(exp) -> rax: python's switch_values - a part x of exp of
# a few values (x % n, n from 2 to 256; a mask of 1 to 8 bits of a word),
# rdx: a vec of its values; rax 0 when exp has none
FUNC switch_values
        ENTER
        sub rsp, 16
        mov rbx, rdi
        call vec_new
        mov r12, rax
        mov rdi, rbx
        mov esi, OP_MOD
        mov rdx, r12
        call find_op_list
        xor r13d, r13d
1:      cmp r13, [r12 + VEC_LEN]
        jae 4f
        mov rax, [r12 + VEC_DATA]
        mov r14, [rax + r13*8]
        inc r13
        cmp dword ptr [r14 + N_AUX], 3
        jne 1b
        mov rax, [r14 + N_DATA + 16]
        test al, 1
        jz 1b                           # (a big one is past 256)
        sar rax, 1
        cmp rax, 2
        jl 1b
        cmp rax, 256
        jg 1b
        mov [rsp], rax
        call vec_new                    # range(n)
        mov r12, rax
        xor r13d, r13d
2:      cmp r13, [rsp]
        jae 3f
        mov rsi, r13
        TAG rsi
        mov rdi, r12
        call vec_push
        inc r13
        jmp 2b
3:      mov rax, r14
        mov rdx, r12
        add rsp, 16
        LEAVE
4:      mov rdi, r12
        mov qword ptr [rdi + VEC_LEN], 0
        mov rdi, rbx
        mov esi, OP_MASK_SHL
        mov rdx, r12
        call find_op_list
        xor r13d, r13d
5:      cmp r13, [r12 + VEC_LEN]
        jae 9f
        mov rax, [r12 + VEC_DATA]
        mov r14, [rax + r13*8]
        inc r13
        cmp dword ptr [r14 + N_AUX], 5
        jne 5b
        mov rdi, [r14 + N_DATA + 8]
        call is_int
        test eax, eax
        jz 5b
        mov rdi, [r14 + N_DATA + 16]
        call is_int
        test eax, eax
        jz 5b
        mov rdi, [r14 + N_DATA + 24]
        call is_int
        test eax, eax
        jz 5b
        mov rdi, [r14 + N_DATA + 32]
        call is_int
        test eax, eax
        jnz 5b
        mov rax, [r14 + N_DATA + 8]     # 1 <= size <= 8
        test al, 1
        jz 5b
        sar rax, 1
        cmp rax, 1
        jl 5b
        cmp rax, 8
        jg 5b
        mov [rsp], rax
        mov rdi, [r14 + N_DATA + 16]    # offset + shl >= 0
        mov rsi, [r14 + N_DATA + 24]
        call int_add
        mov [rsp + 8], rax
        mov rdi, rax
        call int_sign
        test eax, eax
        js 5b
        # [k << (offset + shl) for k in range(2 ** size)]
        mov rdi, [rsp + 8]
        call int_to_i64
        mov rdi, rax
        call pow2
        mov [rsp + 8], rax              # 2 ** (offset + shl)
        call vec_new
        mov r12, rax
        mov rcx, [rsp]
        mov r13d, 1
        shl r13d, cl                    # 2 ** size
        mov [rsp], r13
        xor r13d, r13d
6:      cmp r13, [rsp]
        jae 7f
        mov rdi, r13
        TAG rdi
        mov rsi, [rsp + 8]
        call int_mul
        mov rdi, r12
        mov rsi, rax
        call vec_push
        inc r13
        jmp 6b
7:      mov rax, r14
        mov rdx, r12
        add rsp, 16
        LEAVE
9:      xor eax, eax
        add rsp, 16
        LEAVE
ENDF switch_values

        .set FG_VOLATILE, 0
        .set FG_STORAGE, 1
        .set FG_TLOAD, 2

# forget_mentions(x, kind) -> eax: python's mentions(x, names) for the
# names of forget's kind: VOLATILE's, ("storage",), ("tload",)
FUNC forget_mentions
        ENTER
        mov rbx, rdi
        mov r12d, esi
        cmp r12d, FG_STORAGE
        je 2f
        call is_volatile                # ("tload" is volatile too)
        test eax, eax
        jz 9f
        cmp r12d, FG_TLOAD
        jne 9f
        mov rdi, rbx
        lea rsi, [rip + .Ls_tload]
        call mentions_c
        LEAVE
2:      mov rsi, HF_STORAGE
        call mentions
9:      LEAVE
ENDF forget_mentions

        .section .rodata
.Ls_tload: .asciz "tload"
        .text

# forget(known, kind) -> rax: python's forget - what's still known once
# what the names read may have changed: a fact about the memory loses its
# value when that reads it (not the place: the memory changes by the
# writes only), the others go when they mention one of the names (but
# ('memory_fresh',))
FUNC forget
        ENTER
        mov rbx, rdi
        mov r12d, esi
        call vec_new
        mov r13, rax
        xor r14d, r14d
1:      cmp r14d, [rbx + N_AUX]
        jae 5f
        mov rdi, [rbx + N_DATA + r14*8]
        inc r14d
        push rdi
        push rdi
        OPCODE_OF_RDI
        pop rdi
        pop rdi
        cmp eax, OP_MEMORY
        je 2f
        cmp eax, OP_MEMORY_FRESH
        je 4f
        push rdi
        push rdi
        mov esi, r12d
        call forget_mentions
        pop rdi
        pop rdi
        test eax, eax
        jnz 1b
        jmp 4f
2:      push rdi
        push rdi
        mov rdi, [rdi + N_DATA + 24]
        mov esi, r12d
        call forget_mentions
        pop rdi
        pop rdi
        test eax, eax
        jz 4f
        mov rsi, [rdi + N_DATA + 8]     # fact[:3] + (None,)
        mov rdx, [rdi + N_DATA + 16]
        lea rcx, [rip + sp_none]
        LOADS rdi, MEMORY
        call mk4
        mov rdi, rax
4:      mov rsi, rdi
        mov rdi, r13
        call vec_push
        jmp 1b
5:      mov rdi, r13
        call vec_to_tuple
        LEAVE
ENDF forget

# entry_memory(entries) -> rax: python's entry_memory - what's known of
# the memory when a function starts: what every path of the dispatcher to
# it (an entry: its lines) wrote, in a memory of zeroes; sorted by str.
# entries: a list of entries, or NIL / None.
FUNC entry_memory
        ENTER
        sub rsp, 16
        mov rbx, rdi
        xor r12d, r12d                  # res (a vec), 0: python's None
        test rbx, rbx
        jz .Lem_done
        lea rax, [rip + sp_none]
        cmp rbx, rax
        je .Lem_done
        xor r13d, r13d
.Lem_entry:
        cmp r13d, [rbx + N_AUX]
        jae .Lem_done
        mov r14, [rbx + N_DATA + r13*8] # the entry
        inc r13d
        LOADS rdi, MEMORY_FRESH
        call mk1
        mov rdi, 1
        mov [rsp], rax
        lea rsi, [rsp]
        call mk_tuple                   # (('memory_fresh',),)
        mov [rsp + 8], rax              # known
        xor ecx, ecx
1:      cmp ecx, [r14 + N_AUX]
        jae 3f
        mov rdi, [r14 + N_DATA + rcx*8]
        inc ecx
        mov [rsp], rcx
        mov esi, OP_SETMEM
        mov edx, 3
        call is_op_n
        mov rcx, [rsp]
        test eax, eax
        jz 1b
        mov rax, [r14 + N_DATA + rcx*8 - 8]
        mov rdi, [rsp + 8]
        mov rdx, [rax + N_DATA + 16]
        mov rsi, [rax + N_DATA + 8]
        call write_memory
        mov [rsp + 8], rax
        mov rcx, [rsp]
        jmp 1b
3:      test r12, r12
        jnz 4f
        call vec_new                    # set(known)
        mov r12, rax
        mov rax, [rsp + 8]
        xor ecx, ecx
31:     cmp ecx, [rax + N_AUX]
        jae .Lem_entry
        mov rsi, [rax + N_DATA + rcx*8]
        inc ecx
        mov [rsp], rcx
        mov rdi, r12
        call vec_push_unique
        mov rcx, [rsp]
        mov rax, [rsp + 8]
        jmp 31b
4:      # res & set(known)
        xor ecx, ecx
        xor edx, edx                    # (kept, written back)
5:      cmp rcx, [r12 + VEC_LEN]
        jae 8f
        mov rax, [r12 + VEC_DATA]
        mov rdi, [rax + rcx*8]
        mov rax, [rsp + 8]
        xor esi, esi
6:      cmp esi, [rax + N_AUX]
        jae 7f
        cmp [rax + N_DATA + rsi*8], rdi
        je 61f
        inc esi
        jmp 6b
61:     mov rax, [r12 + VEC_DATA]
        mov [rax + rdx*8], rdi
        inc rdx
7:      inc rcx
        jmp 5b
8:      mov [r12 + VEC_LEN], rdx
        jmp .Lem_entry
.Lem_done:
        test r12, r12
        jz 9f
        cmp qword ptr [r12 + VEC_LEN], 0
        je 9f
        mov rdi, r12
        call sort_by_str
        mov rdi, r12
        call vec_to_tuple
        add rsp, 16
        LEAVE
9:      xor edi, edi
        xor esi, esi
        call mk_tuple
        add rsp, 16
        LEAVE
ENDF entry_memory


# sort_by_str(vec): python's sort(key=str), in place (stable)
FUNC sort_by_str
        ENTER
        mov rbx, rdi
        xor r12d, r12d
1:      cmp r12, [rbx + VEC_LEN]
        jae 2f
        mov rax, [rbx + VEC_DATA]
        mov r13, [rax + r12*8]
        mov rdi, r13
        call value_str
        mov rdi, rax
        mov rsi, r13
        call mk2
        mov rcx, [rbx + VEC_DATA]
        mov [rcx + r12*8], rax
        inc r12
        jmp 1b
2:      mov rdi, rbx
        lea rsi, [rip + pair_key_lt]
        xor edx, edx
        call py_sort
        xor r12d, r12d
3:      cmp r12, [rbx + VEC_LEN]
        jae 4f
        mov rax, [rbx + VEC_DATA]
        mov rcx, [rax + r12*8]
        mov rcx, [rcx + N_DATA + 8]
        mov [rax + r12*8], rcx
        inc r12
        jmp 3b
4:      LEAVE
ENDF sort_by_str

        .section .note.GNU-stack,"",@progbits
