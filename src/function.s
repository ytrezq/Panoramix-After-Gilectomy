# A decompiled function (port of function.py's Function): its name from
# the abi, the types of its parameters, whether it is payable, read-only,
# a constant or a getter, and its text.
#
# The struct is FN_* (defs.inc). The abi entry is (name, inputs[, type]),
# inputs being a list of inputs (see sigs.s) or NIL. FN_INPUTS is what
# python's _abi[hash]["inputs"] is now (get_func_params): the abi's, the
# ones rename_params gives (set_func_params), or the inferred params once
# the function is printed without any (set_func_params_if_none).

.include "defs.inc"

        .section .rodata
.Ls_logname:    .asciz "panoramix.function"
.Ls_unaligned:  .asciz "unusual cd (not aligned)"
.Ls_unknown:    .asciz "unknown"
.Ls_comma_sp:   .asciz ", "
.Ls_comma:      .asciz ","
.Ls_param_:     .asciz "_param"
.Ls_tuple:      .asciz "tuple"
.Ls_array:      .asciz "array"
.Ls_bool:       .asciz "bool"
.Ls_uint:       .asciz "uint"
.Ls_bytes:      .asciz "bytes"
.Ls_int:        .asciz "int"
.Ls_q_store:    .asciz "'store'"
.Ls_q_selfdestruct: .asciz "'selfdestruct'"
.Ls_q_call:     .asciz "'call'"
.Ls_q_delegatecall: .asciz "'delegatecall'"
.Ls_q_callcode: .asciz "'callcode'"
.Ls_q_create:   .asciz "'create'"
.Ls_q_tstore:   .asciz "'tstore'"
.Ls_q_create2:  .asciz "'create2'"
.Ls_q_log:      .asciz "'log'"
.Ls_selfdestruct: .asciz "selfdestruct"
.Ls_const_:     .asciz "const "
.Ls_eq_sp:      .asciz " = "
.Ls_def_:       .asciz "def "
.Ls_payable:    .asciz " payable"
.Ls_colon_sp:   .asciz ": "
.Ls_not_payable: .asciz "# not payable"
.Ls_invalid_note: .asciz " (invalid)"
.Ls_default:    .asciz "# default function"
.Ls_and_default: .asciz ", default function"
.Ls_fallback_q: .asciz "_fallback(?)"
.Ls_stop_line:  .asciz "  stop"
.Ls_empty_paren: .asciz "()"
.Ls_newline:    .asciz "\n"
.Ls_assert_trace: .asciz "AssertionError: function: an empty trace"
.Ls_assert_kind: .asciz "AssertionError: function: a param of no kind"
.Ls_index:      .asciz "IndexError: function: an index out of range"
.Ls_unpack:     .asciz "ValueError: function: a while of more or less than 5 elements"
.Ls_concat:     .asciz "TypeError: can only concatenate tuple (not \"str\") to tuple"

        .section .data.rel.ro
        .align 8
        # the opcodes that make a function not read-only (what changes the
        # state, or does something that stays: a log), quoted as in
        # python's str(trace)
not_read_only:
        .quad .Ls_q_store, .Ls_q_tstore, .Ls_q_selfdestruct, .Ls_q_call, .Ls_q_delegatecall, .Ls_q_callcode, .Ls_q_create, .Ls_q_create2, .Ls_q_log, 0

        .text

.macro B reg, n
        mov \reg, [rsp + 8*(\n)]
.endm

# (the names, signatures.get_func_name and get_abi_name: abi_func_name and
# abi_name in sigs.s)

# --- what the analysis reads ---

# fn_word(exp) -> rax: function.word - a word of data (see memloc,
# "bytes"), as its value: ('bytes', 32, val) -> val, else exp itself
FUNC fn_word
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        PATXD "('bytes', 32, ':val')"
        test eax, eax
        jz 1f
        mov rax, [rsp]
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
1:      mov rax, rbx
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
ENDF fn_word

# fn_disjuncts(cond, out): function.disjuncts - the conditions cond holds
# where one of them does (of `a | b`, a and b - each simplify_bool'ed, and
# its own disjuncts), pushed on the vec out
FUNC fn_disjuncts
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call opcode_of
        cmp eax, OP_OR
        jne 2f
        cmp dword ptr [rbx + N_AUX], 1
        jbe 2f
        mov r13d, 1
1:      cmp r13d, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + r13*8]
        call simplify_bool
        mov rdi, rax
        mov rsi, r12
        call fn_disjuncts
        inc r13d
        jmp 1b
2:      mov rdi, r12
        mov rsi, rbx
        call vec_push
3:      LEAVE
ENDF fn_disjuncts

# the operations that read what can change: the calldata, the state, the
# environment (python's VARYING_READS)
        OPSET_MEMBER varying_reads, OP_CD
        OPSET_MEMBER varying_reads, OP_CALL_DATA
        OPSET_MEMBER varying_reads, OP_STORAGE
        OPSET_MEMBER varying_reads, OP_TLOAD
        OPSET_MEMBER varying_reads, OP_BALANCE
        OPSET_MEMBER varying_reads, OP_EXTCODESIZE
        OPSET_MEMBER varying_reads, OP_EXTCODEHASH
        OPSET_MEMBER varying_reads, OP_EXTCODECOPY
        OPSET_MEMBER varying_reads, OP_BLOCKHASH
        OPSET_MEMBER varying_reads, OP_BLOBHASH
        OPSET_END varying_reads, OP_COUNT

# fn_varies(exp) -> eax: function.varies - exp reads something that isn't
# a constant of the contract: any string but address and codesize (where
# the contract is: CONSTANT_SYMBOLS), an operation of VARYING_READS - but
# not a variable (its value is set in the trace, and checked there). The
# head of a tuple is not looked at, the elements of a list are.
FUNC fn_varies
        STACK_CHECK
        ENTER
        mov rbx, rdi
        test bl, 1
        jnz .Lfv_no
        test rbx, rbx
        jz .Lfv_no
        mov eax, [rbx + N_KIND]
        cmp eax, K_STR
        je .Lfv_str
        cmp eax, K_LIST
        je .Lfv_list
        cmp eax, K_TUPLE
        jne .Lfv_no                     # (an int, None, True...)
        cmp dword ptr [rbx + N_AUX], 0
        je .Lfv_no
        mov rdi, rbx
        call opcode_of
        IN_OPSET varying_reads, rax
        jne .Lfv_yes
        cmp eax, OP_VAR
        je .Lfv_no
        mov r12d, 1                     # exp[1:]
        jmp 1f
.Lfv_list:
        xor r12d, r12d
1:      cmp r12d, [rbx + N_AUX]
        jae .Lfv_no
        mov rdi, [rbx + N_DATA + r12*8]
        inc r12d
        call fn_varies
        test eax, eax
        jz 1b
.Lfv_yes:
        mov eax, 1
        LEAVE
.Lfv_str:
        test dword ptr [rbx + N_AUX], STR_FLOAT         # (a python float)
        jnz .Lfv_no
        LOADS rax, ADDRESS
        cmp rbx, rax
        je .Lfv_no
        LOADS rax, CODESIZE
        cmp rbx, rax
        je .Lfv_no
        jmp .Lfv_yes
.Lfv_no:
        xor eax, eax
        LEAVE
ENDF fn_varies

# --- the parameters ---

# params_get(fn, idx) -> rax: the (idx, kind, name) of a parameter, or 0
FUNC params_get
        mov rax, [rdi + FN_PARAMS]
        xor ecx, ecx
1:      cmp ecx, [rax + N_AUX]
        jae 2f
        mov rdx, [rax + N_DATA + rcx*8]
        cmp [rdx + N_DATA], rsi
        je 3f
        inc ecx
        jmp 1b
2:      xor eax, eax
        ret
3:      mov rax, rdx
        ret
ENDF params_get

# make_params(fn) -> list of (idx, kind, name): python's inferred_params,
# {position in the calldata: (kind, name)} - the words of the params of
# the abi (calldata_params), or, when the abi has none, guessed from how
# the calldata is used: a word that's the pointer to the data of others
# (an array), checked to be a valid value of a type (validation), masked
# everywhere to a type's size, only used as a truth value (a bool)
FUNC make_params
        ENTER
        sub rsp, 96
        .set MP_USES, 0                 # od: idx -> vec of its sizes (0: python's None)
        .set MP_PTRS, 8                 # vec: the pointers (a set)
        .set MP_SIZES, 16               # od: idx -> its size
        .set MP_OCC, 24                 # vec: the references to the calldata
        .set MP_I, 32
        .set MP_IDX, 40
        .set MP_SIZE, 48
        .set MP_T, 56
        .set MP_OUT, 64
        .set MP_COUNT, 72
        .set MP_N, 80
        mov rbx, rdi
        mov r12, [rbx + FN_INPUTS]      # get_func_params
        test r12, r12
        jz .Lmp_guess
        # (none for a function the abi says has none: a word of the
        # calldata it reads isn't a param then)
        mov rdi, r12
        call calldata_params
        mov r12, rax
        call vec_new
        mov r13, rax
        xor r14d, r14d
1:      cmp r14d, [r12 + N_AUX]
        jae 2f
        mov rax, [r12 + N_DATA + r14*8] # (type, name), the word at 4 + 32 i
        mov rdi, [rax + N_DATA]
        call .Lmp_interned
        mov [rsp + MP_T], rax
        mov rax, [r12 + N_DATA + r14*8]
        mov rdi, [rax + N_DATA + 8]
        call .Lmp_interned
        mov rdx, rax
        mov rsi, [rsp + MP_T]
        mov rdi, r14
        shl rdi, 5
        add rdi, 4
        TAG rdi
        call mk3
        mov rdi, r13
        mov rsi, rax
        call vec_push
        inc r14d
        jmp 1b
2:      mov rdi, r13
        call vec_to_list
        add rsp, 96
        LEAVE

.Lmp_guess:
        # good testing: solidstamp, auditContract - every reference to the
        # calldata, ('mask_shl', _, _, _, ('cd', _)) and ('cd', _), and how
        # it's accessed: masked? used as a pointer?
        call vec_new
        mov [rsp + MP_OCC], rax
        mov rdi, [rbx + FN_TRACE]
        mov rsi, rax
        call cd_reads
        call od_new
        mov [rsp + MP_USES], rax
        call vec_new
        mov [rsp + MP_PTRS], rax
        mov qword ptr [rsp + MP_I], 0
.Lmp_occ:
        mov rax, [rsp + MP_OCC]
        mov rcx, [rsp + MP_I]
        cmp rcx, [rax + VEC_LEN]
        jae .Lmp_aligned
        mov rax, [rax + VEC_DATA]
        mov r12, [rax + rcx*8]          # o
        inc qword ptr [rsp + MP_I]
        mov qword ptr [rsp + MP_SIZE], 0        # None
        mov rdi, r12
        call opcode_of
        cmp eax, OP_MASK_SHL
        jne 3f
        # only the lowest bits tell a type: taking a byte out of the
        # middle doesn't make a param an uint8
        mov rax, [r12 + N_DATA + 32]
        mov rax, [rax + N_DATA + 8]
        mov [rsp + MP_IDX], rax
        mov rdi, [r12 + N_DATA + 16]
        mov esi, 1                      # off == 0
        call py_equal
        test eax, eax
        jz 4f
        mov rax, [r12 + N_DATA + 8]
        mov [rsp + MP_SIZE], rax
        jmp 4f
3:      mov rax, [r12 + N_DATA + 8]     # ('cd', idx)
        mov [rsp + MP_IDX], rax
