# Expressions as text (port of prettify.py's prettify and its helpers).
# Every function here returns an arena string (rt_str.s str_new): the
# text is built, appended to, and freed with the thread's arena.
#
# prettify(exp, flags) -> str, with the flags PF_REM_BOOL (rem_bool),
# PF_PARENS (parentheses=True), PF_TOP (top_level), PF_COLOR (add_color)
# and a precedence in PF_CTX_MASK (parentheses=<that precedence>).
#
# As python's, an expression is in parentheses when its operator binds
# less tightly than where it is printed needs: `ctx`, from the flags
# (python's context(): 0 for a whole line, an argument, a subscript -
# parentheses False or top_level -, P_ATOM for parentheses=True, else the
# precedence given), and wrap(text, prec) adds them when prec < ctx.
# python's `pret` is prettify with parentheses=False (the flags with only
# PF_COLOR kept), `operand(e, prec)` prettify with parentheses=prec.

.include "defs.inc"

        .section .rodata
.Ls_comma_sp:   .asciz ", "
.Ls_len:        .asciz "len"
.Ls_sp_len_sp:  .asciz " len "
.Ls_array_len:  .asciz "Array(len="
.Ls_data_eq:    .asciz ", data="
.Ls_rparen:     .asciz ")"
.Ls_lbracket:   .asciz "["
.Ls_rbracket:   .asciz "]"
.Ls_True:       .asciz "True"
.Ls_False:      .asciz "False"
.Ls_code_data:  .asciz "code.data["
.Ls_ceil32:     .asciz "ceil32("
.Ls_floor32:    .asciz "floor32("
.Ls_all:        .asciz "all"
.Ls_call_func_hash: .asciz "call.func_hash"
.Ls_sp_shr224:  .asciz " >> 224"
.Ls_cd_:        .asciz "cd["
.Ls_var:        .asciz "var"
.Ls_mem_:       .asciz "mem["
.Ls_eq_sp:      .asciz " = "
.Ls_uint255:    .asciz "uint255"
.Ls_uint:       .asciz "uint"
.Ls_int:        .asciz "int"
.Ls_address:    .asciz "address"
.Ls_bool_:      .asciz "bool("
.Ls_Mask_:      .asciz "Mask("
.Ls_shift_:     .asciz "shift("
.Ls_signextend_: .asciz "signextend("
.Ls_concat_:    .asciz "concat("
.Ls_ext_code_:  .asciz "ext_code("
.Ls_dot_data_:  .asciz ").data["
.Ls_transient_: .asciz "transient["
.Ls_all_br:     .asciz "[all]"
.Ls_tilde:      .asciz "~"
.Ls_le:         .asciz " <= "
.Ls_ge:         .asciz " >= "
.Ls_ne:         .asciz " != "
.Ls_not_sp:     .asciz "not "
.Ls_pow:        .asciz "**"
.Ls_10pow:      .asciz "10**"
.Ls_times_10pow: .asciz " * 10**"
.Ls_star_sp:    .asciz " * "
.Ls_caller:     .asciz "caller"
.Ls_tx_origin:  .asciz "tx.origin"
.Ls_sar_op:     .asciz " >>\xe2\x80\xb2 "
.Ls_shr_op:     .asciz " >> "
.Ls_mod_op:     .asciz " % "
.Ls_and_op:     .asciz " and "
.Ls_or_op:      .asciz " or "
.Ls_mod2:       .asciz "2"
.Ls_minus_sp:   .asciz " - "
.Ls_plus_sp:    .asciz " + "
.Ls_block_hash: .asciz "block.hash("
.Ls_ext_hash:   .asciz "ext_code.hash("
.Ls_ext_size:   .asciz "ext_code.size("
.Ls_eth_balance: .asciz "eth.balance("
.Ls_blobhash_:  .asciz "blobhash("
.Ls_signed_message: .asciz "'\\x19Ethereum Signed Message:\\n32'"

        # the operators (opcode_to_arithm), and their precedences below
.Ls_op_sub:  .asciz " - "
.Ls_op_div:  .asciz " / "
.Ls_op_mul:  .asciz " * "
.Ls_op_gt:   .asciz " > "
.Ls_op_lt:   .asciz " < "
.Ls_op_le:   .asciz " <= "
.Ls_op_ge:   .asciz " >= "
.Ls_op_or:   .asciz " | "
.Ls_op_eq:   .asciz " == "
.Ls_op_mod:  .asciz " % "
.Ls_op_shl:  .asciz " << "
.Ls_op_shr:  .asciz " >> "
.Ls_op_exp:  .asciz "**"
.Ls_op_and:  .asciz " & "
.Ls_op_sge:  .asciz " >=\xe2\x80\xb2 "
.Ls_op_sle:  .asciz " <=\xe2\x80\xb2 "
.Ls_op_sgt:  .asciz " >\xe2\x80\xb2 "
.Ls_op_slt:  .asciz " <\xe2\x80\xb2 "
.Ls_op_sadd: .asciz " +\xe2\x80\xb2 "
.Ls_op_smul: .asciz " *\xe2\x80\xb2 "
.Ls_op_sdiv: .asciz " /\xe2\x80\xb2 "
.Ls_op_smod: .asciz " %\xe2\x80\xb2 "
.Ls_op_xor:  .asciz " ^ "

        # the atoms with a name of their own
.Ls_block_number:   .asciz "block.number"
.Ls_calldata_size:  .asciz "calldata.size"
.Ls_return_data_size: .asciz "return_data.size"
.Ls_block_difficulty: .asciz "block.difficulty"
.Ls_block_basefee:  .asciz "block.basefee"
.Ls_block_blobbasefee: .asciz "block.blobbasefee"
.Ls_tx_gasprice:    .asciz "tx.gasprice"
.Ls_block_timestamp: .asciz "block.timestamp"
.Ls_block_coinbase: .asciz "block.coinbase"
.Ls_block_gas_limit: .asciz "block.gas_limit"
.Ls_call_value:     .asciz "call.value"
.Ls_this_address:   .asciz "this.address"
.Ls_gas_remaining:  .asciz "gas_remaining"

        # the names of the variables of loops (NICE_NAMES)
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

        # the names the text has for what the EVM gives (BUILTIN_NAMES)
.Lb_caller: .asciz "caller"
.Lb_chainid: .asciz "chainid"
.Lb_gas_remaining: .asciz "gas_remaining"
.Lb_call: .asciz "call"
.Lb_calldata: .asciz "calldata"
.Lb_this: .asciz "this"
.Lb_tx: .asciz "tx"
.Lb_block: .asciz "block"
.Lb_return_data: .asciz "return_data"
.Lb_ext_call: .asciz "ext_call"
.Lb_ext_code: .asciz "ext_code"
.Lb_memcopy: .asciz "memcopy"
.Lb_delegate: .asciz "delegate"
.Lb_create: .asciz "create"
.Lb_create2: .asciz "create2"
.Lb_code: .asciz "code"
.Lb_eth: .asciz "eth"
.Lb_mem: .asciz "mem"
.Lb_stor: .asciz "stor"
.Lb_transient: .asciz "transient"
.Lb_msize: .asciz "msize"
.Lb_True: .asciz "True"
.Lb_False: .asciz "False"
.Lb_ecrecover: .asciz "ecrecover"
.Lb_sha256hash: .asciz "sha256hash"
.Lb_ripemd160hash: .asciz "ripemd160hash"
.Lb_bigModExp: .asciz "bigModExp"
.Lb_bn256Add: .asciz "bn256Add"
.Lb_bn256ScalarMul: .asciz "bn256ScalarMul"
.Lb_bn256Pairing: .asciz "bn256Pairing"

        .section .data.rel.ro
        .align 8
nice_names:
        .quad .Ln_idx, .Ln_s, .Ln_t, .Ln_u, .Ln_v, .Ln_w, .Ln_x, .Ln_y, .Ln_z
        .quad .Ln_a, .Ln_b, .Ln_c, .Ln_d, .Ln_e, .Ln_f, .Ln_g, .Ln_h
        .set NICE_NAMES_COUNT, 17
builtin_names:
        .quad .Lb_caller, .Lb_chainid, .Lb_gas_remaining, .Lb_call, .Lb_calldata
        .quad .Lb_this, .Lb_tx, .Lb_block, .Lb_return_data, .Lb_ext_call
        .quad .Lb_ext_code, .Lb_memcopy, .Lb_delegate, .Lb_create, .Lb_create2
        .quad .Lb_code, .Lb_eth, .Lb_mem, .Lb_stor, .Lb_transient, .Lb_msize
        .quad .Lb_True, .Lb_False, .Lb_ecrecover, .Lb_sha256hash
        .quad .Lb_ripemd160hash, .Lb_bigModExp, .Lb_bn256Add
        .quad .Lb_bn256ScalarMul, .Lb_bn256Pairing, 0

        # (filled by prettify_init: the ids are assembler constants, but a
        # sparse table is easier to fill than to declare)
        .section .bss
        .align 8
arith_ops:                              # opcode id -> operator text (0 for the others)
        .skip 8 * (OP_COUNT + 1)
arith_prec:                             # opcode id -> its precedence
        .skip OP_COUNT + 1
        .align 8
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
        lea rdx, [rip + arith_prec]
        .macro ARITH_OP op, text, prec
        lea rcx, [rip + \text]
        mov [rax + 8*\op], rcx
        mov byte ptr [rdx + \op], \prec
        .endm
        ARITH_OP OP_SUB, .Ls_op_sub, P_ADD
        ARITH_OP OP_DIV, .Ls_op_div, P_MUL
        ARITH_OP OP_MUL, .Ls_op_mul, P_MUL
        ARITH_OP OP_GT, .Ls_op_gt, P_CMP
        ARITH_OP OP_LT, .Ls_op_lt, P_CMP
        ARITH_OP OP_LE, .Ls_op_le, P_CMP
        ARITH_OP OP_GE, .Ls_op_ge, P_CMP
        ARITH_OP OP_OR, .Ls_op_or, P_BOR
        ARITH_OP OP_EQ, .Ls_op_eq, P_CMP
        ARITH_OP OP_MOD, .Ls_op_mod, P_MUL
        ARITH_OP OP_SHL, .Ls_op_shl, P_SHIFT
        ARITH_OP OP_SHR, .Ls_op_shr, P_SHIFT
        ARITH_OP OP_EXP, .Ls_op_exp, P_POW
        ARITH_OP OP_AND, .Ls_op_and, P_BAND
        ARITH_OP OP_SGE, .Ls_op_sge, P_CMP
        ARITH_OP OP_SLE, .Ls_op_sle, P_CMP
        ARITH_OP OP_SGT, .Ls_op_sgt, P_CMP
        ARITH_OP OP_SLT, .Ls_op_slt, P_CMP
        ARITH_OP OP_SADD, .Ls_op_sadd, P_ADD
        ARITH_OP OP_SMUL, .Ls_op_smul, P_MUL
        ARITH_OP OP_SDIV, .Ls_op_sdiv, P_MUL
        ARITH_OP OP_SMOD, .Ls_op_smod, P_MUL
        ARITH_OP OP_XOR, .Ls_op_xor, P_BXOR
        .macro ATOM_NAME op, text
        lea rcx, [rip + \text]
        mov [rax + 8*\op], rcx
        .endm
        lea rax, [rip + atom_names]
        ATOM_NAME OP_NUMBER, .Ls_block_number
        ATOM_NAME OP_CALLDATASIZE, .Ls_calldata_size
        ATOM_NAME OP_RETURNDATASIZE, .Ls_return_data_size
        ATOM_NAME OP_DIFFICULTY, .Ls_block_difficulty
        ATOM_NAME OP_BASEFEE, .Ls_block_basefee
        ATOM_NAME OP_BLOBBASEFEE, .Ls_block_blobbasefee
        ATOM_NAME OP_GASPRICE, .Ls_tx_gasprice
        ATOM_NAME OP_TIMESTAMP, .Ls_block_timestamp
        ATOM_NAME OP_COINBASE, .Ls_block_coinbase
        ATOM_NAME OP_GASLIMIT, .Ls_block_gas_limit
        ATOM_NAME OP_CALLVALUE, .Ls_call_value
        ATOM_NAME OP_ADDRESS, .Ls_this_address
        ATOM_NAME OP_CALLER, .Ls_caller
        ATOM_NAME OP_ORIGIN, .Ls_tx_origin
        ATOM_NAME OP_GAS, .Ls_gas_remaining
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
        PF OP_ECRECOVER, .Lpf_precompiled
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
        PF OP_BYTES, .Lpf_bytes
        PF OP_SIGNEXTEND, .Lpf_signextend
        PF OP_BLOCKHASH, .Lpf_blockhash
        PF OP_EXTCODEHASH, .Lpf_extcodehash
        PF OP_EXTCODESIZE, .Lpf_extcodesize
        PF OP_EXTCODECOPY, .Lpf_extcodecopy
        PF OP_MAX, .Lpf_max
        PF OP_MIN, .Lpf_max
        PF OP_BYTE, .Lpf_max
        PF OP_BLOBHASH, .Lpf_blobhash
        PF OP_TLOAD, .Lpf_tload
        PF OP_MASK_SHL, .Lpf_mask_shl
        PF OP_MULMOD, .Lpf_mulmod
        PF OP_ADDMOD, .Lpf_mulmod
        PF OP_BOOL, .Lpf_bool
        PF OP_CODE_DATA, .Lpf_code_data
        PF OP_BALANCE, .Lpf_balance
        PF OP_SHA3, .Lpf_sha3
        PF OP_CALL_DATA, .Lpf_call_data
        PF OP_EXT_CALL_RETURN_DATA, .Lpf_array
        PF OP_DELEGATE_RETURN_DATA, .Lpf_array
        PF OP_CALLCODE_RETURN_DATA, .Lpf_array
        PF OP_STATICCALL_RETURN_DATA, .Lpf_array
        PF OP_SALL, .Lpf_sall
        PF OP_ST, .Lpf_st
        PF OP_STOR, .Lpf_stor
        PF OP_TYPE, .Lpf_stor
        PF OP_FIELD, .Lpf_stor
        PF OP_CD, .Lpf_cd
        PF OP_VAR, .Lpf_var
        PF OP_MEM, .Lpf_mem
        PF OP_SETVAR, .Lpf_setvar
        PF OP_SETMEM, .Lpf_setmem
        PF OP_MASK, .Lpf_mask
        PF OP_SHIFT, .Lpf_shift
        PF OP_SAR, .Lpf_sar_shr
        PF OP_SHR, .Lpf_sar_shr
        PF OP_NOT, .Lpf_not
        PF OP_ADD, .Lpf_add
        PF OP_MUL, .Lpf_mul
        PF OP_DIV, .Lpf_div
        PF OP_EXP, .Lpf_exp
        PF OP_LAND, .Lpf_land
        PF OP_LOR, .Lpf_land
        PF OP_SUB, .Lpf_arith
        PF OP_GT, .Lpf_arith
        PF OP_LT, .Lpf_arith
        PF OP_LE, .Lpf_arith
        PF OP_GE, .Lpf_arith
        PF OP_OR, .Lpf_arith
        PF OP_EQ, .Lpf_arith
        PF OP_MOD, .Lpf_arith
        PF OP_SHL, .Lpf_arith
        PF OP_AND, .Lpf_arith
        PF OP_SGE, .Lpf_arith
        PF OP_SLE, .Lpf_arith
        PF OP_SGT, .Lpf_arith
        PF OP_SLT, .Lpf_arith
        PF OP_SADD, .Lpf_arith
        PF OP_SMUL, .Lpf_arith
        PF OP_SDIV, .Lpf_arith
        PF OP_SMOD, .Lpf_arith
        PF OP_XOR, .Lpf_arith
        PF OP_ISZERO, .Lpf_iszero
        ret
