# Expressions as text (port of prettify.py's prettify and its helpers).
# Every function here returns an arena string (rt_str.s str_new): the
# text is built, appended to, and freed with the thread's arena.
#
# prettify(exp, flags) -> str, with the flags PF_REM_BOOL (rem_bool),
# PF_PARENS (parentheses), PF_TOP (top_level) and PF_COLOR (add_color).
# python's `pret` is prettify with parentheses=False: the flags with only
# PF_COLOR kept.

.include "defs.inc"

        .section .rodata
.Ls_lparen:     .asciz "("
.Ls_rparen:     .asciz ")"
.Ls_comma_sp:   .asciz ", "
.Ls_plus:       .asciz " + "
.Ls_minus:      .asciz " - "
.Ls_len:        .asciz "len"
.Ls_sp_len_sp:  .asciz " len "
.Ls_array_len:  .asciz "Array(len="
.Ls_data_eq:    .asciz ", data="
.Ls_block_hash: .asciz "block.hash("
.Ls_ext_hash:   .asciz "ext_code.hash("
.Ls_ext_size:   .asciz "ext_code.size("
.Ls_ext_copy:   .asciz "ext_code.copy("
.Ls_max_:       .asciz "max("
.Ls_mulmod_:    .asciz "mulmod("
.Ls_True:       .asciz "True"
.Ls_False:      .asciz "False"
.Ls_code_data:  .asciz "code.data["
.Ls_rbracket:   .asciz "]"
.Ls_lbracket:   .asciz "["
.Ls_eth_balance: .asciz "eth.balance("
.Ls_sha3_:      .asciz "sha3("
.Ls_ceil32:     .asciz "ceil32("
.Ls_floor32:    .asciz "floor32("
.Ls_all:        .asciz "all"
.Ls_call_func_hash: .asciz "call.func_hash"
.Ls_cd_:        .asciz "cd["
.Ls_var:        .asciz "var"
.Ls_mem_:       .asciz "mem["
.Ls_eq_sp:      .asciz " = "
.Ls_uint255:    .asciz "uint255"
.Ls_bool_:      .asciz "bool("
.Ls_Mask_:      .asciz "Mask("
.Ls_bang:       .asciz "!"
.Ls_dash:       .asciz "-"
.Ls_caret:      .asciz "^"
.Ls_le:         .asciz " <= "
.Ls_ge:         .asciz " >= "
.Ls_ne:         .asciz " != "
.Ls_not_sp:     .asciz "not "
.Ls_10pow:      .asciz "10^"
.Ls_times_10pow: .asciz " * 10^"
.Ls_caller:     .asciz "caller"
.Ls_tx_origin:  .asciz "tx.origin"
.Ls_2300:       .asciz "2300 * is_zero(value)"
.Ls_quote:      .asciz "'"
.Ls_empty_call: .asciz "empty()"
.Ls_mem:        .asciz "mem"
.Ls_signed_message: .asciz "'\\x19Ethereum Signed Message:\\n32'"

        # the arithmetic operators (opcode_to_arithm)
.Ls_op_sub:  .asciz " - "
.Ls_op_div:  .asciz " / "
.Ls_op_mul:  .asciz " * "
.Ls_op_gt:   .asciz " > "
.Ls_op_lt:   .asciz " < "
.Ls_op_le:   .asciz " <= "
.Ls_op_ge:   .asciz " >= "
.Ls_op_or:   .asciz " or "
.Ls_op_eq:   .asciz " == "
.Ls_op_mod:  .asciz " % "
.Ls_op_shl:  .asciz " << "
.Ls_op_shr:  .asciz " >> "
.Ls_op_exp:  .asciz "^"
.Ls_op_and:  .asciz " and "
.Ls_op_sge:  .asciz " >=\xe2\x80\xb2 "
.Ls_op_sle:  .asciz " <=\xe2\x80\xb2 "
.Ls_op_sgt:  .asciz " >\xe2\x80\xb2 "
.Ls_op_slt:  .asciz " <\xe2\x80\xb2 "
.Ls_op_sadd: .asciz " +\xe2\x80\xb2 "
.Ls_op_smul: .asciz " *\xe2\x80\xb2 "
.Ls_op_sdiv: .asciz " /\xe2\x80\xb2 "
.Ls_op_xor:  .asciz " xor "

        # the atoms with a name of their own
.Ls_block_number:   .asciz "block.number"
.Ls_calldata_size:  .asciz "calldata.size"
.Ls_return_data_size: .asciz "return_data.size"
.Ls_block_difficulty: .asciz "block.difficulty"
.Ls_block_basefee:  .asciz "block.basefee"
.Ls_block_gasprice: .asciz "block.gasprice"
.Ls_block_timestamp: .asciz "block.timestamp"
.Ls_block_coinbase: .asciz "block.coinbase"
.Ls_block_gas_limit: .asciz "block.gas_limit"
.Ls_call_value:     .asciz "call.value"
.Ls_this_address:   .asciz "this.address"
.Ls_gas_remaining:  .asciz "gas_remaining"

        # the nice names of the variables
.Ln_idx: .asciz "idx"
.Ln_s: .asciz "s"
.Ln_t: .asciz "t"
.Ln_u: .asciz "u"
.Ln_v: .asciz "v"
.Ln_w: .asciz "w"
.Ln_x: .asciz "x"
.Ln_y: .asciz "y"
.Ln_z: .asciz "z"
.Ln_a: .asciz "a"
.Ln_b: .asciz "b"
.Ln_c: .asciz "c"
.Ln_d: .asciz "d"
.Ln_e: .asciz "e"
.Ln_f: .asciz "f"
.Ln_g: .asciz "g"
.Ln_h: .asciz "h"

        .section .data.rel.ro
        .align 8
nice_names:
        .quad .Ln_idx, .Ln_s, .Ln_t, .Ln_u, .Ln_v, .Ln_w, .Ln_x, .Ln_y, .Ln_z
        .quad .Ln_a, .Ln_b, .Ln_c, .Ln_d, .Ln_e, .Ln_f, .Ln_g, .Ln_h
        .set NICE_NAMES_COUNT, 17

        # (filled by prettify_init: the ids are assembler constants, but a
        # sparse table is easier to fill than to declare)
        .section .bss
        .align 8
arith_ops:                              # opcode id -> operator text (0 for the others)
        .skip 8 * (OP_COUNT + 1)
atom_names:                             # opcode id -> the text of a string atom
        .skip 8 * (OP_COUNT + 1)
pf_table:                               # opcode id -> prettify's handler for the head
        .skip 8 * (OP_COUNT + 1)

        .text

.macro B reg, n
        mov \reg, [rsp + 8*(\n)]
.endm

# prettify_init(): the tables (called from rt_init)
FUNC prettify_init
        lea rax, [rip + arith_ops]
        .macro ARITH_OP op, text
        lea rcx, [rip + \text]
        mov [rax + 8*\op], rcx
        .endm
        ARITH_OP OP_SUB, .Ls_op_sub
        ARITH_OP OP_DIV, .Ls_op_div
        ARITH_OP OP_MUL, .Ls_op_mul
        ARITH_OP OP_GT, .Ls_op_gt
        ARITH_OP OP_LT, .Ls_op_lt
        ARITH_OP OP_LE, .Ls_op_le
        ARITH_OP OP_GE, .Ls_op_ge
        ARITH_OP OP_OR, .Ls_op_or
        ARITH_OP OP_EQ, .Ls_op_eq
        ARITH_OP OP_MOD, .Ls_op_mod
        ARITH_OP OP_SHL, .Ls_op_shl
        ARITH_OP OP_SHR, .Ls_op_shr
        ARITH_OP OP_EXP, .Ls_op_exp
        ARITH_OP OP_AND, .Ls_op_and
        ARITH_OP OP_SGE, .Ls_op_sge
        ARITH_OP OP_SLE, .Ls_op_sle
        ARITH_OP OP_SGT, .Ls_op_sgt
        ARITH_OP OP_SLT, .Ls_op_slt
        ARITH_OP OP_SADD, .Ls_op_sadd
        ARITH_OP OP_SMUL, .Ls_op_smul
        ARITH_OP OP_SDIV, .Ls_op_sdiv
        ARITH_OP OP_XOR, .Ls_op_xor
        lea rax, [rip + atom_names]
        ARITH_OP OP_NUMBER, .Ls_block_number
        ARITH_OP OP_CALLDATASIZE, .Ls_calldata_size
        ARITH_OP OP_RETURNDATASIZE, .Ls_return_data_size
        ARITH_OP OP_DIFFICULTY, .Ls_block_difficulty
        ARITH_OP OP_BASEFEE, .Ls_block_basefee
        ARITH_OP OP_GASPRICE, .Ls_block_gasprice
        ARITH_OP OP_TIMESTAMP, .Ls_block_timestamp
        ARITH_OP OP_COINBASE, .Ls_block_coinbase
        ARITH_OP OP_GASLIMIT, .Ls_block_gas_limit
        ARITH_OP OP_CALLVALUE, .Ls_call_value
        ARITH_OP OP_ADDRESS, .Ls_this_address
        ARITH_OP OP_CALLER, .Ls_caller
        ARITH_OP OP_ORIGIN, .Ls_tx_origin
        ARITH_OP OP_GAS, .Ls_gas_remaining
        lea rax, [rip + pf_table]
        lea rcx, [rip + .Lpf_default]
        xor edx, edx