4:      mov rdi, [rsp + MP_IDX]
        call is_int                     # (python's type(idx) is int: not a bool)
        test eax, eax
        jnz 5f
        # an element of an array, or its length: what it's read relatively
        # to is a pointer to it - the n of every ('cd', n) in idx
        call vec_new
        mov r13, rax
        mov rdi, [rsp + MP_IDX]
        lea rsi, [rip + pred_cd_number]
        mov rdx, rax
        call walk_collect
        xor r14d, r14d
41:     cmp r14, [r13 + VEC_LEN]
        jae .Lmp_occ
        mov rax, [r13 + VEC_DATA]
        mov rax, [rax + r14*8]
        mov rdi, [rsp + MP_PTRS]
        mov rsi, [rax + N_DATA + 8]
        call set_add
        inc r14
        jmp 41b
5:      cmp qword ptr [rsp + MP_IDX], 1         # idx == 0: the selector
        je .Lmp_occ
        mov rdi, [rsp + MP_USES]
        mov rsi, [rsp + MP_IDX]
        call od_get
        test rax, rax
        jnz 6f
        call vec_new
        mov r13, rax
        mov rdi, [rsp + MP_USES]
        mov rsi, [rsp + MP_IDX]
        mov rdx, rax
        call od_put
        mov rax, r13
6:      mov rdi, rax
        mov rsi, [rsp + MP_SIZE]
        call vec_push
        jmp .Lmp_occ

.Lmp_aligned:
        # the params are words: (idx - 4) % 32 == 0 for every one
        mov rdi, [rsp + MP_USES]
        call od_len
        mov [rsp + MP_N], rax
        xor r14d, r14d
1:      cmp r14, [rsp + MP_N]
        jae 2f
        mov rdi, [rsp + MP_USES]
        mov rsi, r14
        call od_key
        mov rdi, rax
        call .Lmp_is_word_loc
        test eax, eax
        jz .Lmp_unaligned
        inc r14
        jmp 1b
2:      # the sizes: a pointer is an array (-1); a param checked to be a
        # valid value has the type it's checked for; one masked everywhere
        # (as the compilers did before validating the params) the type of
        # its smallest mask; any other is an uint256
        call od_new
        mov [rsp + MP_SIZES], rax
        xor r14d, r14d
3:      cmp r14, [rsp + MP_N]
        jae .Lmp_pointers
        mov rdi, [rsp + MP_USES]
        mov rsi, r14
        call od_key
        mov [rsp + MP_IDX], rax
        mov rdi, [rsp + MP_PTRS]
        mov rsi, rax
        call set_has
        mov rdx, -1                     # (-1)
        test eax, eax
        jnz 5f
        mov rdi, rbx
        mov rsi, [rsp + MP_IDX]
        call fn_validation
        mov rdx, rax
        test rax, rax
        jnz 5f
        mov rdi, [rsp + MP_USES]
        mov rsi, r14
        call od_val
        mov rdi, rax
        call .Lmp_min_size
        mov rdx, rax
        test rax, rax
        jnz 5f
        mov edx, (256 << 1) | 1
5:      mov rdi, [rsp + MP_SIZES]
        mov rsi, [rsp + MP_IDX]
        call od_put
        inc r14
        jmp 3b
.Lmp_pointers:
        # the pointers to the data of params not read themselves (python
        # goes through a set difference, in its order: the sizes are only
        # read in the order of their positions)
        mov rax, [rsp + MP_PTRS]
        xor r14d, r14d
1:      mov rax, [rsp + MP_PTRS]
        cmp r14, [rax + VEC_LEN]
        jae .Lmp_bools
        mov rax, [rax + VEC_DATA]
        mov r12, [rax + r14*8]
        inc r14
        mov rdi, [rsp + MP_SIZES]
        mov rsi, r12
        call od_index
        test rax, rax
        jns 1b
        mov rdi, r12
        call is_int
        test eax, eax
        jz 1b
        mov rdi, r12
        call int_sign
        cmp eax, 1
        jne 1b
        mov rdi, r12
        call .Lmp_is_word_loc
        test eax, eax
        jz 1b
        mov rdi, [rsp + MP_SIZES]
        mov rsi, r12
        mov rdx, -1
        call od_put
        jmp 1b
.Lmp_bools:
        # for every idx check if it's a bool by any chance: only used
        # under a bool, an if, an iszero
        mov rdi, [rsp + MP_SIZES]
        call od_len
        mov [rsp + MP_N], rax
        xor r14d, r14d
1:      cmp r14, [rsp + MP_N]
        jae 2f
        mov rdi, [rsp + MP_SIZES]
        mov rsi, r14
        call od_key
        mov rdi, rax
        call .Lmp_is_bool
        test eax, eax
        jz 11f
        mov rdi, [rsp + MP_SIZES]
        mov rsi, r14
        mov edx, 3                      # 1
        call od_set_val
11:     inc r14
        jmp 1b
2:      # (python's check that every idx is an int never fails here: they
        # all are) - sorted by idx: (kind, _param<n>)
        call vec_new
        mov r13, rax
        mov rax, [rsp + MP_SIZES]
        mov rsi, [rax + OD_KEYS]
        mov rdx, [rsi + VEC_LEN]
        mov rsi, [rsi + VEC_DATA]
        mov rdi, r13
        call vec_extend
        mov rdi, r13
        lea rsi, [rip + py_lt]
        xor edx, edx
        call py_sort
        call vec_new
        mov [rsp + MP_OUT], rax
        mov qword ptr [rsp + MP_COUNT], 1
        xor r14d, r14d
.Lmp_kinds:
        cmp r14, [r13 + VEC_LEN]
        jae 12f
        mov rax, [r13 + VEC_DATA]
        mov rax, [rax + r14*8]
        mov [rsp + MP_IDX], rax
        mov rdi, [rsp + MP_SIZES]
        mov rsi, rax
        call od_get
        mov r12, rax                    # the size
        mov rdi, rax
        call .Lmp_is_text
        test eax, eax
        jz 101f
        mov rax, r12                    # (a type, from the validation)
        jmp 104f
101:    mov rdi, r12
        mov rsi, -3                     # -2
        call py_equal
        test eax, eax
        jz 102f
        lea rdi, [rip + .Ls_tuple]
        call str_intern_c
        jmp 104f
102:    mov rdi, r12
        mov rsi, -1
        call py_equal
        test eax, eax
        jz 103f
        lea rdi, [rip + .Ls_array]
        call str_intern_c
        jmp 104f
103:    mov rdi, r12
        mov esi, 3                      # 1
        call py_equal
        test eax, eax
        jz 105f
        lea rdi, [rip + .Ls_bool]
        call str_intern_c
        jmp 104f
105:    # (of a whole number of bytes, its type: uint24, not the uint32
        # that's the next one mask_to_type knows)
        test r12b, 1
        jz 106f
        mov rax, r12
        sar rax, 1
        test rax, rax
        jle 106f
        cmp rax, 256
        jge 106f
        test al, 7
        jnz 106f
        mov rdi, r12
        xor esi, esi
        call mask_to_type
        test rax, rax
        jz 107f
        lea rcx, [rip + sp_none]
        cmp rax, rcx
        je 107f
        mov rdi, rax
        call .Lmp_interned
        jmp 104f
107:    lea rsi, [rip + .Ls_uint]
        mov rdx, r12
        call .Lfc_text_int
        jmp 104f
106:    mov rdi, r12
        mov esi, 1
        call mask_to_type
        test rax, rax
        jz .Lmp_assert
        lea rcx, [rip + sp_none]
        cmp rax, rcx
        je .Lmp_assert
        mov rdi, rax
        call .Lmp_interned
104:    mov [rsp + MP_T], rax           # the kind
        call sb_new
        mov r12, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_param_]
        call sb_append_c
        mov rdi, r12
        mov rsi, [rsp + MP_COUNT]
        call sb_append_u64
        mov rdi, r12
        call sb_finish_intern
        mov rdx, rax
        mov rdi, [rsp + MP_IDX]
        mov rsi, [rsp + MP_T]
        call mk3
        mov rdi, [rsp + MP_OUT]
        mov rsi, rax
        call vec_push
        inc qword ptr [rsp + MP_COUNT]
        inc r14
        jmp .Lmp_kinds
12:     mov rdi, [rsp + MP_OUT]
        call vec_to_list
        add rsp, 96
        LEAVE
.Lmp_unaligned:
        mov edi, LOG_WARNING
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_unaligned]
        call log_fmt
        xor edi, edi
        xor esi, esi
        call mk_list
        add rsp, 96
        LEAVE
.Lmp_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_kind]
        call err_throw

# locals of make_params
# the interned string of a string, anything else as it is
.Lmp_interned:
        sub rsp, 24
        mov [rsp], rdi
        call .Lmp_is_text
        test eax, eax
        jz 1f
        mov rdi, [rsp]
        call str_interned
        add rsp, 24
        ret
1:      mov rax, [rsp]
        add rsp, 24
        ret
# eax: a str of python (a string, but not the text of a float)
.Lmp_is_text:
        xor eax, eax
        test dil, 1
        jnz 1f
        test rdi, rdi
        jz 1f
        cmp dword ptr [rdi + N_KIND], K_STR
        jne 1f
        test dword ptr [rdi + N_AUX], STR_FLOAT
        jnz 1f
        mov eax, 1
1:      ret
# eax: the int rdi is a word's position (idx - 4) % 32 == 0
.Lmp_is_word_loc:
        sub rsp, 8
        mov rsi, (4 << 1) | 1
        call int_sub
        mov rdi, rax
        mov rsi, (32 << 1) | 1
        call int_mod
        xor ecx, ecx
        cmp rax, 1
        sete cl
        mov eax, ecx
        add rsp, 8
        ret
# rax: min() of the sizes of the vec rdi, or 0 when one is None or isn't
# a known size (an int, 0 < s <= 256: masked everywhere, as the compilers
# did before validating the params, by masks of known sizes)
.Lmp_min_size:
        push rbx
        push r12
        push r13
        mov rbx, rdi
        xor r12d, r12d
1:      cmp r12, [rbx + VEC_LEN]
        jae 2f
        mov rax, [rbx + VEC_DATA]
        mov rax, [rax + r12*8]
        test al, 1                      # (a small int: the known sizes are)
        jz 8f
        sar rax, 1
        test rax, rax
        jle 8f
        cmp rax, 256
        jg 8f
        inc r12
        jmp 1b
2:      mov rax, [rbx + VEC_DATA]
        mov r13, [rax]
        mov r12d, 1
3:      cmp r12, [rbx + VEC_LEN]
        jae 4f
        mov rax, [rbx + VEC_DATA]
        mov rdi, [rax + r12*8]
        mov rsi, r13
        xor edx, edx
        call py_lt                      # item < min
        test eax, eax
        jz 31f
        mov rax, [rbx + VEC_DATA]
        mov r13, [rax + r12*8]
31:     inc r12
        jmp 3b
4:      mov rax, r13
        pop r13
        pop r12
        pop rbx
        ret
8:      xor eax, eax
        pop r13
        pop r12
        pop rbx
        ret
# eax: every parent of ('cd', idx) in the trace is a bool, an if or an
# iszero (none at all too: python's for-else)
.Lmp_is_bool:
        sub rsp, 24
        mov rsi, rdi
        LOADS rdi, CD
        call mk2
        mov [rsp], rax
        call vec_new
        mov [rsp + 8], rax
        mov rdi, [rbx + FN_TRACE]
        mov rsi, [rsp]
        mov rdx, rax
        call find_parents
        mov qword ptr [rsp + 16], 0