ENDF prettify_init

# --- small helpers ---

# PF_COLOR_OF dst, src: the flags of python's `pret` (add_color only)
.macro PF_COLOR_OF dst, src
        mov \dst, \src
        and \dst, PF_COLOR
.endm
# OPF dst, prec: the flags of `operand(e, prec)` from r12's
.macro OPF dst, prec
        mov \dst, r12
        and \dst, PF_COLOR
        or \dst, (\prec) << PF_CTX_SHIFT
.endm
# CTXF dst: the flags of `pret(e, parentheses=ctx)` (prettify's frame)
.macro CTXF dst
        mov \dst, [rsp + PF_CTX]
        shl \dst, PF_CTX_SHIFT
        test r12, PF_COLOR
        jz .Lctxf\@
        or \dst, PF_COLOR
.Lctxf\@:
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
        JT_SWITCH truthy, K_VMNODE, .Lpt_other
        JT_CASE truthy, K_STR, .Lpt_str
        JT_CASE truthy, K_SPECIAL, .Lpt_special
        JT_CASE truthy, K_TUPLE, .Lpt_seq
        JT_CASE truthy, K_LIST, .Lpt_seq
        JT_END truthy, K_VMNODE, .Lpt_other
.Lpt_other:
        mov eax, 1                      # a big int, a vm node
        ret
.Lpt_str:
5:      xor eax, eax
        cmp dword ptr [rdi + N_DATA], 0
        setne al
        ret
.Lpt_seq:
7:      xor eax, eax
        cmp dword ptr [rdi + N_AUX], 0
        setne al
        ret
.Lpt_special:
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
        STACK_CHECK
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

# sb_append_operand(sb, exp, prec, flags): python's operand(e, prec) -
# prettify(e, parentheses=prec) - appended; of the flags, PF_COLOR and
# PF_REM_BOOL are kept
FUNC sb_append_operand
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov rdi, rsi
        and ecx, PF_COLOR | PF_REM_BOOL
        shl edx, PF_CTX_SHIFT
        or ecx, edx
        mov esi, ecx
        call prettify
        mov rdi, rbx
        mov rsi, rax
        call sb_append_str
        LEAVE
ENDF sb_append_operand

# pf_wrap(str, prec, ctx) -> str: python's wrap - the text in parentheses
# when its operator binds less tightly than its place needs (prec < ctx)
FUNC pf_wrap
        cmp esi, edx
        jl 1f
        mov rax, rdi
        ret
1:      ENTER
        mov rbx, rdi
        call sb_new
        mov r12, rax
        mov rdi, rax
        mov esi, '('
        call sb_append_char
        mov rdi, r12
        mov rsi, rbx
        call sb_append_str
        mov rdi, r12
        mov esi, ')'
        call sb_append_char
        mov rdi, r12
        call sb_finish
        LEAVE
ENDF pf_wrap

# num_precedence(str) -> eax: the precedence of a number as pretty_num
# prints it
FUNC num_precedence
        ENTER
        mov rbx, rdi
        lea rsi, [rip + .Ls_star_sp]
        call str_contains_c
        test eax, eax
        jz 1f
        mov eax, P_MUL
        LEAVE
1:      cmp dword ptr [rbx + N_DATA], 0
        je 2f
        cmp byte ptr [rbx + N_DATA + 4], '-'
        jne 2f
        mov eax, P_UNARY
        LEAVE
2:      mov rdi, rbx
        lea rsi, [rip + .Ls_pow]
        call str_contains_c
        test eax, eax
        jz 3f
        mov eax, P_POW
        LEAVE
3:      mov eax, P_ATOM
        LEAVE
ENDF num_precedence

# pf_multiple_above(v, n) -> eax: the int v is a multiple of the small
# int n (both tagged) above it (exp % n == 0 and exp > n)
FUNC pf_multiple_above
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call int_mod
        cmp rax, 1
        jne 1f
        mov rdi, rbx
        mov rsi, r12
        call int_cmp
        cmp eax, 1
        jne 1f
        mov eax, 1
        LEAVE
1:      xor eax, eax
        LEAVE
ENDF pf_multiple_above

# pow2_exact(k) -> value: 2 ** k for an int k >= 0, not clamped (python's
# big ints: a mask's 2**shl); past 2^24 bits, python's MemoryError
FUNC pow2_exact
        ENTER
        mov rbx, rdi
        test bl, 1
        jz 9f
        sar rbx, 1
        js 9f
        cmp rbx, 1 << 24
        ja 9f
        lea rdi, [r15 + CTX_MPZ_R]
        xor esi, esi
        call __gmpz_set_ui@PLT
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rbx
        call __gmpz_setbit@PLT
        call arith_result
        LEAVE
9:      mov edi, E_MEMORY
        lea rsi, [rip + .Ls_pow2_big]
        call err_throw
ENDF pow2_exact

        .section .rodata
.Ls_pow2_big: .asciz "MemoryError: 2 ** k of a k too big"
        .text

# pm_join(sep_cstr, pm) -> str: python's sep.join(...) of what
# pretty_memory gave: its strings, or the characters of the bare string
# it gives for no element ("empty()") or for "mem"
FUNC pm_join
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rsi
        call is_str
        test eax, eax
        jz 1f
        mov rdi, r12
        call str_chars
        mov r12, rax
1:      mov rdi, rbx
        mov rsi, r12
        call str_join
        LEAVE
ENDF pm_join

# pm_list(pm) -> list: what pretty_memory gave, as python's list() of it
FUNC pm_list
        ENTER
        mov rbx, rdi
        call is_str
        test eax, eax
        jz 1f
        mov rdi, rbx
        call str_chars
        LEAVE
1:      mov rax, rbx
        LEAVE
ENDF pm_list

# --- prettify ---

FUNC prettify
        STACK_CHECK
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 64
        .set PF_FLAGS, MATCH_BINDINGS_SIZE + 8
        .set PF_SB, MATCH_BINDINGS_SIZE + 16
        .set PF_T1, MATCH_BINDINGS_SIZE + 24
        .set PF_T2, MATCH_BINDINGS_SIZE + 32
        .set PF_T3, MATCH_BINDINGS_SIZE + 40
        .set PF_CTX, MATCH_BINDINGS_SIZE + 48
        .set PF_T4, MATCH_BINDINGS_SIZE + 56
        mov rbx, rdi
        mov r12, rsi
        mov [rsp + PF_FLAGS], rsi
        # ctx = context(parentheses, top_level)
        xor eax, eax
        test r12, PF_TOP
        jnz 1f
        mov rax, r12
        shr rax, PF_CTX_SHIFT
        and eax, 0xf
        jnz 1f
        test r12, PF_PARENS
        jz 1f
        mov eax, P_ATOM
1:      mov [rsp + PF_CTX], rax
        test r12, PF_REM_BOOL
        jz .Lpf_values
        mov rdi, rbx
        call simplify_bool
        mov rbx, rax
        # a xor is true when it isn't 0: when its operands differ
        mov rdi, rax
        OP_N_CHECK OP_XOR, 3, 2f
        LOADS rdi, EQ
        mov rsi, [rbx + N_DATA + 8]
        mov rdx, [rbx + N_DATA + 16]
        call mk3
        mov rsi, rax
        LOADS rdi, ISZERO
        call mk2
        mov rbx, rax
2:      mov rdi, rbx
        call opcode_of
        cmp eax, OP_BOOL
        jne .Lpf_values
        mov rdi, rbx
        mov rsi, r12
        call prettify
        jmp .Lpf_ret
.Lpf_values:
        mov rdi, rbx
        call is_int
        test eax, eax
        jz .Lpf_not_int
        # time constants: multiples of a day, then of an hour
        mov rdi, rbx
        mov rsi, (86400 << 1) | 1
        call pf_multiple_above
        test eax, eax
        jz 3f
        mov rdi, rbx
        mov rsi, (86400 << 1) | 1
        call int_floordiv
        mov rsi, rax
        LOADS rdi, MUL
        mov rdx, (24 << 1) | 1
        mov rcx, (3600 << 1) | 1
        call mk4
        mov rbx, rax
        jmp .Lpf_dispatch
3:      mov rdi, rbx
        mov rsi, (3600 << 1) | 1
        call pf_multiple_above
        test eax, eax
        jz 4f
        mov rdi, rbx
        mov rsi, (3600 << 1) | 1
        call int_floordiv
        mov rsi, rax
        LOADS rdi, MUL
        mov rdx, (3600 << 1) | 1
        call mk3
        mov rbx, rax
        jmp .Lpf_dispatch
4:      mov rdi, rbx
        mov rsi, r12
        call pretty_num
.Lpf_number:
        mov r13, rax
        mov rdi, rax
        call num_precedence
        mov rdi, r13
        mov esi, eax
        mov rdx, [rsp + PF_CTX]
        call pf_wrap
        jmp .Lpf_ret
.Lpf_not_int:
        mov rdi, rbx
        call is_str
        test eax, eax
        jz .Lpf_dispatch
        mov eax, [rbx + N_AUX]
        test eax, STR_FLOAT
        jz 5f
        mov rax, rbx                    # a float: the text of its repr
        jmp .Lpf_number