1:      mov [rax + rdx*8], rcx
        inc edx
        cmp edx, OP_COUNT + 1
        jb 1b
        .macro PF op, handler
        lea rcx, [rip + \handler]
        mov [rax + 8*\op], rcx
        .endm
        PF OP_ERECOVER, .Lpf_precompiled
        PF OP_SHA256HASH, .Lpf_precompiled
        PF OP_RIPEMD160HASH, .Lpf_precompiled
        PF OP_BIGMODEXP, .Lpf_precompiled
        PF OP_BN256ADD, .Lpf_precompiled
        PF OP_BN256SCALARMUL, .Lpf_precompiled
        PF OP_BN256PAIRING, .Lpf_precompiled
        PF OP_ARR, .Lpf_arr
        PF OP_PARAM, .Lpf_param
        PF OP_RANGE, .Lpf_range
        PF OP_DATA, .Lpf_data
        PF OP_BLOCKHASH, .Lpf_blockhash
        PF OP_EXTCODEHASH, .Lpf_extcodehash
        PF OP_EXTCODESIZE, .Lpf_extcodesize
        PF OP_EXTCODECOPY, .Lpf_extcodecopy
        PF OP_MAX, .Lpf_max
        PF OP_MASK_SHL, .Lpf_mask_shl
        PF OP_MULMOD, .Lpf_mulmod
        PF OP_BOOL, .Lpf_bool
        PF OP_CODE_DATA, .Lpf_code_data
        PF OP_BALANCE, .Lpf_balance
        PF OP_SHA3, .Lpf_sha3
        PF OP_MASK, .Lpf_mask
        PF OP_CALL_DATA, .Lpf_call_data
        PF OP_EXT_CALL_RETURN_DATA, .Lpf_array
        PF OP_DELEGATE_RETURN_DATA, .Lpf_array
        PF OP_CALLCODE_RETURN_DATA, .Lpf_array
        PF OP_STATICCALL_RETURN_DATA, .Lpf_array
        PF OP_STOR, .Lpf_stor
        PF OP_TYPE, .Lpf_stor
        PF OP_FIELD, .Lpf_stor
        PF OP_CD, .Lpf_cd
        PF OP_VAR, .Lpf_var
        PF OP_MEM, .Lpf_mem
        PF OP_SETVAR, .Lpf_setvar
        PF OP_SETMEM, .Lpf_setmem
        PF OP_NOT, .Lpf_not
        PF OP_ADD, .Lpf_add
        PF OP_MUL, .Lpf_mul
        PF OP_DIV, .Lpf_div
        PF OP_EXP, .Lpf_exp
        PF OP_SUB, .Lpf_arith
        PF OP_GT, .Lpf_arith
        PF OP_LT, .Lpf_arith
        PF OP_LE, .Lpf_arith
        PF OP_GE, .Lpf_arith
        PF OP_OR, .Lpf_arith
        PF OP_EQ, .Lpf_arith
        PF OP_MOD, .Lpf_arith
        PF OP_SHL, .Lpf_arith
        PF OP_SHR, .Lpf_arith
        PF OP_AND, .Lpf_arith
        PF OP_SGE, .Lpf_arith
        PF OP_SLE, .Lpf_arith
        PF OP_SGT, .Lpf_arith
        PF OP_SLT, .Lpf_arith
        PF OP_SADD, .Lpf_arith
        PF OP_SMUL, .Lpf_arith
        PF OP_SDIV, .Lpf_arith
        PF OP_XOR, .Lpf_arith
        PF OP_ISZERO, .Lpf_iszero
        ret
ENDF prettify_init

# --- small helpers ---

# pf_color(flags) -> eax: the flags of python's `pret` (add_color only)
# pf_color_parens(flags) -> eax: pret(x, parentheses=parentheses)
# pf_full(flags) -> eax: prettify(x, add_color=add_color)
.macro PF_COLOR_OF dst, src
        mov \dst, \src
        and \dst, PF_COLOR
.endm
.macro PF_COLOR_PARENS dst, src
        mov \dst, \src
        and \dst, PF_COLOR | PF_PARENS
.endm
.macro PF_FULL dst, src
        mov \dst, \src
        and \dst, PF_COLOR
        or \dst, PF_PARENS
.endm

# py_truthy(v) -> eax: python's bool(v) for our values
FUNC py_truthy
        test dil, 1
        jz 1f
        xor eax, eax
        cmp rdi, 1                      # tagged 0
        setne al
        ret
1:      test rdi, rdi
        jz 3f
        mov eax, [rdi + N_KIND]
        cmp eax, K_STR
        je 5f
        cmp eax, K_SPECIAL
        je 6f
        cmp eax, K_TUPLE
        je 7f
        cmp eax, K_LIST
        je 7f
        mov eax, 1                      # a big int, a vm node
        ret
5:      xor eax, eax
        cmp dword ptr [rdi + N_DATA], 0
        setne al
        ret
7:      xor eax, eax
        cmp dword ptr [rdi + N_AUX], 0
        setne al
        ret
6:      xor eax, eax
        cmp dword ptr [rdi + N_AUX], SP_TRUE
        sete al
        ret
3:      xor eax, eax
        ret
ENDF py_truthy

# is_none(v) -> eax: NIL or the None special
FUNC is_none
        test rdi, rdi
        jz 1f
        mov esi, SP_NONE
        jmp is_special
1:      mov eax, 1
        ret
ENDF is_none

# sb_append_pret(sb, exp, flags): prettify appended
FUNC sb_append_pret
        ENTER
        mov rbx, rdi
        mov rdi, rsi
        mov rsi, rdx
        call prettify
        mov rdi, rbx
        mov rsi, rax
        call sb_append_str
        LEAVE
ENDF sb_append_pret

# --- prettify ---

FUNC prettify
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 64
        .set PF_EXP, MATCH_BINDINGS_SIZE
        .set PF_FLAGS, MATCH_BINDINGS_SIZE + 8
        .set PF_SB, MATCH_BINDINGS_SIZE + 16
        .set PF_T1, MATCH_BINDINGS_SIZE + 24
        .set PF_T2, MATCH_BINDINGS_SIZE + 32
        .set PF_T3, MATCH_BINDINGS_SIZE + 40
        mov rbx, rdi
        mov r12, rsi
        test r12, PF_REM_BOOL
        jz 1f
        mov rdi, rbx
        call simplify_bool
        mov rbx, rax
        mov rdi, rax
        call opcode_of
        cmp eax, OP_BOOL
        jne 1f
        mov rdi, rbx
        mov rsi, r12
        call prettify
        jmp .Lpf_ret
1:      mov rdi, rbx
        call is_int
        test eax, eax
        jz .Lpf_not_int
        # time constants: multiples of a day, then of an hour
        mov rdi, rbx
        mov rsi, 86400
        TAG rsi
        call .Lpf_multiple_above
        test eax, eax
        jz 2f
        mov rdi, rbx
        mov rsi, 3600
        TAG rsi
        call int_floordiv
        mov rsi, rax
        LOADS rdi, MUL
        mov rdx, 24
        TAG rdx
        mov rcx, 3600
        TAG rcx
        call mk4
        mov rbx, rax
        jmp .Lpf_dispatch
2:      mov rdi, rbx
        mov rsi, 3600
        TAG rsi
        call .Lpf_multiple_above
        test eax, eax
        jz 3f
        mov rdi, rbx
        mov rsi, 3600
        TAG rsi
        call int_floordiv
        mov rsi, rax
        LOADS rdi, MUL
        mov rdx, 3600
        TAG rdx
        call mk3
        mov rbx, rax
        jmp .Lpf_dispatch
3:      mov rdi, rbx
        mov rsi, r12
        call pretty_num
        jmp .Lpf_ret
.Lpf_not_int:
        mov rdi, rbx
        call is_str
        test eax, eax
        jz .Lpf_dispatch
        mov rdi, rbx
        call str_id
        test eax, eax
        jz .Lpf_default
        cmp eax, OP_COUNT
        ja .Lpf_default
        lea rcx, [rip + atom_names]
        mov rdi, [rcx + rax*8]
        test rdi, rdi
        jz .Lpf_default
        call str_new_c
        jmp .Lpf_ret
.Lpf_dispatch:
        mov [rsp + PF_EXP], rbx
        mov [rsp + PF_FLAGS], r12
        mov rdi, rbx
        call opcode_of
        test eax, eax
        jz .Lpf_default
        lea rcx, [rip + pf_table]
        jmp [rcx + rax*8]

# a local: is rdi a multiple of rsi above it? (exp % n == 0 and exp > n)
.Lpf_multiple_above:
        sub rsp, 24
        mov [rsp], rdi
        mov [rsp + 8], rsi
        call int_mod
        cmp rax, 1
        jne 1f
        mov rdi, [rsp]
        mov rsi, [rsp + 8]
        call int_cmp
        cmp eax, 1
        sete al
        movzx eax, al
        add rsp, 24
        ret
1:      xor eax, eax
        add rsp, 24
        ret

.Lpf_default:
        mov rdi, rbx
        call value_str
        jmp .Lpf_ret

.Lpf_precompiled:
        # f"{exp[0]}({pret(exp[1])})"
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, [rbx + N_DATA]
        call sb_append_str
        mov rdi, r13
        mov esi, '('
        call sb_append_char
        mov rdi, r13
        mov rsi, [rbx + N_DATA + 8]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, r13
        mov esi, ')'
        call sb_append_char
        jmp .Lpf_finish

.Lpf_arr:
        PAT rsi, "('arr', ':int:num', ('mask_shl', 'Any', 'Any', 'Any', ':str:s'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        B rax, 1
        mov ecx, [rax + N_DATA]
        sub ecx, 2
        mov rdi, rcx
        TAG rdi
        B rsi, 0
        call values_equal
        test eax, eax
        jz 1f
        B rax, 1
        jmp .Lpf_ret
1:      cmp dword ptr [rbx + N_AUX], 1
        jbe .Lpf_default
        # Array(len=l, data=terms)
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_array_len]
        lea rdx, [rip + C_GRAY]
        mov rcx, r12
        call sb_append_col_c
        mov rdi, r13
        mov rsi, [rbx + N_DATA + 8]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, r13
        lea rsi, [rip + .Ls_data_eq]
        lea rdx, [rip + C_GRAY]
        mov rcx, r12
        call sb_append_col_c
        # ('data',) + exp[2:]
        mov rdi, rbx
        mov esi, 2
        call list_from
        mov rdi, rax
        LOADS rsi, DATA
        call list_prepend
        mov rdi, rax
        call seq_to_tuple
        mov rdi, r13
        mov rsi, rax
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, r13
        lea rsi, [rip + .Ls_rparen]
        lea rdx, [rip + C_GRAY]
        mov rcx, r12
        call sb_append_col_c
        jmp .Lpf_finish

.Lpf_param:
        cmp dword ptr [rbx + N_AUX], 2
        jne .Lpf_default
        mov rdi, [rbx + N_DATA + 8]
        call value_str
        mov rdi, rax
        lea rsi, [rip + C_GREEN]
        mov rdx, r12
        call colorize
        jmp .Lpf_ret

.Lpf_range:
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lpf_default
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, [rbx + N_DATA + 8]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, r13
        mov esi, ' '
        call sb_append_char
        mov rdi, r13
        lea rsi, [rip + .Ls_len]
        lea rdx, [rip + C_HEADER]
        mov rcx, r12
        call sb_append_col_c
        mov rdi, r13
        mov esi, ' '
        call sb_append_char
        mov rdi, r13
        mov rsi, [rbx + N_DATA + 16]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        jmp .Lpf_finish

.Lpf_data:
        mov rdi, rbx
        mov rsi, r12
        call pretty_memory
        lea rdi, [rip + .Ls_comma_sp]
        mov rsi, rax
        call str_join
        jmp .Lpf_ret

.Lpf_blockhash:
        lea r13, [rip + .Ls_block_hash]
        jmp .Lpf_call1
.Lpf_extcodehash:
        lea r13, [rip + .Ls_ext_hash]
        jmp .Lpf_call1
.Lpf_extcodesize:
        lea r13, [rip + .Ls_ext_size]
        jmp .Lpf_call1
.Lpf_balance:
        lea r13, [rip + .Ls_eth_balance]