1:      mov rax, [rsp + 8]
        mov rcx, [rsp + 16]
        cmp rcx, [rax + VEC_LEN]
        jae 2f
        mov rax, [rax + VEC_DATA]
        mov rdi, [rax + rcx*8]
        call opcode_of
        cmp eax, OP_BOOL
        je 3f
        cmp eax, OP_IF
        je 3f
        cmp eax, OP_ISZERO
        je 3f
        xor eax, eax
        add rsp, 24
        ret
3:      inc qword ptr [rsp + 16]
        jmp 1b
2:      mov eax, 1
        add rsp, 24
        ret
ENDF make_params

# cd_reads(exp, out): python's reads of make_params - every
# ('mask_shl', _, _, _, ('cd', _)) and ('cd', _) of exp, depth first. A
# mask of a read is that read: not, as find_f_list would have it, the read
# inside it as well, unmasked (its size, offset and shift, and what the
# read is of, are walked).
FUNC cd_reads
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call is_seq
        test eax, eax
        jz 9f
        mov rdi, rbx
        call pred_cd_ref
        test eax, eax
        jz 5f
        mov rdi, r12
        mov rsi, rbx
        call vec_push
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_CD
        je 4f
        mov r13d, 1                     # the mask's size, offset, shift
1:      cmp r13d, 4
        jae 2f
        mov rdi, [rbx + N_DATA + r13*8]
        mov rsi, r12
        call cd_reads
        inc r13d
        jmp 1b
2:      mov rbx, [rbx + N_DATA + 32]    # and the read's
4:      mov rdi, [rbx + N_DATA + 8]
        mov rsi, r12
        call cd_reads
        jmp 9f
5:      xor r13d, r13d
6:      cmp r13d, [rbx + N_AUX]
        jae 9f
        mov rdi, [rbx + N_DATA + r13*8]
        mov rsi, r12
        call cd_reads
        inc r13d
        jmp 6b
9:      LEAVE
ENDF cd_reads

# pred_cd_ref(exp) -> eax: ('mask_shl', _, _, _, ('cd', _)) or ('cd', _)
FUNC pred_cd_ref
        ENTER
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_CD
        jne 1f
        cmp dword ptr [rbx + N_AUX], 2
        sete al
        movzx eax, al
        LEAVE
1:      cmp eax, OP_MASK_SHL
        jne 2f
        cmp dword ptr [rbx + N_AUX], 5
        jne 2f
        mov rdi, [rbx + N_DATA + 32]
        call opcode_of
        cmp eax, OP_CD
        jne 2f
        mov rdi, [rbx + N_DATA + 32]
        cmp dword ptr [rdi + N_AUX], 2
        sete al
        movzx eax, al
        LEAVE
2:      xor eax, eax
        LEAVE
ENDF pred_cd_ref

# pred_cd_number(exp) -> eax: ('cd', n) of a number n (python's match of
# ('cd', int), isinstance: a bool too)
FUNC pred_cd_number
        ENTER
        mov rbx, rdi
        OP_N_CHECK OP_CD, 2, 1f
        mov rdi, [rbx + N_DATA + 8]
        call vr_number
        test rax, rax
        setnz al
        movzx eax, al
        LEAVE
1:      xor eax, eax
        LEAVE
ENDF pred_cd_number

# fn_validation(fn, idx) -> rax: Function.validation - the type of the
# param at idx (an interned str) if the function checks that its value is
# a valid one - as solc does since 0.8, reverting if it's not -, with one
# type wherever it does; else 0
FUNC fn_validation
        ENTER
        mov rbx, rdi
        LOADS rdi, CD
        call mk2                        # cd = ('cd', idx)
        mov r12, rax
        call vec_new
        mov r13, rax
        mov rdi, [rbx + FN_TRACE]
        mov rsi, r12
        mov rdx, r13
        call fv_walk
        # set(found): a single one
        mov rcx, [r13 + VEC_LEN]
        test rcx, rcx
        jz 9f
        mov rdx, [r13 + VEC_DATA]
        mov rax, [rdx]
1:      dec rcx
        jz 8f
        cmp rax, [rdx + rcx*8]
        jne 9f
        jmp 1b
8:      LEAVE
9:      xor eax, eax
        LEAVE
ENDF fn_validation

# fv_walk(exp, cd, out): fv_check of every tuple and list of exp, depth
# first (python's find_f_list)
FUNC fv_walk
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        IS_SEQ_RDI
        test eax, eax
        jz 9f
        mov rdi, rbx
        mov rsi, r12
        mov rdx, r13
        call fv_check
        xor r14d, r14d
1:      cmp r14d, [rbx + N_AUX]
        jae 9f
        mov rdi, [rbx + N_DATA + r14*8]
        mov rsi, r12
        mov rdx, r13
        call fv_walk
        inc r14d
        jmp 1b
9:      LEAVE
ENDF fv_walk

# fv_check(exp, cd, out): validation's f - for ('eq', cd, x) (or ('eq',
# x, cd)) where x is cd as a valid value of a type would be (cut to its
# size, its lowest bits or its highest ones; a bool; sign-extended), that
# type pushed (an interned str)
FUNC fv_check
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi                    # cd
        mov r13, rdx                    # out
        OP_N_CHECK OP_EQ, 3, 9f
        mov rax, [rbx + N_DATA + 8]     # a
        mov r14, [rbx + N_DATA + 16]    # b
        cmp rax, r12
        je 1f                           # other = b
        cmp r14, r12
        jne 9f
        mov r14, rax                    # other = a
1:      # ('mask_shl', :int:size, :int:off, 0, cd)
        mov rdi, r14
        OP_N_CHECK OP_MASK_SHL, 5, 5f
        cmp [r14 + N_DATA + 32], r12
        jne 5f
        mov rdi, [r14 + N_DATA + 24]
        mov esi, 1
        call py_equal
        test eax, eax
        jz 5f
        mov rdi, [r14 + N_DATA + 8]
        call vr_number
        test rax, rax
        jz 5f
        mov [rsp], rax                  # size
        mov rdi, [r14 + N_DATA + 16]
        call vr_number
        test rax, rax
        jz 5f
        mov [rsp + 8], rax              # off
        # off == 0 and size % 8 == 0 and 0 < size <= 256: an uint of that
        # size (or its name: address...)
        cmp rax, 1
        jne 3f
        mov rdi, [rsp]
        call .Lfc_bytes
        test eax, eax
        jz 3f
        mov rdi, [rsp]
        call int_sign
        cmp eax, 1
        jne 3f
        mov rdi, [rsp]
        mov rsi, (256 << 1) | 1
        call int_cmp
        cmp eax, 1
        je 3f
        mov rdi, [rsp]
        xor esi, esi
        call mask_to_type
        test rax, rax
        jnz 8f
        lea rsi, [rip + .Ls_uint]
        mov rdx, [rsp]
        call .Lfc_text_int
        jmp 8f
3:      # off + size == 256 and size % 8 == 0: bytes<size // 8>
        mov rdi, [rsp + 8]
        mov rsi, [rsp]
        call int_add
        cmp rax, (256 << 1) | 1
        jne 9f
        mov rdi, [rsp]
        call .Lfc_bytes
        test eax, eax
        jz 9f
        mov rdi, [rsp]
        mov rsi, (8 << 1) | 1
        call int_floordiv
        lea rsi, [rip + .Ls_bytes]
        mov rdx, rax
        call .Lfc_text_int
        jmp 8f
5:      # ('bool', cd)
        mov rdi, r14
        OP_N_CHECK OP_BOOL, 2, 6f
        cmp [r14 + N_DATA + 8], r12
        jne 6f
        lea rdi, [rip + .Ls_bool]
        call str_intern_c
        jmp 8f
6:      # ('signextend', :int:b, cd): int<8 * (b + 1)>
        mov rdi, r14
        OP_N_CHECK OP_SIGNEXTEND, 3, 9f
        cmp [r14 + N_DATA + 16], r12
        jne 9f
        mov rdi, [r14 + N_DATA + 8]
        call vr_number
        test rax, rax
        jz 9f
        mov rdi, rax
        mov esi, 3
        call int_add
        mov rdi, (8 << 1) | 1
        mov rsi, rax
        call int_mul
        lea rsi, [rip + .Ls_int]
        mov rdx, rax
        call .Lfc_text_int
8:      mov rdi, r13
        mov rsi, rax
        call vec_push
9:      add rsp, 16
        LEAVE
# eax: size % 8 == 0 (python's %: of a negative number too)
.Lfc_bytes:
        sub rsp, 8
        mov rsi, (8 << 1) | 1
        call int_mod
        xor ecx, ecx
        cmp rax, 1
        sete cl
        mov eax, ecx
        add rsp, 8
        ret
# rax: the interned text rsi (a C string) + the decimal of the int rdx
.Lfc_text_int:
        push rbx
        push r12
        push r13
        mov r12, rsi
        mov r13, rdx
        call sb_new
        mov rbx, rax
        mov rdi, rax
        mov rsi, r12
        call sb_append_c
        mov rdi, rbx
        mov rsi, r13
        mov edx, 10
        call sb_append_int
        mov rdi, rbx
        call sb_finish_intern
        pop r13
        pop r12
        pop rbx
        ret
ENDF fv_check

# find_parents(exp, child, out): the tuples and lists that contain child
# directly, depth first, once per occurrence
FUNC find_parents
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        call is_seq
        test eax, eax
        jz 3f
        xor r14d, r14d
1:      cmp r14d, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + r14*8]
        mov rsi, r12
        call py_equal
        test eax, eax
        jz 2f
        mov rdi, r13
        mov rsi, rbx
        call vec_push
2:      mov rdi, [rbx + N_DATA + r14*8]
        mov rsi, r12
        mov rdx, r13
        call find_parents
        inc r14d
        jmp 1b
3:      LEAVE
ENDF find_parents

# make_names(fn): the names from the inferred parameters, for an unknown
# function
FUNC make_names
        ENTER
        sub rsp, 16
        mov rbx, rdi
        # new_name = name.split("(")[0]
        mov rax, [rbx + FN_NAME]
        lea rdi, [rax + N_DATA + 4]
        mov esi, '('
        call strchr@PLT
        mov rdx, [rbx + FN_NAME]
        lea rdi, [rdx + N_DATA + 4]
        test rax, rax
        jz 1f
        mov rsi, rax
        sub rsi, rdi
        jmp 2f
1:      mov esi, [rdx + N_DATA]
2:      call str_new
        mov r12, rax                    # new_name
        # name: "new_name(kind name, ...)", color_name with green names,
        # abi_name: "new_name(kind,kind)"
        mov rdi, r12
        xor esi, esi
        call .Lmn_with_params
        mov [rbx + FN_NAME], rax
        mov rdi, r12
        mov esi, PF_COLOR
        call .Lmn_with_params
        mov [rbx + FN_COLOR_NAME], rax
        mov rdi, r12
        mov esi, 2                      # (the abi form)
        call .Lmn_with_params
        mov [rbx + FN_ABI_NAME], rax
        add rsp, 16
        LEAVE
# rdi = new_name, esi = flags (2: kinds only, joined by ",")
.Lmn_with_params:
        sub rsp, 40
        mov [rsp], rdi
        mov [rsp + 8], rsi
        call sb_new
        mov [rsp + 16], rax
        mov rdi, rax
        mov rsi, [rsp]
        call sb_append_str
        mov rdi, [rsp + 16]
        mov esi, '('
        call sb_append_char
        mov qword ptr [rsp + 24], 0
1:      mov rax, [rbx + FN_PARAMS]
        mov rcx, [rsp + 24]
        cmp ecx, [rax + N_AUX]
        jae 3f
        test ecx, ecx
        jz 2f
        lea rsi, [rip + .Ls_comma_sp]
        cmp qword ptr [rsp + 8], 2
        jne 11f
        lea rsi, [rip + .Ls_comma]