5:      and eax, STR_ID_MASK
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
        mov rdi, rbx
        call opcode_of
        test eax, eax
        jz .Lpf_default
        lea rcx, [rip + pf_table]
        jmp [rcx + rax*8]

.Lpf_default:
        # str(exp)
        mov rdi, rbx
        call value_str
        jmp .Lpf_ret

.Lpf_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_pf_index]
        call err_throw

.Lpf_precompiled:
        # f"{exp[0]}({pret(exp[1])})"
        cmp dword ptr [rbx + N_AUX], 2
        jb .Lpf_index
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
        # an array of a string constant, of its length
        PAT rsi, "('arr', ':int:num', ('mask_shl', 'Any', 'Any', 'Any', ':str:s'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        B rdi, 1
        call str_charlen
        sub rax, 2
        mov rdi, rax
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
        mov rdi, rbx                    # ('data',) + exp[2:]
        mov esi, 2
        call data_of_rest
        mov rdi, rax
        PF_COLOR_OF rsi, r12
        call pretty_memory
        lea rdi, [rip + .Ls_comma_sp]
        mov rsi, rax
        call pm_join
        mov rdi, r13
        mov rsi, rax
        call sb_append_str
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
        # the bytes of its elements one after the other
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_concat_]
        call sb_append_c
        mov rdi, rbx
        PF_COLOR_OF rsi, r12
        call pretty_memory
        lea rdi, [rip + .Ls_comma_sp]
        mov rsi, rax
        call pm_join
        mov rdi, r13
        mov rsi, rax
        call sb_append_str
        mov rdi, r13
        mov esi, ')'
        call sb_append_char
        jmp .Lpf_finish

.Lpf_bytes:
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lpf_default
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rbx + N_DATA + 16]
        mov rdx, r12
        mov rcx, [rsp + PF_CTX]
        call pretty_bytes
        jmp .Lpf_ret

.Lpf_signextend:
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lpf_default
        mov rdi, [rbx + N_DATA + 8]
        call is_int
        test eax, eax
        jz 2f
        # int{8 * (b + 1)}(val) - of a field of the storage of that size,
        # an int rather than an uint
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, 3                      # tagged 1
        call int_add
        mov rdi, rax
        mov rsi, (8 << 1) | 1
        call int_mul
        mov r14, rax                    # the bits
        mov rax, [rbx + N_DATA + 16]
        mov [rsp + PF_T1], rax          # val
        PAT rsi, "('type', ':size', ':loc')"
        mov rdi, rax
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        B rdi, 0
        mov rsi, r14
        call py_equal
        test eax, eax
        jz 1f
        B rax, 1
        mov [rsp + PF_T1], rax
1:      call sb_new
        mov r13, rax
        mov [rsp + PF_SB], rax
        call sb_new
        mov [rsp + PF_T2], rax          # "int{bits}("
        mov rdi, rax
        lea rsi, [rip + .Ls_int]
        call sb_append_c
        mov rdi, [rsp + PF_T2]
        mov rsi, r14
        mov edx, 10
        call sb_append_int
        mov rdi, [rsp + PF_T2]
        mov esi, '('
        call sb_append_char
        mov rdi, [rsp + PF_T2]
        call sb_finish
        mov rdi, r13
        mov rsi, rax
        lea rdx, [rip + C_GRAY]
        mov rcx, r12
        call sb_append_col
        mov rdi, r13
        mov rsi, [rsp + PF_T1]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, r13
        lea rsi, [rip + .Ls_rparen]
        lea rdx, [rip + C_GRAY]
        mov rcx, r12
        call sb_append_col_c
        jmp .Lpf_finish
2:      # signextend(b, val)
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_signextend_]
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

.Lpf_blockhash:
        lea r13, [rip + .Ls_block_hash]
        jmp .Lpf_call1
.Lpf_extcodehash:
        lea r13, [rip + .Ls_ext_hash]
        jmp .Lpf_call1
.Lpf_extcodesize:
        lea r13, [rip + .Ls_ext_size]
        jmp .Lpf_call1
.Lpf_blobhash:
        lea r13, [rip + .Ls_blobhash_]
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

.Lpf_tload:
        # col("transient[", GRAY) + pret(key) + col("]", GRAY)
        cmp dword ptr [rbx + N_AUX], 2
        jne .Lpf_default
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_transient_]
        lea rdx, [rip + C_GRAY]
        mov rcx, r12
        call sb_append_col_c
        mov rdi, r13
        mov rsi, [rbx + N_DATA + 8]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, r13
        lea rsi, [rip + .Ls_rbracket]
        lea rdx, [rip + C_GRAY]
        mov rcx, r12
        call sb_append_col_c
        jmp .Lpf_finish

.Lpf_extcodecopy:
        # the bytes of the code of the account: ext_code(addr).data[s len n]
        PAT rsi, "('extcodecopy', ':addr', ('range', ':start', ':size'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lpf_default
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_ext_code_]
        call sb_append_c
        mov rdi, r13
        B rsi, 0
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, r13
        lea rsi, [rip + .Ls_dot_data_]
        call sb_append_c
        mov rdi, r13
        B rsi, 1
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, r13
        lea rsi, [rip + .Ls_sp_len_sp]
        call sb_append_c
        mov rdi, r13
        B rsi, 2
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, r13
        mov esi, ']'
        call sb_append_char
        jmp .Lpf_finish

.Lpf_max:
        # max / min / byte: "op(" + ", ".join(pret(e) for e in terms) + ")"
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, [rbx + N_DATA]
        call sb_append_str
        mov rdi, r13
        mov esi, '('
        call sb_append_char
        mov rdi, r13
        mov rsi, rbx
        mov edx, 1
        PF_COLOR_OF rcx, r12
        call sb_append_pret_join
        mov rdi, r13
        mov esi, ')'
        call sb_append_char
        jmp .Lpf_finish

.Lpf_mulmod:
        # mulmod / addmod: f"{op}({a}, {b}, {c})"
        cmp dword ptr [rbx + N_AUX], 4
        jne .Lpf_default
        jmp .Lpf_max

.Lpf_bool:
        cmp dword ptr [rbx + N_AUX], 2
        jne .Lpf_default
        mov rax, [rbx + N_DATA + 8]
        cmp rax, 3                      # ('bool', 1)
        jne 1f
        lea rdi, [rip + .Ls_True]
        call str_new_c
        jmp .Lpf_ret
1:      cmp rax, 1                      # ('bool', 0)
        jne 2f
        lea rdi, [rip + .Ls_False]
        call str_new_c
        jmp .Lpf_ret
2:      # ('bool', val): a comparison as it is (pret(val, parentheses=ctx)),
        # else bool(val)
        mov rdi, rax
        call opcode_of
        IN_OPSET boolish, rax           # lt, gt, iszero, le, ge, bool
        jne 3f
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
        CTXF rsi
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

.Lpf_sha3:
        # of the bytes of its terms one after the other (a single data: its
        # elements)
        mov rax, rbx
        cmp dword ptr [rbx + N_AUX], 2
        jne 1f
        mov rdi, [rbx + N_DATA + 8]
        call opcode_of
        cmp eax, OP_DATA
        jne 1f
        mov rax, [rbx + N_DATA + 8]
        mov rdi, rax
        mov esi, 1
        call data_of_rest
        jmp 2f
1:      mov rdi, rbx
        mov esi, 1
        call data_of_rest
2:      mov rdi, rax
        PF_COLOR_OF rsi, r12
        call pretty_memory
        lea rdi, [rip + .Ls_comma_sp]
        mov rsi, rax
        call pm_join
        mov r14, rax
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_sha3_]
        call sb_append_c
        mov rdi, r13
        mov rsi, r14
        call sb_append_str
        mov rdi, r13
        mov esi, ')'
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
        mov rdx, rax
        mov rsi, (4 << 1) | 1
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
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, (32 << 1) | 1
        call py_equal
        test eax, eax
        jnz 1f
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

.Lpf_sall:
        # the bytes of a bytes (or string) of the storage
        cmp dword ptr [rbx + N_AUX], 2
        jne .Lpf_default
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, r12
        call pretty_loc
        mov r14, rax
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, r14
        call sb_append_str
        mov rdi, r13
        lea rsi, [rip + .Ls_all_br]
        lea rdx, [rip + C_GREEN]
        mov rcx, r12
        call sb_append_col_c
        jmp .Lpf_finish

.Lpf_st:
        # an access of the storage (see storage.py)
        cmp dword ptr [rbx + N_AUX], 4
        jne .Lpf_default
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, r12
        call pretty_loc
        mov r14, rax                    # text
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rbx + N_DATA + 24]
        call py_equal
        test eax, eax
        jnz 1f
        mov rdi, [rbx + N_DATA + 24]
        call is_none
        test eax, eax
        jz 2f
1:      mov rax, r14
        jmp .Lpf_ret
2:      # (address or uint{pret(size)})(text)
        call sb_new
        mov [rsp + PF_T1], rax
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, (160 << 1) | 1
        call py_equal
        test eax, eax
        jz 3f
        mov rdi, [rsp + PF_T1]
        lea rsi, [rip + .Ls_address]
        call sb_append_c
        jmp 4f
3:      mov rdi, [rsp + PF_T1]
        lea rsi, [rip + .Ls_uint]
        call sb_append_c
        mov rdi, [rsp + PF_T1]
        mov rsi, [rbx + N_DATA + 8]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
4:      mov rdi, [rsp + PF_T1]
        mov esi, '('
        call sb_append_char
        mov rdi, [rsp + PF_T1]
        call sb_finish
        mov [rsp + PF_T1], rax
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, [rsp + PF_T1]
        lea rdx, [rip + C_GRAY]
        mov rcx, r12
        call sb_append_col
        mov rdi, r13
        mov rsi, r14
        call sb_append_str
        mov rdi, r13
        lea rsi, [rip + .Ls_rparen]
        lea rdx, [rip + C_GRAY]
        mov rcx, r12
        call sb_append_col_c
        jmp .Lpf_finish

.Lpf_stor:
        mov rdi, rbx
        mov rsi, r12
        call pretty_stor
        jmp .Lpf_ret

.Lpf_cd:
        cmp dword ptr [rbx + N_AUX], 2
        jne .Lpf_default
        mov rdi, rbx
        mov rsi, r12
        call get_param_name
        mov r13, rax
        mov rdi, rax
        call is_str
        test eax, eax
        jnz 2f
        # "cd[" + pret(parsed[1]) + "]"
        cmp dword ptr [r13 + N_AUX], 2
        jb .Lpf_index
        call sb_new
        mov r14, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_cd_]
        call sb_append_c
        mov rdi, r14
        mov rsi, [r13 + N_DATA + 8]
        PF_COLOR_OF rdx, r12
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
        jz 4f
        # (not a name the text has for something else, see set_names)
        call names_state
        mov r13, rax
        mov rdi, [rbx + N_DATA + 8]
        test dil, 1
        jnz 11f
        call int_sign                   # a big int: a negative one is an
        cmp eax, -1                     # index before the list's start
        je .Lpf_index
        jmp 3f
11:     sar rdi, 1
        mov rcx, [r13 + NM_NFREE]
        cmp rdi, rcx
        jge 3f
        test rdi, rdi
        jns 1f
        add rdi, rcx                    # (python's negative index)
        js .Lpf_index
1:      mov rdi, [r13 + NM_FREE + rdi*8]
        call str_new_c
        jmp 5f
3:      # "var" + str(idx), then _ while that's a name of something else
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
        mov rdi, rax
        call var_name
        jmp 5f
4:      mov rdi, [rbx + N_DATA + 8]
        call value_str
        mov rdi, rax
        call var_name
5:      mov rdi, rax
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
2:      mov rdi, r13
        call opcode_of
        cmp eax, OP_RANGE
        je .Lpf_mem_assert
        call sb_new
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
.Lpf_mem_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_pf_mem_assert]
        call err_throw

.Lpf_setvar:
        # pret(('var', idx)) + " = " + pret(val)
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lpf_default
        LOADS rdi, VAR
        mov rsi, [rbx + N_DATA + 8]
        call mk2
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