.Lpf_call1:
        # f"name({pret(exp[1])})"
        cmp dword ptr [rbx + N_AUX], 2
        jne .Lpf_default
        call sb_new
        mov r14, rax
        mov rdi, rax
        mov rsi, r13
        call sb_append_c
        mov rdi, r14
        mov rsi, [rbx + N_DATA + 8]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, r14
        mov esi, ')'
        call sb_append_char
        mov r13, r14
        jmp .Lpf_finish

.Lpf_extcodecopy:
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lpf_default
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_ext_copy]
        call sb_append_c
        mov rdi, r13
        mov rsi, [rbx + N_DATA + 8]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, r13
        lea rsi, [rip + .Ls_comma_sp]
        call sb_append_c
        mov rdi, r13
        mov rsi, [rbx + N_DATA + 16]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, r13
        mov esi, ')'
        call sb_append_char
        jmp .Lpf_finish

.Lpf_max:
        lea r13, [rip + .Ls_max_]
        jmp .Lpf_call_n
.Lpf_sha3:
        lea r13, [rip + .Ls_sha3_]
.Lpf_call_n:
        # f"name({', '.join(pret(e) for e in terms)})"
        call sb_new
        mov r14, rax
        mov rdi, rax
        mov rsi, r13
        call sb_append_c
        mov rdi, r14
        mov rsi, rbx
        mov edx, 1
        PF_COLOR_OF rcx, r12
        call sb_append_pret_join
        mov rdi, r14
        mov esi, ')'
        call sb_append_char
        mov r13, r14
        jmp .Lpf_finish

.Lpf_mulmod:
        cmp dword ptr [rbx + N_AUX], 4
        jne .Lpf_default
        lea r13, [rip + .Ls_mulmod_]
        jmp .Lpf_call_n

.Lpf_bool:
        cmp dword ptr [rbx + N_AUX], 2
        jne .Lpf_default
        mov rax, [rbx + N_DATA + 8]
        cmp rax, 3                      # tagged 1
        jne 1f
        lea rdi, [rip + .Ls_True]
        call str_new_c
        jmp .Lpf_ret
1:      cmp rax, 1                      # tagged 0
        jne 2f
        lea rdi, [rip + .Ls_False]
        call str_new_c
        jmp .Lpf_ret
2:      # ('bool', val): comparisons as they are, else bool(val)
        mov rdi, rax
        call opcode_of
        cmp eax, OP_LT
        je 3f
        cmp eax, OP_GT
        je 3f
        cmp eax, OP_ISZERO
        je 3f
        cmp eax, OP_LE
        je 3f
        cmp eax, OP_GE
        je 3f
        cmp eax, OP_BOOL
        je 3f
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_bool_]
        call sb_append_c
        mov rdi, r13
        mov rsi, [rbx + N_DATA + 8]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, r13
        mov esi, ')'
        call sb_append_char
        jmp .Lpf_finish
3:      mov rdi, [rbx + N_DATA + 8]
        PF_COLOR_PARENS rsi, r12
        call prettify
        jmp .Lpf_ret

.Lpf_code_data:
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lpf_default
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_code_data]
        call sb_append_c
        mov rdi, r13
        mov rsi, [rbx + N_DATA + 8]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, r13
        lea rsi, [rip + .Ls_sp_len_sp]
        call sb_append_c
        mov rdi, r13
        mov rsi, [rbx + N_DATA + 16]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, r13
        mov esi, ']'
        call sb_append_char
        jmp .Lpf_finish

.Lpf_call_data:
        # the whole of an array parameter: param[all]
        PAT rsi, "('call.data', ('add', 36, ('param', ':p_name')), ':size')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lpf_array
        B rsi, 0
        LOADS rdi, PARAM
        call mk2
        mov rsi, rax
        mov rdi, 4
        TAG rdi
        mov rdx, rsi
        mov rsi, rdi
        LOADS rdi, ADD
        call mk3
        mov rsi, rax
        LOADS rdi, CD
        call mk2
        B rdi, 1
        mov rsi, rax
        call values_equal
        test eax, eax
        jz .Lpf_array
        call sb_new
        mov r13, rax
        # (p_name + "[") in green, "all", "]" in green
        B rdi, 0
        call value_str
        mov r14, rax
        lea rdi, [rip + .Ls_lbracket]
        call str_new_c
        mov rdi, r14
        mov rsi, rax
        call str_cat2
        mov rdi, rax
        lea rsi, [rip + C_GREEN]
        mov rdx, r12
        call colorize
        mov rdi, r13
        mov rsi, rax
        call sb_append_str
        mov rdi, r13
        lea rsi, [rip + .Ls_all]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + .Ls_rbracket]
        lea rdx, [rip + C_GREEN]
        mov rcx, r12
        call sb_append_col_c
        jmp .Lpf_finish

.Lpf_array:
        # (name, offset, size): name[offset] or name[offset len size]
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lpf_default
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, [rbx + N_DATA]
        call sb_append_str
        mov rdi, r13
        mov esi, '['
        call sb_append_char
        mov rdi, r13
        mov rsi, [rbx + N_DATA + 8]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rax, [rbx + N_DATA + 16]
        cmp rax, 65                     # tagged 32
        je 1f
        mov rdi, r13
        lea rsi, [rip + .Ls_sp_len_sp]
        call sb_append_c
        mov rdi, r13
        mov rsi, [rbx + N_DATA + 16]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
1:      mov rdi, r13
        mov esi, ']'
        call sb_append_char
        jmp .Lpf_finish

.Lpf_stor:
        mov rdi, rbx
        mov rsi, r12
        call pretty_stor
        jmp .Lpf_ret

.Lpf_cd:
        cmp dword ptr [rbx + N_AUX], 2
        jne .Lpf_default
        cmp qword ptr [rbx + N_DATA + 8], 1     # tagged 0
        jne 1f
        lea rdi, [rip + .Ls_call_func_hash]
        lea rsi, [rip + C_GREEN]
        mov rdx, r12
        call colorize_c
        jmp .Lpf_ret
1:      mov rdi, rbx
        mov rsi, r12
        call get_param_name
        mov r13, rax
        mov rdi, rax
        call is_str
        test eax, eax
        jnz 2f
        # "cd[" + prettify(parsed[1], add_color) + "]"
        call sb_new
        mov r14, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_cd_]
        call sb_append_c
        mov rdi, r14
        mov rsi, [r13 + N_DATA + 8]
        PF_FULL rdx, r12
        call sb_append_pret
        mov rdi, r14
        mov esi, ']'
        call sb_append_char
        mov r13, r14
        jmp .Lpf_finish
2:      mov rax, r13
        jmp .Lpf_ret

.Lpf_var:
        cmp dword ptr [rbx + N_AUX], 2
        jne .Lpf_default
        mov rdi, [rbx + N_DATA + 8]
        call is_int
        test eax, eax
        jz 2f
        mov rdi, [rbx + N_DATA + 8]
        call int_to_i64
        cmp rax, NICE_NAMES_COUNT
        jae 1f
        test rax, rax
        js 1f
        lea rcx, [rip + nice_names]
        mov rdi, [rcx + rax*8]
        call str_new_c
        jmp 3f
1:      # "var" + str(idx)
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_var]
        call sb_append_c
        mov rdi, r13
        mov rsi, [rbx + N_DATA + 8]
        mov edx, 10
        call sb_append_int
        mov rdi, r13
        call sb_finish
        jmp 3f
2:      mov rdi, [rbx + N_DATA + 8]
        call value_str
3:      mov rdi, rax
        lea rsi, [rip + C_BLUE]
        mov rdx, r12
        call colorize
        jmp .Lpf_ret

.Lpf_mem:
        cmp dword ptr [rbx + N_AUX], 2
        jne .Lpf_default
        mov r13, [rbx + N_DATA + 8]     # idx
        PAT rsi, "('range', ':loc', 32)"
        mov rdi, r13
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        B r13, 0                        # ('mem', ('range', loc, 32)) -> ('mem', loc)
1:      PAT rsi, "('range', ':loc', ':size')"
        mov rdi, r13
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        call sb_new
        mov r14, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_mem_]
        lea rdx, [rip + C_HEADER]
        mov rcx, r12
        call sb_append_col_c
        mov rdi, r14
        B rsi, 0
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, r14
        lea rsi, [rip + .Ls_sp_len_sp]
        lea rdx, [rip + C_HEADER]
        mov rcx, r12
        call sb_append_col_c
        mov rdi, r14
        B rsi, 1
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, r14
        lea rsi, [rip + .Ls_rbracket]
        lea rdx, [rip + C_HEADER]
        mov rcx, r12
        call sb_append_col_c
        mov r13, r14
        jmp .Lpf_finish
2:      call sb_new
        mov r14, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_mem_]
        lea rdx, [rip + C_HEADER]
        mov rcx, r12
        call sb_append_col_c
        mov rdi, r14
        mov rsi, r13
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, r14
        lea rsi, [rip + .Ls_rbracket]
        lea rdx, [rip + C_HEADER]
        mov rcx, r12
        call sb_append_col_c
        mov r13, r14
        jmp .Lpf_finish

.Lpf_setvar:
        # pret(('var', idx)) + " = " + pret(val)
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lpf_default
        LOADS rdi, VAR
        mov rsi, [rbx + N_DATA + 8]
        call mk2
        jmp .Lpf_assign
.Lpf_setmem:
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lpf_default
        LOADS rdi, MEM
        mov rsi, [rbx + N_DATA + 8]
        call mk2
.Lpf_assign:
        mov r13, rax
        call sb_new
        mov r14, rax
        mov rdi, rax
        mov rsi, r13
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, r14
        lea rsi, [rip + .Ls_eq_sp]
        call sb_append_c
        mov rdi, r14
        mov rsi, [rbx + N_DATA + 16]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov r13, r14
        jmp .Lpf_finish

.Lpf_mask_shl:
        cmp dword ptr [rbx + N_AUX], 5
        jne .Lpf_default
        # ('mask_shl', 160, 0, 0, 'caller') / 'origin'
        # (the literals are consed on the global context, hence the
        # structural comparison)
        PAT rsi, "('mask_shl', 160, 0, 0, 'caller')"
        mov rdi, rbx
        call pat_match_nobind
        test eax, eax
        jz 1f
        lea rdi, [rip + .Ls_caller]
        call str_new_c
        jmp .Lpf_ret
1:      PAT rsi, "('mask_shl', 160, 0, 0, 'origin')"
        mov rdi, rbx
        call pat_match_nobind
        test eax, eax
        jz 2f
        lea rdi, [rip + .Ls_tx_origin]
        call str_new_c
        jmp .Lpf_ret
2:      # ('mask_shl', size, 5, 0, val) with size > 245: ceil32 / floor32
        PAT rsi, "('mask_shl', ':size', 5, 0, ':val')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 3f
        call .Lpf_floor32
        test rax, rax
        jz 3f
        jmp .Lpf_ret