11:     mov rdi, [rsp + 16]
        call sb_append_c
2:      mov rax, [rbx + FN_PARAMS]
        mov rcx, [rsp + 24]
        mov rax, [rax + N_DATA + rcx*8] # (idx, kind, name)
        mov [rsp + 32], rax
        mov rdi, [rax + N_DATA + 8]
        call is_str
        test eax, eax
        jz .Lmn_not_str                 # (the size of an expression: python's kind + " ")
        mov rax, [rsp + 32]
        mov rdi, [rsp + 16]
        mov rsi, [rax + N_DATA + 8]
        call sb_append_str
        cmp qword ptr [rsp + 8], 2
        je 21f
        mov rdi, [rsp + 16]
        mov esi, ' '
        call sb_append_char
        mov rax, [rsp + 32]
        mov rdi, [rsp + 16]
        mov rsi, [rax + N_DATA + 16]
        lea rdx, [rip + C_GREEN]
        mov rcx, [rsp + 8]
        call sb_append_col
21:     inc qword ptr [rsp + 24]
        jmp 1b
3:      mov rdi, [rsp + 16]
        mov esi, ')'
        call sb_append_char
        mov rdi, [rsp + 16]
        call sb_finish
        add rsp, 40
        ret
.Lmn_not_str:
        mov rdi, [rsp + 16]
        call sb_free
        mov edi, E_TYPE
        lea rsi, [rip + .Ls_concat]
        call err_throw
ENDF make_names

# --- the params, once checked ---

        # cleanup_masks' known: a chain of records, the newest first (a
        # python dict's lookups: its keys give their values, the same)
        .set KN_NEXT, 0
        .set KN_KEY, 8
        .set KN_VAL, 16
        .set KN_SIZEOF, 32

# cleanup_masks(fn, trace) -> list: Function.cleanup_masks - a param as it
# is once it's checked: after `require _param1 == address(_param1)`,
# address(_param1) is _param1 - the calldata has no more than an address
# there. Not before, nor without the check (solc < 0.5 has none): a param
# is the word of calldata, whatever its type.
FUNC cleanup_masks
        mov rdi, rsi
        xor esi, esi
        jmp cm_rem
ENDF cleanup_masks

# cm_rem(trace, known) -> list: cleanup_masks' rem - the lines with what's
# known (x -> cd: the clean forms checked) put in, and past an if whose
# branch reverts when a param isn't clean, its form known in the other
FUNC cm_rem
        STACK_CHECK
        ENTER
        sub rsp, 48
        .set CR_OUT, 0
        .set CR_COND, 8
        .set CR_TRUE, 16
        .set CR_FALSE, 24
        .set CR_CD, 32
        .set CR_X, 40
        mov rbx, rdi                    # trace
        mov r12, rsi                    # known
        call vec_new
        mov [rsp + CR_OUT], rax
        xor r13d, r13d
.Lcr_line:
        cmp r13d, [rbx + N_AUX]
        jae .Lcr_done
        mov r14, [rbx + N_DATA + r13*8]
        inc r13d
        mov rdi, r14
        call opcode_of
        cmp eax, OP_IF
        je .Lcr_if
        cmp eax, OP_WHILE
        je .Lcr_while
.Lcr_other:
        mov rdi, r14
        mov rsi, r12
        call cm_subst
        mov rdi, [rsp + CR_OUT]
        mov rsi, rax
        call vec_push
        jmp .Lcr_line
.Lcr_if:
        cmp dword ptr [r14 + N_AUX], 4  # (python's match of ('if', :cond, :if_true, :if_false))
        jne .Lcr_other
        mov rdi, [r14 + N_DATA + 8]
        mov rsi, r12
        call cm_subst
        mov [rsp + CR_COND], rax
        mov rax, [r14 + N_DATA + 16]
        mov [rsp + CR_TRUE], rax
        mov rax, [r14 + N_DATA + 24]
        mov [rsp + CR_FALSE], rax
        mov rdi, [rsp + CR_TRUE]
        call cm_reverts
        test eax, eax
        jz 2f
        # `if not check: revert`: past it, its form is the param's
        mov rdi, [r14 + N_DATA + 8]
        call cm_validated               # rax: cd, rdx: x (or rax 0)
        test rax, rax
        jz .Lcr_plain
        mov rdi, r12
        mov rsi, rdx
        mov rdx, rax
        call cm_known_add
        mov rdi, [rsp + CR_FALSE]
        mov rsi, rax
        call cm_rem
        mov [rsp + CR_FALSE], rax
        mov rdi, [rsp + CR_TRUE]
        mov rsi, r12
        call cm_rem
        mov [rsp + CR_TRUE], rax
        jmp .Lcr_if_done
2:      # `if cd == x: ... else: revert`
        mov rdi, [rsp + CR_FALSE]
        call cm_reverts
        test eax, eax
        jz .Lcr_plain
        mov rdi, [r14 + N_DATA + 8]
        OP_N_CHECK OP_EQ, 3, .Lcr_plain
        mov rax, [r14 + N_DATA + 8]
        mov rdi, [rax + N_DATA + 8]     # (cd, x) = (a, b)
        mov rsi, [rax + N_DATA + 16]
        mov [rsp + CR_CD], rdi
        mov [rsp + CR_X], rsi
        call cm_cd_and_clean
        test eax, eax
        jnz 3f
        mov rax, [r14 + N_DATA + 8]
        mov rdi, [rax + N_DATA + 16]    # (b, a)
        mov rsi, [rax + N_DATA + 8]
        mov [rsp + CR_CD], rdi
        mov [rsp + CR_X], rsi
        call cm_cd_and_clean
        test eax, eax
        jz .Lcr_plain
3:      mov rdi, r12
        mov rsi, [rsp + CR_X]
        mov rdx, [rsp + CR_CD]
        call cm_known_add
        mov rdi, [rsp + CR_TRUE]
        mov rsi, rax
        call cm_rem
        mov [rsp + CR_TRUE], rax
        mov rdi, [rsp + CR_FALSE]
        mov rsi, r12
        call cm_rem
        mov [rsp + CR_FALSE], rax
        jmp .Lcr_if_done
.Lcr_plain:
        mov rdi, [rsp + CR_TRUE]
        mov rsi, r12
        call cm_rem
        mov [rsp + CR_TRUE], rax
        mov rdi, [rsp + CR_FALSE]
        mov rsi, r12
        call cm_rem
        mov [rsp + CR_FALSE], rax
.Lcr_if_done:
        mov rdi, [rsp + CR_COND]
        mov rsi, [rsp + CR_TRUE]
        mov rdx, [rsp + CR_FALSE]
        call mk_if
        mov rdi, [rsp + CR_OUT]
        mov rsi, rax
        call vec_push
        jmp .Lcr_line
.Lcr_while:
        # _, cond, path, jd, setvars = line
        cmp dword ptr [r14 + N_AUX], 5
        jne .Lcr_unpack
        mov rdi, [r14 + N_DATA + 8]
        mov rsi, r12
        call cm_subst
        mov [rsp + CR_COND], rax
        mov rdi, [r14 + N_DATA + 16]
        mov rsi, r12
        call cm_rem
        mov [rsp + CR_TRUE], rax
        mov rdi, [r14 + N_DATA + 32]
        mov rsi, r12
        call cm_subst
        mov r8, rax
        LOADS rdi, WHILE
        mov rsi, [rsp + CR_COND]
        mov rdx, [rsp + CR_TRUE]
        mov rcx, [r14 + N_DATA + 24]
        call mk5
        mov rdi, [rsp + CR_OUT]
        mov rsi, rax
        call vec_push
        jmp .Lcr_line
.Lcr_done:
        mov rdi, [rsp + CR_OUT]
        call vec_to_list
        add rsp, 48
        LEAVE
.Lcr_unpack:
        mov edi, E_VALUE
        lea rsi, [rip + .Ls_unpack]
        call err_throw
ENDF cm_rem

# cm_known_add(known, key, value) -> known: {**known, key: value}
FUNC cm_known_add
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov edi, KN_SIZEOF
        call arena_alloc
        mov [rax + KN_NEXT], rbx
        mov [rax + KN_KEY], r12
        mov [rax + KN_VAL], r13
        LEAVE
ENDF cm_known_add

# cm_reverts(branch) -> eax: the branch only reverts - [('revert', None)]
# or [('invalid',)]
FUNC cm_reverts
        ENTER
        mov rbx, rdi
        call is_seq
        test eax, eax
        jz .Lcrv_type
        cmp dword ptr [rbx + N_AUX], 1
        jne 9f
        mov rbx, [rbx + N_DATA]
        mov rdi, rbx
        OP_N_CHECK OP_INVALID, 1, 1f
        jmp 8f
1:      mov rdi, rbx
        OP_N_CHECK OP_REVERT, 2, 9f
        mov rdi, [rbx + N_DATA + 8]
        call is_none
        LEAVE
8:      mov eax, 1
        LEAVE
9:      xor eax, eax
        LEAVE
.Lcrv_type:
        mov edi, E_TYPE
        lea rsi, [rip + .Ls_no_len]
        call err_throw
ENDF cm_reverts

        .section .rodata
.Ls_no_len: .asciz "TypeError: a branch that has no len()"
        .text

# cm_cd_and_clean(cd, x) -> eax: opcode(cd) == "cd" and x is cd in one
# of its clean forms (cm_clean_form)
FUNC cm_cd_and_clean
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call opcode_of
        cmp eax, OP_CD
        jne 9f
        mov rdi, r12
        mov rsi, rbx
        call cm_clean_form
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF cm_cd_and_clean

# cm_clean_form(x, cd) -> eax: cleanup_masks' clean_form - x is cd as a
# value of a type: ('mask_shl', _, _, 0, cd) (its lowest bits, or its
# highest ones), ('bool', cd), ('signextend', _, cd)
FUNC cm_clean_form
        ENTER
        mov rbx, rdi
        mov r12, rsi
        OP_N_CHECK OP_MASK_SHL, 5, 1f
        cmp [rbx + N_DATA + 32], r12
        jne 9f
        mov rdi, [rbx + N_DATA + 24]
        mov esi, 1
        call py_equal
        LEAVE
1:      mov rdi, rbx
        OP_N_CHECK OP_BOOL, 2, 2f
        cmp [rbx + N_DATA + 8], r12
        jne 9f
        jmp 8f
2:      mov rdi, rbx
        OP_N_CHECK OP_SIGNEXTEND, 3, 9f
        cmp [rbx + N_DATA + 16], r12
        jne 9f
8:      mov eax, 1
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF cm_clean_form

# cm_validated(cond) -> rax: cd, rdx: x - cleanup_masks' validated: where
# cond holds, the if's branch reverts unless cd == x - or rax 0 (None)
FUNC cm_validated
        ENTER
        sub rsp, 16
        mov rbx, rdi
        # ('iszero', ('eq', a, b)), of cd and its clean form
        OP_N_CHECK OP_ISZERO, 2, 3f
        mov r12, [rbx + N_DATA + 8]
        mov rdi, r12
        OP_N_CHECK OP_EQ, 3, 3f
        mov rdi, [r12 + N_DATA + 8]
        mov rsi, [r12 + N_DATA + 16]
        call cm_cd_and_clean
        test eax, eax
        jz 1f
        mov rax, [r12 + N_DATA + 8]
        mov rdx, [r12 + N_DATA + 16]
        jmp 8f
1:      mov rdi, [r12 + N_DATA + 16]
        mov rsi, [r12 + N_DATA + 8]
        call cm_cd_and_clean
        test eax, eax
        jz 3f
        mov rax, [r12 + N_DATA + 16]
        mov rdx, [r12 + N_DATA + 8]
        jmp 8f