.Lpf_setmem:
        # pret(('mem', idx)) + " = " + ", ".join(pretty_memory(val))
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lpf_default
        mov rax, [rbx + N_DATA + 16]
        mov [rsp + PF_T1], rax          # val
        mov rdi, rax
        call is_int
        test eax, eax
        jz 1f
        mov rdi, [rsp + PF_T1]
        call int_lt_pow2_256
        test eax, eax
        jnz 1f
        mov rdi, [rsp + PF_T1]
        call int_sign
        cmp eax, 1
        jne 1f
        # bytes of more than a word: as many as the range
        PAT rsi, "('range', 'Any', ':int:n')"
        mov rdi, [rbx + N_DATA + 8]
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        LOADS rdi, BYTES
        B rsi, 0
        mov rdx, [rsp + PF_T1]
        call mk3
        mov [rsp + PF_T1], rax
1:      LOADS rdi, MEM
        mov rsi, [rbx + N_DATA + 8]
        call mk2
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
        mov rdi, [rsp + PF_T1]
        PF_COLOR_OF rsi, r12
        call pretty_memory
        lea rdi, [rip + .Ls_comma_sp]
        mov rsi, rax
        call pm_join
        mov rdi, r14
        mov rsi, rax
        call sb_append_str
        mov r13, r14
        jmp .Lpf_finish

.Lpf_mask_shl:
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
2:      # ('mask_shl', 251, 5, 0, val): ceil32 / floor32
        PAT rsi, "('mask_shl', 251, 5, 0, ':val')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 3f
        B rdi, 0
        mov rsi, r12
        call pf_floor32
        jmp .Lpf_ret
3:      # a storage under a mask that keeps all of it
        PAT rsi, "('mask_shl', ':size', ':offset', ':shl', ('stor', ':s_size', ':s_off', ':s_idx'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 4f
        B rdi, 3
        B rsi, 0
        call alg_safe_le_op
        cmp eax, TRI_TRUE
        jne 4f
        cmp qword ptr [rsp + 16], 1     # shl == 0
        jne 4f
        cmp qword ptr [rsp + 8], 1      # offset == 0
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
4:      # a storage access of fewer bits than the mask's top: its bits from
        # off on, x >> off
        PAT rsi, "('mask_shl', ':int:size', ':int:off', ':int:shl', ':val')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 5f
        B rdi, 3
        call opcode_of
        cmp eax, OP_ST
        jne 5f
        B rax, 3
        cmp dword ptr [rax + N_AUX], 2
        jb .Lpf_index
        mov rdi, [rax + N_DATA + 8]
        call is_int
        test eax, eax
        jz 5f
        B rdi, 1                        # 0 < off == -shl
        call int_sign
        cmp eax, 1
        jne 5f
        B rdi, 2
        call int_neg
        B rsi, 1
        mov rdi, rax
        call values_equal
        test eax, eax
        jz 5f
        B rdi, 1                        # val[1] <= off + size
        B rsi, 0
        call int_add
        mov rsi, rax
        B rax, 3
        mov rdi, [rax + N_DATA + 8]
        call int_cmp
        cmp eax, 1
        je 5f
        B rdi, 1
        mov rsi, (8 << 1) | 1
        call int_cmp
        cmp eax, -1
        jne 41f
        # off < 8: ('div', val, 2 ** off)
        B rdi, 1
        sar rdi, 1
        call pow2
        mov rdx, rax
        B rsi, 3
        LOADS rdi, DIV
        call mk3
        mov rdi, rax
        CTXF rsi
        call prettify
        jmp .Lpf_ret
41:     # wrap(operand(val, SHIFT) + " >> " + pret(off), SHIFT)
        call sb_new
        mov r13, rax
        mov rdi, rax
        B rsi, 3
        mov edx, P_SHIFT
        mov rcx, r12
        and ecx, PF_COLOR
        call sb_append_operand
        mov rdi, r13
        lea rsi, [rip + .Ls_shr_op]
        lea rdx, [rip + C_BOLD]
        mov rcx, r12
        call sb_append_bold_c
        mov rdi, r13
        B rsi, 1
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov r14d, P_SHIFT
        jmp .Lpf_finish_wrap
5:      # the first 4 bytes of the calldata, as msg.sig
        PAT rsi, "('mask_shl', 32, 224, 0, ('cd', 0))"
        mov rdi, rbx
        call pat_match_nobind
        test eax, eax
        jz 6f
        lea rdi, [rip + .Ls_call_func_hash]
        lea rsi, [rip + C_GREEN]
        mov rdx, r12
        call colorize_c
        jmp .Lpf_ret
6:      PAT rsi, "('mask_shl', 32, 224, -224, ('cd', 0))"
        mov rdi, rbx
        call pat_match_nobind
        test eax, eax
        jz 7f
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_call_func_hash]
        lea rdx, [rip + C_GREEN]
        mov rcx, r12
        call sb_append_col_c
        mov rdi, r13
        lea rsi, [rip + .Ls_sp_shr224]
        call sb_append_c
        mov r14d, P_SHIFT
        jmp .Lpf_finish_wrap
7:      cmp dword ptr [rbx + N_AUX], 5
        jne .Lpf_default
        jmp .Lpf_mask_shl_5

.Lpf_mask_shl_5:
        # ('mask_shl', size, offset, shl, val)
        mov r13, [rbx + N_DATA + 8]     # size
        mov r14, [rbx + N_DATA + 16]    # offset
        mov rax, [rbx + N_DATA + 24]
        mov [rsp + PF_T2], rax          # shl
        mov rax, [rbx + N_DATA + 32]
        mov [rsp + PF_T3], rax          # val
        mov edi, 3
        lea rsi, [rbx + N_DATA + 8]
        call all_ints
        mov [rsp + PF_T4], rax          # all_concrete(size, offset, shl)
        test eax, eax
        jz .Lms_c
        # e.g. Mask(255, 1, eth.balance(this.address)) >> 1 is
        # eth.balance(this.address) / 2, for offsets smaller than 8:
        # size + offset == 256 and offset == -shl and offset < 8
        mov rdi, r13
        mov rsi, r14
        call int_add
        cmp rax, (256 << 1) | 1
        jne .Lms_b
        mov rdi, [rsp + PF_T2]
        call int_neg
        mov rdi, rax
        mov rsi, r14
        call values_equal
        test eax, eax
        jz .Lms_b
        mov rdi, r14
        mov rsi, (8 << 1) | 1
        call int_cmp
        cmp eax, -1
        jne .Lms_b
        mov rdi, [rsp + PF_T2]
        mov rsi, (8 << 1) | 1
        call int_cmp
        cmp eax, 1
        je 1f
        # shl <= 8: ('div', val, 2 ** offset) - offset from -8 to 7, a
        # float below zero, as python's
        mov rdi, r14
        sar rdi, 1
        call pow2_or_float
        mov rdx, rax
        mov rsi, [rsp + PF_T3]
        LOADS rdi, DIV
        call mk3
        jmp .Lms_pret_ctx
1:      mov rsi, [rsp + PF_T2]          # ('shr', shl, val)
        mov rdx, [rsp + PF_T3]
        LOADS rdi, SHR
        call mk3
        jmp .Lms_pret_ctx
.Lms_b:
        # e.g. Mask(255, 1, eth.balance(this.address)) << x is
        # eth.balance(this.address) * 2**x, for offsets smaller than 8:
        # offset == shl and offset < 8
        mov rdi, r14
        mov rsi, [rsp + PF_T2]
        call values_equal
        test eax, eax
        jz .Lms_c
        mov rdi, r14
        mov rsi, (8 << 1) | 1
        call int_cmp
        cmp eax, -1
        jne .Lms_c
        # val = ('mask', size + offset, 0, val) unless size + offset is 256
        # or val a store (a hotfix of python's)
        mov rdi, r13
        mov rsi, r14
        call int_add
        cmp rax, (256 << 1) | 1
        je 2f
        mov [rsp + PF_T1], rax
        mov rdi, [rsp + PF_T3]
        call opcode_of
        cmp eax, OP_STORE
        je 2f
        LOADS rdi, MASK
        mov rsi, [rsp + PF_T1]
        mov edx, 1
        mov rcx, [rsp + PF_T3]
        call mk4
        mov [rsp + PF_T3], rax
2:      cmp r14, 1                      # shl == 0: val itself
        jne 3f
        mov rdi, [rsp + PF_T3]
        CTXF rsi
        call prettify
        jmp .Lpf_ret
3:      # -8 <= shl <= 8: ('mul', val, 2 ** shl) (a float below zero); a
        # shl below -8: ('shr', -shl, val) (above 8 it can't be: it's the
        # offset, below 8)
        mov rdi, r14
        mov rsi, (-8 << 1) | 1
        call int_cmp
        cmp eax, -1
        je 4f
        mov rdi, r14
        sar rdi, 1
        call pow2_or_float
        mov rdx, rax
        mov rsi, [rsp + PF_T3]
        LOADS rdi, MUL
        call mk3
        jmp .Lms_pret_ctx
4:      mov rdi, r14
        call int_neg
        mov rsi, rax
        mov rdx, [rsp + PF_T3]
        LOADS rdi, SHR
        call mk3
        jmp .Lms_pret_ctx
.Lms_c:
        # all concrete: the mask applied
        mov edi, 4
        lea rsi, [rbx + N_DATA + 8]
        call all_ints
        test eax, eax
        jz .Lms_d
        mov rdi, [rsp + PF_T3]
        mov rsi, r13
        mov rdx, r14
        mov rcx, [rsp + PF_T2]
        call alg_apply_mask
        mov rdi, rax
        PF_COLOR_OF rsi, r12
        call prettify
        jmp .Lpf_ret
.Lms_d:
        # val >> offset, with the bits above size cut off if there are any
        # (Mask(16, 160, x) >> 160 is uint16(x >> 160)): concrete, offset ==
        # -shl, 8 <= offset < 256, 0 < size <= 256 - offset, val no data
        cmp qword ptr [rsp + PF_T4], 0
        je .Lms_e
        test r14b, 1
        jz .Lms_e
        mov rax, r14
        sar rax, 1
        cmp rax, 8
        jl .Lms_e
        cmp rax, 256
        jge .Lms_e
        mov rdi, [rsp + PF_T2]
        call int_neg
        mov rdi, rax
        mov rsi, r14
        call values_equal
        test eax, eax
        jz .Lms_e
        test r13b, 1
        jz .Lms_e
        mov rax, r13
        sar rax, 1
        test rax, rax
        jle .Lms_e
        mov rcx, r14
        sar rcx, 1
        mov rdx, 256
        sub rdx, rcx
        cmp rax, rdx
        jg .Lms_e
        mov rdi, [rsp + PF_T3]
        call opcode_of
        cmp eax, OP_DATA
        je .Lms_e
        # shifted = operand(val, SHIFT) + " >> " + pret(offset)
        call sb_new
        mov [rsp + PF_SB], rax
        mov rdi, rax
        mov rsi, [rsp + PF_T3]
        mov edx, P_SHIFT
        mov rcx, r12
        and ecx, PF_COLOR
        call sb_append_operand
        mov rdi, [rsp + PF_SB]
        lea rsi, [rip + .Ls_shr_op]
        lea rdx, [rip + C_BOLD]
        mov rcx, r12
        call sb_append_bold_c
        mov rdi, [rsp + PF_SB]
        mov rsi, r14
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, [rsp + PF_SB]
        call sb_finish
        mov [rsp + PF_T1], rax          # shifted
        mov rdi, r13
        mov rsi, r14
        call int_add
        cmp rax, (256 << 1) | 1
        jne 1f
        mov rdi, [rsp + PF_T1]          # wrap(shifted, SHIFT)
        mov esi, P_SHIFT
        mov rdx, [rsp + PF_CTX]
        call pf_wrap
        jmp .Lpf_ret
1:      cmp r13, 3
        jne 2f
        # its lowest bit: not a bool (bool(x) is x != 0) - (shifted) % 2
        call sb_new
        mov [rsp + PF_SB], rax
        mov rdi, rax
        mov esi, '('
        call sb_append_char
        mov rdi, [rsp + PF_SB]
        mov rsi, [rsp + PF_T1]
        call sb_append_str
        mov rdi, [rsp + PF_SB]
        mov esi, ')'
        call sb_append_char
        mov rdi, [rsp + PF_SB]
        lea rsi, [rip + .Ls_mod_op]
        lea rdx, [rip + C_BOLD]
        mov rcx, r12
        call sb_append_bold_c
        mov rdi, [rsp + PF_SB]
        lea rsi, [rip + .Ls_mod2]
        call sb_append_c
        mov r13, [rsp + PF_SB]
        mov r14d, P_MUL
        jmp .Lpf_finish_wrap
2:      mov rdi, r13
        xor esi, esi
        call mask_to_type
        test rax, rax
        jnz 3f
        mov rax, r13
        sar rax, 1
        test al, 7
        jnz .Lms_e
        mov rdi, rax
        call uint_name