3:      # a storage under a mask that keeps all of it
        PAT rsi, "('mask_shl', ':size', ':offset', ':shl', ('stor', ':s_size', ':s_off', ':s_idx'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 4f
        cmp qword ptr [rsp + 16], 1     # shl == 0
        jne 4f
        B rdi, 3
        B rsi, 0
        call alg_safe_le_op
        cmp eax, TRI_TRUE
        jne 4f
        B rsi, 3
        B rdx, 4
        B rcx, 5
        LOADS rdi, STOR
        call mk4
        mov rdi, rax
        PF_COLOR_OF rsi, r12
        call prettify
        jmp .Lpf_ret
4:      mov r13, [rbx + N_DATA + 8]     # size
        mov r14, [rbx + N_DATA + 16]    # offset
        mov [rsp + PF_T1], r14
        mov rax, [rbx + N_DATA + 24]    # shl
        mov [rsp + PF_T2], rax
        mov rax, [rbx + N_DATA + 32]    # val
        mov [rsp + PF_T3], rax
        # all ints (size, offset, shl)?
        mov edi, 3
        lea rsi, [rbx + N_DATA + 8]
        call all_ints
        test eax, eax
        jz .Lms_general
        # size + offset == 256 and offset == -shl and offset < 8: a division
        mov rdi, r13
        mov rsi, r14
        call int_add
        cmp rax, 513                    # tagged 256
        jne 5f
        mov rdi, [rsp + PF_T2]
        call int_neg
        cmp rax, r14
        jne 5f
        mov rdi, r14
        mov rsi, 8
        TAG rsi
        call int_cmp
        cmp eax, -1
        jne 5f
        # shl <= 8: ('div', val, 2 ** offset) - a float, as python, below
        # zero; else ('shr', shl, val)
        mov rdi, r14
        call int_to_i64
        cmp rax, -8
        jl 51f
        mov rdi, rax
        call pow2_or_float
        mov rdx, rax
        mov rsi, [rsp + PF_T3]
        LOADS rdi, DIV
        call mk3
        mov rdi, rax
        PF_COLOR_PARENS rsi, r12
        call prettify
        jmp .Lpf_ret
51:     mov rsi, [rsp + PF_T2]
        mov rdx, [rsp + PF_T3]
        LOADS rdi, SHR
        call mk3
        mov rdi, rax
        PF_COLOR_PARENS rsi, r12
        call prettify
        jmp .Lpf_ret
5:      # offset == shl and offset < 8: a multiplication
        cmp r14, [rsp + PF_T2]
        jne .Lms_general
        mov rdi, r14
        mov rsi, 8
        TAG rsi
        call int_cmp
        cmp eax, -1
        jne .Lms_general
        # val = ('mask', size + offset, 0, val) unless size + offset == 256
        # or val is a store
        mov rdi, r13
        mov rsi, r14
        call int_add
        cmp rax, 513
        je 6f
        push rax
        push rax
        mov rdi, [rsp + 16 + PF_T3]
        call opcode_of
        pop rsi
        pop rsi
        cmp eax, OP_STORE
        je 6f
        mov rcx, [rsp + PF_T3]
        mov edx, 1                      # tagged 0
        LOADS rdi, MASK
        call mk4
        mov [rsp + PF_T3], rax
6:      cmp r14, 1                      # shl == 0
        jne 7f
        mov rdi, [rsp + PF_T3]
        PF_COLOR_PARENS rsi, r12
        call prettify
        jmp .Lpf_ret
7:      # -8 <= shl <= 8: ('mul', val, 2 ** shl) (a float below zero);
        # else a shift
        mov rdi, r14
        call int_to_i64
        cmp rax, -8
        jl 71f
        mov rdi, rax
        call pow2_or_float
        mov rdx, rax
        mov rsi, [rsp + PF_T3]
        LOADS rdi, MUL
        call mk3
        mov rdi, rax
        PF_COLOR_PARENS rsi, r12
        call prettify
        jmp .Lpf_ret
71:     # ('shr', -shl, val)  (shl > 8 can't happen here: offset < 8)
        mov rdi, r14
        call int_neg
        mov rsi, rax
        mov rdx, [rsp + PF_T3]
        LOADS rdi, SHR
        call mk3
        mov rdi, rax
        PF_COLOR_PARENS rsi, r12
        call prettify
        jmp .Lpf_ret
.Lms_general:
        # all concrete: the mask applied
        mov edi, 4
        lea rsi, [rbx + N_DATA + 8]
        call all_ints
        test eax, eax
        jz 8f
        mov rdi, [rsp + PF_T3]
        mov rsi, r13
        mov rdx, r14
        mov rcx, [rsp + PF_T2]
        call alg_apply_mask
        mov rdi, rax
        PF_COLOR_OF rsi, r12
        call prettify
        jmp .Lpf_ret
8:      cmp qword ptr [rsp + PF_T2], 1  # shl == 0: ('mask', size, offset, val)
        jne 9f
        mov rsi, r13
        mov rdx, r14
        mov rcx, [rsp + PF_T3]
        LOADS rdi, MASK
        call mk4
        mov rbx, rax
        jmp .Lpf_dispatch
9:      mov rdi, [rsp + PF_T2]
        call alg_safe_ge_zero
        cmp eax, TRI_FALSE
        je 12f
        # shl >= 0 or unknown
        mov edi, 3
        lea rsi, [rbx + N_DATA + 8]
        call all_ints
        test eax, eax
        jz 10f
        mov rdi, r13
        mov rsi, [rsp + PF_T2]
        call int_add
        cmp rax, 513                    # size + shl == 256
        jne 10f
        cmp r14, 1                      # offset == 0
        jne 10f
        mov rdi, [rsp + PF_T2]
        mov rsi, -8
        TAG rsi
        call int_cmp
        cmp eax, 1                      # shl > -8
        jne 10f
        # ('mul', 2 ** shl, val)
        mov rdi, [rsp + PF_T2]
        call int_to_i64
        mov rdi, rax
        call pow2
        mov rsi, rax
        mov rdx, [rsp + PF_T3]
        LOADS rdi, MUL
        call mk3
        mov rbx, rax
        jmp .Lpf_dispatch
10:     # ('mask', size, offset, val) under a mul or a shift
        mov rsi, r13
        mov rdx, r14
        mov rcx, [rsp + PF_T3]
        LOADS rdi, MASK
        call mk4
        mov [rsp + PF_T3], rax
        mov rdi, [rsp + PF_T2]
        call is_int
        test eax, eax
        jz 11f
        mov rdi, [rsp + PF_T2]
        mov rsi, 7
        TAG rsi
        call int_cmp
        cmp eax, -1
        jne 11f
        mov rdi, [rsp + PF_T2]
        mov rsi, -8
        TAG rsi
        call int_cmp
        cmp eax, -1
        je 11f
        # ('mul', 2 ** shl, mask)
        mov rdi, [rsp + PF_T2]
        call int_to_i64
        mov rdi, rax
        call pow2
        mov rsi, rax
        mov rdx, [rsp + PF_T3]
        LOADS rdi, MUL
        call mk3
        mov rbx, rax
        jmp .Lpf_dispatch
11:     # ('shl', shl, mask) (a negative int shl can't get here: it is
        # safe_ge_zero False)
        mov rsi, [rsp + PF_T2]
        mov rdx, [rsp + PF_T3]
        LOADS rdi, SHL
        call mk3
        mov rbx, rax
        jmp .Lpf_dispatch
12:     # ('shr', -shl, mask)
        mov rsi, r13
        mov rdx, r14
        mov rcx, [rsp + PF_T3]
        LOADS rdi, MASK
        call mk4
        mov [rsp + PF_T3], rax
        mov rdi, [rsp + PF_T2]
        call alg_minus_op
        mov rsi, rax
        mov rdx, [rsp + PF_T3]
        LOADS rdi, SHR
        call mk3
        mov rbx, rax
        jmp .Lpf_dispatch

# a local: after a match of (op, ':size', 5, [0,] ':val') with the
# bindings size (0) and val (1): ceil32(num) / floor32(val) when
# size > 245, else 0
.Lpf_floor32:
        sub rsp, 8
        B rdi, 0 + 2
        call must_int
        B rdi, 0 + 2
        mov rsi, 245
        TAG rsi
        call int_cmp
        cmp eax, 1
        jne 1f
        call sb_new
        mov r13, rax
        # val ~ ('add', 31, num)?
        B rdi, 1 + 2
        push rdi
        push rdi
        call opcode_of
        pop rdi
        pop rdi
        cmp eax, OP_ADD
        jne 2f
        cmp dword ptr [rdi + N_AUX], 3
        jne 2f
        cmp qword ptr [rdi + N_DATA + 8], 63    # tagged 31
        jne 2f
        mov rsi, [rdi + N_DATA + 16]
        mov rdi, r13
        push rsi
        push rsi
        lea rsi, [rip + .Ls_ceil32]
        call sb_append_c
        pop rsi
        pop rsi
        mov rdi, r13
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        jmp 3f
2:      mov rdi, r13
        lea rsi, [rip + .Ls_floor32]
        call sb_append_c
        mov rdi, r13
        B rsi, 1 + 2
        PF_COLOR_OF rdx, r12
        call sb_append_pret
3:      mov rdi, r13
        mov esi, ')'
        call sb_append_char
        mov rdi, r13
        call sb_finish
        add rsp, 8
        ret
1:      xor eax, eax
        add rsp, 8
        ret

.Lpf_mask:
        cmp dword ptr [rbx + N_AUX], 4
        jne .Lpf_default
        # ('mask', size, 5, val) with size > 245: ceil32 / floor32
        PAT rsi, "('mask', ':size', 5, ':val')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        call .Lpf_floor32
        test rax, rax
        jz 1f
        jmp .Lpf_ret
1:      mov r13, [rbx + N_DATA + 8]     # size
        mov r14, [rbx + N_DATA + 24]    # val
        cmp qword ptr [rbx + N_DATA + 16], 1    # offset == 0
        jne 5f
        cmp r13, 513                    # size == 256
        jne 2f
        mov rdi, r14
        PF_COLOR_OF rsi, r12
        call prettify
        jmp .Lpf_ret
2:      mov rdi, r13
        call is_int
        test eax, eax
        jz 5f
        cmp r13, 511                    # tagged 255
        jne 3f
        lea rdi, [rip + .Ls_uint255]
        call str_new_c
        jmp 4f
3:      mov rdi, r13
        xor esi, esi
        call mask_to_type
        test rax, rax
        jz 5f