3:      # ('mask_shl', :int:size, :int:off, 0, cd) with size + off == 256 and
        # off > 0: the bits above the type are 0
        mov rdi, rbx
        OP_N_CHECK OP_MASK_SHL, 5, 9f
        mov rdi, [rbx + N_DATA + 8]
        call vr_number
        test rax, rax
        jz 9f
        mov [rsp], rax                  # size
        mov rdi, [rbx + N_DATA + 16]
        call vr_number
        test rax, rax
        jz 9f
        mov [rsp + 8], rax              # off
        mov rdi, [rbx + N_DATA + 24]
        mov esi, 1
        call py_equal
        test eax, eax
        jz 9f
        mov rdi, [rbx + N_DATA + 32]
        call opcode_of
        cmp eax, OP_CD
        jne 9f
        mov rdi, [rsp]
        mov rsi, [rsp + 8]
        call int_add
        cmp rax, (256 << 1) | 1
        jne 9f
        mov rdi, [rsp + 8]
        call int_sign
        cmp eax, 1
        jne 9f
        # (cd, ('mask_shl', off, 0, 0, cd)), off as the trace has it
        LOADS rdi, MASK_SHL
        mov rsi, [rbx + N_DATA + 16]
        mov edx, 1
        mov ecx, 1
        mov r8, [rbx + N_DATA + 32]
        call mk5
        mov rdx, rax
        mov rax, [rbx + N_DATA + 32]
8:      add rsp, 16
        LEAVE
9:      xor eax, eax
        add rsp, 16
        LEAVE
ENDF cm_validated

# cm_subst(exp, known) -> value: cleanup_masks' subst - what's known put
# in exp, innermost last (an expression known is replaced as it is); an
# element of bytes stays as wide as it's written (memloc.keep_width)
FUNC cm_subst
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        test rsi, rsi
        jz .Lcs_asis                    # (nothing known)
        IS_SEQ_RDI
        test eax, eax
        jz .Lcs_asis
        cmp dword ptr [rbx + N_KIND], K_TUPLE
        jne 2f
        # exp in known
        mov rax, r12
1:      cmp [rax + KN_KEY], rbx
        je 11f
        mov rax, [rax + KN_NEXT]
        test rax, rax
        jnz 1b
        jmp 2f
11:     mov rax, [rax + KN_VAL]
        add rsp, 16
        LEAVE
2:      # its elements
        mov edi, [rbx + N_AUX]
        test edi, edi
        jz .Lcs_asis
        shl rdi, 3
        call arena_alloc
        mov r13, rax
        xor r14d, r14d
3:      cmp r14d, [rbx + N_AUX]
        jae 4f
        mov rdi, [rbx + N_DATA + r14*8]
        mov rsi, r12
        call cm_subst
        mov [r13 + r14*8], rax
        inc r14d
        jmp 3b
4:      cmp dword ptr [rbx + N_KIND], K_TUPLE
        jne 6f
        # the elements of bytes that changed keep their width
        xor r14d, r14d
5:      cmp r14d, [rbx + N_AUX]
        jae 6f
        mov rax, [r13 + r14*8]
        cmp rax, [rbx + N_DATA + r14*8]
        je 51f
        mov rdi, rbx
        mov rsi, r14
        call is_byte_element
        test eax, eax
        jz 51f
        mov rdi, [rbx + N_DATA + r14*8]
        mov rsi, [r13 + r14*8]
        call keep_width
        mov [r13 + r14*8], rax
51:     inc r14d
        jmp 5b
6:      mov rdi, rbx
        mov rsi, r13
        call mk_seq_like
        add rsp, 16
        LEAVE
.Lcs_asis:
        mov rax, rbx
        add rsp, 16
        LEAVE
ENDF cm_subst

# --- the names of the params ---

# word_prefix_len(str) -> rax: python's len(re.match(r"\w*", s).group(0)) -
# the letters, digits and _ it starts with (a byte of a non-ASCII
# character is taken as a letter's: python's \w is unicode, and the names
# of the abis have none)
FUNC word_prefix_len
        mov ecx, [rdi + N_DATA]
        xor eax, eax
1:      cmp eax, ecx
        jae 9f
        movzx edx, byte ptr [rdi + N_DATA + 4 + rax]
        cmp edx, 0x80
        jae 2f
        cmp edx, '_'
        je 2f
        lea r8d, [rdx - '0']
        cmp r8d, 9
        jbe 2f
        or edx, 0x20
        sub edx, 'a'
        cmp edx, 25
        ja 9f
2:      inc eax
        jmp 1b
9:      ret
ENDF word_prefix_len

# param_word_name((idx, kind, name), arg) -> str: re.match(r"\w*",
# name).group(0) - what a param's name says it is (desc of desc.srcToken,
# amounts of amounts[2])
FUNC param_word_name
        ENTER
        mov rbx, [rdi + N_DATA + 16]
        mov rdi, rbx
        call is_str
        test eax, eax
        jz 9f
        mov rdi, rbx
        call word_prefix_len
        lea rdi, [rbx + N_DATA + 4]
        mov rsi, rax
        call str_new
        LEAVE
9:      mov edi, E_TYPE
        lea rsi, [rip + .Ls_not_text]
        call err_throw
ENDF param_word_name

        .section .rodata
.Ls_not_text: .asciz "TypeError: expected string or bytes-like object"
        .text

# fn_rename_params(fn, storage_names): Function.rename_params - the params
# (of the abi) that have the name of a storage variable (`owner`, which
# would read as both), or of something the EVM gives (`caller`), have it
# after a _ (`_owner`), and then __ while that's taken too. storage_names:
# a list of str, or 0. The abi's inputs are renamed (set_func_params),
# the inferred params' names with them (desc.srcToken of desc too), and
# the names of the function made again (not its abi_name: types only).
FUNC fn_rename_params
        ENTER
        sub rsp, 48
        .set RP_NAMES, 0                # vec: the names taken by the params
        .set RP_RENAMES, 8              # vec: old, new, old, new... (a dict)
        .set RP_STORAGE, 16
        .set RP_NEW, 24
        .set RP_OUT, 32
        mov rbx, rdi
        mov [rsp + RP_STORAGE], rsi
        mov r12, [rbx + FN_INPUTS]      # get_func_params
        test r12, r12
        jz .Lrp_ret
        cmp dword ptr [r12 + N_AUX], 0
        je .Lrp_ret
        # names = {p["name"] for p in inputs}
        call vec_new
        mov [rsp + RP_NAMES], rax
        xor r13d, r13d
1:      cmp r13d, [r12 + N_AUX]
        jae 2f
        mov rax, [r12 + N_DATA + r13*8]
        mov rdi, [rsp + RP_NAMES]
        mov rsi, [rax + N_DATA + 8]
        call vec_push
        inc r13d
        jmp 1b
2:      call vec_new
        mov [rsp + RP_RENAMES], rax
        xor r13d, r13d
.Lrp_input:
        cmp r13d, [r12 + N_AUX]
        jae .Lrp_renamed
        mov rax, [r12 + N_DATA + r13*8]
        mov r14, [rax + N_DATA + 8]     # p["name"]
        inc r13d
        mov rdi, r14
        mov rsi, [rsp + RP_STORAGE]
        call rp_taken
        test eax, eax
        jz .Lrp_input
        mov rdi, [rsp + RP_RENAMES]     # (once for a name two of them have)
        mov rsi, r14
        call rp_find
        test rax, rax
        jnz .Lrp_input
        # new = "_" + name, then "_" + new while it's taken or a param's
        mov rdi, r14
        call rp_underscore
        mov [rsp + RP_NEW], rax
3:      mov rdi, [rsp + RP_NEW]
        mov rsi, [rsp + RP_STORAGE]
        call rp_taken
        test eax, eax
        jnz 31f
        mov rdi, [rsp + RP_NAMES]
        mov rsi, [rsp + RP_NEW]
        call rp_in_vec
        test eax, eax
        jz 4f
31:     mov rdi, [rsp + RP_NEW]
        call rp_underscore
        mov [rsp + RP_NEW], rax
        jmp 3b
4:      # renames[name] = new
        mov rdi, [rsp + RP_RENAMES]
        mov rsi, r14
        call vec_push
        mov rdi, [rsp + RP_RENAMES]
        mov rsi, [rsp + RP_NEW]
        call vec_push
        mov rdi, [rsp + RP_NAMES]
        mov rsi, [rsp + RP_NEW]
        call vec_push
        jmp .Lrp_input
.Lrp_renamed:
        mov rax, [rsp + RP_RENAMES]
        cmp qword ptr [rax + VEC_LEN], 0
        je .Lrp_ret
        # set_func_params: the inputs with their new names
        call vec_new
        mov [rsp + RP_OUT], rax
        xor r13d, r13d
5:      cmp r13d, [r12 + N_AUX]
        jae 6f
        mov r14, [r12 + N_DATA + r13*8]
        inc r13d
        mov rdi, [rsp + RP_RENAMES]
        mov rsi, [r14 + N_DATA + 8]
        call rp_find
        test rax, rax
        jz 51f
        mov rdi, r14
        mov rsi, [rax]                  # the new name
        mov edx, 1
        call rp_with_elem
        mov r14, rax
51:     mov rdi, [rsp + RP_OUT]
        mov rsi, r14
        call vec_push
        jmp 5b
6:      mov rdi, [rsp + RP_OUT]
        call vec_to_list
        mov [rbx + FN_INPUTS], rax
        mov rdi, [rbx + FN_ABI]
        mov rsi, rax
        mov edx, 1
        call rp_with_elem
        mov [rbx + FN_ABI], rax
        # the inferred params' names (desc of desc.srcToken, amounts of
        # amounts[2])
        call vec_new
        mov [rsp + RP_OUT], rax
        xor r13d, r13d
7:      mov rax, [rbx + FN_PARAMS]
        cmp r13d, [rax + N_AUX]
        jae 8f
        mov r14, [rax + N_DATA + r13*8] # (idx, kind, name)
        inc r13d
        mov rdi, [r14 + N_DATA + 16]
        mov rsi, [rsp + RP_RENAMES]
        call rp_renamed_name
        cmp rax, [r14 + N_DATA + 16]
        je 71f
        mov rdx, rax
        mov rdi, [r14 + N_DATA]
        mov rsi, [r14 + N_DATA + 8]
        call mk3
        mov r14, rax
71:     mov rdi, [rsp + RP_OUT]
        mov rsi, r14
        call vec_push
        jmp 7b
8:      mov rdi, [rsp + RP_OUT]
        call vec_to_list
        mov [rbx + FN_PARAMS], rax
        mov rdi, [rbx + FN_ABI]
        xor esi, esi
        call abi_func_name
        mov [rbx + FN_NAME], rax
        mov rdi, [rbx + FN_ABI]
        mov esi, PF_COLOR
        call abi_func_name
        mov [rbx + FN_COLOR_NAME], rax
.Lrp_ret:
        add rsp, 48
        LEAVE
ENDF fn_rename_params

# rp_taken(name, storage_names) -> eax: rename_params' `name in taken` -
# a builtin name (prettify's BUILTIN_NAMES), a storage variable's
FUNC rp_taken
        ENTER
        mov rbx, rdi
        mov r12, rsi
        lea rdi, [rbx + N_DATA + 4]
        call is_builtin_name_c
        test eax, eax
        jnz 1f
        mov rdi, r12
        lea rsi, [rbx + N_DATA + 4]
        call str_in_list_c
1:      LEAVE
ENDF rp_taken

