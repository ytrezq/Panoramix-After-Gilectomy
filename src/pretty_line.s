# Lines and traces as text (port of prettify.py's pretty_line and
# pprint_logic): pretty_line(line, flags) -> list of str, pprint_logic
# (trace, indent) -> list of str (the lines, indented).

.include "defs.inc"

        .section .rodata
.Ls_hash_sp:    .asciz "# "
.Ls_log:        .asciz "log"
.Ls_log_sp:     .asciz "log "
.Ls_comma_sp:   .asciz ", "
.Ls_rparen:     .asciz ")"
.Ls_six_sp:     .asciz "      "
.Ls_codecall:   .asciz "codecall"
.Ls_delegate:   .asciz "delegate"
.Ls_sp_with:    .asciz " with:"
.Ls_funct:      .asciz "   funct "
.Ls_funct5:     .asciz "     funct "
.Ls_value:      .asciz "   value "
.Ls_wei:        .asciz "wei"
.Ls_gas5:       .asciz "     gas "
.Ls_gas8:       .asciz "        gas "
.Ls_args4:      .asciz "    args "
.Ls_args7:      .asciz "       args "
.Ls_selfdestruct_: .asciz "selfdestruct("
.Ls_precompiled_c: .asciz "# precompiled"
.Ls_create_with: .asciz "create contract with "
.Ls_create2_with: .asciz "create2 contract with "
.Ls_sp_wei_end: .asciz " wei"
.Ls_code_:      .asciz "                code: "
.Ls_salt_:      .asciz "                salt: "
.Ls_call_sp:    .asciz "call "
.Ls_static_call_sp: .asciz "static call "
.Ls_label_:     .asciz "label "
.Ls_setvars_:   .asciz " setvars: "
.Ls_continue_sp: .asciz "continue "
.Ls_continue:   .asciz "continue"
.Ls_break:      .asciz "break"
.Ls_minusminus: .asciz "--"
.Ls_plusplus:   .asciz "++"
.Ls_minus_eq:   .asciz " -= "
.Ls_plus_eq:    .asciz " += "
.Ls_eq_sp:      .asciz " = "
.Ls_stop:       .asciz "stop"
.Ls_dots:       .asciz "..."
.Ls_aborted:    .asciz "  # Decompilation aborted, sorry: "
.Ls_invalid:    .asciz "invalid"
.Ls_revert:     .asciz "revert"
.Ls_revert_with_memory: .asciz "revert with memory"
.Ls_sp_memory:  .asciz " memory"
.Ls_from2:      .asciz "  from  "
.Ls_to:         .asciz "    to "
.Ls_from1:      .asciz "  from "
.Ls_three_sp:   .asciz "   "
.Ls_len:        .asciz "len"
.Ls_revert_with: .asciz "revert with"
.Ls_panic:      .asciz " Panic("
.Ls_32:         .asciz "32"
.Ls_32_comma:   .asciz "32, "
.Ls_require_sp: .asciz "require "
.Ls_assert:     .asciz "assert"
.Ls_require:    .asciz "require"
.Ls_while_sp:   .asciz "while "
.Ls_True:       .asciz "True"
.Ls_colon_sp:   .asciz ": "
.Ls_loop:       .asciz "loop"
.Ls_qmark:      .asciz "?"
.Ls_if_sp:      .asciz "if "
.Ls_if:         .asciz "if"
.Ls_or:         .asciz "or"
.Ls_else:       .asciz "else:"
.Ls_indexed_sp: .asciz "indexed "
.Ls_sp_indexed: .asciz " indexed"
.Ls_old:        .asciz "_old"

        # the panic codes and their explanations
.Lp_00: .asciz "Used for generic compiler inserted panics."
.Lp_01: .asciz "If you call assert with an argument that evaluates to false."
.Lp_11: .asciz "If an arithmetic operation results in underflow or overflow outside of an unchecked { ... } block."
.Lp_12: .asciz "If you divide or modulo by zero (e.g. 5 / 0 or 23 % 0)."
.Lp_21: .asciz "If you convert a value that is too big or negative into an enum type."
.Lp_22: .asciz "If you access a storage byte array that is incorrectly encoded."
.Lp_31: .asciz "If you call .pop() on an empty array."
.Lp_32: .asciz "If you access an array, bytesN or an array slice at an out-of-bounds or negative index (i.e. x[i] where i >= x.length or i < 0)."
.Lp_41: .asciz "If you allocate too much memory or create an array that is too large."
.Lp_51: .asciz "If you call a zero-initialized variable of internal function type."

        .section .data.rel.ro
        .align 8
panic_codes:
        .quad 0x00, .Lp_00
        .quad 0x01, .Lp_01
        .quad 0x11, .Lp_11
        .quad 0x12, .Lp_12
        .quad 0x21, .Lp_21
        .quad 0x22, .Lp_22
        .quad 0x31, .Lp_31
        .quad 0x32, .Lp_32
        .quad 0x41, .Lp_41
        .quad 0x51, .Lp_51
        .quad -1, 0

        .text

        # the selectors of Panic(uint256) and Error(string)
        .set PANIC, 0x4E487B71
        .set ERROR, 0x08C379A0

.macro B reg, n
        mov \reg, [rsp + 8*(\n)]
.endm

.macro PF_COLOR_OF dst, src
        mov \dst, \src
        and \dst, PF_COLOR
.endm
.macro PF_FULL dst, src
        mov \dst, \src
        and \dst, PF_COLOR
        or \dst, PF_PARENS
.endm

# --- the lines ---

# pretty_line(line, flags) -> list of str. Only PF_COLOR matters
# (python's add_color); python's `col` is colorize with it, `pret` is
# prettify with parentheses=False and it.
FUNC pretty_line
        STACK_CHECK
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 112
        .set PL_OUT, MATCH_BINDINGS_SIZE        # the lines (a vec)
        .set PL_SB, MATCH_BINDINGS_SIZE + 8
        .set PL_T1, MATCH_BINDINGS_SIZE + 16
        .set PL_T2, MATCH_BINDINGS_SIZE + 24
        .set PL_T3, MATCH_BINDINGS_SIZE + 32
        .set PL_T4, MATCH_BINDINGS_SIZE + 40
        .set PL_T5, MATCH_BINDINGS_SIZE + 48
        .set PL_I, MATCH_BINDINGS_SIZE + 56
        .set PL_LINE, MATCH_BINDINGS_SIZE + 64
        .set PL_FLAGS, MATCH_BINDINGS_SIZE + 72
        .set PL_T6, MATCH_BINDINGS_SIZE + 80
        .set PL_T7, MATCH_BINDINGS_SIZE + 88
        .set PL_T8, MATCH_BINDINGS_SIZE + 96
        mov rbx, rdi
        mov r12, rsi
        mov [rsp + PL_LINE], rdi
        mov [rsp + PL_FLAGS], rsi
        call vec_new
        mov [rsp + PL_OUT], rax
        mov rdi, rbx
        call is_str
        test eax, eax
        jz 1f
        # a comment
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + C_GRAY]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + .Ls_hash_sp]
        call sb_append_c
        mov rdi, r13
        mov rsi, rbx
        call sb_append_str
        mov rdi, r13
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        jmp .Lpl_yield_finish
1:      PAT rsi, "('comment', ':text')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + C_GRAY]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + .Ls_hash_sp]
        call sb_append_c
        mov rdi, r13
        B rsi, 0
        mov edx, PF_PARENS
        call sb_append_pret
        mov rdi, r13
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        jmp .Lpl_yield_finish
2:      mov rdi, rbx
        call opcode_of
        mov r13d, eax
        JT_SWITCH pretty_line, OP_COUNT, .Lpl_other
        JT_CASE pretty_line, OP_LOG, .Lpl_log
        JT_CASE pretty_line, OP_CALLCODE, .Lpl_callcode
        JT_CASE pretty_line, OP_DELEGATECALL, .Lpl_delegatecall
        JT_CASE pretty_line, OP_SELFDESTRUCT, .Lpl_selfdestruct
        JT_CASE pretty_line, OP_PRECOMPILED, .Lpl_precompiled
        JT_CASE pretty_line, OP_CREATE, .Lpl_create
        JT_CASE pretty_line, OP_CREATE2, .Lpl_create2
        JT_CASE pretty_line, OP_CALL, .Lpl_call
        JT_CASE pretty_line, OP_STATICCALL, .Lpl_staticcall
        JT_CASE pretty_line, OP_LABEL, .Lpl_label
        JT_CASE pretty_line, OP_GOTO, .Lpl_goto
        JT_CASE pretty_line, OP_CONTINUE, .Lpl_continue
        JT_CASE pretty_line, OP_SETVAR, .Lpl_prettify
        JT_CASE pretty_line, OP_SETMEM, .Lpl_prettify
        JT_CASE pretty_line, OP_SET, .Lpl_set
        JT_CASE pretty_line, OP_STOP, .Lpl_stop
        JT_CASE pretty_line, OP_UNDEFINED, .Lpl_undefined
        JT_CASE pretty_line, OP_INVALID, .Lpl_invalid
        JT_CASE pretty_line, OP_REVERT, .Lpl_revert_return
        JT_CASE pretty_line, OP_RETURN, .Lpl_revert_return
        JT_CASE pretty_line, OP_STORE, .Lpl_store
        JT_CASE pretty_line, OP_TSTORE, .Lpl_tstore
        JT_END pretty_line, OP_COUNT, .Lpl_other

.Lpl_log:
        # ('log', params, *topics): the params of a log are its data, then
        # its topics after the first, which is the signature of the event
        # (unless it's anonymous) - the topics are the indexed ones
        cmp dword ptr [rbx + N_AUX], 2
        jb .Lpl_other
        mov rdi, [rbx + N_DATA + 8]
        xor esi, esi
        call pretty_memory
        mov [rsp + PL_T1], rax          # data_params
        mov rdi, rax
        call is_str                     # ("empty()": none)
        test eax, eax
        jz 1f
        xor edi, edi
        xor esi, esi
        call mk_list
        mov [rsp + PL_T1], rax
1:      call vec_new                    # topic_params
        mov r14, rax
        mov qword ptr [rsp + PL_I], 3
2:      mov rcx, [rsp + PL_I]
        cmp ecx, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + rcx*8]
        xor esi, esi
        call prettify
        mov rdi, r14
        mov rsi, rax
        call vec_push
        inc qword ptr [rsp + PL_I]
        jmp 2b
3:      mov rdi, r14
        call vec_to_list
        mov [rsp + PL_T2], rax          # topic_params
        mov rdi, [rsp + PL_T1]
        mov rsi, rax
        call list_concat
        mov [rsp + PL_T3], rax          # res_params
        cmp dword ptr [rbx + N_AUX], 2
        jne 4f
        # a log of no topics (see OUTPUT.md): its data, if it has any
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_log_sp]
        call sb_append_c
        lea rdi, [rip + .Ls_comma_sp]
        mov rsi, [rsp + PL_T3]
        call str_join
        mov rdi, r13
        mov rsi, rax
        call sb_append_str
        mov rdi, r13
        call sb_rstrip
        jmp .Lpl_yield_gray_finish
4:      mov rdi, [rbx + N_DATA + 16]
        call event_abi
        test rax, rax
        jnz .Lpl_log_abi
        # the signature of an event this doesn't know: all of it
        mov rdi, [rbx + N_DATA + 16]
        call is_int
        test eax, eax
        jz 5f
        mov rdi, [rbx + N_DATA + 16]
        mov esi, 64
        call padded_hex
        jmp 6f
5:      mov rdi, [rbx + N_DATA + 16]
        xor esi, esi
        call prettify