4:      # type(val)
        mov [rsp + PF_T1], rax
        call sb_new
        mov [rsp + PF_SB], rax
        lea rdi, [rip + .Ls_lparen]
        call str_new_c
        mov rsi, rax
        mov rdi, [rsp + PF_T1]
        call str_cat2
        mov rdi, rax
        lea rsi, [rip + C_GRAY]
        mov rdx, r12
        call colorize
        mov rdi, [rsp + PF_SB]
        mov rsi, rax
        call sb_append_str
        mov rdi, [rsp + PF_SB]
        mov rsi, r14
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, [rsp + PF_SB]
        lea rsi, [rip + .Ls_rparen]
        lea rdx, [rip + C_GRAY]
        mov rcx, r12
        call sb_append_col_c
        mov r13, [rsp + PF_SB]
        jmp .Lpf_finish
5:      # int size < 64 with offset 0: a modulo; else Mask(size, offset, val)
        mov rdi, r13
        call is_int
        test eax, eax
        jz 6f
        cmp qword ptr [rbx + N_DATA + 16], 1
        jne 6f
        mov rdi, r13
        mov rsi, 64
        TAG rsi
        call int_cmp
        cmp eax, -1
        jne 6f
        mov rdi, r13
        call int_to_i64
        mov rdi, rax
        call pow2
        mov rdx, rax
        mov rsi, r14
        LOADS rdi, MOD
        call mk3
        mov rdi, rax
        PF_COLOR_PARENS rsi, r12
        call prettify
        jmp .Lpf_ret
6:      call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_Mask_]
        call sb_append_c
        mov rdi, r13
        mov rsi, rbx
        mov edx, 1
        PF_COLOR_OF rcx, r12
        call sb_append_pret_join
        mov rdi, r13
        mov esi, ')'
        call sb_append_char
        jmp .Lpf_finish

.Lpf_not:
        cmp dword ptr [rbx + N_AUX], 2
        jne .Lpf_default
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + C_BOLD]
        call sb_append_c
        mov rdi, r13
        mov esi, '!'
        call sb_append_char
        mov rdi, r13
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        mov rdi, r13
        mov rsi, [rbx + N_DATA + 8]
        PF_FULL rdx, r12
        call sb_append_pret
        jmp .Lpf_finish

.Lpf_add:
        mov rdi, rbx
        mov rsi, r12
        call pretty_adds
        jmp .Lpf_ret

.Lpf_mul:
        # a multiplication by a big power of two is a shift
        cmp dword ptr [rbx + N_AUX], 3
        jne 1f
        mov rdi, [rbx + N_DATA + 8]
        call to_exp2
        cmp rax, 32
        jle 1f
        mov rdi, rax
        TAG rdi
        mov rsi, rdi
        mov rdx, [rbx + N_DATA + 16]
        LOADS rdi, SHL
        call mk3
        mov rbx, rax
        jmp .Lpf_arith
1:      cmp dword ptr [rbx + N_AUX], 3
        jb .Lpf_arith
        mov rax, [rbx + N_DATA + 8]
        cmp rax, -1                     # tagged -1
        jne 2f
        cmp dword ptr [rbx + N_AUX], 3
        jne 2f
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov esi, '-'
        call sb_append_char
        mov rdi, r13
        mov rsi, [rbx + N_DATA + 16]
        PF_COLOR_PARENS rdx, r12
        call sb_append_pret
        jmp .Lpf_finish
2:      cmp rax, 3                      # tagged 1
        jne .Lpf_arith
        cmp dword ptr [rbx + N_AUX], 3
        jne 3f
        mov rdi, [rbx + N_DATA + 16]
        PF_COLOR_PARENS rsi, r12
        call prettify
        jmp .Lpf_ret
3:      # ('mul', 1, a, b...) -> ('mul', a, b...)
        mov rdi, rbx
        mov esi, 2
        call list_from
        mov rdi, rax
        LOADS rsi, MUL
        call list_prepend
        mov rdi, rax
        call seq_to_tuple
        mov rdi, rax
        PF_COLOR_PARENS rsi, r12
        call prettify
        jmp .Lpf_ret

.Lpf_div:
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lpf_arith
        cmp qword ptr [rbx + N_DATA + 16], 3    # ('div', num, 1)
        jne .Lpf_arith
        mov rdi, [rbx + N_DATA + 8]
        PF_COLOR_PARENS rsi, r12
        call prettify
        jmp .Lpf_ret

.Lpf_exp:
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lpf_arith
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, [rbx + N_DATA + 8]
        PF_COLOR_OF rdx, r12
        or rdx, PF_PARENS
        call sb_append_pret
        mov rdi, r13
        mov esi, '^'
        call sb_append_char
        mov rdi, r13
        mov rsi, [rbx + N_DATA + 16]
        PF_COLOR_OF rdx, r12
        or rdx, PF_PARENS
        call sb_append_pret
        jmp .Lpf_finish

.Lpf_arith:
        mov rdi, rbx
        call opcode_of
        mov r13d, eax
        lea rcx, [rip + arith_ops]
        mov r14, [rcx + rax*8]          # the operator text
        test r14, r14
        jz .Lpf_default
        # shifts: the operands swapped
        cmp eax, OP_SHL
        je 1f
        cmp eax, OP_SHR
        jne 2f
1:      cmp dword ptr [rbx + N_AUX], 3
        jne 2f
        mov rdi, [rbx + N_DATA]
        mov rsi, [rbx + N_DATA + 16]
        mov rdx, [rbx + N_DATA + 8]
        call mk3
        mov rbx, rax
2:      call sb_new
        mov [rsp + PF_SB], rax
        # form: parentheses unless top level
        mov rax, r12
        and rax, PF_PARENS | PF_TOP
        cmp rax, PF_PARENS
        jne 3f
        mov rdi, [rsp + PF_SB]
        mov esi, '('
        call sb_append_char
3:      # the operator, bold when colored
        mov rdi, r14
        call str_new_c
        mov rdi, rax
        lea rsi, [rip + C_BOLD]
        mov rdx, r12
        call colorize
        mov [rsp + PF_T1], rax
        cmp r13d, OP_AND
        jne 4f
        mov rdi, rbx
        call fold_ands
        mov rbx, rax
        PF_COLOR_OF rcx, r12
        or rcx, PF_REM_BOOL
        jmp 5f
4:      PF_COLOR_OF rcx, r12
5:      mov rdi, [rsp + PF_SB]
        mov rsi, rbx
        mov rdx, [rsp + PF_T1]
        call sb_append_pret_join_str
        mov rax, r12
        and rax, PF_PARENS | PF_TOP
        cmp rax, PF_PARENS
        jne 6f
        mov rdi, [rsp + PF_SB]
        mov esi, ')'
        call sb_append_char
6:      mov r13, [rsp + PF_SB]
        jmp .Lpf_finish

.Lpf_iszero:
        cmp dword ptr [rbx + N_AUX], 2
        jne .Lpf_default
        mov r13, [rbx + N_DATA + 8]     # val
        mov rdi, r13
        call opcode_of
        test eax, eax
        jz 4f                           # (not a tuple)
        cmp dword ptr [r13 + N_AUX], 3
        jne 4f
        cmp eax, OP_GT
        je 1f
        cmp eax, OP_LT
        je 2f
        cmp eax, OP_EQ
        je 3f
        jmp 4f
1:      lea r14, [rip + .Ls_le]
        jmp 5f
2:      lea r14, [rip + .Ls_ge]
        jmp 5f
3:      # a != b, the constant on the right
        lea r14, [rip + .Ls_ne]
        mov rdi, [r13 + N_DATA + 8]
        call is_str
        test eax, eax
        jnz 31f
        mov rdi, [r13 + N_DATA + 8]
        call is_int
        test eax, eax
        jz 5f
31:     mov rdi, [r13 + N_DATA]
        mov rsi, [r13 + N_DATA + 16]
        mov rdx, [r13 + N_DATA + 8]
        call mk3
        mov r13, rax
5:      call sb_new
        mov [rsp + PF_SB], rax
        mov rdi, rax
        mov rsi, [r13 + N_DATA + 8]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, [rsp + PF_SB]
        mov rsi, r14
        call sb_append_c
        mov rdi, [rsp + PF_SB]
        mov rsi, [r13 + N_DATA + 16]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov r13, [rsp + PF_SB]
        jmp .Lpf_finish
4:      call sb_new
        mov r14, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_not_sp]
        call sb_append_c
        mov rdi, r14
        mov rsi, r13
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov r13, r14
        jmp .Lpf_finish

.Lpf_finish:
        mov rdi, r13
        call sb_finish
.Lpf_ret:
        add rsp, MATCH_BINDINGS_SIZE + 64
        LEAVE
ENDF prettify

# pow2_or_float(k) -> value: 2 ** k; for a negative k python has a float,
# printed as its decimal - that text (a string) stands for it here
FUNC pow2_or_float
        test rdi, rdi
        js 1f
        jmp pow2
1:      neg rdi
        cmp rdi, 8
        ja 2f
        lea rax, [rip + float_pow2]
        mov rdi, [rax + rdi*8]
        jmp str_intern_c                # (it goes into expressions)
2:      mov edi, E_NOT_IMPLEMENTED
        lea rsi, [rip + .Ls_float]
        jmp err_throw
ENDF pow2_or_float

        .section .rodata
.Ls_float: .asciz "prettify: a float below 2^-8"
.Lf_1: .asciz "0.5"
.Lf_2: .asciz "0.25"
.Lf_3: .asciz "0.125"
.Lf_4: .asciz "0.0625"
.Lf_5: .asciz "0.03125"
.Lf_6: .asciz "0.015625"
.Lf_7: .asciz "0.0078125"
.Lf_8: .asciz "0.00390625"
        .section .data.rel.ro
        .align 8
float_pow2:
        .quad 0, .Lf_1, .Lf_2, .Lf_3, .Lf_4, .Lf_5, .Lf_6, .Lf_7, .Lf_8
        .text

# sb_append_pret_join(sb, seq, start, flags): the elements of seq from
# `start` prettified and joined with ", "
FUNC sb_append_pret_join
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov r14, rcx
        mov [rsp], r13
1:      mov rcx, [rsp]
        cmp ecx, [r12 + N_AUX]
        jae 2f
        cmp rcx, r13
        je 3f
        mov rdi, rbx
        lea rsi, [rip + .Ls_comma_sp]
        call sb_append_c
3:      mov rcx, [rsp]
        mov rdi, rbx
        mov rsi, [r12 + N_DATA + rcx*8]
        mov rdx, r14
        call sb_append_pret
        inc qword ptr [rsp]
        jmp 1b
2:      add rsp, 16
        LEAVE
ENDF sb_append_pret_join

# sb_append_pret_join_str(sb, tuple, sep_str, flags): the elements after
# the head prettified and joined with a string
FUNC sb_append_pret_join_str
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov r14, rcx
        mov qword ptr [rsp], 1
1:      mov rcx, [rsp]
        cmp ecx, [r12 + N_AUX]
        jae 2f
        cmp rcx, 1
        je 3f
        mov rdi, rbx
        mov rsi, r13
        call sb_append_str