3:      # col(type_name + "(", GRAY) + shifted + col(")", GRAY)
        mov [rsp + PF_T4], rax
        lea rdi, [rip + .Ls_lparen_t]
        call str_new_c
        mov rdi, [rsp + PF_T4]
        mov rsi, rax
        call str_cat2
        mov [rsp + PF_T4], rax
        call sb_new
        mov [rsp + PF_SB], rax
        mov rdi, rax
        mov rsi, [rsp + PF_T4]
        lea rdx, [rip + C_GRAY]
        mov rcx, r12
        call sb_append_col
        mov rdi, [rsp + PF_SB]
        mov rsi, [rsp + PF_T1]
        call sb_append_str
        mov rdi, [rsp + PF_SB]
        lea rsi, [rip + .Ls_rparen]
        lea rdx, [rip + C_GRAY]
        mov rcx, r12
        call sb_append_col_c
        mov r13, [rsp + PF_SB]
        jmp .Lpf_finish
.Lms_e:
        # its bits from offset up, moved down: val >> offset (0 when the
        # offset is 256 or more, as the mask is then) - offset and shl not
        # both concrete, offset + shl == 0, offset a word, size + offset == 256
        mov edi, 2
        lea rsi, [rbx + N_DATA + 16]
        call all_ints
        test eax, eax
        jnz .Lms_f
        mov rdi, r14
        mov rsi, [rsp + PF_T2]
        call alg_add2
        cmp rax, 1
        jne .Lms_f
        mov rdi, r14
        xor esi, esi
        call is_word
        test eax, eax
        jz .Lms_f
        mov rdi, r13
        mov rsi, r14
        call alg_add2
        cmp rax, (256 << 1) | 1
        jne .Lms_f
        call sb_new
        mov [rsp + PF_SB], rax
        mov rdi, rax
        mov rsi, [rsp + PF_T3]
        mov edx, P_SHIFT
        mov rcx, r12
        and ecx, PF_COLOR
        call sb_append_operand
        mov rdi, [rsp + PF_SB]
        lea rsi, [rip + .Ls_shr_op]
        lea rdx, [rip + C_BOLD]
        mov rcx, r12
        call sb_append_bold_c
        mov rdi, [rsp + PF_SB]
        mov rsi, r14
        mov edx, P_SHIFT + 1
        mov rcx, r12
        and ecx, PF_COLOR
        call sb_append_operand
        mov r13, [rsp + PF_SB]
        mov r14d, P_SHIFT
        jmp .Lpf_finish_wrap
.Lms_f:
        # the mask, under a shift of the side shift_sign says (or a shift
        # that may be one way or the other)
        mov rdi, [rsp + PF_T2]
        call shift_sign
        mov [rsp + PF_T4], rax          # 1, -1, 0, 2 (None)
        LOADS rdi, MASK
        mov rsi, r13
        mov rdx, r14
        mov rcx, [rsp + PF_T3]
        call mk4
        mov [rsp + PF_T1], rax          # mask
        cmp qword ptr [rsp + PF_T2], 1  # shl == 0: the mask
        jne 1f
        mov rbx, rax
        jmp .Lpf_mask_after251
1:      cmp dword ptr [rsp + PF_T4], 1
        jne 4f
        # a shift left
        mov edi, 3
        lea rsi, [rbx + N_DATA + 8]
        call all_ints
        test eax, eax
        jz 2f
        mov rdi, r13
        mov rsi, [rsp + PF_T2]
        call int_add
        cmp rax, (256 << 1) | 1
        jne 2f
        cmp r14, 1
        jne 2f
        # the bits that the multiplication keeps: ('mul', 2**shl, val)
        mov rdi, [rsp + PF_T2]
        call pow2_exact
        mov rsi, rax
        mov rdx, [rsp + PF_T3]
        jmp 21f
2:      mov rdi, [rsp + PF_T2]          # an int below 7: ('mul', 2**shl, mask)
        call is_int
        test eax, eax
        jz 3f
        mov rdi, [rsp + PF_T2]
        mov rsi, (7 << 1) | 1
        call int_cmp
        cmp eax, -1
        jne 3f
        mov rdi, [rsp + PF_T2]
        call pow2_exact
        mov rsi, rax
        mov rdx, [rsp + PF_T1]
21:     LOADS rdi, MUL
        call mk3
        mov rbx, rax
        jmp .Lpf_dispatch
3:      mov rsi, [rsp + PF_T2]          # ('shl', shl, mask)
        mov rdx, [rsp + PF_T1]
        LOADS rdi, SHL
        call mk3
        mov rbx, rax
        jmp .Lpf_dispatch
4:      cmp dword ptr [rsp + PF_T4], -1
        jne 6f
        # a shift right, by right = minus_op(shl): ('div', mask, 2**right)
        # for an int up to 8, else ('shr', right, mask)
        mov rdi, [rsp + PF_T2]
        call alg_minus_op
        mov [rsp + PF_T4], rax
        mov rdi, rax
        call is_int
        test eax, eax
        jz 5f
        mov rdi, [rsp + PF_T4]
        mov rsi, (8 << 1) | 1
        call int_cmp
        cmp eax, 1
        je 5f
        mov rdi, [rsp + PF_T4]
        call int_sign
        cmp eax, -1
        je 41f
        mov rdi, [rsp + PF_T4]
        call pow2_exact
        jmp 42f
41:     mov rdi, [rsp + PF_T4]          # (a float, as python's 2 ** -k)
        test dil, 1
        jz 43f
        sar rdi, 1
        call pow2_or_float
        jmp 42f
43:     mov eax, 1                      # (0.0: printed 0)
42:     mov rdx, rax
        mov rsi, [rsp + PF_T1]
        LOADS rdi, DIV
        call mk3
        mov rbx, rax
        jmp .Lpf_dispatch
5:      mov rsi, [rsp + PF_T4]
        mov rdx, [rsp + PF_T1]
        LOADS rdi, SHR
        call mk3
        mov rbx, rax
        jmp .Lpf_dispatch
6:      # a shift that may be one way or the other (see OUTPUT.md)
        LOADS rdi, SHIFT
        mov rsi, [rsp + PF_T1]
        mov rdx, [rsp + PF_T2]
        call mk3
        mov rbx, rax
        jmp .Lpf_dispatch
.Lms_pret_ctx:
        # pret(rax, parentheses=ctx)
        mov rdi, rax
        CTXF rsi
        call prettify
        jmp .Lpf_ret



.Lpf_mask:
        # ('mask', 251, 5, val): ceil32 / floor32
        PAT rsi, "('mask', 251, 5, ':val')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lpf_mask_after251
        B rdi, 0
        mov rsi, r12
        call pf_floor32
        jmp .Lpf_ret
.Lpf_mask_after251:
        cmp dword ptr [rbx + N_AUX], 4
        jne .Lpf_default
        mov r13, [rbx + N_DATA + 8]     # size
        mov r14, [rbx + N_DATA + 24]    # val
        cmp qword ptr [rbx + N_DATA + 16], 1    # offset == 0
        jne 5f
        cmp r13, (256 << 1) | 1         # size == 256 and not may_be_wide(val)
        jne 2f
        mov rdi, r14
        call may_be_wide
        test eax, eax
        jnz 2f
        mov rdi, r14
        CTXF rsi
        call prettify
        jmp .Lpf_ret
2:      mov rdi, r13
        call is_int
        test eax, eax
        jz 5f
        cmp r13, 3                      # size not in (1, 256): the lowest
        je 5f                           # bit of a number isn't a bool (x % 2)
        cmp r13, (256 << 1) | 1
        je 5f
        cmp r13, (255 << 1) | 1
        jne 3f
        lea rdi, [rip + .Ls_uint255]
        call str_new_c
        jmp 4f
3:      mov rdi, r13
        xor esi, esi
        call mask_to_type
        test rax, rax
        jnz 4f
        # uint24, uint96... like the ones above (0 < size < 256, size % 8 == 0)
        test r13b, 1
        jz 5f
        mov rax, r13
        sar rax, 1
        test rax, rax
        jle 5f
        cmp rax, 256
        jge 5f
        test al, 7
        jnz 5f
        mov rdi, rax
        call uint_name
4:      # type_name(val)
        mov rdi, rax
        mov rsi, r14
        mov rdx, r12
        call pf_type_call
        jmp .Lpf_ret
5:      # an int size below 64 with offset 0: a modulo; else Mask(size, offset, val)
        mov rdi, r13
        call is_int
        test eax, eax
        jz 6f
        cmp qword ptr [rbx + N_DATA + 16], 1
        jne 6f
        mov rdi, r13
        mov rsi, (64 << 1) | 1
        call int_cmp
        cmp eax, -1
        jne 6f
        mov rdi, r13
        test dil, 1
        jz 61f                          # a big int below 64: 2 ** it is 0.0
        sar rdi, 1
        call pow2_or_float              # (a float below zero, as python)
        jmp 62f
61:     mov eax, 1                      # (0.0: printed 0)
62:     mov rdx, rax
        mov rsi, r14
        LOADS rdi, MOD
        call mk3
        mov rdi, rax
        CTXF rsi
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

.Lpf_shift:
        # a shift that may be one way or the other: shift(val, amount)
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lpf_default
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_shift_]
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

.Lpf_sar_shr:
        # the shifts the vm leaves as they are: the arithmetic ones (>>′),
        # and the ones by a symbolic amount
        mov rdi, rbx
        call opcode_of
        mov r13d, eax
        cmp dword ptr [rbx + N_AUX], 3
        jne 3f
        lea r14, [rip + .Ls_sar_op]
        cmp r13d, OP_SAR
        je 1f
        lea r14, [rip + .Ls_shr_op]
        mov rdi, [rbx + N_DATA + 8]     # (isinstance(off, int): a bool too)
        call is_int
        test eax, eax
        jnz .Lpf_arith
        mov rdi, [rbx + N_DATA + 8]
        mov esi, SP_TRUE
        call is_special
        test eax, eax
        jnz .Lpf_arith
        mov rdi, [rbx + N_DATA + 8]
        mov esi, SP_FALSE
        call is_special
        test eax, eax
        jnz .Lpf_arith
1:      call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, [rbx + N_DATA + 16]
        mov edx, P_SHIFT
        mov rcx, r12
        and ecx, PF_COLOR
        call sb_append_operand
        mov rdi, r13
        mov rsi, r14
        lea rdx, [rip + C_BOLD]
        mov rcx, r12
        call sb_append_bold_c
        mov rdi, r13
        mov rsi, [rbx + N_DATA + 8]
        mov edx, P_SHIFT + 1
        mov rcx, r12
        and ecx, PF_COLOR
        call sb_append_operand
        mov r14d, P_SHIFT
        jmp .Lpf_finish_wrap
3:      cmp r13d, OP_SHR
        je .Lpf_arith
        jmp .Lpf_default

.Lpf_not:
        # bitwise, as in python: `not` is the logical one (iszero)
        cmp dword ptr [rbx + N_AUX], 2
        jb .Lpf_index
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_tilde]
        lea rdx, [rip + C_BOLD]
        mov rcx, r12
        call sb_append_col_c
        mov rdi, r13
        mov rsi, [rbx + N_DATA + 8]
        mov edx, P_UNARY
        mov rcx, r12
        and ecx, PF_COLOR
        call sb_append_operand
        mov r14d, P_UNARY
        jmp .Lpf_finish_wrap

.Lpf_add:
        mov rdi, rbx
        mov rsi, r12
        mov rdx, [rsp + PF_CTX]
        call pretty_adds
        jmp .Lpf_ret

.Lpf_mul:
        # a multiplication by a big power of two is a shift
        cmp dword ptr [rbx + N_AUX], 3
        jne 1f
        mov rdi, [rbx + N_DATA + 8]
        call is_int
        test eax, eax
        jz 1f
        mov rdi, [rbx + N_DATA + 8]
        call to_exp2
        cmp rax, 32
        jle 1f
        mov rsi, rax
        TAG rsi
        mov rdx, [rbx + N_DATA + 16]
        LOADS rdi, SHL
        call mk3
        mov rbx, rax
        jmp .Lpf_arith
1:      cmp dword ptr [rbx + N_AUX], 2
        jb .Lpf_arith
        mov rax, [rbx + N_DATA + 8]
        cmp rax, -1                     # ('mul', -1, val): -val
        jne 2f
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lpf_arith
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov esi, '-'
        call sb_append_char
        mov rdi, r13
        mov rsi, [rbx + N_DATA + 16]
        mov edx, P_UNARY
        mov rcx, r12
        and ecx, PF_COLOR
        call sb_append_operand
        mov r14d, P_UNARY
        jmp .Lpf_finish_wrap