6:      mov [rsp + PL_T4], rax          # e
        call .Lpl_listed
        mov [rsp + PL_T5], rax          # listed
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_log_sp]
        call sb_append_c
        mov rdi, r13
        mov rsi, [rsp + PL_T4]
        call sb_append_str
        mov rdi, r13
        mov esi, ':'
        call sb_append_char
        mov rax, [rsp + PL_T5]
        cmp dword ptr [rax + N_AUX], 0
        je 7f
        mov rdi, r13
        mov esi, ' '
        call sb_append_char
7:      lea rdi, [rip + .Ls_comma_sp]
        mov rsi, [rsp + PL_T5]
        call str_join
        mov rdi, r13
        mov rsi, rax
        call sb_append_str
        jmp .Lpl_yield_gray_finish
.Lpl_log_abi:
        mov rdi, rax
        call fix_input_names
        mov rcx, [rax + N_DATA]
        mov [rsp + PL_T4], rcx          # fname
        mov rcx, [rax + N_DATA + 8]
        test rcx, rcx
        jnz 1f
        mov edi, E_KEY                  # (python's abi["inputs"])
        lea rsi, [rip + .Ls_no_inputs]
        call err_throw
1:      mov [rsp + PL_T5], rcx          # inputs
        # e: "fname(type name, ...)" - a tuple as the types it's made of:
        # the signature is what's hashed
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, [rsp + PL_T4]
        call sb_append_str
        mov rdi, r13
        mov esi, '('
        call sb_append_char
        xor r14d, r14d
2:      mov rax, [rsp + PL_T5]
        cmp r14d, [rax + N_AUX]
        jae 3f
        test r14d, r14d
        jz 21f
        mov rdi, r13
        lea rsi, [rip + .Ls_comma_sp]
        call sb_append_c
21:     mov rax, [rsp + PL_T5]
        mov rsi, [rax + N_DATA + r14*8]
        mov rdi, r13
        call sb_append_canonical_type
        mov rdi, r13
        mov esi, ' '
        call sb_append_char
        mov rax, [rsp + PL_T5]
        mov rax, [rax + N_DATA + r14*8]
        mov rdi, r13
        mov rsi, [rax + N_DATA + 8]
        call sb_append_str
        inc r14d
        jmp 2b
3:      mov rdi, r13
        mov esi, ')'
        call sb_append_char
        mov rdi, r13
        call sb_finish
        mov [rsp + PL_T6], rax          # e
        # the ones not indexed are in the data, the indexed ones are topics:
        # in_log = not_indexed + indexed
        call vec_new
        mov r13, rax
        xor r14d, r14d                  # the count of the indexed ones
        mov qword ptr [rsp + PL_I], 0
4:      mov rax, [rsp + PL_T5]
        mov rcx, [rsp + PL_I]
        cmp ecx, [rax + N_AUX]
        jae 5f
        mov rdi, [rax + N_DATA + rcx*8]
        call input_indexed
        test eax, eax
        jnz 41f
        mov rax, [rsp + PL_T5]
        mov rcx, [rsp + PL_I]
        mov rdi, r13
        mov rsi, [rax + N_DATA + rcx*8]
        call vec_push
        jmp 42f
41:     inc r14d
42:     inc qword ptr [rsp + PL_I]
        jmp 4b
5:      mov rax, [r13 + VEC_LEN]
        mov [rsp + PL_T8], rax          # len(not_indexed)
        mov qword ptr [rsp + PL_I], 0
51:     mov rax, [rsp + PL_T5]
        mov rcx, [rsp + PL_I]
        cmp ecx, [rax + N_AUX]
        jae 52f
        mov rdi, [rax + N_DATA + rcx*8]
        call input_indexed
        test eax, eax
        jz 53f
        mov rax, [rsp + PL_T5]
        mov rcx, [rsp + PL_I]
        mov rdi, r13
        mov rsi, [rax + N_DATA + rcx*8]
        call vec_push
53:     inc qword ptr [rsp + PL_I]
        jmp 51b
52:     mov rdi, r13
        call vec_to_list
        mov [rsp + PL_T7], rax          # in_log
        # no inputs and no params: "log e"
        mov rax, [rsp + PL_T5]
        cmp dword ptr [rax + N_AUX], 0
        jne 6f
        mov rax, [rsp + PL_T3]
        cmp dword ptr [rax + N_AUX], 0
        jne 6f
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_log_sp]
        call sb_append_c
        mov rdi, r13
        mov rsi, [rsp + PL_T6]
        call sb_append_str
        jmp .Lpl_yield_gray_finish
6:      mov rax, [rsp + PL_T1]
        mov ecx, [rax + N_AUX]
        cmp rcx, [rsp + PL_T8]
        jne .Lpl_log_other
        mov rax, [rsp + PL_T2]
        mov ecx, [rax + N_AUX]
        cmp ecx, r14d
        jne .Lpl_log_other
        # p_list: (type[ indexed], name, param) of in_log and res_params, in
        # the order of the declaration
        call vec_new
        mov r13, rax
        mov qword ptr [rsp + PL_I], 0
7:      mov rax, [rsp + PL_T5]
        mov rcx, [rsp + PL_I]
        cmp ecx, [rax + N_AUX]
        jae 8f
        # its place in in_log: in_log.index(i)
        mov rsi, [rax + N_DATA + rcx*8]
        mov rdi, [rsp + PL_T7]
        call seq_index                  # (the inputs are hash-consed: equal ones are one)
        mov [rsp + PL_SB], rax
        mov rcx, [rsp + PL_T7]
        mov rdi, [rcx + N_DATA + rax*8]
        mov rcx, [rsp + PL_T3]
        mov rsi, [rcx + N_DATA + rax*8]
        call .Lpl_pline
        mov rdi, r13
        mov rsi, rax
        call vec_push
        inc qword ptr [rsp + PL_I]
        jmp 7b
8:      cmp qword ptr [r13 + VEC_LEN], 1
        jne 9f
        # "log fname(type name=value)"
        call sb_new
        mov r14, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_log_sp]
        call sb_append_c
        mov rdi, r14
        mov rsi, [rsp + PL_T4]
        call sb_append_str
        mov rdi, r14
        mov esi, '('
        call sb_append_char
        mov rax, [r13 + VEC_DATA]
        mov rdi, r14
        mov rsi, [rax]
        call sb_append_str
        mov rdi, r14
        mov esi, ')'
        call sb_append_char
        mov r13, r14
        jmp .Lpl_yield_gray_finish
9:      # "log fname(", then a parameter a line
        call sb_new
        mov r14, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_log_sp]
        call sb_append_c
        mov rdi, r14
        mov rsi, [rsp + PL_T4]
        call sb_append_str
        mov rdi, r14
        mov esi, '('
        call sb_append_char
        mov rdi, r14
        call .Lpl_yield_gray
        mov qword ptr [rsp + PL_I], 0
10:     mov rcx, [rsp + PL_I]
        cmp rcx, [r13 + VEC_LEN]
        jae .Lpl_ret
        call sb_new
        mov r14, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_six_sp]
        call sb_append_c
        mov rax, [r13 + VEC_DATA]
        mov rcx, [rsp + PL_I]
        mov rdi, r14
        mov rsi, [rax + rcx*8]
        call sb_append_str
        mov rcx, [rsp + PL_I]
        inc rcx
        cmp rcx, [r13 + VEC_LEN]
        je 11f
        mov rdi, r14
        mov esi, ','
        call sb_append_char
        jmp 12f
11:     mov rdi, r14
        mov esi, ')'
        call sb_append_char
12:     mov rdi, r14
        call .Lpl_yield_gray
        inc qword ptr [rsp + PL_I]
        jmp 10b
.Lpl_log_other:
        # not the params of the abi - an event of the same signature,
        # indexed otherwise (ERC-721's Approval, ERC-20's): the signature,
        # then what the log has
        call .Lpl_listed
        mov [rsp + PL_T5], rax
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_log_sp]
        call sb_append_c
        mov rdi, r13
        mov rsi, [rsp + PL_T6]
        call sb_append_str
        mov rax, [rsp + PL_T5]
        cmp dword ptr [rax + N_AUX], 0
        je 1f
        mov rdi, r13
        mov esi, ':'
        call sb_append_char
1:      mov rdi, r13
        mov esi, ' '
        call sb_append_char
        lea rdi, [rip + .Ls_comma_sp]
        mov rsi, [rsp + PL_T5]
        call str_join
        mov rdi, r13
        mov rsi, rax
        call sb_append_str
        mov rdi, r13
        call sb_rstrip
        jmp .Lpl_yield_gray_finish

# locals of the log lines (pretty_line's frame 8 bytes up)
# listed: data_params + ("indexed " + t for t in topic_params) -> rax
.Lpl_listed:
        sub rsp, 8
        call vec_new
        mov [rsp], rax
        mov rdi, rax
        mov rsi, [rsp + 16 + PL_T1]
        call vec_extend_seq
        xor ecx, ecx
1:      mov rax, [rsp + 16 + PL_T2]
        cmp ecx, [rax + N_AUX]
        jae 2f
        push rcx
        push rcx
        lea rdi, [rip + .Ls_indexed_sp]
        call str_new_c
        mov rdi, rax
        mov rcx, [rsp]
        mov rdx, [rsp + 16 + 16 + PL_T2]
        mov rsi, [rdx + N_DATA + rcx*8]
        call str_cat2
        mov rdi, [rsp + 16]
        mov rsi, rax
        call vec_push
        pop rcx
        pop rcx
        inc ecx
        jmp 1b
2:      mov rdi, [rsp]
        call vec_to_list
        add rsp, 8
        ret
# "{canonical type}[ indexed] {name}={param}" of the input rdi and the
# printed param rsi -> rax
.Lpl_pline:
        push rbx
        push r12
        push r13
        mov rbx, rdi
        mov r12, rsi
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, rbx
        call sb_append_canonical_type
        mov rdi, rbx
        call input_indexed
        test eax, eax
        jz 1f
        mov rdi, r13
        lea rsi, [rip + .Ls_sp_indexed]
        call sb_append_c
1:      mov rdi, r13
        mov esi, ' '
        call sb_append_char
        mov rdi, r13
        mov rsi, [rbx + N_DATA + 8]
        call sb_append_str
        mov rdi, r13
        mov esi, '='
        call sb_append_char
        mov rdi, r13
        mov rsi, r12
        call sb_append_str
        mov rdi, r13
        call sb_finish
        pop r13
        pop r12
        pop rbx
        ret
# the builder rdi finished, gray, appended to the lines (frame 8 bytes up)
.Lpl_yield_gray:
        sub rsp, 8
        call sb_finish
        mov rdi, rax
        lea rsi, [rip + C_GRAY]
        mov rdx, r12
        call colorize
        mov rdi, [rsp + 16 + PL_OUT]
        mov rsi, rax
        call vec_push
        add rsp, 8
        ret

.Lpl_callcode:
        # ('callcode', gas, addr, wei, fname, fparams)
        cmp dword ptr [rbx + N_AUX], 6
        jne .Lpl_other
        lea r13, [rip + .Ls_codecall]
        mov rax, [rbx + N_DATA + 24]
        mov [rsp + PL_T5], rax          # wei
        jmp .Lpl_xcall
.Lpl_delegatecall:
        # ('delegatecall', gas, addr, fname, fparams)
        cmp dword ptr [rbx + N_AUX], 5
        jne .Lpl_other
        lea r13, [rip + .Ls_delegate]
        mov qword ptr [rsp + PL_T5], 0  # (no value)