3:      mov rcx, [rsp]
        mov rdi, rbx
        mov rsi, [r12 + N_DATA + rcx*8]
        mov rdx, r14
        call sb_append_pret
        inc qword ptr [rsp]
        jmp 1b
2:      add rsp, 16
        LEAVE
ENDF sb_append_pret_join_str

# fold_ands(exp) -> ('and', ...) with the nested ands flattened
FUNC fold_ands
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        mov rdi, rax
        LOADS rsi, AND
        call vec_push
        mov r13d, 1
1:      cmp r13d, [rbx + N_AUX]
        jae 3f
        mov r14, [rbx + N_DATA + r13*8]
        mov rdi, r14
        call opcode_of
        cmp eax, OP_AND
        jne 2f
        mov rdi, r14
        call fold_ands
        mov edx, [rax + N_AUX]
        dec edx
        lea rsi, [rax + N_DATA + 8]
        mov rdi, r12
        call vec_extend
        jmp 4f
2:      mov rdi, r12
        mov rsi, r14
        call vec_push
4:      inc r13d
        jmp 1b
3:      mov rdi, r12
        call vec_to_tuple
        LEAVE
ENDF fold_ands

# seq_to_tuple(list_or_tuple) -> tuple
FUNC seq_to_tuple
        mov esi, [rdi + N_AUX]
        lea rdx, [rdi + N_DATA]
        mov rdi, rsi
        mov rsi, rdx
        jmp mk_tuple
ENDF seq_to_tuple

# pretty_adds(exp, flags) -> str: an ('add', ...) as a sum, the constant
# term last
FUNC pretty_adds
        ENTER
        sub rsp, 32
        .set PA_SB, 0
        .set PA_REAL, 8
        .set PA_I, 16
        mov rbx, rdi
        mov r12, rsi
        call sb_new
        mov [rsp + PA_SB], rax
        cmp dword ptr [rbx + N_AUX], 2
        jb .Lpa_symbolic_only
        mov rdi, [rbx + N_DATA + 8]
        call is_int
        test eax, eax
        jz .Lpa_symbolic_only
        # real = to_real_int(exp[1]); the symbolic terms joined, then
        # " + real" or " - (-real)"
        mov rdi, [rbx + N_DATA + 8]
        call to_real_int
        mov [rsp + PA_REAL], rax
        mov qword ptr [rsp + PA_I], 2
1:      mov rcx, [rsp + PA_I]
        cmp ecx, [rbx + N_AUX]
        jae 2f
        cmp rcx, 2
        je 3f
        mov rdi, [rsp + PA_SB]
        lea rsi, [rip + .Ls_plus]
        call sb_append_c
3:      mov rcx, [rsp + PA_I]
        mov rdi, [rsp + PA_SB]
        mov rsi, [rbx + N_DATA + rcx*8]
        PF_FULL rdx, r12
        call sb_append_pret
        inc qword ptr [rsp + PA_I]
        jmp 1b
2:      mov rdi, [rsp + PA_REAL]
        call int_sign
        test eax, eax
        jz .Lpa_parens
        cmp eax, 1
        jne 4f
        mov rdi, [rsp + PA_SB]
        lea rsi, [rip + .Ls_plus]
        call sb_append_c
        mov rdi, [rsp + PA_SB]
        mov rsi, [rsp + PA_REAL]
        mov edx, PF_PARENS              # (prettify's default: no color, parentheses)
        call sb_append_pret
        jmp .Lpa_parens
4:      mov rdi, [rsp + PA_SB]
        lea rsi, [rip + .Ls_minus]
        call sb_append_c
        mov rdi, [rsp + PA_REAL]
        call int_neg
        mov rdi, [rsp + PA_SB]
        mov rsi, rax
        mov edx, PF_PARENS
        call sb_append_pret
        jmp .Lpa_parens
.Lpa_symbolic_only:
        # the terms one by one, " - x" for the ('mul', -n, ...) ones
        mov qword ptr [rsp + PA_I], 1
5:      mov rcx, [rsp + PA_I]
        cmp ecx, [rbx + N_AUX]
        jae .Lpa_parens
        mov r13, [rbx + N_DATA + rcx*8]
        mov rax, [rsp + PA_SB]
        cmp qword ptr [rax + SB_LEN], 0
        jne 6f
        mov rdi, rax
        mov rsi, r13
        PF_FULL rdx, r12
        call sb_append_pret
        jmp 8f
6:      mov rdi, r13
        call opcode_of
        cmp eax, OP_MUL
        jne 7f
        cmp dword ptr [r13 + N_AUX], 2
        jb 7f
        mov rdi, [r13 + N_DATA + 8]
        call is_int
        test eax, eax
        jz 7f
        mov rdi, [r13 + N_DATA + 8]
        call int_sign
        cmp eax, -1
        jne 7f
        mov rdi, [rsp + PA_SB]
        lea rsi, [rip + .Ls_minus]
        call sb_append_c
        mov rdi, r13
        call alg_minus_op
        mov rdi, [rsp + PA_SB]
        mov rsi, rax
        PF_FULL rdx, r12
        call sb_append_pret
        jmp 8f
7:      mov rdi, [rsp + PA_SB]
        lea rsi, [rip + .Ls_plus]
        call sb_append_c
        mov rdi, [rsp + PA_SB]
        mov rsi, r13
        PF_FULL rdx, r12
        call sb_append_pret
8:      inc qword ptr [rsp + PA_I]
        jmp 5b
.Lpa_parens:
        test r12, PF_PARENS
        jz 9f
        # "(" + res + ")"
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov esi, '('
        call sb_append_char
        mov rax, [rsp + PA_SB]
        mov rdi, r13
        mov rsi, [rax + SB_BUF]
        mov rdx, [rax + SB_LEN]
        call sb_append
        mov rdi, r13
        mov esi, ')'
        call sb_append_char
        mov rdi, [rsp + PA_SB]
        call sb_free
        mov rdi, r13
        call sb_finish
        add rsp, 32
        LEAVE
9:      mov rdi, [rsp + PA_SB]
        call sb_finish
        add rsp, 32
        LEAVE
ENDF pretty_adds

# --- numbers ---

# pretty_num(v, flags) -> str: an integer as text - hex for the big ones,
# multiples of powers of ten as such, function signatures, and negative
# numbers for the ones with the top bit set
FUNC pretty_num
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rbx
        call is_int
        test eax, eax
        jz .Lpn_str
        # above 8 ** 50: binary data, in hex
        mov edi, 150
        call pow2
        mov rdi, rbx
        mov rsi, rax
        call int_cmp
        cmp eax, 1
        je .Lpn_hex
        cmp rbx, 1                      # zero
        je .Lpn_plain
        # a multiple of 10^18 .. 10^9, or of 10^6
        mov r13d, 18
1:      mov edi, r13d
        call ten_pow
        mov r14, rax
        mov rdi, rbx
        mov rsi, rax
        call int_mod
        cmp rax, 1
        je .Lpn_pow10
        dec r13d
        cmp r13d, 9
        jae 1b
        mov r13d, 6
        mov edi, r13d
        call ten_pow
        mov r14, rax
        mov rdi, rbx
        mov rsi, rax
        call int_mod
        cmp rax, 1
        je .Lpn_pow10
.Lpn_plain:
        mov rdi, rbx
        mov rsi, r12
        call try_fname
        test rax, rax
        jnz .Lpn_ret
        # below 8 ** 30 modulo 2^256: a (possibly negative) number; else hex
        mov rdi, rbx
        mov esi, 256
        call int_mod_2exp
        mov r13, rax
        mov edi, 90
        call pow2
        mov rdi, r13
        mov rsi, rax
        call int_cmp
        cmp eax, -1
        jne 2f
        mov rdi, rbx
        call to_real_int
        mov rdi, rax
        call .Lpn_decimal
        jmp .Lpn_ret
2:      mov rdi, rbx
        call int_sign
        cmp eax, 1
        je .Lpn_hex
.Lpn_str:
        mov rdi, rbx
        call .Lpn_decimal
        jmp .Lpn_ret
.Lpn_hex:
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, rbx
        mov edx, 16
        call sb_append_int
        mov rdi, r13
        call sb_finish
        jmp .Lpn_ret
.Lpn_pow10:
        # "10^count" or "q * 10^count"
        mov rdi, rbx
        mov rsi, r14
        call int_floordiv
        mov r14, rax
        call sb_new
        mov [rsp], rax
        cmp r14, 3                      # q == 1
        je 3f
        mov rdi, rax
        mov rsi, r14
        mov edx, 10
        call sb_append_int
        mov rdi, [rsp]
        lea rsi, [rip + .Ls_times_10pow]
        call sb_append_c
        jmp 4f
3:      mov rdi, rax
        lea rsi, [rip + .Ls_10pow]
        call sb_append_c
4:      mov rdi, [rsp]
        mov esi, r13d
        call sb_append_u64
        mov rdi, [rsp]
        call sb_finish
.Lpn_ret:
        add rsp, 16
        LEAVE

# a local: str(v) - decimal for ints, the repr of anything else
.Lpn_decimal:
        sub rsp, 8
        call value_str
        add rsp, 8
        ret
ENDF pretty_num

# ten_pow(n) -> value: 10 ** n
FUNC ten_pow
        ENTER
        mov rbx, rdi
        lea rdi, [r15 + CTX_MPZ_R]
        mov esi, 10
        mov rdx, rbx
        call __gmpz_ui_pow_ui@PLT
        call arith_result
        LEAVE
ENDF ten_pow

# pretty_bignum_int(v) -> str or 0: helpers.pretty_bignum - an integer
# whose bytes are all printable (the zero bytes skipped) as a quoted
# string
FUNC pretty_bignum_int
        ENTER
        sub rsp, 48
        mov rbx, rdi
        call is_int
        test eax, eax
        jz .Lpb_none
        # the signed message prefix, a special case
        lea rdi, [rip + .Ls_signed_prefix_hex]
        call parse_hex_int
        mov rdi, rbx
        mov rsi, rax
        call values_equal
        test eax, eax
        jz 1f
        lea rdi, [rip + .Ls_signed_message]
        call str_new_c
        jmp .Lpb_ret
1:      # the bytes, big endian (mpz_export), for a positive number
        mov rdi, rbx
        call int_sign
        cmp eax, 1
        jne .Lpb_empty
        mov rdi, rbx
        call value_mpz
        mov r12, rax
        mov rdi, rax
        mov esi, 2
        call __gmpz_sizeinbase@PLT
        add rax, 7
        shr rax, 3
        mov r13, rax                    # the byte count
        mov rdi, rax
        call arena_alloc
        mov r14, rax
        # mpz_export(rop, countp, order=1, size=1, endian=1, nails=0, op)
        mov rdi, r14
        lea rsi, [rsp]
        mov edx, 1
        mov ecx, 1
        mov r8d, 1
        xor r9d, r9d
        push r12
        push r12
        call __gmpz_export@PLT
        pop r12
        pop r12
        mov r13, [rsp]
        # every non-zero byte printable?
        xor ecx, ecx