2:      cmp rax, 3                      # ('mul', 1, ...)
        jne .Lpf_arith
        cmp dword ptr [rbx + N_AUX], 3
        jne 3f
        mov rdi, [rbx + N_DATA + 16]
        CTXF rsi
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
        CTXF rsi
        call prettify
        jmp .Lpf_ret

.Lpf_div:
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lpf_arith
        cmp qword ptr [rbx + N_DATA + 16], 3    # ('div', num, 1)
        jne .Lpf_arith
        mov rdi, [rbx + N_DATA + 8]
        CTXF rsi
        call prettify
        jmp .Lpf_ret

.Lpf_exp:
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lpf_arith
        # wrap(operand(a, POW + 1) + "**" + operand(n, POW), POW)
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, [rbx + N_DATA + 8]
        mov edx, P_POW + 1
        mov rcx, r12
        and ecx, PF_COLOR
        call sb_append_operand
        mov rdi, r13
        lea rsi, [rip + .Ls_pow]
        call sb_append_c
        mov rdi, r13
        mov rsi, [rbx + N_DATA + 16]
        mov edx, P_POW
        mov rcx, r12
        and ecx, PF_COLOR
        call sb_append_operand
        mov r14d, P_POW
        jmp .Lpf_finish_wrap

.Lpf_land:
        # python's and / or (see postprocess.short_circuits): the operand
        # that decides - printed as the value it is where it may be the one
        # given (the last of an and, any of an or), unless only its truth
        # counts
        mov rdi, rbx
        call opcode_of
        lea rsi, [rip + .Ls_and_op]
        mov r14d, P_AND
        cmp eax, OP_LAND
        je 1f
        lea rsi, [rip + .Ls_or_op]
        mov r14d, P_OR
1:      mov [rsp + PF_T1], eax
        mov [rsp + PF_T2], rsi
        call sb_new
        mov r13, rax
        mov qword ptr [rsp + PF_T3], 1
2:      mov rcx, [rsp + PF_T3]
        cmp ecx, [rbx + N_AUX]
        jae 5f
        cmp rcx, 1
        je 3f
        mov rdi, r13
        mov rsi, [rsp + PF_T2]
        lea rdx, [rip + C_BOLD]
        mov rcx, r12
        call sb_append_bold_c
3:      # rem_bool or (an and, and not its last operand)
        mov rcx, r12
        and ecx, PF_COLOR | PF_REM_BOOL
        cmp dword ptr [rsp + PF_T1], OP_LAND
        jne 4f
        mov rax, [rsp + PF_T3]
        inc eax
        cmp eax, [rbx + N_AUX]
        jae 4f
        or ecx, PF_REM_BOOL
4:      mov rax, [rsp + PF_T3]
        mov rdi, r13
        mov rsi, [rbx + N_DATA + rax*8]
        mov edx, r14d
        call sb_append_operand
        inc qword ptr [rsp + PF_T3]
        jmp 2b
5:      jmp .Lpf_finish_wrap

.Lpf_arith:
        mov rdi, rbx
        call opcode_of
        mov r13d, eax
        lea rcx, [rip + arith_ops]
        cmp qword ptr [rcx + rax*8], 0
        je .Lpf_default
        # shifts: the operands swapped (exp[0], exp[2], exp[1])
        cmp eax, OP_SHL
        je 1f
        cmp eax, OP_SHR
        jne 2f
1:      cmp dword ptr [rbx + N_AUX], 3
        jb .Lpf_index
        mov rdi, [rbx + N_DATA]
        mov rsi, [rbx + N_DATA + 16]
        mov rdx, [rbx + N_DATA + 8]
        call mk3
        mov rbx, rax
        jmp 3f
2:      # unsigned: a number of the top half of the words is no negative
        IN_OPSET order_cmps, r13
        je 3f
        mov rdi, rbx
        call unsigned_operands
        mov rbx, rax
3:      cmp r13d, OP_AND
        je 31f
        cmp r13d, OP_OR
        jne .Lpf_arith_plain
31:     # python's and / or: of truth values, they're the bitwise ones; of
        # any values, an or is true where the bitwise one is
        mov rdi, rbx
        call all_bool_operands
        test eax, eax
        jnz 4f
        cmp r13d, OP_OR
        jne .Lpf_arith_plain
        test r12, PF_REM_BOOL
        jz .Lpf_arith_plain
4:      cmp r13d, OP_AND
        jne 5f
        mov rdi, rbx
        call fold_ands
        mov rbx, rax
        lea rax, [rip + .Ls_and_op]
        mov [rsp + PF_T2], rax
        mov r14d, P_AND
        jmp 6f
5:      lea rax, [rip + .Ls_or_op]
        mov [rsp + PF_T2], rax
        mov r14d, P_OR
6:      # where its value counts, not only its truth, they give the operand
        # that decides: the last of an and, any of an or, which is then
        # printed as the 0 or 1 it is (bool(x), not x)
        call sb_new
        mov r13, rax
        mov qword ptr [rsp + PF_T3], 1
7:      mov rcx, [rsp + PF_T3]
        cmp ecx, [rbx + N_AUX]
        jae .Lpf_finish_wrap
        cmp rcx, 1
        je 8f
        mov rdi, r13
        mov rsi, [rsp + PF_T2]
        lea rdx, [rip + C_BOLD]
        mov rcx, r12
        call sb_append_bold_c
8:      mov rcx, r12
        and ecx, PF_COLOR | PF_REM_BOOL
        mov rdi, [rbx + N_DATA]
        mov eax, [rdi + N_AUX]
        and eax, STR_ID_MASK
        cmp eax, OP_AND
        jne 9f
        mov rax, [rsp + PF_T3]
        inc eax
        cmp eax, [rbx + N_AUX]
        jae 9f
        or ecx, PF_REM_BOOL
9:      mov rax, [rsp + PF_T3]
        mov rdi, r13
        mov rsi, [rbx + N_DATA + rax*8]
        lea edx, [r14 + 1]
        call sb_append_operand
        inc qword ptr [rsp + PF_T3]
        jmp 7b
.Lpf_arith_plain:
        # the operands after the first bind tighter: a / (b / c) isn't
        # a / b / c, a * (b / c) isn't a * b / c; and comparisons don't
        # chain
        cmp dword ptr [rbx + N_AUX], 2
        jb .Lpf_index
        mov rdi, rbx
        call opcode_of
        lea rcx, [rip + arith_prec]
        movzx r14d, byte ptr [rcx + rax]
        lea rcx, [rip + arith_ops]
        mov rax, [rcx + rax*8]
        mov [rsp + PF_T2], rax          # the operator
        call sb_new
        mov r13, rax
        mov edx, r14d                   # first_prec
        cmp r14d, P_CMP
        jne 1f
        inc edx
1:      mov rdi, r13
        mov rsi, [rbx + N_DATA + 8]
        mov rcx, r12
        and ecx, PF_COLOR
        call sb_append_operand
        mov qword ptr [rsp + PF_T3], 2
2:      mov rcx, [rsp + PF_T3]
        cmp ecx, [rbx + N_AUX]
        jae .Lpf_finish_wrap
        mov rdi, r13
        mov rsi, [rsp + PF_T2]
        lea rdx, [rip + C_BOLD]
        mov rcx, r12
        call sb_append_bold_c
        mov rax, [rsp + PF_T3]
        mov rdi, r13
        mov rsi, [rbx + N_DATA + rax*8]
        lea edx, [r14 + 1]
        mov rcx, r12
        and ecx, PF_COLOR
        call sb_append_operand
        inc qword ptr [rsp + PF_T3]
        jmp 2b

.Lpf_iszero:
        cmp dword ptr [rbx + N_AUX], 2
        jne .Lpf_default
        mov r13, [rbx + N_DATA + 8]     # val
        mov rdi, r13
        call opcode_of
        cmp eax, OP_LT
        je 1f
        cmp eax, OP_GT
        jne 2f
1:      mov rdi, r13
        call unsigned_operands
        mov r13, rax
2:      mov rdi, r13
        call opcode_of
        test eax, eax
        jz 6f                           # (not a tuple)
        cmp dword ptr [r13 + N_AUX], 3
        jne 6f
        lea r14, [rip + .Ls_le]
        cmp eax, OP_GT
        je 5f
        lea r14, [rip + .Ls_ge]
        cmp eax, OP_LT
        je 5f
        cmp eax, OP_EQ
        jne 6f
        # a != b, the constant on the right
        lea r14, [rip + .Ls_ne]
        mov rdi, [r13 + N_DATA + 8]
        call is_str
        test eax, eax
        jnz 3f
        mov rdi, [r13 + N_DATA + 8]
        call is_int
        test eax, eax
        jz 5f
3:      mov rdi, [r13 + N_DATA]
        mov rsi, [r13 + N_DATA + 16]
        mov rdx, [r13 + N_DATA + 8]
        call mk3
        mov r13, rax
5:      # comparison(left, op, right)
        call sb_new
        mov [rsp + PF_SB], rax
        mov rdi, rax
        mov rsi, [r13 + N_DATA + 8]
        mov edx, P_CMP + 1
        mov rcx, r12
        and ecx, PF_COLOR
        call sb_append_operand
        mov rdi, [rsp + PF_SB]
        mov rsi, r14
        call sb_append_c
        mov rdi, [rsp + PF_SB]
        mov rsi, [r13 + N_DATA + 16]
        mov edx, P_CMP + 1
        mov rcx, r12
        and ecx, PF_COLOR
        call sb_append_operand
        mov r13, [rsp + PF_SB]
        mov r14d, P_CMP
        jmp .Lpf_finish_wrap
6:      # (of its operand, only the truth counts: not bool(x) is not x)
        call sb_new
        mov r14, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_not_sp]
        call sb_append_c
        mov rdi, r14
        mov rsi, r13
        mov edx, P_NOT
        mov rcx, r12
        and ecx, PF_COLOR
        or ecx, PF_REM_BOOL
        call sb_append_operand
        mov r13, r14
        mov r14d, P_NOT
        jmp .Lpf_finish_wrap

.Lpf_finish_wrap:
        # wrap(the text of r13, r14d)
        mov rdi, r13
        call sb_finish
        mov rdi, rax
        mov esi, r14d
        mov rdx, [rsp + PF_CTX]
        call pf_wrap
        jmp .Lpf_ret
.Lpf_finish:
        mov rdi, r13
        call sb_finish
.Lpf_ret:
        add rsp, MATCH_BINDINGS_SIZE + 64
        LEAVE
ENDF prettify

        .section .rodata
.Ls_pf_index:   .asciz "IndexError: tuple index out of range (prettify)"
.Ls_pf_mem_assert: .asciz "prettify: a ('mem', ('range', ...)) of another length"
.Ls_sha3_:      .asciz "sha3("
        .text

        OPSET_MEMBER boolish, OP_LT
        OPSET_MEMBER boolish, OP_GT
        OPSET_MEMBER boolish, OP_ISZERO
        OPSET_MEMBER boolish, OP_LE
        OPSET_MEMBER boolish, OP_GE
        OPSET_MEMBER boolish, OP_BOOL
        OPSET_END boolish, OP_COUNT

        OPSET_MEMBER order_cmps, OP_LT
        OPSET_MEMBER order_cmps, OP_GT
        OPSET_MEMBER order_cmps, OP_LE
        OPSET_MEMBER order_cmps, OP_GE
        OPSET_END order_cmps, OP_COUNT

# sb_append_bold_c(sb, cstr, color_cstr, flags): an operator, bold when
# colored (COLOR_BOLD + op + ENDC: python's, even of an empty one)
FUNC sb_append_bold_c
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        test rcx, PF_COLOR
        jz 1f
        mov rsi, rdx
        call sb_append_c
        mov rdi, rbx
        mov rsi, r12
        call sb_append_c
        mov rdi, rbx
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        LEAVE
1:      mov rsi, r12
        call sb_append_c
        LEAVE
ENDF sb_append_bold_c

# data_of_rest(seq, start) -> tuple: ('data',) + seq[start:]
FUNC data_of_rest
        ENTER
        call list_from
        mov rdi, rax
        LOADS rsi, DATA
        call list_prepend
        mov rdi, rax
        call seq_to_tuple
        LEAVE
ENDF data_of_rest