.Lpl_xcall:
        mov ecx, [rbx + N_AUX]
        mov rdi, [rbx + N_DATA + rcx*8 - 16]    # fname
        mov rsi, [rbx + N_DATA + rcx*8 - 8]     # fparams
        call split_selector
        mov [rsp + PL_T1], rax          # fname
        mov [rsp + PL_T4], rdx          # fparams
        mov rdi, rax
        mov rsi, r12
        call callee_name
        mov [rsp + PL_T6], rax          # name
        mov rdi, [rbx + N_DATA + 16]
        call .Lpl_hex_addr
        mov rdi, rax
        PF_FULL rsi, r12
        call prettify
        mov [rsp + PL_T2], rax          # addr
        mov rdi, [rbx + N_DATA + 8]
        PF_COLOR_OF rsi, r12
        call prettify
        mov [rsp + PL_T3], rax          # gas
        mov rdi, [rsp + PL_T4]
        mov rsi, r12
        call pretty_memory
        mov [rsp + PL_T4], rax          # fparams, as text
        # "{WARNING}codecall{ENDC} {addr}[.{name}] with:"
        call sb_new
        mov r14, rax
        mov rdi, rax
        lea rsi, [rip + C_WARNING]
        call sb_append_c
        mov rdi, r14
        mov rsi, r13
        call sb_append_c
        mov rdi, r14
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        mov rdi, r14
        mov esi, ' '
        call sb_append_char
        mov rdi, r14
        mov rsi, [rsp + PL_T2]
        call sb_append_str
        cmp qword ptr [rsp + PL_T6], 0
        je 2f
        mov rdi, r14
        mov esi, '.'
        call sb_append_char
        mov rdi, r14
        mov rsi, [rsp + PL_T6]
        call sb_append_str
        mov rdi, r14
        lea rsi, [rip + .Ls_sp_with]
        call sb_append_c
        mov rdi, r14
        call .Lpl_yield_sb
        jmp 4f
2:      mov rdi, r14
        lea rsi, [rip + .Ls_sp_with]
        call sb_append_c
        mov rdi, r14
        call .Lpl_yield_sb
        mov rdi, [rsp + PL_T1]
        call is_none
        test eax, eax
        jnz 4f
        # "   funct " + prettify(fname)
        call sb_new
        mov r14, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_funct]
        call sb_append_c
        mov rdi, r14
        mov rsi, [rsp + PL_T1]
        PF_FULL rdx, r12
        call sb_append_pret
        mov rdi, r14
        call .Lpl_yield_sb
4:      mov rdi, [rsp + PL_T5]
        test rdi, rdi
        jz 5f
        call .Lpl_value_line
5:      lea rdi, [rip + .Ls_gas5]
        mov rsi, [rsp + PL_T3]
        call .Lpl_prefixed
        # "    args {', '.join(fparams)}" (fparams, from pretty_memory, isn't None)
        lea rdi, [rip + .Ls_args4]
        mov rsi, [rsp + PL_T4]
        call .Lpl_args_line
        jmp .Lpl_ret

# locals (pretty_line's frame 8 bytes up): the "   value {wei} {GRAY}wei{ENDC}"
# line unless wei is 0
.Lpl_value_line:
        sub rsp, 24
        mov [rsp], rdi
        mov rsi, 1
        call py_equal
        test eax, eax
        jnz 1f
        mov rdi, [rsp]
        PF_COLOR_OF rsi, r12
        call prettify
        mov [rsp], rax
        call sb_new
        mov [rsp + 8], rax
        mov rdi, rax
        lea rsi, [rip + .Ls_value]
        call sb_append_c
        mov rdi, [rsp + 8]
        mov rsi, [rsp]
        call sb_append_str
        mov rdi, [rsp + 8]
        mov esi, ' '
        call sb_append_char
        mov rdi, [rsp + 8]
        lea rsi, [rip + C_GRAY]
        call sb_append_c
        mov rdi, [rsp + 8]
        lea rsi, [rip + .Ls_wei]
        call sb_append_c
        mov rdi, [rsp + 8]
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        mov rdi, [rsp + 8]
        mov rax, [rsp + 24 + 8 + PL_OUT]
        push rax
        push rax
        call sb_finish
        pop rdi
        pop rdi
        mov rsi, rax
        call vec_push
1:      add rsp, 24
        ret
# "{prefix cstr rdi}{str rsi}" appended to the lines
.Lpl_prefixed:
        sub rsp, 24
        mov [rsp], rdi
        mov [rsp + 8], rsi
        call sb_new
        mov [rsp + 16], rax
        mov rdi, rax
        mov rsi, [rsp]
        call sb_append_c
        mov rdi, [rsp + 16]
        mov rsi, [rsp + 8]
        call sb_append_str
        mov rdi, [rsp + 16]
        call sb_finish
        mov rdi, [rsp + 24 + 8 + PL_OUT]
        mov rsi, rax
        call vec_push
        add rsp, 24
        ret
# "{prefix cstr rdi}{', '.join(pm rsi)}" (pm: pretty_memory's, a list or a
# bare str - joined character by character there too)
.Lpl_args_line:
        sub rsp, 24
        mov [rsp], rdi
        lea rdi, [rip + .Ls_comma_sp]
        call pm_join
        mov rsi, rax
        mov rdi, [rsp]
        add rsp, 24
        jmp .Lpl_prefixed
# the builder rdi finished and appended to the lines
.Lpl_yield_sb:
        sub rsp, 8
        call sb_finish
        mov rdi, [rsp + 16 + PL_OUT]
        mov rsi, rax
        call vec_push
        add rsp, 8
        ret
# an int address as its hex string, anything else as it is
.Lpl_hex_addr:
        sub rsp, 24
        mov [rsp], rdi
        call is_int
        test eax, eax
        jz 1f
        call sb_new
        mov [rsp + 8], rax
        mov rdi, rax
        mov rsi, [rsp]
        mov edx, 16
        call sb_append_int
        mov rdi, [rsp + 8]
        call sb_finish
        add rsp, 24
        ret
1:      mov rax, [rsp]
        add rsp, 24
        ret

.Lpl_selfdestruct:
        cmp dword ptr [rbx + N_AUX], 2
        jb .Lpl_index
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_selfdestruct_]
        lea rdx, [rip + C_WARNING]
        mov rcx, r12
        call sb_append_col_c
        mov rdi, [rbx + N_DATA + 8]
        xor esi, esi
        call prettify
        mov rdi, r13
        mov rsi, rax
        lea rdx, [rip + C_FAIL]
        mov rcx, r12
        call sb_append_col
        mov rdi, r13
        lea rsi, [rip + .Ls_rparen]
        lea rdx, [rip + C_WARNING]
        mov rcx, r12
        call sb_append_col_c
        jmp .Lpl_yield_finish

.Lpl_precompiled:
        # "{var_name} = {func_name}({params}) # precompiled"
        cmp dword ptr [rbx + N_AUX], 4
        jne .Lpl_other
        call sb_new
        mov r13, rax
        mov rdi, [rbx + N_DATA + 8]
        call value_str
        mov rdi, rax
        call var_name
        mov rdi, r13
        mov rsi, rax
        lea rdx, [rip + C_BLUE]
        mov rcx, r12
        call sb_append_col
        mov rdi, r13
        lea rsi, [rip + .Ls_eq_sp]
        call sb_append_c
        mov rdi, [rbx + N_DATA + 16]
        call value_str
        mov rdi, r13
        mov rsi, rax
        call sb_append_str
        mov rdi, r13
        mov esi, '('
        call sb_append_char
        mov rdi, [rbx + N_DATA + 24]
        mov rsi, r12
        call pretty_memory
        lea rdi, [rip + .Ls_comma_sp]
        mov rsi, rax
        call pm_join
        mov rdi, r13
        mov rsi, rax
        call sb_append_str
        mov rdi, r13
        lea rsi, [rip + .Ls_rparen]
        call sb_append_c
        mov rdi, r13
        mov esi, ' '
        call sb_append_char
        mov rdi, r13
        lea rsi, [rip + C_GRAY]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + .Ls_precompiled_c]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        jmp .Lpl_yield_finish

.Lpl_create:
        # "create contract with {wei} wei", "                code: {code}"
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lpl_other
        lea rdi, [rip + .Ls_create_with]
        mov rsi, [rbx + N_DATA + 8]
        call .Lpl_create_line
        lea rdi, [rip + .Ls_code_]
        mov rsi, [rbx + N_DATA + 16]
        call .Lpl_code_line
        jmp .Lpl_ret
.Lpl_create2:
        cmp dword ptr [rbx + N_AUX], 4
        jne .Lpl_other
        lea rdi, [rip + .Ls_create2_with]
        mov rsi, [rbx + N_DATA + 8]
        call .Lpl_create_line
        mov rdi, [rbx + N_DATA + 24]
        PF_COLOR_OF rsi, r12
        call prettify
        lea rdi, [rip + .Ls_salt_]
        mov rsi, rax
        call .Lpl_prefixed
        lea rdi, [rip + .Ls_code_]
        mov rsi, [rbx + N_DATA + 16]
        call .Lpl_code_line
        jmp .Lpl_ret
# "{prefix}{pret(wei)} wei"
.Lpl_create_line:
        sub rsp, 24
        mov [rsp], rdi
        mov rdi, rsi
        PF_COLOR_OF rsi, r12
        call prettify
        mov [rsp + 8], rax
        call sb_new
        mov [rsp + 16], rax
        mov rdi, rax
        mov rsi, [rsp]
        call sb_append_c
        mov rdi, [rsp + 16]
        mov rsi, [rsp + 8]
        call sb_append_str
        mov rdi, [rsp + 16]
        lea rsi, [rip + .Ls_sp_wei_end]
        call sb_append_c
        mov rdi, [rsp + 16]
        call sb_finish
        mov rdi, [rsp + 24 + 8 + PL_OUT]
        mov rsi, rax
        call vec_push
        add rsp, 24
        ret
# "{prefix}{', '.join(pretty_memory(code))}"
.Lpl_code_line:
        sub rsp, 24
        mov [rsp], rdi
        mov rdi, rsi
        mov rsi, r12
        call pretty_memory
        mov rsi, rax
        mov rdi, [rsp]
        add rsp, 24
        jmp .Lpl_args_line

.Lpl_call:
        # ('call', gas, addr, wei, fname, fparams)
        cmp dword ptr [rbx + N_AUX], 6
        jne .Lpl_other
        mov rdi, [rbx + N_DATA + 32]
        mov rsi, [rbx + N_DATA + 40]
        call split_selector
        mov [rsp + PL_T1], rax          # fname
        mov [rsp + PL_T4], rdx          # fparams
        # the address: padded to 40 hex digits when long
        mov r13, [rbx + N_DATA + 16]
        mov rdi, r13
        call is_int
        test eax, eax
        jz 1f
        call sb_new
        mov r14, rax
        mov rdi, rax
        mov rsi, r13
        mov edx, 16
        call sb_append_int
        cmp qword ptr [r14 + SB_LEN], 24
        ja 2f
        mov rdi, r14
        call sb_finish
        mov r13, rax
        jmp 1f
2:      mov rdi, r14
        call sb_free
        mov rdi, r13
        mov esi, 40
        call padded_hex
        mov r13, rax