2:      cmp rcx, r13
        jae 3f
        movzx eax, byte ptr [r14 + rcx]
        inc rcx
        test al, al
        jz 2b
        cmp al, 0x20
        jb 4f
        cmp al, 0x7e
        jbe 2b
        jmp .Lpb_none
4:      cmp al, 0x09
        jb .Lpb_none
        cmp al, 0x0d
        jbe 2b
        jmp .Lpb_none
3:      call sb_new
        mov r12, rax
        mov rdi, rax
        mov esi, '\''
        call sb_append_char
        xor ecx, ecx
5:      cmp rcx, r13
        jae 6f
        movzx esi, byte ptr [r14 + rcx]
        inc rcx
        test sil, sil
        jz 5b
        mov [rsp + 8], rcx
        mov rdi, r12
        call sb_append_char
        mov rcx, [rsp + 8]
        jmp 5b
6:      mov rdi, r12
        mov esi, '\''
        call sb_append_char
        mov rdi, r12
        call sb_finish
        jmp .Lpb_ret
.Lpb_empty:
        lea rdi, [rip + .Ls_two_quotes]
        call str_new_c
        jmp .Lpb_ret
.Lpb_none:
        xor eax, eax
.Lpb_ret:
        add rsp, 48
        LEAVE
ENDF pretty_bignum_int

        .section .rodata
.Ls_signed_prefix_hex: .asciz "19457468657265756d205369676e6564204d6573736167653a0a333200000000"
.Ls_two_quotes: .asciz "''"
        .text

# parse_hex_int(cstr) -> value: an integer from its hex digits
FUNC parse_hex_int
        ENTER
        mov rbx, rdi
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rbx
        mov edx, 16
        call __gmpz_set_str@PLT
        call arith_result
        LEAVE
ENDF parse_hex_int

# --- memory, function names, gas ---

# unmask(v) -> value: the value under a mask_shl
FUNC unmask
        ENTER
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_MASK_SHL
        jne 1f
        cmp dword ptr [rbx + N_AUX], 5
        jne 1f
        mov rax, [rbx + N_DATA + 32]
        LEAVE
1:      mov rax, rbx
        LEAVE
ENDF unmask

# pretty_memory(exp, flags) -> list of str: the terms of a ('data', ...)
# as text, the strings among them merged (python returns a bare string
# for "mem" and for no terms, which its callers iterate: those come back
# as lists of their characters)
FUNC pretty_memory
        ENTER
        sub rsp, 48
        .set PM_OUT, 0
        .set PM_IDX, 8
        .set PM_STR, 16                 # the string being merged (an sb), or 0
        .set PM_BYTES, 24               # its byte length
        .set PM_I, 32
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rbx
        call is_none
        test eax, eax
        jz 1f
        xor edi, edi
        xor esi, esi
        call mk_list
        jmp .Lpm_ret
1:      LOADS rax, MEM
        cmp rbx, rax
        jne 2f
        mov rdi, rbx
        mov rsi, r12
        call prettify
        mov rdi, rax
        call str_chars
        jmp .Lpm_ret
2:      mov rdi, rbx
        call opcode_of
        cmp eax, OP_DATA
        je 3f
        mov rdi, rbx
        PF_FULL rsi, r12
        call prettify
        mov rdi, rax
        call mk_list1
        jmp .Lpm_ret
3:      cmp dword ptr [rbx + N_AUX], 1
        jne 4f
        lea rdi, [rip + .Ls_empty_call]
        call str_new_c
        mov rdi, rax
        call str_chars
        jmp .Lpm_ret
4:      call vec_new
        mov [rsp + PM_OUT], rax
        mov qword ptr [rsp + PM_IDX], 1         # (exp[1:] in python: our idx is 1-based)
.Lpm_loop:
        mov rcx, [rsp + PM_IDX]
        cmp ecx, [rbx + N_AUX]
        jae .Lpm_done
        mov r13, [rbx + N_DATA + rcx*8]         # el
        cmp rcx, 1
        jne 5f
        # the first term as a selector: ('mask_shl', 32, 224, 0, int)
        PAT rsi, "('mask_shl', 32, 224, 0, ':int:v')"
        mov rdi, r13
        lea rdx, [rsp + 40]             # one binding
        call pat_match
        test eax, eax
        jz 5f
        mov rdi, [rsp + 40]
        mov rsi, 224
        TAG rsi
        call int_shr
        mov rdi, rax
        mov rsi, r12
        xor edx, edx
        call pretty_fname
        mov rdi, [rsp + PM_OUT]
        mov rsi, rax
        call vec_push
        inc qword ptr [rsp + PM_IDX]
        jmp .Lpm_loop
5:      mov qword ptr [rsp + PM_STR], 0
        mov rdi, r13
        call unmask
        cmp rax, 65                     # 32
        jne .Lpm_plain
        mov rcx, [rsp + PM_IDX]
        inc rcx
        cmp ecx, [rbx + N_AUX]
        jae .Lpm_plain
        mov rdi, [rbx + N_DATA + rcx*8]
        call unmask
        mov r14, rax                    # length
        mov rdi, rax
        call is_int
        test eax, eax
        jz .Lpm_plain
        # byte_length = ((length - 1) >> 5) + 1
        mov rdi, r14
        mov rsi, 3
        call int_sub
        mov rdi, rax
        mov rsi, 5
        TAG rsi
        call int_shr
        mov rdi, rax
        mov rsi, 3
        call int_add
        mov rdi, rax
        call int_to_i64
        test rax, rax
        js .Lpm_plain                   # (python would go backwards)
        mov [rsp + PM_BYTES], rax
        mov rcx, [rsp + PM_IDX]
        add rcx, rax
        inc rcx                         # idx + 1 + byte_length (0-based: our idx is 1-based, see below)
        cmp ecx, [rbx + N_AUX]
        jae .Lpm_plain
        call sb_new
        mov [rsp + PM_STR], rax
        mov qword ptr [rsp + PM_I], 0
6:      mov rax, [rsp + PM_I]
        cmp rax, [rsp + PM_BYTES]
        jae 8f
        mov rcx, [rsp + PM_IDX]
        add rcx, rax
        mov rdi, [rbx + N_DATA + rcx*8 + 16]    # exp[idx + 2 + i]
        call unmask
        mov r14, rax
        mov rdi, rax
        call is_str
        test eax, eax
        jnz 7f
        mov rdi, r14
        call pretty_bignum_int
        test rax, rax
        jz 9f
        mov r14, rax
7:      # the text without its quotes
        mov rdi, [rsp + PM_STR]
        lea rsi, [r14 + N_DATA + 4 + 1]
        mov edx, [r14 + N_DATA]
        sub edx, 2
        js 61f
        call sb_append
61:     inc qword ptr [rsp + PM_I]
        jmp 6b
9:      mov rdi, [rsp + PM_STR]
        call sb_free
        mov qword ptr [rsp + PM_STR], 0
        jmp .Lpm_plain
8:      # a string: "'" + text + "'", and the terms it took are skipped
        mov rax, [rsp + PM_BYTES]
        inc rax
        add [rsp + PM_IDX], rax
        call sb_new
        mov r14, rax
        mov rdi, rax
        mov esi, '\''
        call sb_append_char
        mov rax, [rsp + PM_STR]
        mov rdi, r14
        mov rsi, [rax + SB_BUF]
        mov rdx, [rax + SB_LEN]
        call sb_append
        mov rdi, r14
        mov esi, '\''
        call sb_append_char
        mov rdi, [rsp + PM_STR]
        call sb_free
        mov rdi, r14
        call sb_finish
        mov rdi, [rsp + PM_OUT]
        mov rsi, rax
        call vec_push
        inc qword ptr [rsp + PM_IDX]
        jmp .Lpm_loop
.Lpm_plain:
        mov rdi, r13
        PF_COLOR_OF rsi, r12
        call prettify
        mov rdi, [rsp + PM_OUT]
        mov rsi, rax
        call vec_push
        inc qword ptr [rsp + PM_IDX]
        jmp .Lpm_loop
.Lpm_done:
        mov rdi, [rsp + PM_OUT]
        call vec_to_list
.Lpm_ret:
        add rsp, 48
        LEAVE
ENDF pretty_memory

# pretty_fname(v, flags, force) -> value: a function name for a selector
# (its hex when unknown), the text of a memory reference (or of anything
# when force), else v itself
FUNC pretty_fname
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        call is_int
        test eax, eax
        jz 2f
        mov rdi, rbx
        mov rsi, r12
        call try_fname
        test rax, rax
        jz 1f
        mov rdi, rax
        push rax
        push rax
        lea rsi, [rip + .Ls_unknown_]
        call str_contains_c
        pop rdi
        pop rdi
        test eax, eax
        jnz 1f
        mov rax, rdi
        LEAVE
1:      call sb_new
        mov r12, rax
        mov rdi, rax
        mov rsi, rbx
        mov edx, 16
        call sb_append_int
        mov rdi, r12
        call sb_finish
        LEAVE
2:      test r13, r13
        jnz 4f
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_MEM
        jne 5f
4:      mov rdi, rbx
        PF_FULL rsi, r12
        call prettify
        LEAVE
5:      mov rax, rbx
        LEAVE
ENDF pretty_fname

        .section .rodata
.Ls_unknown_: .asciz "unknown_"
        .text

# pretty_gas(gas, value, flags) -> str
FUNC pretty_gas
        ENTER
        mov rbx, rdi
        mov r12, rdx
        PAT rsi, "('mul', 2300, ('iszero', 'Any'))"
        mov rdi, rbx
        xor edx, edx
        call pat_match_nobind
        test eax, eax
        jz 1f
        lea rdi, [rip + .Ls_2300]
        call str_new_c
        LEAVE
1:      mov rdi, rbx
        PF_COLOR_OF rsi, r12
        call prettify
        LEAVE
ENDF pretty_gas

# pat_match_nobind(exp, pattern, 0) -> eax: a match with no bindings kept
FUNC pat_match_nobind
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rdx, rsp
        call pat_match
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
ENDF pat_match_nobind

# --- storage and types ---

# pretty_stor(exp, flags) -> str
FUNC pretty_stor
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 32
        .set PS_SB, MATCH_BINDINGS_SIZE
        .set PS_T1, MATCH_BINDINGS_SIZE + 8
        mov rbx, rdi
        mov r12, rsi
        PAT rsi, "('stor', ('length', ':idx'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        B rdi, 0
        call .Lps_stor
        mov rdi, rax
        lea rsi, [rip + .Ls_dot_length]
        jmp .Lps_cat_green
1:      PAT rsi, "('loc', ':loc')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_stor_l]
        call sb_append_c
        B rdi, 0
        call value_str
        mov rdi, r13
        mov rsi, rax
        call sb_append_str
        mov rdi, r13
        call sb_finish
        mov rdi, rax
        jmp .Lps_green