# unsigned_operands(exp) -> tuple: (exp[0],) + tuple(unsigned(e) for e in
# exp[1:]) - a number as the unsigned word it is: 2**256 - 1 rather than -1
FUNC unsigned_operands
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        mov rdi, rax
        mov rsi, [rbx + N_DATA]
        call vec_push
        mov r13d, 1
1:      cmp r13d, [rbx + N_AUX]
        jae 3f
        mov r14, [rbx + N_DATA + r13*8]
        mov rdi, r14
        call is_int
        test eax, eax
        jz 2f
        mov rdi, r14
        mov esi, 256
        call int_mod_2exp
        mov r14, rax
2:      mov rdi, r12
        mov rsi, r14
        call vec_push
        inc r13d
        jmp 1b
3:      mov rdi, r12
        call vec_to_tuple
        LEAVE
ENDF unsigned_operands

# all_bool_operands(exp) -> eax: all(is_bool(e) for e in exp[1:])
FUNC all_bool_operands
        ENTER
        mov rbx, rdi
        mov r12d, 1
1:      cmp r12d, [rbx + N_AUX]
        jae 2f
        mov rdi, [rbx + N_DATA + r12*8]
        call is_bool
        test eax, eax
        jz 3f
        inc r12d
        jmp 1b
2:      mov eax, 1
        LEAVE
3:      xor eax, eax
        LEAVE
ENDF all_bool_operands

# pf_floor32(val, flags) -> str: of a mask of 251 bits from 5, ceil32(num)
# when val is ('add', 31, num), else floor32(val)
FUNC pf_floor32
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call sb_new
        mov r13, rax
        mov rdi, rbx
        OP_N_CHECK OP_ADD, 3, 1f
        cmp qword ptr [rbx + N_DATA + 8], (31 << 1) | 1
        jne 1f
        mov rdi, r13
        lea rsi, [rip + .Ls_ceil32]
        call sb_append_c
        mov rdi, r13
        mov rsi, [rbx + N_DATA + 16]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        jmp 2f
1:      mov rdi, r13
        lea rsi, [rip + .Ls_floor32]
        call sb_append_c
        mov rdi, r13
        mov rsi, rbx
        PF_COLOR_OF rdx, r12
        call sb_append_pret
2:      mov rdi, r13
        mov esi, ')'
        call sb_append_char
        mov rdi, r13
        call sb_finish
        LEAVE
ENDF pf_floor32

# uint_name(n) -> str: "uint" + str(n) (n a small positive int)
FUNC uint_name
        ENTER
        mov rbx, rdi
        call sb_new
        mov r12, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_uint]
        call sb_append_c
        mov rdi, r12
        mov rsi, rbx
        call sb_append_u64
        mov rdi, r12
        call sb_finish
        LEAVE
ENDF uint_name

# pf_type_call(type_name, val, flags) -> str: col(type_name + "(", GRAY) +
# pret(val) + col(")", GRAY)
FUNC pf_type_call
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rdx
        mov r14, rsi
        call sb_new
        mov r13, rax
        lea rdi, [rip + .Ls_lparen_t]
        call str_new_c
        mov rdi, rbx
        mov rsi, rax
        call str_cat2
        mov rdi, r13
        mov rsi, rax
        lea rdx, [rip + C_GRAY]
        mov rcx, r12
        call sb_append_col
        mov rdi, r13
        mov rsi, r14
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, r13
        lea rsi, [rip + .Ls_rparen]
        lea rdx, [rip + C_GRAY]
        mov rcx, r12
        call sb_append_col_c
        mov rdi, r13
        call sb_finish
        LEAVE
ENDF pf_type_call

        .section .rodata
.Ls_lparen_t: .asciz "("
        .text

# pretty_adds(exp, flags, ctx) -> str: an ('add', ...) as a sum, the
# number last
FUNC pretty_adds
        STACK_CHECK
        ENTER
        sub rsp, 48
        .set PA_SB, 0
        .set PA_REAL, 8
        .set PA_I, 16
        .set PA_CTX, 24
        mov rbx, rdi
        mov r12, rsi
        mov [rsp + PA_CTX], rdx
        cmp dword ptr [rbx + N_AUX], 2
        jb .Lpa_index
        call sb_new
        mov [rsp + PA_SB], rax
        mov qword ptr [rsp + PA_REAL], 1        # real = 0
        mov qword ptr [rsp + PA_I], 1           # the terms from exp[1]
        mov r13, [rbx + N_DATA + 8]
        mov rdi, r13
        call is_int
        test eax, eax
        jz 1f
        mov rdi, r13
        call to_real_int
        mov [rsp + PA_REAL], rax
        mov qword ptr [rsp + PA_I], 2
        jmp 2f
1:      mov rdi, r13                    # a float (python's 32.0 is 32: the
        call is_str                     # port's floats are below 1)
        test eax, eax
        jz 2f
        test dword ptr [r13 + N_AUX], STR_FLOAT
        jz 2f
        mov [rsp + PA_REAL], r13
        mov qword ptr [rsp + PA_I], 2
2:      # the terms
        mov rcx, [rsp + PA_I]
        cmp ecx, [rbx + N_AUX]
        jae .Lpa_real
        mov r13, [rbx + N_DATA + rcx*8]
        mov rax, [rsp + PA_SB]
        cmp qword ptr [rax + SB_LEN], 0
        jne 3f
        mov rdi, rax
        mov rsi, r13
        mov edx, P_ADD
        mov rcx, r12
        and ecx, PF_COLOR
        call sb_append_operand
        jmp 5f
3:      # " - " + operand(minus_op(x), ADD + 1) for a ('mul', -n, ...)
        mov rdi, r13
        call opcode_of
        cmp eax, OP_MUL
        jne 4f
        cmp dword ptr [r13 + N_AUX], 2
        jb .Lpa_index
        mov rdi, [r13 + N_DATA + 8]
        call is_int
        test eax, eax
        jz 4f
        mov rdi, [r13 + N_DATA + 8]
        call int_sign
        cmp eax, -1
        jne 4f
        mov rdi, [rsp + PA_SB]
        lea rsi, [rip + .Ls_minus_sp]
        call sb_append_c
        mov rdi, r13
        call alg_minus_op
        mov rdi, [rsp + PA_SB]
        mov rsi, rax
        mov edx, P_ADD + 1
        mov rcx, r12
        and ecx, PF_COLOR
        call sb_append_operand
        jmp 5f
4:      mov rdi, [rsp + PA_SB]
        lea rsi, [rip + .Ls_plus_sp]
        call sb_append_c
        mov rdi, [rsp + PA_SB]
        mov rsi, r13
        mov edx, P_ADD
        mov rcx, r12
        and ecx, PF_COLOR
        call sb_append_operand
5:      inc qword ptr [rsp + PA_I]
        jmp 2b
.Lpa_real:
        mov r13, [rsp + PA_REAL]
        mov rdi, r13
        call is_str
        test eax, eax
        jnz .Lpa_float
        mov rdi, r13
        call int_sign
        cmp eax, 1
        je 6f
        cmp eax, -1
        jne .Lpa_wrap
        # real <= -(2 ** 128): a big one - a hash, say - is added, however
        # large it is
        mov edi, 128
        call pow2
        mov rdi, rax
        call int_neg
        mov rdi, r13
        mov rsi, rax
        call int_cmp
        cmp eax, 1
        je 7f
6:      # " + " + operand(real % 2**256, ADD)
        mov rdi, [rsp + PA_SB]
        lea rsi, [rip + .Ls_plus_sp]
        call sb_append_c
        mov rdi, r13
        mov esi, 256
        call int_mod_2exp
        mov rdi, [rsp + PA_SB]
        mov rsi, rax
        mov edx, P_ADD
        mov rcx, r12
        and ecx, PF_COLOR
        call sb_append_operand
        jmp .Lpa_wrap
7:      # " - " + operand(-real, ADD + 1)
        mov rdi, [rsp + PA_SB]
        lea rsi, [rip + .Ls_minus_sp]
        call sb_append_c
        mov rdi, r13
        call int_neg
        mov rdi, [rsp + PA_SB]
        mov rsi, rax
        mov edx, P_ADD + 1
        mov rcx, r12
        and ecx, PF_COLOR
        call sb_append_operand
        jmp .Lpa_wrap
.Lpa_float:
        # a (positive) float: " + " + operand(real % 2**256, ADD), itself
        mov rdi, [rsp + PA_SB]
        lea rsi, [rip + .Ls_plus_sp]
        call sb_append_c
        mov rdi, [rsp + PA_SB]
        mov rsi, r13
        mov edx, P_ADD
        mov rcx, r12
        and ecx, PF_COLOR
        call sb_append_operand
.Lpa_wrap:
        mov rdi, [rsp + PA_SB]
        call sb_finish
        mov rdi, rax
        mov esi, P_ADD
        mov rdx, [rsp + PA_CTX]
        call pf_wrap
        add rsp, 48
        LEAVE
.Lpa_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_pf_index]
        call err_throw
ENDF pretty_adds

# --- numbers ---

# pretty_num(v, flags) -> str: a number as text - hex for the big ones,
# multiples of powers of ten as such, the words of the top half (of
# more than 30 bytes: an address, not a negative number) in hex
FUNC pretty_num
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rbx
        call is_int
        test eax, eax
        jz .Lpn_str
        test bl, 1
        jz 5f
        # a small int: never above 8 ** 50, and the multiples of 10^9 and
        # up and of 10^6 are multiples of 10^6 (most numbers aren't: none
        # of the eleven divisions then)
        cmp rbx, 1                      # zero
        je .Lpn_plain
        mov rax, rbx
        sar rax, 1
        cqo
        mov ecx, 1000000
        idiv rcx
        test rdx, rdx
        jnz .Lpn_plain
        jmp 6f
5:      # above 8 ** 50: binary data, in hex
        mov edi, 150
        call pow2
        mov rdi, rbx
        mov rsi, rax
        call int_cmp
        cmp eax, 1
        je .Lpn_hex
        lea rdi, [rbx + N_DATA]         # (not a multiple of 10^6: none)
        mov esi, 1000000
        call __gmpz_divisible_ui_p@PLT
        test eax, eax
        jz .Lpn_plain
6:      # a multiple of 10^18 .. 10^9, or of 10^6
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
        # the word (-2**256 + 128 is 128): below 8 ** 30, in decimal; else
        # hex when positive
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
        mov rdi, r13
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
        # "10**count" or "q * 10**count"
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

# --- the names of the variables ---

        # the names state (CTX_NAMES): python's _names - the storage
        # variables' names (of the contract) and the params' (of the
        # function printed), and what's made of them: the NICE_NAMES that
        # aren't taken
        .set NM_STORAGE, 0              # a list of str, or 0 (none)
        .set NM_PARAMS, 8               # a list of str, or 0
        .set NM_NFREE, 16               # the count of the free nice names
        .set NM_FREE, 24                # their texts (C strings), in order
        .set NM_SIZEOF, NM_FREE + 8 * NICE_NAMES_COUNT

# set_names(storage, params): python's set_names - the names of the
# storage variables (of the contract; 0: as they were) and of the params
# (of the function printed; 0: none) - the variables of its loops have
# others: `s = ...` would be a write to the storage variable s, and `x` a
# param x. On the context (CTX_NAMES): a thread printing what another one
# set takes that one's (a pointer to a record that never changes).
FUNC set_names
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov edi, NM_SIZEOF
        call arena_alloc
        mov r13, rax
        mov rax, [r15 + CTX_NAMES]
        xor ecx, ecx
        test rax, rax
        jz 1f
        mov rcx, [rax + NM_STORAGE]
1:      test rbx, rbx
        jz 2f
        mov rcx, rbx
2:      mov [r13 + NM_STORAGE], rcx
        mov [r13 + NM_PARAMS], r12
        mov [r15 + CTX_NAMES], r13      # (name_taken reads it)
        # the free nice names
        xor r14d, r14d
        mov qword ptr [r13 + NM_NFREE], 0
3:      cmp r14d, NICE_NAMES_COUNT
        jae 5f
        lea rax, [rip + nice_names]
        mov rdi, [rax + r14*8]
        call name_taken_c
        test eax, eax
        jnz 4f
        lea rax, [rip + nice_names]
        mov rdx, [rax + r14*8]
        mov rcx, [r13 + NM_NFREE]
        mov [r13 + NM_FREE + rcx*8], rdx
        inc qword ptr [r13 + NM_NFREE]
4:      inc r14d
        jmp 3b