1:      mov rdi, r13
        PF_COLOR_OF rsi, r12
        call prettify
        mov [rsp + PL_T2], rax          # addr
        mov rdi, [rbx + N_DATA + 8]
        PF_COLOR_OF rsi, r12
        call prettify
        mov [rsp + PL_T3], rax          # gas
        mov rdi, [rsp + PL_T1]
        mov rsi, r12
        call callee_name
        mov [rsp + PL_T6], rax          # name
        lea rax, [rip + .Ls_call_sp]
        mov [rsp + PL_T7], rax
        lea rax, [rip + .Ls_funct]
        mov [rsp + PL_T8], rax
        call .Lpl_call_head
        mov rdi, [rbx + N_DATA + 24]
        call .Lpl_value_line
        lea rdi, [rip + .Ls_gas5]
        mov rsi, [rsp + PL_T3]
        call .Lpl_prefixed
        mov rdi, [rsp + PL_T4]
        call is_none
        test eax, eax
        jnz .Lpl_ret
        mov rdi, [rsp + PL_T4]
        mov rsi, r12
        call pretty_memory
        lea rdi, [rip + .Ls_args4]
        mov rsi, rax
        call .Lpl_args_line
        jmp .Lpl_ret
# "{T7}{addr}.{name} with:", or "{T7}{addr} with:" and, when there's a
# fname, "{T8}{pret(fname)}" (pretty_line's frame 8 bytes up)
.Lpl_call_head:
        sub rsp, 24
        call sb_new
        mov [rsp], rax
        mov rdi, rax
        mov rsi, [rsp + 32 + PL_T7]
        call sb_append_c
        mov rdi, [rsp]
        mov rsi, [rsp + 32 + PL_T2]
        call sb_append_str
        cmp qword ptr [rsp + 32 + PL_T6], 0
        je 1f
        mov rdi, [rsp]
        mov esi, '.'
        call sb_append_char
        mov rdi, [rsp]
        mov rsi, [rsp + 32 + PL_T6]
        call sb_append_str
1:      mov rdi, [rsp]
        lea rsi, [rip + .Ls_sp_with]
        call sb_append_c
        mov rdi, [rsp]
        call sb_finish
        mov rdi, [rsp + 32 + PL_OUT]
        mov rsi, rax
        call vec_push
        cmp qword ptr [rsp + 32 + PL_T6], 0
        jne 2f
        mov rdi, [rsp + 32 + PL_T1]
        call is_none
        test eax, eax
        jnz 2f
        mov rdi, [rsp + 32 + PL_T1]
        PF_COLOR_OF rsi, r12
        call prettify
        mov rdi, [rsp + 32 + PL_T8]
        mov rsi, rax
        call .Lpl_prefixed_nested
2:      add rsp, 24
        ret
# .Lpl_prefixed, called from a local 32 bytes deeper
.Lpl_prefixed_nested:
        sub rsp, 24
        mov [rsp], rdi
        mov [rsp + 8], rsi
        call sb_new
        mov [rsp + 16], rax
        mov rdi, rax
        mov rsi, [rsp]
        call sb_append_c
        mov rdi, [rsp + 16]
        mov rsi, [rsp + 8]
        call sb_append_str
        mov rdi, [rsp + 16]
        call sb_finish
        mov rdi, [rsp + 24 + 8 + 32 + PL_OUT]
        mov rsi, rax
        call vec_push
        add rsp, 24
        ret

.Lpl_staticcall:
        # ('staticcall', gas, addr, wei, fname, fparams)
        cmp dword ptr [rbx + N_AUX], 6
        jne .Lpl_other
        mov rdi, [rbx + N_DATA + 32]
        mov rsi, [rbx + N_DATA + 40]
        call split_selector
        mov [rsp + PL_T1], rax          # fname
        mov [rsp + PL_T4], rdx          # fparams
        mov rdi, [rbx + N_DATA + 16]
        call .Lpl_hex_addr
        mov rdi, rax
        PF_COLOR_OF rsi, r12
        call prettify
        mov [rsp + PL_T2], rax          # addr
        mov rdi, [rbx + N_DATA + 8]
        PF_COLOR_OF rsi, r12
        call prettify
        mov [rsp + PL_T3], rax          # gas
        mov rdi, [rsp + PL_T1]
        mov rsi, r12
        call callee_name
        mov [rsp + PL_T6], rax          # name
        lea rax, [rip + .Ls_static_call_sp]
        mov [rsp + PL_T7], rax
        lea rax, [rip + .Ls_funct5]
        mov [rsp + PL_T8], rax
        call .Lpl_call_head
        lea rdi, [rip + .Ls_gas8]
        mov rsi, [rsp + PL_T3]
        call .Lpl_prefixed
        mov rdi, [rsp + PL_T4]
        call is_none
        test eax, eax
        jnz .Lpl_ret
        mov rdi, [rsp + PL_T4]
        mov rsi, r12
        call pretty_memory
        lea rdi, [rip + .Ls_args7]
        mov rsi, rax
        call .Lpl_args_line
        jmp .Lpl_ret

.Lpl_label:
        # GREEN "label {name} setvars: {setvars}" ENDC
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lpl_other
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + C_GREEN]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + .Ls_label_]
        call sb_append_c
        mov rdi, [rbx + N_DATA + 8]
        call value_str
        mov rdi, r13
        mov rsi, rax
        call sb_append_str
        mov rdi, r13
        lea rsi, [rip + .Ls_setvars_]
        call sb_append_c
        mov rdi, [rbx + N_DATA + 16]
        call value_str
        mov rdi, r13
        mov rsi, rax
        call sb_append_str
        mov rdi, r13
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        jmp .Lpl_yield_finish

.Lpl_goto:
        # GREEN "continue {list(rest)}" ENDC
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + C_GREEN]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + .Ls_continue_sp]
        call sb_append_c
        mov rdi, rbx
        mov esi, 1
        call list_from
        mov rdi, rax
        call value_str
        mov rdi, r13
        mov rsi, rax
        call sb_append_str
        mov rdi, r13
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        jmp .Lpl_yield_finish

.Lpl_continue:
        # ('continue', jd, setvars): the setvars one after the other (the
        # first line of each), then "continue "
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lpl_other
        mov rdi, [rbx + N_DATA + 16]
        call sequential_setvars
        mov r13, rax
        xor r14d, r14d
1:      cmp r14d, [r13 + N_AUX]
        jae 2f
        mov rdi, [r13 + N_DATA + r14*8]
        mov esi, PF_COLOR
        call pretty_line
        cmp dword ptr [rax + N_AUX], 0
        je .Lpl_index
        mov rdi, [rax + N_DATA]
        call value_str
        mov rdi, [rsp + PL_OUT]
        mov rsi, rax
        call vec_push
        inc r14d
        jmp 1b
2:      call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + C_GREEN]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + .Ls_continue_sp]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        jmp .Lpl_yield_finish

.Lpl_prettify:
        mov rdi, rbx
        PF_FULL rsi, r12
        call prettify
        mov rdi, [rsp + PL_OUT]
        mov rsi, rax
        call vec_push
        jmp .Lpl_ret

.Lpl_set:
        # ('set', idx, val)
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lpl_other
        mov r13, [rbx + N_DATA + 8]     # idx
        mov r14, [rbx + N_DATA + 16]    # val
        mov rdi, r13
        PF_FULL rsi, r12
        call prettify
        mov [rsp + PL_T1], rax          # the prettified idx
        mov rdi, r14
        call opcode_of
        cmp eax, OP_ADD
        jne .Lpl_set_assign
        cmp dword ptr [r14 + N_AUX], 3
        jne .Lpl_set_assign
        # ('add', int v, idx): ++, --, += v, -= -v
        mov rdi, [r14 + N_DATA + 16]
        mov rsi, r13
        call values_equal
        test eax, eax
        jz 2f
        mov rdi, [r14 + N_DATA + 8]
        call is_int
        test eax, eax
        jz 2f
        mov rdi, [r14 + N_DATA + 8]
        mov [rsp + PL_T2], rdi
        cmp rdi, 1                      # assert v != 0
        je .Lpl_assert_set
        cmp rdi, -1                     # tagged -1
        je .Lpl_set_suffix
        cmp rdi, 3                      # tagged 1
        je .Lpl_set_suffix
        call int_sign
        cmp eax, -1
        jne 13f
        mov rdi, [rsp + PL_T2]
        call int_neg
        mov rsi, rax
        lea rdi, [rip + .Ls_minus_eq]
        jmp .Lpl_set_op
13:     mov rsi, [rsp + PL_T2]
        lea rdi, [rip + .Ls_plus_eq]
        jmp .Lpl_set_op
2:      # ('add', idx, ('mul', -1, v)) / ('add', idx, v)
        mov rdi, [r14 + N_DATA + 8]
        mov rsi, r13
        call values_equal
        test eax, eax
        jz 3f
        mov rdi, [r14 + N_DATA + 16]
        call .Lpl_neg_of
        test rax, rax
        jz 21f
        mov rsi, rax
        lea rdi, [rip + .Ls_minus_eq]
        jmp .Lpl_set_op
21:     mov rsi, [r14 + N_DATA + 16]
        lea rdi, [rip + .Ls_plus_eq]
        jmp .Lpl_set_op
3:      # ('add', ('mul', -1, v), idx) / ('add', v, idx)
        mov rdi, [r14 + N_DATA + 16]
        mov rsi, r13
        call values_equal
        test eax, eax
        jz .Lpl_set_assign
        mov rdi, [r14 + N_DATA + 8]
        call .Lpl_neg_of
        test rax, rax
        jz 31f
        mov rsi, rax
        lea rdi, [rip + .Ls_minus_eq]
        jmp .Lpl_set_op
31:     mov rsi, [r14 + N_DATA + 8]
        lea rdi, [rip + .Ls_plus_eq]
        jmp .Lpl_set_op
.Lpl_set_suffix:
        # idx + "++" / "--"
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, [rsp + PL_T1]
        call sb_append_str
        mov rdi, r13
        lea rsi, [rip + .Ls_minusminus]
        cmp qword ptr [rsp + PL_T2], -1
        je 4f
        lea rsi, [rip + .Ls_plusplus]
4:      call sb_append_c
        jmp .Lpl_yield_finish
.Lpl_set_op:
        # idx + op + pret(v)
        mov [rsp + PL_T2], rdi
        mov [rsp + PL_T3], rsi
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, [rsp + PL_T1]
        call sb_append_str
        mov rdi, r13
        mov rsi, [rsp + PL_T2]
        call sb_append_c
        mov rdi, r13
        mov rsi, [rsp + PL_T3]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        jmp .Lpl_yield_finish
.Lpl_set_assign:
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, [rsp + PL_T1]
        call sb_append_str
        mov rdi, r13
        lea rsi, [rip + .Ls_eq_sp]
        call sb_append_c
        mov rdi, r13
        mov rsi, r14
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        jmp .Lpl_yield_finish
# a local: v of ('mul', -1, v), else 0
.Lpl_neg_of:
        sub rsp, 8
        mov [rsp], rdi
        call opcode_of
        cmp eax, OP_MUL
        jne 1f
        mov rdi, [rsp]
        cmp dword ptr [rdi + N_AUX], 3
        jne 1f
        cmp qword ptr [rdi + N_DATA + 8], -1
        jne 1f
        mov rax, [rdi + N_DATA + 16]
        add rsp, 8
        ret
1:      xor eax, eax
        add rsp, 8
        ret

.Lpl_stop:
        lea rdi, [rip + .Ls_stop]
        call str_new_c
        mov rdi, [rsp + PL_OUT]
        mov rsi, rax
        call vec_push
        jmp .Lpl_ret

.Lpl_undefined:
        # WARNING "..." ENDC GRAY "  # Decompilation aborted, sorry: {params}" ENDC
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + C_WARNING]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + .Ls_dots]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + C_GRAY]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + .Ls_aborted]
        call sb_append_c
        mov rdi, rbx
        mov esi, 1
        call list_from
        mov rdi, rax
        call seq_to_tuple
        mov rdi, rax
        call value_str
        mov rdi, r13
        mov rsi, rax
        call sb_append_str
        mov rdi, r13
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        jmp .Lpl_yield_finish