# rp_underscore(name) -> str: "_" + name (interned: it goes into the
# expressions, ('param', name))
FUNC rp_underscore
        ENTER
        mov rbx, rdi
        call sb_new
        mov r12, rax
        mov rdi, rax
        mov esi, '_'
        call sb_append_char
        mov rdi, r12
        mov rsi, rbx
        call sb_append_str
        mov rdi, r12
        call sb_finish_intern
        LEAVE
ENDF rp_underscore

# rp_in_vec(vec, name) -> eax: a str of the vec has the text of name
FUNC rp_in_vec
        ENTER
        mov rbx, rdi
        mov r12, rsi
        xor r13d, r13d
1:      cmp r13, [rbx + VEC_LEN]
        jae 2f
        mov rax, [rbx + VEC_DATA]
        mov rdi, [rax + r13*8]
        mov rsi, r12
        call str_values_equal
        test eax, eax
        jnz 3f
        inc r13
        jmp 1b
2:      xor eax, eax
3:      LEAVE
ENDF rp_in_vec

# rp_find(renames, name) -> rax: where renames[name] is in the vec (old,
# new, old, new...) - a pointer to its new name -, or 0
FUNC rp_find
        ENTER
        mov rbx, rdi
        mov r12, rsi
        xor r13d, r13d
1:      cmp r13, [rbx + VEC_LEN]
        jae 2f
        mov rax, [rbx + VEC_DATA]
        mov rdi, [rax + r13*8]
        mov rsi, r12
        call str_values_equal
        test eax, eax
        jnz 3f
        add r13, 2
        jmp 1b
2:      xor eax, eax
        LEAVE
3:      mov rax, [rbx + VEC_DATA]
        lea rax, [rax + r13*8 + 8]
        LEAVE
ENDF rp_find

# rp_with_elem(seq, value, i) -> the sequence with its element i made
# value (python's dict(p, name=new) of an input, an abi with its inputs)
FUNC rp_with_elem
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13d, edx
        mov edi, [rbx + N_AUX]
        shl edi, 3
        call arena_alloc
        xor edx, edx
1:      cmp edx, [rbx + N_AUX]
        jae 2f
        mov rcx, [rbx + N_DATA + rdx*8]
        mov [rax + rdx*8], rcx
        inc edx
        jmp 1b
2:      mov [rax + r13*8], r12
        mov rdi, rbx
        mov rsi, rax
        call mk_seq_like
        LEAVE
ENDF rp_with_elem

# rp_renamed_name(name, renames) -> str: rename_params' renamed - the
# name with its word (re.match(r"\w*")) renamed, if it is; else itself
FUNC rp_renamed_name
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call is_str
        test eax, eax
        jz 9f
        mov rdi, rbx
        call word_prefix_len
        mov r13, rax
        lea rdi, [rbx + N_DATA + 4]
        mov rsi, rax
        call str_new                    # base
        mov rdi, r12
        mov rsi, rax
        call rp_find
        test rax, rax
        jz 1f
        mov r14, [rax]                  # renames[base]
        call sb_new
        mov r12, rax
        mov rdi, rax
        mov rsi, r14
        call sb_append_str
        mov rdi, r12
        lea rsi, [rbx + N_DATA + 4 + r13]
        mov edx, [rbx + N_DATA]
        sub edx, r13d
        call sb_append
        mov rdi, r12
        call sb_finish_intern
        LEAVE
1:      mov rax, rbx
        LEAVE
9:      mov edi, E_TYPE
        lea rsi, [rip + .Ls_not_text]
        call err_throw
ENDF rp_renamed_name

# --- the analysis ---

# trace_text(trace) -> sb: python's str(trace), for the searches below,
# in a builder (sb_free it): its text isn't made a string node - one
# would hash and scan all of it, which took more than printing it
FUNC trace_text
        ENTER
        mov rbx, rdi
        call sb_new
        mov r12, rax
        mov rdi, rax
        mov rsi, rbx
        call value_print
        mov rax, r12
        LEAVE
ENDF trace_text

# text_mentions_any(sb, table) -> eax: one of the C strings of the table
# (0-terminated) occurs in the builder's text (no NUL in it: value_print
# escapes them)
FUNC text_mentions_any
        ENTER
        mov rbx, [rdi + SB_BUF]
        mov r12, rsi
1:      mov rsi, [r12]
        test rsi, rsi
        jz 2f
        mov rdi, rbx
        call strstr@PLT
        test rax, rax
        jnz 3f
        add r12, 8
        jmp 1b
2:      xor eax, eax
        LEAVE
3:      mov eax, 1
        LEAVE
ENDF text_mentions_any

# pred_return(exp) -> eax
FUNC pred_return
        ENTER
        call opcode_of
        cmp eax, OP_RETURN
        sete al
        movzx eax, al
        LEAVE
ENDF pred_return

# is_revert_none_or_invalid(line) -> eax: ('revert', None) - a revert
# with no data - or an invalid
FUNC is_revert_none_or_invalid
        ENTER
        mov rbx, rdi
        OP_N_CHECK OP_REVERT, 2, 1f
        mov rdi, [rbx + N_DATA + 8]
        call is_none
        test eax, eax
        jnz 2f
1:      mov rdi, rbx
        call opcode_of
        cmp eax, OP_INVALID
        sete al
        movzx eax, al
2:      LEAVE
ENDF is_revert_none_or_invalid

# fn_analyse(fn): Function.analyse - the returns, payable, read_only, the
# constant, the getter
FUNC fn_analyse
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 48
        .set FA_TEXT, MATCH_BINDINGS_SIZE
        .set FA_T1, MATCH_BINDINGS_SIZE + 8
        .set FA_T2, MATCH_BINDINGS_SIZE + 16
        .set FA_TERMS, MATCH_BINDINGS_SIZE + 24
        .set FA_K, MATCH_BINDINGS_SIZE + 32
        mov rbx, rdi
        mov rax, [rbx + FN_TRACE]
        cmp dword ptr [rax + N_AUX], 0
        je .Lfa_assert_trace
        # the returns
        call vec_new
        mov r12, rax
        mov rdi, [rbx + FN_TRACE]
        lea rsi, [rip + pred_return]
        mov rdx, r12
        call walk_collect
        mov rdi, r12
        call vec_to_list
        mov [rbx + FN_RETURNS], rax
        # the check that there's no value, after what has no effect (Vyper
        # writes some constants to memory first)
        mov r12, [rbx + FN_TRACE]
        xor r13d, r13d                  # k
1:      mov eax, [r12 + N_AUX]
        dec eax
        cmp r13d, eax
        jae 2f
        mov rdi, [r12 + N_DATA + r13*8]
        call opcode_of
        cmp eax, OP_SETMEM
        je 11f
        cmp eax, OP_SETVAR
        jne 2f
11:     inc r13d
        jmp 1b
2:      mov [rsp + FA_K], r13
        mov r14, [r12 + N_DATA + r13*8] # first
        # a function is printed as payable unless the check is there: its
        # body is what it does whatever ether it's sent (one that always
        # reverts does it with the ether too - with the data it reverts with)
        mov qword ptr [rbx + FN_PAYABLE], 1
        mov rdi, r14
        call opcode_of
        cmp eax, OP_IF
        jne .Lfa_read_only
        cmp dword ptr [r14 + N_AUX], 2
        jb .Lfa_index
        mov rdi, [r14 + N_DATA + 8]
        call simplify_bool
        mov r12, rax                    # cond
        cmp dword ptr [r14 + N_AUX], 4
        jb .Lfa_index
        mov rax, [r14 + N_DATA + 16]
        mov [rsp + FA_T1], rax          # fails
        mov rax, [r14 + N_DATA + 24]
        mov [rsp + FA_T2], rax          # rest
        LOADS rdi, ISZERO
        LOADS rsi, CALLVALUE
        call mk2
        cmp r12, rax
        jne 3f
        LOADS r12, CALLVALUE
        mov rax, [rsp + FA_T1]
        mov rcx, [rsp + FA_T2]
        mov [rsp + FA_T1], rcx
        mov [rsp + FA_T2], rax
3:      # (Vyper 0.3.10 checks the size of the calldata with it, `if
        # call.value or calldata.size < 36: revert`: that check stays)
        call vec_new
        mov r13, rax                    # disjuncts(cond)
        mov rdi, r12
        mov rsi, rax
        call fn_disjuncts
        call vec_new
        mov [rsp + FA_TERMS], rax       # the others
        LOADS r12, CALLVALUE
        xor ecx, ecx
4:      cmp rcx, [r13 + VEC_LEN]
        jae 5f
        mov rax, [r13 + VEC_DATA]
        mov rsi, [rax + rcx*8]
        inc rcx
        cmp rsi, r12
        je 4b
        push rcx
        push rcx
        mov rdi, [rsp + 16 + FA_TERMS]
        call vec_push
        pop rcx
        pop rcx
        jmp 4b
5:      mov rax, [rsp + FA_TERMS]
        mov rax, [rax + VEC_LEN]
        cmp rax, [r13 + VEC_LEN]
        jae .Lfa_read_only
        mov rdi, [rsp + FA_T1]          # fails: not empty...
        call py_truthy
        test eax, eax
        jz .Lfa_read_only
        mov rdi, [rsp + FA_T1]
        call is_seq
        test eax, eax
        jz .Lfa_type
        mov rax, [rsp + FA_T1]
        mov rdi, [rax + N_DATA]         # ...its first line a revert with no data, or an invalid
        call is_revert_none_or_invalid
        test eax, eax
        jz .Lfa_read_only
        # what fails is the check: the rest is the function (the other
        # disjuncts their own check, before it)
        mov r13, [rsp + FA_TERMS]
        cmp qword ptr [r13 + VEC_LEN], 0
        je 7f
        mov rax, [r13 + VEC_DATA]
        mov r12, [rax]                  # other = others[0]
        mov r14d, 1
6:      cmp r14, [r13 + VEC_LEN]
        jae 61f
        mov rax, [r13 + VEC_DATA]
        mov rdx, [rax + r14*8]
        LOADS rdi, OR
        mov rsi, r12
        call mk3
        mov r12, rax
        inc r14
        jmp 6b
61:     mov rdi, r12
        mov rsi, [rsp + FA_T1]
        mov rdx, [rsp + FA_T2]
        call mk_if
        mov rdi, rax
        call mk_list1
        mov [rsp + FA_T2], rax
7:      # self.trace[:k] + rest
        mov rax, [rbx + FN_TRACE]
        mov rdi, [rsp + FA_K]
        lea rsi, [rax + N_DATA]
        call mk_list
        mov rdi, rax
        mov rsi, [rsp + FA_T2]
        call list_concat
        mov [rbx + FN_TRACE], rax
        mov qword ptr [rbx + FN_PAYABLE], 0
        mov rax, [rsp + FA_T1]
        mov rax, [rax + N_DATA]         # opcode(fails[0])
        mov rax, [rax + N_DATA]
        mov [rbx + FN_VALUE_FAILS], rax
.Lfa_read_only:
        # read-only: no store, call, create... in str(trace)
        mov rdi, [rbx + FN_TRACE]
        call trace_text
        mov [rsp + FA_TEXT], rax
        mov rdi, rax
        lea rsi, [rip + not_read_only]
        call text_mentions_any
        mov r12d, eax
        mov rdi, [rsp + FA_TEXT]        # (str(trace) done with)
        call sb_free
        xor r12d, 1
        mov [rbx + FN_READ_ONLY], r12
        # a constant: read-only, one return, nothing that varies read (and
        # sent ether, a const reverts with no data: see OUTPUT.md)
        mov qword ptr [rbx + FN_CONST], 0
        test r12, r12
        jz .Lfa_getter
        mov rax, [rbx + FN_RETURNS]
        cmp dword ptr [rax + N_AUX], 1
        jne .Lfa_getter
        mov rdi, [rbx + FN_TRACE]
        call fn_varies
        test eax, eax
        jnz .Lfa_getter
        LOADS rax, REVERT
        cmp [rbx + FN_VALUE_FAILS], rax
        jne .Lfa_getter
        mov rax, [rbx + FN_RETURNS]
        mov r12, [rax + N_DATA]
        # (a 3-element return's data, mask_shl, int: one after the other)
        mov esi, OP_DATA
        call .Lfa_const_part
        mov esi, OP_MASK_SHL
        call .Lfa_const_part
        cmp dword ptr [r12 + N_AUX], 3
        jne 21f
        mov rdi, [r12 + N_DATA + 16]
        call is_int
        test eax, eax
        jz 21f
        mov r12, [r12 + N_DATA + 16]