5:      LEAVE
ENDF set_names

# names_state() -> rax: the context's names record (made, without names
# but the builtin ones, the first time)
FUNC names_state
        mov rax, [r15 + CTX_NAMES]
        test rax, rax
        jz 1f
        ret
1:      ENTER
        xor edi, edi
        xor esi, esi
        call set_names
        mov rax, [r15 + CTX_NAMES]
        LEAVE
ENDF names_state

# name_taken_c(cstr) -> eax: python's `name in _names["taken"]` - a
# builtin name, a storage variable's, a param's
FUNC name_taken_c
        ENTER
        mov rbx, rdi
        lea r12, [rip + builtin_names]
1:      mov rsi, [r12]
        test rsi, rsi
        jz 2f
        mov rdi, rbx
        call strcmp@PLT
        test eax, eax
        jz 8f
        add r12, 8
        jmp 1b
2:      mov r13, [r15 + CTX_NAMES]
        test r13, r13
        jz 9f
        mov rdi, [r13 + NM_STORAGE]
        mov rsi, rbx
        call str_in_list_c
        test eax, eax
        jnz 8f
        mov rdi, [r13 + NM_PARAMS]
        mov rsi, rbx
        call str_in_list_c
        test eax, eax
        jnz 8f
9:      xor eax, eax
        LEAVE
8:      mov eax, 1
        LEAVE
ENDF name_taken_c

# str_in_list_c(list or 0, cstr) -> eax: one of the strings of the list
# has that text
FUNC str_in_list_c
        ENTER
        mov rbx, rdi
        mov r12, rsi
        test rbx, rbx
        jz 9f
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 9f
        mov rdi, [rbx + N_DATA + r13*8]
        inc r13d
        call is_str
        test eax, eax
        jz 1b
        mov rdi, [rbx + N_DATA + r13*8 - 8]
        mov rsi, r12
        call str_eq_c
        test eax, eax
        jz 1b
        mov eax, 1
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF str_in_list_c

# var_name(str) -> str: python's var_name - the name a variable with a
# name (the result of a precompiled contract, `_3`...) is printed with:
# its own, then _ while that's the name of something else - `signer_ =
# ecrecover(...)` where signer is a storage variable or a param
FUNC var_name
        ENTER
        mov rbx, rdi
        call names_state
1:      lea rdi, [rbx + N_DATA + 4]
        call name_taken_c
        test eax, eax
        jz 2f
        lea rdi, [rip + .Ls_underscore]
        call str_new_c
        mov rdi, rbx
        mov rsi, rax
        call str_cat2
        mov rbx, rax
        jmp 1b
2:      mov rax, rbx
        LEAVE
ENDF var_name

        .section .rodata
.Ls_underscore: .asciz "_"
        .text


# pow2_or_float(k) -> value: 2 ** k; for a negative k python has a float,
# printed as its repr - that text (a string) stands for it here
FUNC pow2_or_float
        test rdi, rdi
        js 1f
        jmp pow2
1:      neg rdi
        cmp rdi, 8
        ja 2f
        lea rax, [rip + float_pow2]
        mov rdi, [rax + rdi*8]
        jmp float_str
2:      neg rdi
        jmp pow2_float_str
ENDF pow2_or_float

# pow2_float_str(k) -> the float 2.0 ** k (k < 0) as python's repr
# (float_repr); below 2^-1074 it is 0.0, which python prints as 0: the
# int 0 then
FUNC pow2_float_str
        cmp rdi, -1022
        jl 1f
        lea rax, [rdi + 1023]
        shl rax, 52                     # a normal double: the exponent alone
        movq xmm0, rax
        jmp float_repr
1:      cmp rdi, -1074
        jl 2f
        lea rcx, [rdi + 1074]
        mov eax, 1
        shl rax, cl                     # a subnormal: one bit of the mantissa
        movq xmm0, rax
        jmp float_repr
2:      mov eax, 1
        ret
ENDF pow2_float_str

# float_repr(x: xmm0, positive, finite) -> the interned STR_FLOAT string of
# python's repr(x): the shortest decimal that reads back as x (the
# nearest one of that length: the correctly rounded digits, or the next
# ones up or down when those fall outside x's rounding interval, which
# happens at powers of two), fixed notation from 1e-4 to 1e16
FUNC float_repr
        ENTER
        sub rsp, 144
        .set FR_X, 0
        .set FR_P, 8                    # the number of digits
        .set FR_EXP, 16                 # the decimal exponent
        .set FR_DIGS, 32                # the digits (up to 17), then a candidate
        .set FR_BUF, 64                 # snprintf's text; the result
        movq [rsp + FR_X], xmm0
        mov qword ptr [rsp + FR_P], 1
.Lfr_try:
        lea rdi, [rsp + FR_BUF]
        mov esi, 48
        lea rdx, [rip + .Lf_fmt_e]
        mov rcx, [rsp + FR_P]
        dec ecx                         # %.*e: the digits after the point
        movq xmm0, [rsp + FR_X]
        mov eax, 1
        call snprintf@PLT
        # the digits and the exponent of "d.ddde-xx"
        lea rsi, [rsp + FR_BUF]
        lea rdi, [rsp + FR_DIGS]
        xor ecx, ecx
1:      movzx eax, byte ptr [rsi]
        cmp al, 'e'
        je 2f
        cmp al, '.'
        je 3f
        mov [rdi + rcx], al
        inc ecx
3:      inc rsi
        jmp 1b
2:      lea rdi, [rsi + 1]
        xor esi, esi
        mov edx, 10
        call strtol@PLT
        mov [rsp + FR_EXP], rax
        # as rounded, then one up, then one down
        call .Lfr_check
        test eax, eax
        jnz .Lfr_found
        mov rcx, [rsp + FR_P]           # up: + 1 in the last digit
4:      dec rcx
        js 6f                           # (a carry out: fewer digits, seen already)
        lea rdx, [rsp + FR_DIGS]
        inc byte ptr [rdx + rcx]
        cmp byte ptr [rdx + rcx], '9'
        jbe 5f
        mov byte ptr [rdx + rcx], '0'
        jmp 4b
5:      call .Lfr_check
        test eax, eax
        jnz .Lfr_found
6:      # down: from the rounded digits again (- 1 twice from the one up)
        call .Lfr_digits_again
        mov rcx, [rsp + FR_P]
7:      dec rcx
        js 9f
        lea rdx, [rsp + FR_DIGS]
        dec byte ptr [rdx + rcx]
        cmp byte ptr [rdx + rcx], '0'
        jae 8f
        mov byte ptr [rdx + rcx], '9'
        jmp 7b
8:      cmp byte ptr [rsp + FR_DIGS], '0'
        je 9f                           # (a borrow into the first digit: fewer digits)
        call .Lfr_check
        test eax, eax
        jnz .Lfr_found
9:      inc qword ptr [rsp + FR_P]
        cmp qword ptr [rsp + FR_P], 17
        jbe .Lfr_try
        dec qword ptr [rsp + FR_P]      # (17 digits always read back)
        call .Lfr_digits_again
.Lfr_found:
        # python's layout of the digits
        lea rdi, [rsp + FR_BUF]
        mov rax, [rsp + FR_EXP]
        cmp rax, -4
        jl .Lfr_sci
        cmp rax, 16
        jge .Lfr_sci
        test rax, rax
        js 10f
        # 1 <= x < 1e16: the digits (zeros past them) up to the point after
        # exp + 1 of them, the rest after it; ".0" when nothing follows it
        xor ecx, ecx
11:     cmp rcx, [rsp + FR_P]
        jb 12f
        cmp rcx, [rsp + FR_EXP]
        ja 14f
        mov dl, '0'
        jmp 13f
12:     mov dl, [rsp + FR_DIGS + rcx]
13:     mov [rdi], dl
        inc rdi
        cmp rcx, [rsp + FR_EXP]
        jne 22f
        mov byte ptr [rdi], '.'
        inc rdi
22:     inc rcx
        jmp 11b
14:     cmp byte ptr [rdi - 1], '.'
        jne 15f
        mov byte ptr [rdi], '0'
        inc rdi
        jmp 15f
10:     # 1e-4 <= x < 1: "0." then -exp - 1 zeros, then the digits
        mov word ptr [rdi], 0x2e30      # "0."
        add rdi, 2
        mov rcx, [rsp + FR_EXP]
        not rcx                         # -exp - 1
16:     test rcx, rcx
        jz 17f
        mov byte ptr [rdi], '0'
        inc rdi
        dec rcx
        jmp 16b
17:     xor ecx, ecx
18:     cmp rcx, [rsp + FR_P]
        jae 15f
        mov dl, [rsp + FR_DIGS + rcx]
        mov [rdi], dl
        inc rdi
        inc rcx
        jmp 18b
.Lfr_sci:
        # d[.ddd]e-XX
        mov dl, [rsp + FR_DIGS]
        mov [rdi], dl
        inc rdi
        cmp qword ptr [rsp + FR_P], 1
        je 20f
        mov byte ptr [rdi], '.'
        inc rdi
        mov ecx, 1
19:     cmp rcx, [rsp + FR_P]
        jae 20f
        mov dl, [rsp + FR_DIGS + rcx]
        mov [rdi], dl
        inc rdi
        inc rcx
        jmp 19b
20:     mov byte ptr [rdi], 0
        lea rsi, [rip + .Lf_fmt_exp]
        mov rdx, [rsp + FR_EXP]
        xor eax, eax
        call sprintf@PLT
        jmp 21f
15:     mov byte ptr [rdi], 0
21:     lea rdi, [rsp + FR_BUF]
        call float_str
        add rsp, 144
        LEAVE
# (the local routines: float_repr's frame is 16 bytes up, the return
# address and the alignment)
# eax: the digits (FR_DIGS, FR_P of them) with FR_EXP read back as x
.Lfr_check:
        sub rsp, 8
        lea rdi, [rsp + 16 + FR_BUF]
        mov byte ptr [rdi], 0
        lea rax, [rsp + 16 + FR_DIGS]
        mov rcx, [rsp + 16 + FR_P]
        xor edx, edx
1:      cmp rdx, rcx
        jae 2f
        mov r8b, [rax + rdx]
        mov [rdi + rdx], r8b
        inc rdx
        jmp 1b
2:      mov byte ptr [rdi + rdx], 'e'
        lea rdi, [rdi + rdx + 1]
        lea rsi, [rip + .Lf_fmt_ld]
        mov rdx, [rsp + 16 + FR_EXP]
        mov rcx, [rsp + 16 + FR_P]
        dec rcx                         # (the digits read as an integer)
        sub rdx, rcx
        xor eax, eax
        call sprintf@PLT
        lea rdi, [rsp + 16 + FR_BUF]
        xor esi, esi
        call strtod@PLT
        movq rax, xmm0
        cmp rax, [rsp + 16 + FR_X]
        sete al
        movzx eax, al
        add rsp, 8
        ret
# FR_DIGS := the correctly rounded digits again (FR_BUF was overwritten)
.Lfr_digits_again:
        sub rsp, 8
        lea rdi, [rsp + 16 + FR_BUF]
        mov esi, 48
        lea rdx, [rip + .Lf_fmt_e]
        mov rcx, [rsp + 16 + FR_P]
        dec ecx
        movq xmm0, [rsp + 16 + FR_X]
        mov eax, 1
        call snprintf@PLT
        lea rsi, [rsp + 16 + FR_BUF]
        lea rdi, [rsp + 16 + FR_DIGS]
        xor ecx, ecx
1:      movzx eax, byte ptr [rsi]
        cmp al, 'e'
        je 2f
        cmp al, '.'
        je 3f
        mov [rdi + rcx], al
        inc ecx
3:      inc rsi
        jmp 1b
2:      add rsp, 8
        ret
ENDF float_repr

# float_str(cstr) -> the interned string flagged STR_FLOAT: python's float
# in an expression (it prints bare, like a number)
FUNC float_str
        ENTER
        call str_intern_c
        or dword ptr [rax + N_AUX], STR_FLOAT
        LEAVE
ENDF float_str

        .section .rodata
.Lf_fmt_e: .asciz "%.*e"
.Lf_fmt_ld: .asciz "%ld"
.Lf_fmt_exp: .asciz "e%+03ld"
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
        STACK_CHECK
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
        STACK_CHECK
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
        STACK_CHECK
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
        STACK_CHECK
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
        STACK_CHECK
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
        call must_int                   # (a symbolic offset: python's
        mov rdi, rax                    # TypeError on `off > 0`)
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