.Lpl_invalid:
        # not a revert: all the gas is used (an assert of solidity < 0.8, a
        # jump to where it can't)
        lea rdi, [rip + .Ls_invalid]
        call str_new_c
        mov rdi, [rsp + PL_OUT]
        mov rsi, rax
        call vec_push
        jmp .Lpl_ret

.Lpl_revert_return:
        # ('revert', None): "revert"
        cmp r13d, OP_REVERT
        jne 1f
        cmp dword ptr [rbx + N_AUX], 2
        jne 1f
        mov rdi, [rbx + N_DATA + 8]
        call is_none
        test eax, eax
        jz 1f
        lea rdi, [rip + .Ls_revert]
        call str_new_c
        mov rdi, [rsp + PL_OUT]
        mov rsi, rax
        call vec_push
        jmp .Lpl_ret
1:      cmp dword ptr [rbx + N_AUX], 2
        jne .Lpl_other
        mov r14, [rbx + N_DATA + 8]     # the parameter
        # (op, ('mem', ('range', mem_idx, mem_len)))
        PAT rsi, "('mem', ('range', ':mem_idx', ':mem_len'))"
        mov rdi, r14
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lpl_ret_data
        mov [rsp + PL_T1], r13          # the opcode
        call sb_new
        mov r13, rax
        cmp qword ptr [rsp + PL_T1], OP_REVERT
        jne 3f
        mov rdi, r13
        lea rsi, [rip + .Ls_revert_with_memory]
        call sb_append_c
        jmp 4f
3:      mov rdi, r13
        mov rax, [rsp + PL_LINE]
        mov rsi, [rax + N_DATA]
        call sb_append_str
        mov rdi, r13
        lea rsi, [rip + .Ls_sp_memory]
        call sb_append_c
4:      mov rdi, r13
        call .Lpl_yield_sb
        # mem_len ~ ('sub', mem_until, mem_idx): "from  idx", "to until"
        B rdi, 1
        call opcode_of
        cmp eax, OP_SUB
        jne 5f
        B rdi, 1
        cmp dword ptr [rdi + N_AUX], 3
        jne 5f
        mov rdi, [rdi + N_DATA + 16]
        B rsi, 0
        call values_equal
        test eax, eax
        jz 5f
        B rdi, 0
        PF_COLOR_OF rsi, r12
        call prettify
        lea rdi, [rip + .Ls_from2]
        mov rsi, rax
        call .Lpl_prefixed
        B rax, 1
        mov rdi, [rax + N_DATA + 8]
        PF_COLOR_OF rsi, r12
        call prettify
        lea rdi, [rip + .Ls_to]
        mov rsi, rax
        call .Lpl_prefixed
        jmp .Lpl_ret
5:      B rdi, 0
        PF_COLOR_OF rsi, r12
        call prettify
        lea rdi, [rip + .Ls_from1]
        mov rsi, rax
        call .Lpl_prefixed
        # "   " + col("len", WARNING) + " " + pret(mem_len)
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_three_sp]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + .Ls_len]
        lea rdx, [rip + C_WARNING]
        mov rcx, r12
        call sb_append_col_c
        mov rdi, r13
        mov esi, ' '
        call sb_append_char
        mov rdi, r13
        B rsi, 1
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        jmp .Lpl_yield_finish
.Lpl_ret_data:
        # op = "return" / "revert with"; the memory as text
        lea rdi, [rip + .Ls_revert_with]
        cmp r13d, OP_REVERT
        je 1f
        mov rax, [rsp + PL_LINE]
        mov rdi, [rax + N_DATA]
        add rdi, N_DATA + 4             # "return"
1:      call str_new_c
        mov [rsp + PL_T3], rax          # op
        # a custom error without params: its selector alone
        cmp r13d, OP_REVERT
        jne 2f
        PAT rsi, "('bytes', 4, ':int:sel')"
        mov rdi, r14
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        LOADS rdi, DATA
        mov rsi, r14
        call mk2
        mov r14, rax
2:      mov rdi, r14
        mov esi, PF_COLOR | PF_ABI_TEXT
        call pretty_memory
        mov rdi, rax
        call pm_list
        mov [rsp + PL_T1], rax          # res_mem
        lea rdi, [rip + .Ls_comma_sp]
        mov rsi, rax
        call str_join
        mov [rsp + PL_T2], rax          # ret_val
        # a panic
        PAT rsi, "('revert', ('data', ('bytes', 4, 1313373041), ':int:panic_code'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 3f
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, [rsp + PL_T3]
        call sb_append_str
        mov rdi, r13
        lea rsi, [rip + .Ls_panic]
        call sb_append_c
        mov rdi, r13
        B rsi, 0
        mov edx, 10
        call sb_append_int
        mov rdi, r13
        lea rsi, [rip + .Ls_rparen]
        call sb_append_c
        mov rdi, r13
        mov esi, ' '
        call sb_append_char
        B rdi, 0
        call .Lpl_panic_text
        test rax, rax
        jz .Lpl_yield_finish
        mov r14, rax
        mov rdi, r13
        mov esi, ' '
        call sb_append_char
        mov rdi, r13
        lea rsi, [rip + C_GRAY]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + .Ls_hash_sp]
        call sb_append_c
        mov rdi, r13
        mov rsi, r14
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        jmp .Lpl_yield_finish
3:      # revert("...") / require(..., "..."): the string alone
        PAT rsi, "('revert', ('data', ('bytes', 4, 147028384), '...'))"
        mov rdi, rbx
        call pat_match_nobind
        test eax, eax
        jz 4f
        mov rax, [rsp + PL_T1]
        cmp dword ptr [rax + N_AUX], 2
        jne 4f
        mov rax, [rax + N_DATA + 8]
        cmp dword ptr [rax + N_DATA], 0
        je 4f
        cmp byte ptr [rax + N_DATA + 4], '\''
        jne 4f
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, [rsp + PL_T3]
        call sb_append_str
        mov rdi, r13
        mov esi, ' '
        call sb_append_char
        mov rax, [rsp + PL_T1]
        mov rdi, r13
        mov rsi, [rax + N_DATA + 8]
        call sb_append_str
        jmp .Lpl_yield_finish
4:      # short, or not a data: "{op} {ret_val}"
        mov rdi, [rsp + PL_T2]
        call clean_color
        mov rdi, rax
        call str_charlen
        cmp eax, 120
        jb 5f
        mov rdi, r14
        call opcode_of
        cmp eax, OP_DATA
        je 6f
5:      call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, [rsp + PL_T3]
        call sb_append_str
        mov rdi, r13
        mov esi, ' '
        call sb_append_char
        mov rdi, r13
        mov rsi, [rsp + PL_T2]
        call sb_append_str
        jmp .Lpl_yield_finish
6:      # split long returns into lines (kitties.getKitten...); a leading
        # "32" (an array, probably) joins the next one
        mov r14, [rsp + PL_T1]
        cmp dword ptr [r14 + N_AUX], 0
        je .Lpl_index
        mov rdi, [r14 + N_DATA]
        lea rsi, [rip + .Ls_32]
        call str_eq_c
        test eax, eax
        jz 7f
        cmp dword ptr [r14 + N_AUX], 1
        jbe 7f
        lea rdi, [rip + .Ls_32_comma]
        call str_new_c
        mov rdi, rax
        mov rsi, [r14 + N_DATA + 8]
        call str_cat2
        mov [rsp + PL_T4], rax
        mov rdi, r14
        mov esi, 2
        call list_from
        mov rdi, rax
        mov rsi, [rsp + PL_T4]
        call list_prepend
        mov r14, rax
7:      cmp dword ptr [r14 + N_AUX], 1
        jne 8f
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, [rsp + PL_T3]
        call sb_append_str
        mov rdi, r13
        mov esi, ' '
        call sb_append_char
        mov rdi, r13
        mov rsi, [r14 + N_DATA]
        call sb_append_str
        jmp .Lpl_yield_finish
8:      # "{op} {res_mem[0]}, " then the others under it
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, [rsp + PL_T3]
        call sb_append_str
        mov rdi, r13
        mov esi, ' '
        call sb_append_char
        mov rdi, r13
        mov rsi, [r14 + N_DATA]
        call sb_append_str
        mov rdi, r13
        lea rsi, [rip + .Ls_comma_sp]
        call sb_append_c
        mov rdi, r13
        call .Lpl_yield_sb
        mov qword ptr [rsp + PL_I], 1
9:      mov rcx, [rsp + PL_I]
        cmp ecx, [r14 + N_AUX]
        jae .Lpl_ret
        call sb_new
        mov r13, rax
        mov rax, [rsp + PL_T3]
        mov rdi, rax
        call str_charlen
        lea rsi, [rax + 1]
        mov rdi, r13
        call sb_append_spaces
        mov rcx, [rsp + PL_I]
        mov rdi, r13
        mov rsi, [r14 + N_DATA + rcx*8]
        call sb_append_str
        mov rcx, [rsp + PL_I]
        inc ecx
        cmp ecx, [r14 + N_AUX]
        je 10f
        mov rdi, r13
        mov esi, ','
        call sb_append_char
10:     mov rdi, r13
        call .Lpl_yield_sb
        inc qword ptr [rsp + PL_I]
        jmp 9b
# a local: the explanation of a panic code (an int value), or 0
.Lpl_panic_text:
        sub rsp, 8
        test dil, 1
        jz 2f                           # (a big int: none)
        sar rdi, 1
        mov rax, rdi
        lea rcx, [rip + panic_codes]
1:      mov rdx, [rcx]
        cmp rdx, -1
        je 2f
        cmp rdx, rax
        je 3f
        add rcx, 16
        jmp 1b
3:      mov rax, [rcx + 8]
        add rsp, 8
        ret
2:      xor eax, eax
        add rsp, 8
        ret

.Lpl_store:
        # ('store', size, off, idx, val): "{stor} = {val}"
        cmp dword ptr [rbx + N_AUX], 5
        jne .Lpl_other
        mov rsi, [rbx + N_DATA + 8]
        mov rdx, [rbx + N_DATA + 16]
        mov rcx, [rbx + N_DATA + 24]
        LOADS rdi, STOR
        call mk4
        mov rdi, rax
        PF_FULL rsi, r12
        call prettify
        mov r13, rax
        call sb_new
        mov r14, rax
        mov rdi, rax
        mov rsi, r13
        call sb_append_str
        mov rdi, r14
        lea rsi, [rip + .Ls_eq_sp]
        call sb_append_c
        mov rdi, r14
        mov rsi, [rbx + N_DATA + 32]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov r13, r14
        jmp .Lpl_yield_finish

.Lpl_tstore:
        # ('tstore', key, val): "transient[key] = val"
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lpl_other
        LOADS rdi, TLOAD
        mov rsi, [rbx + N_DATA + 8]
        call mk2
        mov rdi, rax
        PF_FULL rsi, r12
        call prettify
        mov r13, rax
        call sb_new
        mov r14, rax
        mov rdi, rax
        mov rsi, r13
        call sb_append_str
        mov rdi, r14
        lea rsi, [rip + .Ls_eq_sp]
        call sb_append_c
        mov rdi, r14
        mov rsi, [rbx + N_DATA + 16]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov r13, r14
        jmp .Lpl_yield_finish