2:      PAT rsi, "('name', ':name', ':loc')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 3f
        B rdi, 0
        call value_str
        mov rdi, rax
        jmp .Lps_green
3:      PAT rsi, "('stor', ':loc')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 4f
        B rdi, 0
        call .Lps_stor
        jmp .Lps_ret
4:      PAT rsi, "('field', ':off', ':loc')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 5f
        B rdi, 1
        call .Lps_stor
        mov r13, rax
        call sb_new
        mov r14, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_dot_field_]
        call sb_append_c
        mov rdi, r14
        B rsi, 0
        xor edx, edx
        call sb_append_pret
        mov rdi, r14
        call sb_finish
        mov rdi, rax
        lea rsi, [rip + C_GREEN]
        mov rdx, r12
        call colorize
        mov rdi, r13
        mov rsi, rax
        call str_cat2
        jmp .Lps_ret
5:      PAT rsi, "('type', ':size', ':loc')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 6f
        B rdi, 1
        call .Lps_stor
        mov r13, rax
        cmp qword ptr [rsp], 513        # size == 256
        jne 51f
        call sb_new
        mov r14, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_uint256_]
        lea rdx, [rip + C_GRAY]
        mov rcx, r12
        call sb_append_col_c
        mov rdi, r14
        mov rsi, r13
        call sb_append_str
        mov rdi, r14
        lea rsi, [rip + .Ls_rparen]
        lea rdx, [rip + C_GRAY]
        mov rcx, r12
        call sb_append_col_c
        mov rdi, r14
        call sb_finish
        jmp .Lps_ret
51:     # pret(('mask', size, 0, stor(loc)))
        B rsi, 0
        mov edx, 1
        mov rcx, r13
        LOADS rdi, MASK
        call mk4
        mov rdi, rax
        PF_COLOR_OF rsi, r12
        call prettify
        jmp .Lps_ret
6:      PAT rsi, "('map', ':idx', ':var')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jnz .Lps_index
        PAT rsi, "('array', ('mul', ':int:any', ':idx'), ':var')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 7f
        # ('array', idx, var) - the multiplier of a struct's index dropped
        B rsi, 1
        B rdx, 2
        LOADS rdi, ARRAY
        call mk3
        mov rbx, rax
7:      PAT rsi, "('array', ':idx', ':var')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jnz .Lps_index
        PAT rsi, "('length', ':var')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 8f
        B rdi, 0
        call .Lps_stor
        mov rdi, rax
        lea rsi, [rip + .Ls_dot_length]
        jmp .Lps_cat_green
8:      PAT rsi, "('stor', ':size', ':off', ':loc')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 9f
        # pret(('mask', size, off, "stor[" + pret(loc) + "]"))
        B rdi, 2
        call .Lps_bracketed
        B rsi, 0
        B rdx, 1
        mov rcx, rax
        LOADS rdi, MASK
        call mk4
        mov rdi, rax
        PF_COLOR_OF rsi, r12
        call prettify
        jmp .Lps_ret
9:      mov rdi, rbx
        call .Lps_bracketed
        jmp .Lps_ret
.Lps_index:
        # stor(var) + "[" + pr_idx(idx) + "]"
        B rdi, 1
        call .Lps_stor
        mov r13, rax
        call sb_new
        mov r14, rax
        mov rdi, rax
        mov rsi, r13
        call sb_append_str
        mov rdi, r14
        lea rsi, [rip + .Ls_lbracket]
        lea rdx, [rip + C_GREEN]
        mov rcx, r12
        call sb_append_col_c
        B rdi, 0
        call .Lps_pr_idx
        mov rdi, r14
        mov rsi, rax
        call sb_append_str
        mov rdi, r14
        lea rsi, [rip + .Ls_rbracket]
        lea rdx, [rip + C_GREEN]
        mov rcx, r12
        call sb_append_col_c
        mov rdi, r14
        call sb_finish
        jmp .Lps_ret
.Lps_cat_green:
        # rdi (str) + colorize(rsi (cstr), GREEN)
        mov r13, rdi
        mov rdi, rsi
        lea rsi, [rip + C_GREEN]
        mov rdx, r12
        call colorize_c
        mov rdi, r13
        mov rsi, rax
        call str_cat2
        jmp .Lps_ret
.Lps_green:
        lea rsi, [rip + C_GREEN]
        mov rdx, r12
        call colorize
.Lps_ret:
        add rsp, MATCH_BINDINGS_SIZE + 32
        LEAVE

# locals of pretty_stor (r12 = flags): stor(x), pr_idx(idx), and
# col("stor[") + pret(x) + col("]")
.Lps_stor:
        sub rsp, 8
        mov rsi, r12
        call pretty_stor
        add rsp, 8
        ret
.Lps_pr_idx:
        sub rsp, 24
        mov [rsp], rdi
        call opcode_of
        cmp eax, OP_DATA
        jne 1f
        # the terms joined with "]["
        lea rdi, [rip + .Ls_index_sep]
        lea rsi, [rip + C_GREEN]
        mov rdx, r12
        call colorize_c
        mov [rsp + 8], rax
        call sb_new
        mov [rsp + 16], rax
        mov rdi, rax
        mov rsi, [rsp]
        mov rdx, [rsp + 8]
        PF_COLOR_OF rcx, r12
        call sb_append_pret_join_str
        mov rdi, [rsp + 16]
        call sb_finish
        add rsp, 24
        ret
1:      mov rdi, [rsp]
        PF_COLOR_OF rsi, r12
        call prettify
        add rsp, 24
        ret
.Lps_bracketed:
        sub rsp, 24
        mov [rsp], rdi
        call sb_new
        mov [rsp + 8], rax
        mov rdi, rax
        lea rsi, [rip + .Ls_stor_]
        lea rdx, [rip + C_GREEN]
        mov rcx, r12
        call sb_append_col_c
        mov rdi, [rsp + 8]
        mov rsi, [rsp]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, [rsp + 8]
        lea rsi, [rip + .Ls_rbracket]
        lea rdx, [rip + C_GREEN]
        mov rcx, r12
        call sb_append_col_c
        mov rdi, [rsp + 8]
        call sb_finish
        add rsp, 24
        ret
ENDF pretty_stor

        .section .rodata
.Ls_dot_length: .asciz ".length"
.Ls_stor_l:     .asciz "stor_l"
.Ls_dot_field_: .asciz ".field_"
.Ls_uint256_:   .asciz "uint256("
.Ls_index_sep:  .asciz "]["
.Ls_stor_:      .asciz "stor["
        .text

# pretty_type(t) -> str: a storage definition ('def', name, loc, type)
# or a type
FUNC pretty_type
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 32
        .set PT_SB, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        PAT rsi, "('def', ':name', ':loc', ('mask', ':size', ':off'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        # the definition with the size, then " offset n" in gray
        B rsi, 0
        B rdx, 1
        B rcx, 2
        LOADS rdi, DEF
        call mk4
        mov rdi, rax
        call pretty_type
        mov r12, rax
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, r12
        call sb_append_str
        mov rdi, r13
        lea rsi, [rip + C_GRAY]
        call sb_append_c
        B rdi, 3
        call int_sign
        cmp eax, 1
        jne 11f
        mov rdi, r13
        lea rsi, [rip + .Ls_offset_]
        call sb_append_c
        mov rdi, r13
        B rsi, 3
        mov edx, 10
        call sb_append_int
11:     mov rdi, r13
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        jmp .Lpt_finish
1:      PAT rsi, "('def', ':name', ':loc', ':bts')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        # "  {GREEN}{name}{ENDC} is {type} {GRAY}at storage {loc}{ENDC}"
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_two_spaces]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + C_GREEN]
        call sb_append_c
        B rdi, 0
        call value_str
        mov rdi, r13
        mov rsi, rax
        call sb_append_str
        mov rdi, r13
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + .Ls_is_]
        call sb_append_c
        B rdi, 2
        call pretty_type
        mov rdi, r13
        mov rsi, rax
        call sb_append_str
        mov rdi, r13
        mov esi, ' '
        call sb_append_char
        mov rdi, r13
        lea rsi, [rip + C_GRAY]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + .Ls_at_storage_]
        call sb_append_c
        # loc: hex above 1000
        B rdi, 1
        call is_int
        test eax, eax
        jz 12f
        B rdi, 1
        mov rsi, 1000
        TAG rsi
        call int_cmp
        cmp eax, 1
        jne 12f
        mov rdi, r13
        B rsi, 1
        mov edx, 16
        call sb_append_int
        jmp 13f
12:     B rdi, 1
        call value_str
        mov rdi, r13
        mov rsi, rax
        call sb_append_str
13:     mov rdi, r13
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        jmp .Lpt_finish
2:      PAT rsi, "('struct', 1)"
        mov rdi, rbx
        call pat_match_nobind
        test eax, eax
        jnz 3f
        LOADS rax, STRUCT
        cmp rbx, rax
        jne 4f
3:      lea rdi, [rip + .Ls_struct]
        call str_new_c
        jmp .Lpt_ret
4:      PAT rsi, "('struct', ':int:num')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 5f
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_struct_]
        call sb_append_c
        mov rdi, r13
        B rsi, 0
        mov edx, 10
        call sb_append_int
        mov rdi, r13
        lea rsi, [rip + .Ls_bytes]
        call sb_append_c
        jmp .Lpt_finish
5:      PAT rsi, "('array', ':bts')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 6f
        lea r12, [rip + .Ls_array_of]
        jmp 7f
6:      PAT rsi, "('mapping', ':bts')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 8f
        lea r12, [rip + .Ls_mapping_of]
7:      call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, r12
        call sb_append_c
        B rdi, 0
        call pretty_type
        mov rdi, r13
        mov rsi, rax
        call sb_append_str
        jmp .Lpt_finish
8:      mov rdi, rbx
        call is_int
        test eax, eax
        jz .Lpt_assert
        mov rdi, rbx
        mov esi, 1
        call mask_to_type
        jmp .Lpt_ret
.Lpt_finish:
        mov rdi, r13
        call sb_finish
.Lpt_ret:
        add rsp, MATCH_BINDINGS_SIZE + 32
        LEAVE
.Lpt_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_unknown_type]
        call err_throw
ENDF pretty_type

        .section .rodata
.Ls_offset_:     .asciz " offset "
.Ls_two_spaces:  .asciz "  "
.Ls_is_:         .asciz " is "
.Ls_at_storage_: .asciz "at storage "
.Ls_struct:      .asciz "struct"
.Ls_struct_:     .asciz "struct "
.Ls_bytes:       .asciz " bytes"
.Ls_array_of:    .asciz "array of "
.Ls_mapping_of:  .asciz "mapping of "
.Ls_unknown_type: .asciz "pretty_type: unknown type"

        .section .note.GNU-stack,"",@progbits