21:     mov [rbx + FN_CONST], r12
.Lfa_getter:
        mov qword ptr [rbx + FN_GETTER], 0
        cmp qword ptr [rbx + FN_CONST], 0
        jne .Lfa_done
        cmp qword ptr [rbx + FN_READ_ONLY], 0
        je .Lfa_done
        mov rax, [rbx + FN_RETURNS]
        cmp dword ptr [rax + N_AUX], 1
        jne .Lfa_done
        mov rax, [rax + N_DATA]
        cmp dword ptr [rax + N_AUX], 2
        jb .Lfa_index
        mov rdi, [rax + N_DATA + 8]
        call fn_word
        mov r12, rax                    # ret
        PAT rsi, "('bool', ('storage', 'Any', 'Any', ':loc'))"
        mov rdi, r12
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 3f
        # we have to be careful when using this for naming purposes,
        # because sometimes the storage can refer to array length
        mov [rbx + FN_GETTER], r12
        jmp .Lfa_done
3:      mov rdi, r12
        call opcode_of
        mov r13d, eax
        cmp eax, OP_MASK_SHL
        jne 4f
        cmp dword ptr [r12 + N_AUX], 5
        jb .Lfa_index
        mov rdi, [r12 + N_DATA + 32]
        call opcode_of
        cmp eax, OP_STORAGE
        jne 41f
        mov rax, [r12 + N_DATA + 32]
        mov [rbx + FN_GETTER], rax
        jmp .Lfa_done
41:     mov r13d, OP_MASK_SHL
4:      cmp r13d, OP_STORAGE
        jne 5f
        mov [rbx + FN_GETTER], r12
        jmp .Lfa_done
5:      cmp r13d, OP_DATA
        jne .Lfa_done
        # for structs, we check if all the parts of the struct are storage
        # from the same location: then the location
        cmp dword ptr [r12 + N_AUX], 2
        jb .Lfa_index
        call vec_new
        mov [rsp + FA_TERMS], rax       # the words of the data
        mov r14d, 1
51:     cmp r14d, [r12 + N_AUX]
        jae 52f
        mov rdi, [r12 + N_DATA + r14*8]
        call fn_word
        mov rdi, [rsp + FA_TERMS]
        mov rsi, rax
        call vec_push
        inc r14d
        jmp 51b
52:     mov r12, [rsp + FA_TERMS]
        mov rax, [r12 + VEC_DATA]
        mov r13, [rax]                  # t0 (0xFAFfea71A6da719D6CAfCF7F52eA04Eb643F6De2 - documents)
        PAT rsi, "('storage', 256, 0, ':loc')"
        mov rdi, r13
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 7f
        B rax, 0
        mov [rsp + FA_T1], rax          # loc
        mov r14d, 1
6:      cmp r14, [r12 + VEC_LEN]
        jae 61f
        mov rax, [r12 + VEC_DATA]
        mov rdi, [rax + r14*8]
        mov rsi, [rsp + FA_T1]
        call .Lfa_is_storage_add_loc
        test eax, eax
        jz 7f
        inc r14
        jmp 6b
61:     mov [rbx + FN_GETTER], r13
7:      cmp qword ptr [rbx + FN_GETTER], 0
        jne .Lfa_done
        # kitties getKitten - with more cases this and the above could be
        # uniformed: every term hashing the same small location
        mov qword ptr [rsp + FA_T2], -1 # prev_loc = -1
        xor r14d, r14d
8:      cmp r14, [r12 + VEC_LEN]
        jae 9f
        mov rax, [r12 + VEC_DATA]
        mov rdi, [rax + r14*8]
        lea rsi, [rip + small_sha3_loc]
        call walk_find
        test rax, rax
        jz .Lfa_done                    # not loc: None...
        cmp rax, 1                      # ...or 0
        je .Lfa_done
        mov r13, rax
        mov rdi, [rsp + FA_T2]
        mov rsi, -1
        call values_equal
        test eax, eax
        jnz 81f
        mov rdi, [rsp + FA_T2]
        mov rsi, r13
        call values_equal
        test eax, eax
        jz .Lfa_done
81:     mov [rsp + FA_T2], r13
        inc r14
        jmp 8b
9:      mov rsi, [rsp + FA_T2]          # (the last loc)
        LOADS rdi, LOC
        call mk2
        mov rsi, rax
        LOADS rdi, STRUCT
        call mk2
        mov [rbx + FN_GETTER], rax
.Lfa_done:
        mov rdi, rbx                    # (--explain: explain_text, explain.s)
        call explain_traits
        add rsp, MATCH_BINDINGS_SIZE + 48
        LEAVE
# locals
# r12 = r12[2] when r12 has 3 elements and r12[2] has the opcode esi
.Lfa_const_part:
        cmp dword ptr [r12 + N_AUX], 3
        jne 1f
        sub rsp, 24
        mov [rsp], esi
        mov rdi, [r12 + N_DATA + 16]
        call opcode_of
        cmp eax, [rsp]
        jne 2f
        mov r12, [r12 + N_DATA + 16]
2:      add rsp, 24
1:      ret
# eax: rdi ~ ('storage', 256, 0, ('add', Any, rsi))
.Lfa_is_storage_add_loc:
        sub rsp, 24
        mov [rsp], rdi
        mov [rsp + 8], rsi
        call opcode_of
        cmp eax, OP_STORAGE
        jne 1f
        mov rdi, [rsp]
        cmp dword ptr [rdi + N_AUX], 4
        jne 1f
        cmp qword ptr [rdi + N_DATA + 8], 513
        jne 1f
        cmp qword ptr [rdi + N_DATA + 16], 1
        jne 1f
        mov rdi, [rdi + N_DATA + 24]
        mov [rsp + 16], rdi
        call opcode_of
        cmp eax, OP_ADD
        jne 1f
        mov rdi, [rsp + 16]
        cmp dword ptr [rdi + N_AUX], 3
        jne 1f
        mov rdi, [rdi + N_DATA + 16]
        mov rsi, [rsp + 8]
        call py_equal
        add rsp, 24
        ret
1:      xor eax, eax
        add rsp, 24
        ret
.Lfa_assert_trace:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_trace]
        call err_throw
.Lfa_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_index]
        call err_throw
.Lfa_type:
        mov edi, E_TYPE
        lea rsi, [rip + .Ls_not_subscriptable]
        call err_throw
ENDF fn_analyse

        .section .rodata
.Ls_not_subscriptable: .asciz "TypeError: function: a branch that isn't a sequence"
        .text

# small_sha3_loc(x) -> rax: the location of ('sha3', ('data', _, l)) or
# ('sha3', l, ...) when l is an int below 1000 (getKitten's l2: the loc
# itself, so 0 gives 0 - python's `not loc` treats it the same)
FUNC small_sha3_loc
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        PAT rsi, "('sha3', ('data', 'Any', ':l'))"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        mov rdi, [rsp]
        call .Lss_small
        test rax, rax
        jnz 2f
1:      mov rdi, rbx
        call opcode_of
        cmp eax, OP_SHA3
        jne 3f
        cmp dword ptr [rbx + N_AUX], 2
        jb .Lss_index
        mov rdi, [rbx + N_DATA + 8]
        call .Lss_small
        test rax, rax
        jnz 2f
3:      xor eax, eax
2:      add rsp, MATCH_BINDINGS_SIZE
        LEAVE
.Lss_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_index]
        call err_throw
# the value if an int below 1000, else 0
.Lss_small:
        sub rsp, 24
        mov [rsp], rdi
        call is_int
        test eax, eax
        jz 1f
        mov rdi, [rsp]
        mov rsi, 1000
        TAG rsi
        call int_cmp
        cmp eax, -1
        jne 1f
        mov rax, [rsp]
        add rsp, 24
        ret
1:      xor eax, eax
        add rsp, 24
        ret
ENDF small_sha3_loc

# --- the function ---

# function_new(hash, trace, abi) -> fn: Function(hash, trace)
FUNC function_new
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov edi, FN_SIZEOF
        call arena_alloc
        mov r14, rax
        mov [r14 + FN_HASH], rbx
        mov [r14 + FN_ABI], r13
        mov rax, [r13 + N_DATA + 8]
        mov [r14 + FN_INPUTS], rax
        mov rdi, r13
        xor esi, esi
        call abi_func_name
        mov [r14 + FN_NAME], rax
        mov rdi, r13
        mov esi, PF_COLOR
        call abi_func_name
        mov [r14 + FN_COLOR_NAME], rax
        mov rdi, r13
        call abi_name
        mov [r14 + FN_ABI_NAME], rax
        mov qword ptr [r14 + FN_VALUE_FAILS], 0
        mov [r14 + FN_TRACE], r12
        mov [r14 + FN_ORIG_TRACE], r12
        mov rdi, r14
        call make_params
        mov [r14 + FN_PARAMS], rax
        mov rdi, [r14 + FN_NAME]
        lea rsi, [rip + .Ls_unknown]
        call str_contains_c
        test eax, eax
        jz 1f
        mov rdi, r14
        call make_names
1:      mov rdi, r14
        mov rsi, [r14 + FN_TRACE]
        call cleanup_masks
        mov [r14 + FN_TRACE], rax
        mov qword ptr [r14 + FN_AST], 0
        mov rdi, r14
        call fn_analyse
        xor eax, eax
        cmp qword ptr [r14 + FN_CONST], 0
        jne 2f
        cmp qword ptr [r14 + FN_GETTER], 0
        jne 2f
        mov eax, 1
2:      mov [r14 + FN_IS_REGULAR], rax
        mov rax, r14
        LEAVE
ENDF function_new

# --- the text ---

# fn_print_lines(fn) -> list of str: Function._print
FUNC fn_print_lines
        ENTER
        sub rsp, 32
        mov rbx, rdi
        mov r12, [r15 + CTX_FUNC]
        mov [rsp], r12                  # (restored after)
        mov [r15 + CTX_FUNC], rbx
        # the parameters for get_param_name, when the abi had none
        cmp qword ptr [rbx + FN_INPUTS], 0
        jne 1f
        mov rdi, [rbx + FN_PARAMS]
        lea rsi, [rip + param_kind_name]
        call map_seq
        mov [rbx + FN_INPUTS], rax
1:      # set_names(params=...): the variables of its loops have other names
        # than its params (desc of desc.srcToken, amounts of amounts[2])
        mov rdi, [rbx + FN_PARAMS]
        lea rsi, [rip + param_word_name]
        call map_seq
        xor edi, edi
        mov rsi, rax
        call set_names
        cmp qword ptr [rbx + FN_CONST], 0
        je .Lfp_def
        # "const name = value"
        mov r12, [rbx + FN_CONST]
        mov rdi, r12
        call opcode_of
        cmp eax, OP_RETURN
        jne 2f
        cmp dword ptr [r12 + N_AUX], 2
        jb .Lfp_index
        mov r12, [r12 + N_DATA + 8]