.Lpl_other:
        mov rdi, rbx
        call is_list
        test eax, eax
        jz 3f
        cmp dword ptr [rbx + N_AUX], 1
        jbe 2f
        # "{r[0]} {', '.join(prettify(x, rem_bool, no parentheses))}"
        call sb_new
        mov r13, rax
        mov rdi, [rbx + N_DATA]
        call value_str
        mov rdi, r13
        mov rsi, rax
        call sb_append_str
        mov rdi, r13
        mov esi, ' '
        call sb_append_char
        mov rdi, r13
        mov rsi, rbx
        mov edx, 1
        PF_COLOR_OF rcx, r12
        or rcx, PF_REM_BOOL
        call sb_append_pret_join
        jmp .Lpl_yield_finish
2:      cmp dword ptr [rbx + N_AUX], 0
        je .Lpl_index
        mov rdi, [rbx + N_DATA]
        call value_str
        mov rdi, [rsp + PL_OUT]
        mov rsi, rax
        call vec_push
        jmp .Lpl_ret
3:      mov rdi, rbx
        call value_str
        mov rdi, [rsp + PL_OUT]
        mov rsi, rax
        call vec_push
        jmp .Lpl_ret

.Lpl_yield_gray_finish:
        mov rdi, r13
        call .Lpl_yield_gray
        jmp .Lpl_ret
.Lpl_yield_finish:
        mov rdi, r13
        call sb_finish
        mov rdi, [rsp + PL_OUT]
        mov rsi, rax
        call vec_push
.Lpl_ret:
        mov rdi, [rsp + PL_OUT]
        call vec_to_list
        add rsp, MATCH_BINDINGS_SIZE + 112
        LEAVE
.Lpl_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_index]
        call err_throw
.Lpl_assert_set:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_set]
        call err_throw
ENDF pretty_line

        .section .rodata
.Ls_index:      .asciz "pretty_line: an index out of range"
.Ls_assert_set: .asciz "pretty_line: a set of the same plus 0"
.Ls_no_inputs:  .asciz "KeyError: 'inputs'"
        .text

# sb_rstrip(sb): python's rstrip() - the whitespace at the end removed
FUNC sb_rstrip
        mov rcx, [rdi + SB_LEN]
        mov rdx, [rdi + SB_BUF]
1:      test rcx, rcx
        jz 2f
        movzx eax, byte ptr [rdx + rcx - 1]
        cmp eax, ' '
        je 3f
        cmp eax, 9
        jb 2f
        cmp eax, 13
        jbe 3f
        cmp eax, 0x1c
        jb 2f
        cmp eax, 0x1f
        ja 2f
3:      dec rcx
        jmp 1b
2:      mov [rdi + SB_LEN], rcx
        mov byte ptr [rdx + rcx], 0
        ret
ENDF sb_rstrip

# str_split(str, sep_cstr) -> list of str: python's split with a separator
FUNC str_split
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rsi
        call strlen@PLT
        mov [rsp], rax                  # len(sep)
        call vec_new
        mov r13, rax
        lea r14, [rbx + N_DATA + 4]     # the start of the current piece
1:      mov rdi, r14
        mov rsi, r12
        call strstr@PLT
        test rax, rax
        jz 2f
        mov rdi, r14
        mov rsi, rax
        sub rsi, r14
        mov [rsp + 8], rax
        call str_new
        mov rdi, r13
        mov rsi, rax
        call vec_push
        mov r14, [rsp + 8]
        add r14, [rsp]
        jmp 1b
2:      mov rdi, r14
        call strlen@PLT
        mov rdi, r14
        mov rsi, rax
        call str_new
        mov rdi, r13
        mov rsi, rax
        call vec_push
        mov rdi, r13
        call vec_to_list
        add rsp, 16
        LEAVE
ENDF str_split

# sb_append_spaces(sb, n)
FUNC sb_append_spaces
        ENTER
        mov rbx, rdi
        mov r12, rsi
1:      test r12, r12
        jz 2f
        mov rdi, rbx
        mov esi, ' '
        call sb_append_char
        dec r12
        jmp 1b
2:      LEAVE
ENDF sb_append_spaces

# --- the setvars of a continue ---

# sequential_setvars(setvars) -> list: python's sequential_setvars - the
# setvars of a continue, one after the other. They all happen at once:
# each one reads the values from before any of them (idx = idx + 1 and s
# = s + 3 * idx add the idx of the iteration that ends). Printed one per
# line, they are read one after the other, so one that reads a variable
# goes before the one that sets it, and when two read each other's (a
# swap), a copy of one of them is made first.
FUNC sequential_setvars
        STACK_CHECK
        ENTER
        sub rsp, 32
        .set SS_PENDING, 0
        .set SS_RES, 8
        .set SS_COPIES, 16
        mov rbx, rdi
        call is_seq
        test eax, eax
        jz .Lss_type
        call vec_new
        mov [rsp + SS_PENDING], rax
        call vec_new
        mov [rsp + SS_RES], rax
        mov qword ptr [rsp + SS_COPIES], 0
        # the ones that change their variable: sv[2] != ('var', sv[1])
        xor r12d, r12d
1:      cmp r12d, [rbx + N_AUX]
        jae .Lss_loop
        mov r13, [rbx + N_DATA + r12*8]
        inc r12d
        mov rdi, r13
        call is_seq
        test eax, eax
        jz .Lss_type
        cmp dword ptr [r13 + N_AUX], 3
        jb .Lss_index
        LOADS rdi, VAR
        mov rsi, [r13 + N_DATA + 8]
        call mk2
        cmp rax, [r13 + N_DATA + 16]
        je 1b
        cmp dword ptr [r13 + N_AUX], 3
        jne .Lss_unpack
        mov rdi, [rsp + SS_PENDING]
        mov rsi, r13
        call vec_push
        jmp 1b
.Lss_loop:
        mov rax, [rsp + SS_PENDING]
        cmp qword ptr [rax + VEC_LEN], 0
        je .Lss_done
        # the first one no other one reads
        xor r12d, r12d
.Lss_try:
        mov rax, [rsp + SS_PENDING]
        cmp r12, [rax + VEC_LEN]
        jae .Lss_copy
        mov rax, [rax + VEC_DATA]
        mov rax, [rax + r12*8]
        LOADS rdi, VAR
        mov rsi, [rax + N_DATA + 8]
        call mk2
        mov r14, rax                    # ('var', idx)
        xor r13d, r13d
2:      mov rax, [rsp + SS_PENDING]
        cmp r13, [rax + VEC_LEN]
        jae .Lss_pop                    # nobody reads it
        cmp r13, r12
        je 3f
        mov rax, [rax + VEC_DATA]
        mov rax, [rax + r13*8]
        mov rdi, [rax + N_DATA + 16]
        mov rsi, r14
        call contains
        test eax, eax
        jnz 4f
3:      inc r13
        jmp 2b
4:      inc r12
        jmp .Lss_try
.Lss_pop:
        # res.append(pending.pop(i))
        mov rax, [rsp + SS_PENDING]
        mov rcx, [rax + VEC_DATA]
        mov rsi, [rcx + r12*8]
        mov rdi, [rsp + SS_RES]
        call vec_push
        mov rax, [rsp + SS_PENDING]
        mov rcx, [rax + VEC_DATA]
        mov rdx, [rax + VEC_LEN]
        dec rdx
        mov [rax + VEC_LEN], rdx
5:      cmp r12, rdx
        jae .Lss_loop
        mov r8, [rcx + r12*8 + 8]
        mov [rcx + r12*8], r8
        inc r12
        jmp 5b
.Lss_copy:
        # each one reads another's: a copy of the first's variable first
        mov rax, [rsp + SS_PENDING]
        mov rax, [rax + VEC_DATA]
        mov rax, [rax]
        LOADS rdi, VAR
        mov rsi, [rax + N_DATA + 8]
        call mk2
        mov r14, rax                    # ('var', idx)
        inc qword ptr [rsp + SS_COPIES]
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_old]
        call sb_append_c
        cmp qword ptr [rsp + SS_COPIES], 1
        je 6f
        mov rdi, r13
        mov rsi, [rsp + SS_COPIES]
        call sb_append_u64
6:      mov rdi, r13
        call sb_finish_intern
        mov r13, rax                    # its name
        LOADS rdi, SETVAR
        mov rsi, r13
        mov rdx, r14
        call mk3
        mov rdi, [rsp + SS_RES]
        mov rsi, rax
        call vec_push
        LOADS rdi, VAR
        mov rsi, r13
        call mk2
        mov r13, rax                    # the copy
        # the others read the copy
        mov r12d, 1
7:      mov rax, [rsp + SS_PENDING]
        cmp r12, [rax + VEC_LEN]
        jae .Lss_loop
        mov rax, [rax + VEC_DATA]
        mov rbx, [rax + r12*8]
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, r14
        mov rdx, r13
        call replace
        mov rdi, [rbx + N_DATA]
        mov rsi, [rbx + N_DATA + 8]
        mov rdx, rax
        call mk3
        mov rcx, [rsp + SS_PENDING]
        mov rcx, [rcx + VEC_DATA]
        mov [rcx + r12*8], rax
        inc r12
        jmp 7b
.Lss_done:
        mov rdi, [rsp + SS_RES]
        call vec_to_list
        add rsp, 32
        LEAVE
.Lss_type:
        mov edi, E_TYPE
        lea rsi, [rip + .Ls_ss_type]
        call err_throw
.Lss_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_ss_index]
        call err_throw
.Lss_unpack:
        mov edi, E_VALUE
        lea rsi, [rip + .Ls_ss_unpack]
        call err_throw
ENDF sequential_setvars

        .section .rodata
.Ls_ss_type:   .asciz "TypeError: a setvar that isn't a sequence"
.Ls_ss_index:  .asciz "IndexError: a setvar of less than 3 elements"
.Ls_ss_unpack: .asciz "ValueError: too many values to unpack (expected 3)"
        .text

# --- the traces ---

# pprint_logic(exp, indent) -> list of str: a trace (or a line) as
# indented lines of text
FUNC pprint_logic
        xor edx, edx
        jmp pprint_logic_l
ENDF pprint_logic

# pprint_logic_l(exp, indent, loops) -> list of str: python's pprint_logic
# - loops: the (jd, label) of the loops it's in, the innermost last (a
# list, or 0 for none) - a continue of another one than the innermost
# names it
FUNC pprint_logic_l
        STACK_CHECK
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 64
        .set PP_OUT, MATCH_BINDINGS_SIZE
        .set PP_INDENT, MATCH_BINDINGS_SIZE + 8
        .set PP_I, MATCH_BINDINGS_SIZE + 16
        .set PP_T1, MATCH_BINDINGS_SIZE + 24
        .set PP_LOOPS, MATCH_BINDINGS_SIZE + 32
        .set PP_T2, MATCH_BINDINGS_SIZE + 40
        .set PP_T3, MATCH_BINDINGS_SIZE + 48
        mov rbx, rdi
        mov [rsp + PP_INDENT], rsi
        test rdx, rdx
        jnz 1f
        xor edi, edi
        xor esi, esi
        call mk_list
        mov rdx, rax
1:      mov [rsp + PP_LOOPS], rdx
        call vec_new
        mov [rsp + PP_OUT], rax
        mov rdi, rbx
        call opcode_of
        mov r12d, eax
        JT_SWITCH pprint_logic, OP_COUNT, .Lpp_other
        JT_CASE pprint_logic, OP_WHILE, .Lpp_while
        JT_CASE pprint_logic, OP_CONTINUE, .Lpp_continue
        JT_CASE pprint_logic, OP_BREAK, .Lpp_break
        JT_CASE pprint_logic, OP_REQUIRE, .Lpp_require
        JT_CASE pprint_logic, OP_IF, .Lpp_if
        JT_CASE pprint_logic, OP_OR, .Lpp_or
        JT_END pprint_logic, OP_COUNT, .Lpp_other
.Lpp_other:
        mov rdi, rbx
        call is_list
        test eax, eax
        jnz .Lpp_list
.Lpp_line:
        # the line's texts, indented
        mov rdi, rbx
        mov esi, PF_COLOR
        call pretty_line
        mov r13, rax
        xor r14d, r14d
1:      cmp r14d, [r13 + N_AUX]
        jae .Lpp_ret
        mov rdi, [rsp + PP_INDENT]
        mov rsi, [r13 + N_DATA + r14*8]
        call .Lpp_indented
        inc r14d
        jmp 1b

.Lpp_while:
        cmp dword ptr [rbx + N_AUX], 3
        jb .Lpp_index
        mov qword ptr [rsp + PP_T1], 0  # jd (None)
        cmp dword ptr [rbx + N_AUX], 5
        jne 2f
        mov rax, [rbx + N_DATA + 24]
        mov [rsp + PP_T1], rax
        # the setvars before it, one after the other
        mov rdi, [rbx + N_DATA + 32]
        call sequential_setvars
        mov r13, rax
        xor r14d, r14d
1:      cmp r14d, [r13 + N_AUX]
        jae 2f
        mov rax, [r13 + N_DATA + r14*8]
        mov rsi, [rax + N_DATA + 8]
        mov rdx, [rax + N_DATA + 16]
        LOADS rdi, SETVAR
        call mk3
        mov rdi, rax
        mov esi, PF_COLOR
        call pretty_line
        cmp dword ptr [rax + N_AUX], 0
        je .Lpp_index
        mov rdi, [rsp + PP_INDENT]
        mov rsi, [rax + N_DATA]
        call .Lpp_indented
        inc r14d
        jmp 1b
2:      mov r13, [rbx + N_DATA + 16]    # path
        # a label when a loop inside it continues this one
        mov qword ptr [rsp + PP_T2], 0  # label (None)
        mov rdi, [rsp + PP_T1]
        call is_none
        test eax, eax
        jnz 3f
        mov rdi, r13
        mov rsi, [rsp + PP_T1]
        call continues_from_inside
        test eax, eax
        jz 3f
        call sb_new
        mov r14, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_loop]
        call sb_append_c
        mov rax, [rsp + PP_LOOPS]
        mov esi, [rax + N_AUX]
        inc esi
        mov rdi, r14
        call sb_append_u64
        mov rdi, r14
        call sb_finish_intern
        mov [rsp + PP_T2], rax
3:      # "[label: ]while cond:" - True for 1 and ('bool', 1)
        call sb_new
        mov r14, rax
        cmp qword ptr [rsp + PP_T2], 0
        je 4f
        mov rdi, rax
        mov rsi, [rsp + PP_T2]
        call sb_append_str
        mov rdi, r14
        lea rsi, [rip + .Ls_colon_sp]
        call sb_append_c
4:      mov rdi, r14
        lea rsi, [rip + C_GREEN]
        call sb_append_c
        mov rdi, r14
        lea rsi, [rip + .Ls_while_sp]
        call sb_append_c
        mov rdi, r14
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        mov rdi, [rbx + N_DATA + 8]
        call is_true_cond
        test eax, eax
        jz 5f
        mov rdi, r14
        lea rsi, [rip + .Ls_True]
        call sb_append_c
        jmp 6f
5:      mov rdi, r14
        mov rsi, [rbx + N_DATA + 8]
        mov edx, PF_COLOR | PF_REM_BOOL
        call sb_append_pret
6:      mov rdi, r14
        lea rsi, [rip + C_GREEN]
        call sb_append_c
        mov rdi, r14
        mov esi, ':'
        call sb_append_char
        mov rdi, r14
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        mov rdi, r14
        call sb_finish
        mov rdi, [rsp + PP_INDENT]
        mov rsi, rax
        call .Lpp_indented
        # its body, with a break where it ends, in loops + ((jd, label),)
        mov rdi, [rsp + PP_T1]
        mov rsi, [rsp + PP_T2]
        call mk2
        mov rdi, rax
        call mk_list1
        mov rdi, [rsp + PP_LOOPS]
        mov rsi, rax
        call list_concat
        mov [rsp + PP_T3], rax
        mov rdi, r13
        call add_breaks
        mov rdi, rax
        mov rsi, [rsp + PP_INDENT]
        add rsi, 4
        mov rdx, [rsp + PP_T3]
        call .Lpp_extend_loops
        jmp .Lpp_ret

.Lpp_continue:
        # ('continue', jd, setvars): the setvars one after the other, then
        # continue - with the label of its loop when it's another one than
        # the innermost
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lpp_line
        mov rdi, [rbx + N_DATA + 16]
        call sequential_setvars
        mov r13, rax
        xor r14d, r14d
1:      cmp r14d, [r13 + N_AUX]
        jae 2f
        mov rdi, [r13 + N_DATA + r14*8]
        mov esi, PF_COLOR
        call pretty_line
        cmp dword ptr [rax + N_AUX], 0
        je .Lpp_index
        mov rdi, [rax + N_DATA]
        call value_str
        mov rdi, [rsp + PP_INDENT]
        mov rsi, rax
        call .Lpp_indented
        inc r14d
        jmp 1b
2:      call sb_new
        mov r14, rax
        mov rdi, rax
        lea rsi, [rip + C_GREEN]
        call sb_append_c
        mov rdi, r14
        lea rsi, [rip + .Ls_continue]
        call sb_append_c
        mov rdi, r14
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        mov r13, [rsp + PP_LOOPS]
        mov ecx, [r13 + N_AUX]
        test ecx, ecx
        jz 6f
        mov rax, [r13 + N_DATA + rcx*8 - 8]
        mov rdi, [rax + N_DATA]         # loops[-1][0] != jd
        mov rsi, [rbx + N_DATA + 8]
        call py_equal
        test eax, eax
        jnz 6f
        # (of a loop the continue is in a loop in) " " + the first label
        # of a loop of its jd, else "?"
        mov rdi, r14
        mov esi, ' '
        call sb_append_char
        xor r12d, r12d
3:      cmp r12d, [r13 + N_AUX]
        jae 5f
        mov rax, [r13 + N_DATA + r12*8]
        mov rdi, [rax + N_DATA]
        mov rsi, [rbx + N_DATA + 8]
        call py_equal
        test eax, eax
        jnz 4f
        inc r12d
        jmp 3b
4:      mov rax, [r13 + N_DATA + r12*8]
        mov rsi, [rax + N_DATA + 8]
        test rsi, rsi                   # (None, or an empty label: "?")
        jz 5f
        mov rdi, rsi
        call py_truthy
        test eax, eax
        jz 5f
        mov rax, [r13 + N_DATA + r12*8]
        mov rdi, r14
        mov rsi, [rax + N_DATA + 8]
        call sb_append_str
        jmp 6f
5:      mov rdi, r14
        lea rsi, [rip + .Ls_qmark]
        call sb_append_c
6:      mov rdi, r14
        call sb_finish
        mov rdi, [rsp + PP_INDENT]
        mov rsi, rax
        call .Lpp_indented
        jmp .Lpp_ret

.Lpp_break:
        call sb_new
        mov r14, rax
        mov rdi, rax
        lea rsi, [rip + C_GREEN]
        call sb_append_c
        mov rdi, r14
        lea rsi, [rip + .Ls_break]
        call sb_append_c
        mov rdi, r14
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        mov rdi, r14
        call sb_finish
        mov rdi, [rsp + PP_INDENT]
        mov rsi, rax
        call .Lpp_indented
        jmp .Lpp_ret

.Lpp_require:
        cmp dword ptr [rbx + N_AUX], 2
        jne .Lpp_unpack
        lea rdi, [rip + .Ls_require]
        mov rsi, [rbx + N_DATA + 8]
        call .Lpp_word_line
        jmp .Lpp_ret

.Lpp_if:
        cmp dword ptr [rbx + N_AUX], 3
        je .Lpp_if1
        cmp dword ptr [rbx + N_AUX], 4
        jne .Lpp_other
        # ('if', cond, if_true, if_false)
        mov rdi, [rbx + N_DATA + 24]
        call check_word
        test rax, rax
        jz 1f
        # a require (or an assert): the true branch at the same level
        mov rdi, rax
        mov rsi, [rbx + N_DATA + 8]
        call .Lpp_word_line
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, [rsp + PP_INDENT]
        call .Lpp_extend
        jmp .Lpp_ret
1:      mov rdi, [rbx + N_DATA + 16]
        call check_word
        test rax, rax
        jz 2f
        mov r13, rax
        mov rdi, [rbx + N_DATA + 8]
        call is_zero
        mov rdi, r13
        mov rsi, rax
        call .Lpp_word_line
        mov rdi, [rbx + N_DATA + 24]
        mov rsi, [rsp + PP_INDENT]
        call .Lpp_extend
        jmp .Lpp_ret
2:      # a branch that leaves the loop (see add_breaks): the other one
        # follows the if rather than being its else
        mov rdi, [rbx + N_DATA + 24]
        call py_truthy
        test eax, eax
        jz 4f
        mov rdi, [rbx + N_DATA + 16]
        call breaks
        test eax, eax
        jnz 3f
        mov rdi, [rbx + N_DATA + 24]
        call breaks
        test eax, eax
        jz 4f
        mov rdi, [rbx + N_DATA + 16]
        call py_truthy
        test eax, eax
        jz 4f
        # not breaks(if_true): cond, if_true, if_false = is_zero(cond),
        # if_false, if_true
        mov rdi, [rbx + N_DATA + 8]
        call is_zero
        mov [rsp + PP_T1], rax
        mov rax, [rbx + N_DATA + 24]
        mov [rsp + PP_T2], rax
        mov rax, [rbx + N_DATA + 16]
        mov [rsp + PP_T3], rax
        jmp 31f
3:      mov rax, [rbx + N_DATA + 8]
        mov [rsp + PP_T1], rax
        mov rax, [rbx + N_DATA + 16]
        mov [rsp + PP_T2], rax
        mov rax, [rbx + N_DATA + 24]
        mov [rsp + PP_T3], rax
31:     mov rdi, [rsp + PP_T1]
        call .Lpp_if_line
        mov rdi, [rsp + PP_T2]
        mov rsi, [rsp + PP_INDENT]
        add rsi, 4
        call .Lpp_extend
        mov rdi, [rsp + PP_T3]
        mov rsi, [rsp + PP_INDENT]
        call .Lpp_extend
        jmp .Lpp_ret
4:      mov rdi, [rbx + N_DATA + 8]
        call .Lpp_if_line
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, [rsp + PP_INDENT]
        add rsi, 4
        call .Lpp_extend
        lea rdi, [rip + .Ls_else]
        call str_new_c
        mov rsi, rax
        mov rdi, [rsp + PP_INDENT]
        call .Lpp_indented
        mov rdi, [rbx + N_DATA + 24]
        mov rsi, [rsp + PP_INDENT]
        add rsi, 4
        call .Lpp_extend
        jmp .Lpp_ret
.Lpp_if1:
        # ('if', cond, if_true): one-sided, only after folding
        mov rdi, [rbx + N_DATA + 16]
        call check_word
        test rax, rax
        jz 1f
        mov r13, rax
        mov rdi, [rbx + N_DATA + 8]
        call is_zero
        mov rdi, r13
        mov rsi, rax
        call .Lpp_word_line
        jmp .Lpp_ret