2:      call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + C_HEADER]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + .Ls_const_]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        # color_name.split("()")[0]
        mov rax, [rbx + FN_COLOR_NAME]
        lea rdi, [rax + N_DATA + 4]
        lea rsi, [rip + .Ls_empty_paren]
        call strstr@PLT
        mov rdx, [rbx + FN_COLOR_NAME]
        lea rsi, [rdx + N_DATA + 4]
        test rax, rax
        jz 3f
        mov rdx, rax
        sub rdx, rsi
        jmp 4f
3:      mov edx, [rdx + N_DATA]
4:      mov rdi, r13
        call sb_append
        mov rdi, r13
        lea rsi, [rip + .Ls_eq_sp]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + C_BOLD]
        call sb_append_c
        # what the function returns: its data, as a return's
        mov rdi, r12
        mov esi, PF_ABI_TEXT
        call pretty_memory
        lea rdi, [rip + .Ls_comma_sp]
        mov rsi, rax
        call str_join
        mov rdi, r13
        mov rsi, rax
        call sb_append_str
        mov rdi, r13
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        mov rdi, r13
        call sb_finish
        mov rdi, rax
        call mk_list1
        jmp .Lfp_ret
.Lfp_def:
        # "def name[ payable]: # comment"
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_def_]
        lea rdx, [rip + C_HEADER]
        mov ecx, PF_COLOR
        call sb_append_col_c
        mov rdi, r13
        mov rsi, [rbx + FN_COLOR_NAME]
        call sb_append_str
        cmp qword ptr [rbx + FN_PAYABLE], 0
        je 5f
        mov rdi, r13
        lea rsi, [rip + .Ls_payable]
        lea rdx, [rip + C_HEADER]
        mov ecx, PF_COLOR
        call sb_append_col_c
5:      mov rdi, r13
        lea rsi, [rip + .Ls_colon_sp]
        call sb_append_c
        # the comment: sent ether, it reverts with no data - or, the check
        # of old compilers, it runs an invalid opcode (see OUTPUT.md)
        call sb_new
        mov r14, rax
        cmp qword ptr [rbx + FN_PAYABLE], 0
        jne 6f
        mov rdi, r14
        lea rsi, [rip + .Ls_not_payable]
        call sb_append_c
        LOADS rax, INVALID
        cmp [rbx + FN_VALUE_FAILS], rax
        jne 6f
        mov rdi, r14
        lea rsi, [rip + .Ls_invalid_note]
        call sb_append_c
6:      mov rdi, [rbx + FN_NAME]
        lea rsi, [rip + .Ls_fallback_q]
        call str_eq_c
        test eax, eax
        jz 7f
        cmp qword ptr [rbx + FN_PAYABLE], 0
        je 61f
        mov rdi, r14
        call sb_reset
        mov rdi, r14
        lea rsi, [rip + .Ls_default]
        call sb_append_c
        jmp 7f
61:     mov rdi, r14
        lea rsi, [rip + .Ls_and_default]
        call sb_append_c
7:      mov rdi, r14
        call sb_finish
        mov rdi, r13
        mov rsi, rax
        lea rdx, [rip + C_GRAY]
        mov ecx, PF_COLOR
        call sb_append_col              # (nothing for no comment)
8:      mov rdi, r13
        call sb_finish
        mov rdi, rax
        call mk_list1
        mov r14, rax                    # the header line
        mov rdi, [rbx + FN_AST]
        test rdi, rdi
        jnz 9f
        mov rdi, [rbx + FN_TRACE]
9:      mov esi, 2
        call pprint_logic
        cmp dword ptr [rax + N_AUX], 0
        jne 10f
        lea rdi, [rip + .Ls_stop_line]
        call str_new_c
        mov rdi, rax
        call mk_list1
10:     mov rdi, r14
        mov rsi, rax
        call list_concat
.Lfp_ret:
        mov rcx, [rsp]
        mov [r15 + CTX_FUNC], rcx
        add rsp, 32
        LEAVE
.Lfp_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_index]
        call err_throw
ENDF fn_print_lines

# param_kind_name((idx, kind, name), arg) -> (kind, name)
FUNC param_kind_name
        mov rsi, [rdi + N_DATA + 16]
        mov rdi, [rdi + N_DATA + 8]
        jmp mk2
ENDF param_kind_name

# fn_print(fn) -> str: the lines joined with newlines (kept on the
# function, as python's priority prints it repeatedly)
FUNC fn_print
        ENTER
        mov rbx, rdi
        mov rax, [rbx + FN_PRINT]
        test rax, rax
        jnz 1f
        call fn_print_lines
        lea rdi, [rip + .Ls_newline]
        mov rsi, rax
        call str_join
        mov [rbx + FN_PRINT], rax
1:      LEAVE
ENDF fn_print

# fn_priority(fn) -> rax: the sort key of the functions in the output -
# the self-destructing ones first, then by the length of their text
FUNC fn_priority
        ENTER
        mov rbx, rdi
        mov rax, [rbx + FN_PRIORITY]
        test rax, rax
        jz 3f
        sub rax, 2
        LEAVE
3:      cmp qword ptr [rbx + FN_TRACE], 0
        je 1f
        mov rdi, [rbx + FN_TRACE]       # "selfdestruct" in str(self.trace)
        lea rsi, [rip + .Ls_selfdestruct]
        call mentions_c
        test eax, eax
        jnz 2f
        mov rdi, rbx
        call fn_print
        mov rdi, rax
        call str_charlen
        jmp 4f
1:      xor eax, eax
        jmp 4f
2:      mov rax, -1
4:      lea rcx, [rax + 2]
        mov [rbx + FN_PRIORITY], rcx
        LEAVE
ENDF fn_priority

# --- the functions printed on threads ---

        # an iteration of print_many
        .set PT_TEXT, 0                 # the text (malloc'd), or 0 when it failed
        .set PT_LEN, 8
        .set PT_PRIORITY, 16            # FN_PRIORITY's value
        .set PT_SIZEOF, 24
        # print_many's shared state
        .set PM_FUNCS, 0                # the vec of functions
        .set PM_TASKS, 8
        .set PM_LIMIT, 16
        .set PM_LOADER, 24
        .set PM_NAMES, 32               # the main context's CTX_NAMES (set_names')
        .set PM_SIZEOF, 40

# print_many(funcs, threads): every function printed (fn_print) and its
# priority computed (fn_priority), on threads - what the contract's text
# and json take of the functions, the same work for each. Each function
# is printed on a context of its own, from a copy of it whose values are
# imported there (the printer compares what it makes with what it reads,
# by pointer: both must be of the same context), with the names of the
# main context (set_names: the storage's). The texts are made strings of
# this context after, in order. A function whose printing fails is left
# as it was: fn_print, later, fails the same way where python does.
FUNC print_many
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r13, rsi
        cmp r13, 1
        jbe 9f
        cmp qword ptr [rbx + VEC_LEN], 1
        jbe 9f
        mov edi, PM_SIZEOF
        call arena_alloc
        mov r12, rax
        mov [r12 + PM_FUNCS], rbx
        mov rdi, [rbx + VEC_LEN]
        imul rdi, rdi, PT_SIZEOF
        call arena_alloc
        mov [r12 + PM_TASKS], rax
        mov rax, [r15 + CTX_CHILD_LIMIT]
        mov [r12 + PM_LIMIT], rax
        mov rax, [r15 + CTX_LOADER]
        mov [r12 + PM_LOADER], rax
        mov rax, [r15 + CTX_NAMES]
        mov [r12 + PM_NAMES], rax
        mov rdi, [rbx + VEC_LEN]
        mov rsi, r13
        lea rdx, [rip + print_one]
        mov rcx, r12
        call par_for
        # the texts, strings of this context now
        xor r14d, r14d
1:      cmp r14, [rbx + VEC_LEN]
        jae 9f
        imul r13, r14, PT_SIZEOF
        add r13, [r12 + PM_TASKS]
        mov rdi, [r13 + PT_TEXT]
        test rdi, rdi
        jz 2f
        mov rsi, [r13 + PT_LEN]
        call str_new
        mov rcx, [rbx + VEC_DATA]
        mov rcx, [rcx + r14*8]
        mov [rcx + FN_PRINT], rax
        mov rax, [r13 + PT_PRIORITY]
        mov [rcx + FN_PRIORITY], rax
        mov rdi, [r13 + PT_TEXT]
        call free@PLT
2:      inc r14
        jmp 1b
9:      add rsp, 16
        LEAVE
ENDF print_many

# print_one(i, pm): print_many's iteration i (see there)
FUNC print_one
        push r15
        ENTER
        sub rsp, ERR_SIZEOF + 24        # (with r15 pushed: 8 mod 16 keeps rsp aligned)
        .set PO1_CTX, ERR_SIZEOF
        .set PO1_MAIN, ERR_SIZEOF + 8
        mov [rsp + PO1_MAIN], r15
        mov rbx, rsi                    # pm
        imul r12, rdi, PT_SIZEOF
        add r12, [rbx + PM_TASKS]       # the task
        mov rax, [rbx + PM_FUNCS]
        mov rax, [rax + VEC_DATA]
        mov r13, [rax + rdi*8]          # the function (the main context's)
        call ctx_try_new                # (bound to this thread)
        test rax, rax
        jz 8f
        mov [rsp + PO1_CTX], rax
        mov r15, rax
        call ctx_set_stack
        mov rax, [rbx + PM_LIMIT]
        mov [r15 + CTX_MEM_LIMIT], rax
        mov rax, [rbx + PM_LOADER]
        mov [r15 + CTX_LOADER], rax
        mov rax, [rbx + PM_NAMES]       # (a record that never changes)
        mov [r15 + CTX_NAMES], rax
        mov rdi, rsp
        call err_catch
        test eax, eax
        jnz 7f
        # the copy, its values imported
        mov edi, FN_SIZEOF
        call arena_alloc
        mov r14, rax
        mov rdi, rax
        mov rsi, r13
        mov edx, FN_SIZEOF
        call memcpy@PLT
        mov qword ptr [r14 + FN_PRINT], 0
        mov qword ptr [r14 + FN_PRIORITY], 0
        lea rbx, [rip + fn_value_fields]
3:      mov ecx, [rbx]
        cmp ecx, -1
        je 4f
        mov rdi, [r14 + rcx]
        call value_import_root
        mov ecx, [rbx]
        mov [r14 + rcx], rax
        add rbx, 4
        jmp 3b
4:      mov rdi, r14
        call fn_print
        mov rdi, r14
        call fn_priority
        call err_end
        mov rax, [r14 + FN_PRIORITY]
        mov [r12 + PT_PRIORITY], rax
        mov rax, [r14 + FN_PRINT]       # its text, for the main thread
        mov ebx, [rax + N_DATA]
        mov [r12 + PT_LEN], rbx
        lea rdi, [rbx + 1]
        call malloc@PLT
        test rax, rax
        jz 7f
        mov [r12 + PT_TEXT], rax
        mov rdi, rax
        mov rsi, [r14 + FN_PRINT]
        add rsi, N_DATA + 4
        lea rdx, [rbx + 1]
        call memcpy@PLT
7:      mov rdi, [rsp + PO1_CTX]
        call ctx_free
8:      mov r15, [rsp + PO1_MAIN]
        add rsp, ERR_SIZEOF + 24
        LEAVE_NORET
        pop r15
        ret
ENDF print_one

        .section .rodata
        .align 4
# the fields of a function that hold values of its context
fn_value_fields:
        .long FN_ABI, FN_INPUTS, FN_TRACE, FN_ORIG_TRACE, FN_PARAMS, FN_CONST
        .long FN_GETTER, FN_RETURNS, FN_AST, -1
        .text

        .section .note.GNU-stack,"",@progbits