1:      mov rdi, [rbx + N_DATA + 8]
        call .Lpp_if_line
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, [rsp + PP_INDENT]
        add rsi, 4
        call .Lpp_extend
        jmp .Lpp_ret

.Lpp_list:
        # the lines; the last stop of a function isn't printed
        xor r14d, r14d
1:      cmp r14d, [rbx + N_AUX]
        jae .Lpp_ret
        mov r13, [rbx + N_DATA + r14*8]
        lea eax, [r14 + 1]
        cmp eax, [rbx + N_AUX]
        jne 2f
        cmp qword ptr [rsp + PP_INDENT], 2
        jne 2f
        PAT rsi, "('stop',)"
        mov rdi, r13
        call pat_match_nobind
        test eax, eax
        jnz 3f
2:      mov rdi, r13
        mov rsi, [rsp + PP_INDENT]
        call .Lpp_extend
3:      inc r14d
        jmp 1b

.Lpp_or:
        cmp dword ptr [rbx + N_AUX], 1
        jbe .Lpp_line
        lea rdi, [rip + .Ls_if]
        call str_new_c
        mov rsi, rax
        mov rdi, [rsp + PP_INDENT]
        call .Lpp_indented
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rsp + PP_INDENT]
        add rsi, 4
        call .Lpp_extend
        mov r14d, 2
1:      cmp r14d, [rbx + N_AUX]
        jae .Lpp_ret
        lea rdi, [rip + .Ls_or]
        call str_new_c
        mov rsi, rax
        mov rdi, [rsp + PP_INDENT]
        call .Lpp_indented
        mov rdi, [rbx + N_DATA + r14*8]
        mov rsi, [rsp + PP_INDENT]
        add rsi, 4
        call .Lpp_extend
        inc r14d
        jmp 1b

.Lpp_ret:
        mov rdi, [rsp + PP_OUT]
        call vec_to_list
        add rsp, MATCH_BINDINGS_SIZE + 64
        LEAVE
.Lpp_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_index]
        call err_throw
.Lpp_unpack:
        mov edi, E_VALUE
        lea rsi, [rip + .Ls_pp_unpack]
        call err_throw

# locals of pprint_logic_l (its frame 8 bytes up)
# " " * rdi + rsi, appended to the lines
.Lpp_indented:
        sub rsp, 24
        mov [rsp], rdi
        mov [rsp + 8], rsi
        call sb_new
        mov [rsp + 16], rax
        mov rdi, rax
        mov rsi, [rsp]
        call sb_append_spaces
        mov rdi, [rsp + 16]
        mov rsi, [rsp + 8]
        call sb_append_str
        mov rdi, [rsp + 16]
        call sb_finish
        mov rdi, [rsp + 24 + 8 + PP_OUT]
        mov rsi, rax
        call vec_push
        add rsp, 24
        ret
# the lines of pprint_logic(rdi, rsi, loops) appended
.Lpp_extend:
        mov rdx, [rsp + 8 + PP_LOOPS]
.Lpp_extend_loops:
        sub rsp, 8
        call pprint_logic_l
        mov rdi, [rsp + 16 + PP_OUT]
        mov rsi, rax
        call vec_extend_seq
        add rsp, 8
        ret
# "{word} " + prettify(rsi, color, rem_bool, no parentheses), indented
# (word: a C string)
.Lpp_word_line:
        sub rsp, 24
        mov [rsp], rsi
        mov [rsp + 16], rdi
        call sb_new
        mov [rsp + 8], rax
        mov rdi, rax
        mov rsi, [rsp + 16]
        call sb_append_c
        mov rdi, [rsp + 8]
        mov esi, ' '
        call sb_append_char
        mov rdi, [rsp + 8]
        mov rsi, [rsp]
        mov edx, PF_COLOR | PF_REM_BOOL
        call sb_append_pret
        mov rdi, [rsp + 8]
        call sb_finish
        mov rdi, [rsp + 24 + 8 + PP_INDENT]
        mov rsi, rax
        add rsp, 24
        jmp .Lpp_indented
# "if " + prettify(rdi) + ":", indented
.Lpp_if_line:
        sub rsp, 24
        mov [rsp], rdi
        call sb_new
        mov [rsp + 8], rax
        mov rdi, rax
        lea rsi, [rip + .Ls_if_sp]
        call sb_append_c
        mov rdi, [rsp + 8]
        mov rsi, [rsp]
        mov edx, PF_COLOR | PF_REM_BOOL
        call sb_append_pret
        mov rdi, [rsp + 8]
        mov esi, ':'
        call sb_append_char
        mov rdi, [rsp + 8]
        call sb_finish
        mov rdi, [rsp + 24 + 8 + PP_INDENT]
        mov rsi, rax
        add rsp, 24
        jmp .Lpp_indented
ENDF pprint_logic_l

        .section .rodata
.Ls_pp_unpack: .asciz "ValueError: a require of more or less than a condition"
        .text

# check_word(branch) -> rax: python's check_word - "require" (a C string)
# if the branch only reverts, "assert" if it's only an invalid (an assert
# of solidity < 0.8 - it uses all the gas), 0 otherwise
FUNC check_word
        ENTER
        mov rbx, rdi
        call is_seq
        test eax, eax
        jz .Lcw_type
        cmp dword ptr [rbx + N_AUX], 1
        jne 9f
        mov r12, [rbx + N_DATA]
        mov rdi, r12
        OP_N_CHECK OP_REVERT, 2, 1f
        mov rdi, [r12 + N_DATA + 8]
        call is_none
        test eax, eax
        jz 1f
        lea rax, [rip + .Ls_require]
        LEAVE
1:      mov rdi, r12
        call opcode_of
        cmp eax, OP_INVALID
        jne 9f
        lea rax, [rip + .Ls_assert]
        LEAVE
9:      xor eax, eax
        LEAVE
.Lcw_type:
        mov edi, E_TYPE
        lea rsi, [rip + .Ls_cw_type]
        call err_throw
ENDF check_word

        .section .rodata
.Ls_cw_type: .asciz "TypeError: a branch that has no len()"
        .text

        # what a path ends with, not going on after it (ENDS_PATH)
        OPSET_MEMBER ends_path, OP_RETURN
        OPSET_MEMBER ends_path, OP_STOP
        OPSET_MEMBER ends_path, OP_SELFDESTRUCT
        OPSET_MEMBER ends_path, OP_INVALID
        OPSET_MEMBER ends_path, OP_REVERT
        OPSET_MEMBER ends_path, OP_CONTINUE
        OPSET_MEMBER ends_path, OP_BREAK
        OPSET_MEMBER ends_path, OP_UNDEFINED
        OPSET_END ends_path, OP_COUNT

# add_breaks(path) -> list: python's add_breaks - the body of a loop, with
# a break where it ends: the loop is left there (see make_whiles), not
# gone on with - it's only by a continue that it is
FUNC add_breaks
        STACK_CHECK
        ENTER
        mov rbx, rdi
        LOADS rdi, BREAK
        call mk_tuple1
        mov r13, rax                    # ('break',)
        cmp dword ptr [rbx + N_AUX], 0
        jne 1f
        mov rdi, r13
        call mk_list1
        LEAVE
1:      mov ecx, [rbx + N_AUX]
        mov r12, [rbx + N_DATA + rcx*8 - 8]     # the last line
        mov rdi, r12
        call opcode_of
        IN_OPSET ends_path, rax
        jne 8f
        mov rdi, r12
        OP_N_CHECK OP_IF, 4, 7f
        # path[:-1] + [('if', cond, add_breaks(if_true), add_breaks(if_false))]
        mov rdi, [r12 + N_DATA + 16]
        call add_breaks
        mov r13, rax
        mov rdi, [r12 + N_DATA + 24]
        call add_breaks
        mov rcx, rax
        mov rdx, r13
        mov rsi, [r12 + N_DATA + 8]
        LOADS rdi, IF
        call mk4
        mov rdi, rax
        call mk_list1
        mov r13, rax
        mov rdi, rbx
        call list_but_last
        mov rdi, rax
        mov rsi, r13
        call list_concat
        LEAVE
7:      mov rdi, r13                    # path + [('break',)]
        call mk_list1
        mov rdi, rbx
        mov rsi, rax
        call list_concat
        LEAVE
8:      mov rax, rbx
        LEAVE
ENDF add_breaks

# mk_tuple1(x) -> (x,)
FUNC mk_tuple1
        ENTER
        sub rsp, 16
        mov [rsp], rdi
        mov edi, 1
        mov rsi, rsp
        call mk_tuple
        add rsp, 16
        LEAVE
ENDF mk_tuple1

# list_but_last(seq) -> list: seq[:-1]
FUNC list_but_last
        mov esi, [rdi + N_AUX]
        dec esi
        lea rdx, [rdi + N_DATA]
        mov edi, esi
        mov rsi, rdx
        jmp mk_list
ENDF list_but_last

# breaks(path) -> eax: python's breaks - whether path ends with a break
# (see add_breaks)
FUNC breaks
        ENTER
        mov rbx, rdi
        call py_truthy
        test eax, eax
        jz 9f
        mov rdi, rbx
        call is_seq
        test eax, eax
        jz 9f
        mov ecx, [rbx + N_AUX]
        mov rdi, [rbx + N_DATA + rcx*8 - 8]
        call opcode_of
        cmp eax, OP_BREAK
        jne 9f
        mov eax, 1
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF breaks

# is_true_cond(cond) -> eax: python's `cond in (1, ("bool", 1))`
FUNC is_true_cond
        ENTER
        mov rbx, rdi
        mov rsi, 3
        call py_equal
        test eax, eax
        jnz 8f
        mov rdi, rbx
        OP_N_CHECK OP_BOOL, 2, 9f
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, 3
        call py_equal
        LEAVE
8:      mov eax, 1
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF is_true_cond

# continues_from_inside(path, jd) -> eax: python's continues_from_inside -
# whether a loop inside path continues the loop jd: a while (anywhere in
# path) whose body holds a ('continue', jd, _)
FUNC continues_from_inside
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_WHILE
        jne 1f
        cmp dword ptr [rbx + N_AUX], 3
        jb .Lcf_index
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, r12
        call holds_continue
        test eax, eax
        jnz 8f
1:      mov rdi, rbx
        call is_seq
        test eax, eax
        jz 9f
        xor r13d, r13d
2:      cmp r13d, [rbx + N_AUX]
        jae 9f
        mov rdi, [rbx + N_DATA + r13*8]
        mov rsi, r12
        call continues_from_inside
        test eax, eax
        jnz 8f
        inc r13d
        jmp 2b
8:      mov eax, 1
        LEAVE
9:      xor eax, eax
        LEAVE
.Lcf_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_index]
        call err_throw
ENDF continues_from_inside

# holds_continue(exp, jd) -> eax: a ('continue', jd, _) anywhere in exp
FUNC holds_continue
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rbx
        OP_N_CHECK OP_CONTINUE, 3, 1f
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, r12
        call py_equal
        test eax, eax
        jnz 8f
1:      mov rdi, rbx
        call is_seq
        test eax, eax
        jz 9f
        mov rax, [rbx + N_HASH]         # (no "continue" in it: none)
        mov rcx, HF_CONTINUE
        test rax, rcx
        jz 9f
        xor r13d, r13d
2:      cmp r13d, [rbx + N_AUX]
        jae 9f
        mov rdi, [rbx + N_DATA + r13*8]
        mov rsi, r12
        call holds_continue
        test eax, eax
        jnz 8f
        inc r13d
        jmp 2b
8:      mov eax, 1
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF holds_continue

        .section .note.GNU-stack,"",@progbits
