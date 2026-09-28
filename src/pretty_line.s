# Lines and traces as text (port of prettify.py's pretty_line and
# pprint_logic): pretty_line(line, flags) -> list of str, pprint_logic
# (trace, indent) -> list of str (the lines, indented).

.include "defs.inc"

        .section .rodata
.Ls_hash_sp:    .asciz "# "
.Ls_log_sp:     .asciz "log "
.Ls_colon:      .asciz ":"
.Ls_comma_sp:   .asciz ", "
.Ls_comma:      .asciz ","
.Ls_lparen:     .asciz "("
.Ls_rparen:     .asciz ")"
.Ls_eq:         .asciz "="
.Ls_sp:         .asciz " "
.Ls_six_sp:     .asciz "      "
.Ls_codecall:   .asciz "codecall"
.Ls_delegate:   .asciz "delegate"
.Ls_sp_with:    .asciz " with:"
.Ls_dot:        .asciz "."
.Ls_funct:      .asciz "   funct "
.Ls_funct5:     .asciz "     funct "
.Ls_value:      .asciz "   value "
.Ls_sp_wei:     .asciz " "
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
.Ls_0x0:        .asciz "0x0"
.Ls_label_:     .asciz "label "
.Ls_setvars_:   .asciz " setvars: "
.Ls_continue_sp: .asciz "continue "
.Ls_minusminus: .asciz "--"
.Ls_plusplus:   .asciz "++"
.Ls_minus_eq:   .asciz " -= "
.Ls_plus_eq:    .asciz " += "
.Ls_eq_sp:      .asciz " = "
.Ls_stop:       .asciz "stop"
.Ls_dots:       .asciz "..."
.Ls_aborted:    .asciz "  # Decompilation aborted, sorry: "
.Ls_revert_sp:  .asciz "revert "
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
.Ls_hash_sp2:   .asciz "# "
.Ls_32:         .asciz "32"
.Ls_32_comma:   .asciz "32, "
.Ls_NHq:        .asciz "'NH{q'"
.Ls_require_sp: .asciz "require "
.Ls_while_sp:   .asciz "while "
.Ls_if_sp:      .asciz "if "
.Ls_if:         .asciz "if"
.Ls_or:         .asciz "or"
.Ls_else:       .asciz "else:"
.Ls_weird_log:  .asciz "weird log %S"
.Ls_logname:    .asciz "panoramix.prettify"
.Ls_assert_log: .asciz "pretty_line: a log event without a closing parenthesis"

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
        sub rsp, MATCH_BINDINGS_SIZE + 96
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
        JT_END pretty_line, OP_COUNT, .Lpl_other

.Lpl_log:
        # ('log', params, *events)
        cmp dword ptr [rbx + N_AUX], 2
        jb .Lpl_other
        mov rdi, [rbx + N_DATA + 8]
        xor esi, esi
        call pretty_memory
        mov [rsp + PL_T1], rax          # res_params (a list)
        mov rdi, rbx
        mov esi, 2
        call list_from
        mov [rsp + PL_T2], rax          # events
        # an event that isn't an int: the others become parameters, and
        # only the first is kept
        mov r14, rax
        xor ecx, ecx
3:      cmp ecx, [r14 + N_AUX]
        jae 5f
        mov rdi, [r14 + N_DATA + rcx*8]
        mov [rsp + PL_I], rcx
        call is_int
        mov rcx, [rsp + PL_I]
        test eax, eax
        jnz 4f
        # res_params += prettify(e) for e in events[1:]
        mov rdi, r14
        mov esi, 1
        call list_from
        mov rdi, rax
        lea rsi, [rip + prettify_plain_cb]
        xor edx, edx
        call map_seq
        mov rdi, [rsp + PL_T1]
        mov rsi, rax
        call list_concat
        mov [rsp + PL_T1], rax
        mov edi, 1
        lea rsi, [r14 + N_DATA]
        call mk_list
        mov [rsp + PL_T2], rax
        jmp 5f
4:      inc ecx
        jmp 3b
5:      # res_events: the names, hex ones cut to 10 characters
        mov rdi, [rsp + PL_T2]
        lea rsi, [rip + fname_force_cb]
        xor edx, edx
        call map_seq
        mov [rsp + PL_T2], rax
        mov qword ptr [rsp + PL_I], 0
.Lpl_log_event:
        mov rcx, [rsp + PL_I]
        mov rax, [rsp + PL_T2]
        cmp ecx, [rax + N_AUX]
        jae .Lpl_ret
        mov r14, [rax + N_DATA + rcx*8] # e
        inc qword ptr [rsp + PL_I]
        mov rdi, r14
        mov esi, '('
        call str_count_char
        cmp eax, 1
        je 6f
        # "log {e}{':' if res_params else ''} {', '.join(res_params)}"
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_log_sp]
        call sb_append_c
        mov rdi, r13
        mov rsi, r14
        call sb_append_str
        mov rax, [rsp + PL_T1]
        cmp dword ptr [rax + N_AUX], 0
        je 51f
        mov rdi, r13
        mov esi, ':'
        call sb_append_char
51:     mov rdi, r13
        mov esi, ' '
        call sb_append_char
        lea rdi, [rip + .Ls_comma_sp]
        mov rsi, [rsp + PL_T1]
        call str_join
        mov rdi, r13
        mov rsi, rax
        call sb_append_str
        mov rdi, r13
        mov rsi, [rsp + PL_OUT]
        call .Lpl_yield_gray
        jmp .Lpl_log_event
6:      # fname, fparams = e.split("("); fparams must end with ")"
        lea rdi, [r14 + N_DATA + 4]
        mov esi, '('
        call strchr@PLT
        mov r13, rax                    # -> "("
        lea rdi, [r14 + N_DATA + 4]
        mov rsi, r13
        sub rsi, rdi
        call str_new
        mov [rsp + PL_T3], rax          # fname
        mov ecx, [r14 + N_DATA]
        lea rax, [r14 + N_DATA + 4 + rcx - 1]
        cmp byte ptr [rax], ')'
        jne .Lpl_assert_log
        lea rdi, [r13 + 1]
        mov rsi, rax
        sub rsi, rdi
        call str_new
        mov rdi, rax
        lea rsi, [rip + .Ls_comma_sp]
        call str_split
        mov [rsp + PL_T4], rax          # fparams (a list of str)
        # fparams == [""] or no res_params: "log {e}"
        mov rcx, [rsp + PL_T1]
        cmp dword ptr [rcx + N_AUX], 0
        je 61f
        cmp dword ptr [rax + N_AUX], 1
        jne 62f
        mov rdi, [rax + N_DATA]
        cmp dword ptr [rdi + N_DATA], 0
        jne 62f
61:     call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_log_sp]
        call sb_append_c
        mov rdi, r13
        mov rsi, r14
        call sb_append_str
        mov rdi, r13
        mov rsi, [rsp + PL_OUT]
        call .Lpl_yield_gray
        jmp .Lpl_log_event
62:     mov rax, [rsp + PL_T4]
        mov ecx, [rax + N_AUX]
        mov rdx, [rsp + PL_T1]
        cmp ecx, [rdx + N_AUX]
        jne .Lpl_log_mismatch
        # p_list: (type, name, value) triples; a parameter that isn't
        # "type name" is a weird log
        call vec_new
        mov [rsp + PL_T5], rax
        xor ecx, ecx
63:     mov rax, [rsp + PL_T4]
        cmp ecx, [rax + N_AUX]
        jae 64f
        mov [rsp + PL_SB], rcx
        mov rdi, [rax + N_DATA + rcx*8]
        lea rsi, [rip + .Ls_sp]
        call str_split
        cmp dword ptr [rax + N_AUX], 2
        jne .Lpl_weird_log
        mov rcx, [rsp + PL_SB]
        mov rdx, [rsp + PL_T1]
        mov rdx, [rdx + N_DATA + rcx*8]
        mov rdi, [rax + N_DATA]
        mov rsi, [rax + N_DATA + 8]
        call mk3
        mov rdi, [rsp + PL_T5]
        mov rsi, rax
        call vec_push
        mov rcx, [rsp + PL_SB]
        inc ecx
        jmp 63b
64:     mov rax, [rsp + PL_T5]
        cmp qword ptr [rax + VEC_LEN], 1
        jne 65f
        # "log {fname}({type} {name}={value})"
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_log_sp]
        call sb_append_c
        mov rdi, r13
        mov rsi, [rsp + PL_T3]
        call sb_append_str
        mov rdi, r13
        mov esi, '('
        call sb_append_char
        mov rax, [rsp + PL_T5]
        mov rax, [rax + VEC_DATA]
        mov rdi, r13
        mov rsi, [rax]
        call .Lpl_pline
        mov rdi, r13
        mov esi, ')'
        call sb_append_char
        mov rdi, r13
        mov rsi, [rsp + PL_OUT]
        call .Lpl_yield_gray
        jmp .Lpl_log_event
65:     # "log {fname}(", then one parameter per line
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_log_sp]
        call sb_append_c
        mov rdi, r13
        mov rsi, [rsp + PL_T3]
        call sb_append_str
        mov rdi, r13
        mov esi, '('
        call sb_append_char
        mov rdi, r13
        mov rsi, [rsp + PL_OUT]
        call .Lpl_yield_gray
        mov qword ptr [rsp + PL_SB], 0
66:     mov rax, [rsp + PL_T5]
        mov rcx, [rsp + PL_SB]
        cmp rcx, [rax + VEC_LEN]
        jae .Lpl_log_event
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_six_sp]
        call sb_append_c
        mov rax, [rsp + PL_T5]
        mov rcx, [rsp + PL_SB]
        mov rax, [rax + VEC_DATA]
        mov rdi, r13
        mov rsi, [rax + rcx*8]
        call .Lpl_pline
        mov rax, [rsp + PL_T5]
        mov rcx, [rsp + PL_SB]
        inc rcx
        cmp rcx, [rax + VEC_LEN]
        je 67f
        mov rdi, r13
        mov esi, ','
        call sb_append_char
        jmp 68f
67:     mov rdi, r13
        mov esi, ')'
        call sb_append_char
68:     mov rdi, r13
        mov rsi, [rsp + PL_OUT]
        call .Lpl_yield_gray
        inc qword ptr [rsp + PL_SB]
        jmp 66b
.Lpl_log_mismatch:
        # "log {e}:", then the parameters indented under "log {fname}("
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_log_sp]
        call sb_append_c
        mov rdi, r13
        mov rsi, r14
        call sb_append_str
        mov rdi, r13
        mov esi, ':'
        call sb_append_char
        mov rdi, r13
        mov rsi, [rsp + PL_OUT]
        call .Lpl_yield_gray
        mov rax, [rsp + PL_T3]
        mov ecx, [rax + N_DATA]
        add ecx, 5                      # len("log ") + len(fname) + len("(")
        mov [rsp + PL_T4], rcx
        mov qword ptr [rsp + PL_SB], 0
69:     mov rax, [rsp + PL_T1]
        mov rcx, [rsp + PL_SB]
        cmp ecx, [rax + N_AUX]
        jae .Lpl_log_event
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, [rsp + PL_T4]
        call sb_append_spaces
        mov rax, [rsp + PL_T1]
        mov rcx, [rsp + PL_SB]
        mov rdi, r13
        mov rsi, [rax + N_DATA + rcx*8]
        call sb_append_str
        mov rdi, r13
        mov esi, ','
        call sb_append_char
        mov rdi, r13
        mov rsi, [rsp + PL_OUT]
        call .Lpl_yield_gray
        inc qword ptr [rsp + PL_SB]
        jmp 69b
.Lpl_weird_log:
        mov edi, LOG_WARNING
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_weird_log]
        mov rcx, r14
        call log_fmt
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_log_sp]
        call sb_append_c
        mov rdi, r13
        mov rsi, r14
        call sb_append_str
        mov rdi, r13
        call sb_finish
        mov rdi, [rsp + PL_OUT]
        mov rsi, rax
        call vec_push
        jmp .Lpl_ret                    # (python returns from the generator)

# locals of the log lines: "{type} {name}={pret(value)}" appended to the
# builder rdi from the triple rsi; the builder r13 as a gray line
.Lpl_pline:
        sub rsp, 24
        mov [rsp], rdi
        mov [rsp + 8], rsi
        mov rsi, [rsi + N_DATA]
        call sb_append_str
        mov rdi, [rsp]
        mov esi, ' '
        call sb_append_char
        mov rax, [rsp + 8]
        mov rdi, [rsp]
        mov rsi, [rax + N_DATA + 8]
        call sb_append_str
        mov rdi, [rsp]
        mov esi, '='
        call sb_append_char
        mov rax, [rsp + 8]
        mov rdi, [rsp]
        mov rsi, [rax + N_DATA + 16]
        xor edx, edx
        call sb_append_pret
        add rsp, 24
        ret
# (rdi = the builder, rsi = the lines)
.Lpl_yield_gray:
        sub rsp, 8
        mov [rsp], rsi
        call sb_finish
        mov rdi, rax
        lea rsi, [rip + C_GRAY]
        mov rdx, r12
        call colorize
        mov rdi, [rsp]
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
        mov qword ptr [rsp + PL_T5], 1  # (no value)
.Lpl_xcall:
        # fname = pretty_fname(fname); addr (hex when an int) prettified;
        # gas prettified; fparams = pretty_memory(fparams)
        mov ecx, [rbx + N_AUX]
        mov rdi, [rbx + N_DATA + rcx*8 - 16]    # fname
        mov rsi, r12
        xor edx, edx
        call pretty_fname
        mov [rsp + PL_T1], rax
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
        mov ecx, [rbx + N_AUX]
        mov rdi, [rbx + N_DATA + rcx*8 - 8]
        mov rsi, r12
        call pretty_memory
        mov [rsp + PL_T4], rax          # fparams
        # "{WARNING}codecall{ENDC} {addr}[.{fname}] with:"
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
        mov rdi, [rsp + PL_T1]
        call is_none
        test eax, eax
        jnz 3f
        mov rdi, [rsp + PL_T1]
        call is_str
        test eax, eax
        jz 2f
        mov rdi, r14
        mov esi, '.'
        call sb_append_char
        mov rdi, r14
        mov rsi, [rsp + PL_T1]
        call sb_append_str
        jmp 3f
2:      mov rdi, r14
        lea rsi, [rip + .Ls_sp_with]
        call sb_append_c
        mov rdi, r14
        mov rsi, [rsp + PL_OUT]
        call .Lpl_yield_sb
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
        mov rsi, [rsp + PL_OUT]
        call .Lpl_yield_sb
        jmp 4f
3:      mov rdi, r14
        lea rsi, [rip + .Ls_sp_with]
        call sb_append_c
        mov rdi, r14
        mov rsi, [rsp + PL_OUT]
        call .Lpl_yield_sb
4:      mov rdi, [rsp + PL_T5]
        call .Lpl_value_line
        # "     gas {gas} {GRAY}wei{ENDC}"
        lea rdi, [rip + .Ls_gas5]
        mov rsi, [rsp + PL_T3]
        mov rdx, [rsp + PL_OUT]
        call .Lpl_gas_line
        # "    args {', '.join(fparams)}"
        lea rdi, [rip + .Ls_args4]
        mov rsi, [rsp + PL_T4]
        mov rdx, [rsp + PL_OUT]
        call .Lpl_args_line
        jmp .Lpl_ret

# locals: the "   value {wei} {GRAY}wei{ENDC}" line unless wei is 0
.Lpl_value_line:
        sub rsp, 24
        mov [rsp], rdi
        mov [rsp + 16], rsi
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
        call .Lpl_wei_end
        mov rdi, [rsp + 8]
        mov rsi, [rsp + 16]
        call .Lpl_yield_sb
1:      add rsp, 24
        ret
# "{prefix}{gas} {GRAY}wei{ENDC}"
.Lpl_gas_line:
        sub rsp, 40
        mov [rsp], rdi
        mov [rsp + 8], rsi
        mov [rsp + 24], rdx
        call sb_new
        mov [rsp + 16], rax
        mov rdi, rax
        mov rsi, [rsp]
        call sb_append_c
        mov rdi, [rsp + 16]
        mov rsi, [rsp + 8]
        call sb_append_str
        mov rdi, [rsp + 16]
        call .Lpl_wei_end
        mov rdi, [rsp + 16]
        mov rsi, [rsp + 24]
        call .Lpl_yield_sb
        add rsp, 40
        ret
.Lpl_wei_end:
        sub rsp, 8
        mov [rsp], rdi
        mov esi, ' '
        call sb_append_char
        mov rdi, [rsp]
        lea rsi, [rip + C_GRAY]
        call sb_append_c
        mov rdi, [rsp]
        lea rsi, [rip + .Ls_wei]
        call sb_append_c
        mov rdi, [rsp]
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        add rsp, 8
        ret
# "{prefix}{', '.join(fparams)}" (fparams: a list, or a str for python's
# bare strings - joined character by character there too)
.Lpl_args_line:
        sub rsp, 40
        mov [rsp], rdi
        mov [rsp + 8], rsi
        mov [rsp + 24], rdx
        call sb_new
        mov [rsp + 16], rax
        mov rdi, rax
        mov rsi, [rsp]
        call sb_append_c
        lea rdi, [rip + .Ls_comma_sp]
        mov rsi, [rsp + 8]
        call str_join
        mov rdi, [rsp + 16]
        mov rsi, rax
        call sb_append_str
        mov rdi, [rsp + 16]
        mov rsi, [rsp + 24]
        call .Lpl_yield_sb
        add rsp, 40
        ret
# the builder rdi finished and appended to the lines rsi
.Lpl_yield_sb:
        sub rsp, 8
        mov [rsp], rsi
        call sb_finish
        mov rdi, [rsp]
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
        jb .Lpl_other
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
        mov rdi, r13
        mov rsi, [rbx + N_DATA + 24]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
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
        mov rdx, [rsp + PL_OUT]
        call .Lpl_create_line
        lea rdi, [rip + .Ls_code_]
        mov rsi, [rbx + N_DATA + 16]
        mov rdx, [rsp + PL_OUT]
        call .Lpl_pretty_after
        jmp .Lpl_ret
.Lpl_create2:
        cmp dword ptr [rbx + N_AUX], 4
        jne .Lpl_other
        lea rdi, [rip + .Ls_create2_with]
        mov rsi, [rbx + N_DATA + 8]
        mov rdx, [rsp + PL_OUT]
        call .Lpl_create_line
        lea rdi, [rip + .Ls_salt_]
        mov rsi, [rbx + N_DATA + 24]
        mov rdx, [rsp + PL_OUT]
        call .Lpl_pretty_after
        lea rdi, [rip + .Ls_code_]
        mov rsi, [rbx + N_DATA + 16]
        mov rdx, [rsp + PL_OUT]
        call .Lpl_pretty_after
        jmp .Lpl_ret
# "{prefix}{str(wei)} wei"
.Lpl_create_line:
        sub rsp, 40
        mov [rsp], rdi
        mov [rsp + 8], rsi
        mov [rsp + 24], rdx
        call sb_new
        mov [rsp + 16], rax
        mov rdi, rax
        mov rsi, [rsp]
        call sb_append_c
        mov rdi, [rsp + 8]
        call value_str
        mov rdi, [rsp + 16]
        mov rsi, rax
        call sb_append_str
        mov rdi, [rsp + 16]
        lea rsi, [rip + .Ls_sp_wei_end]
        call sb_append_c
        mov rdi, [rsp + 16]
        mov rsi, [rsp + 24]
        call .Lpl_yield_sb
        add rsp, 40
        ret
# "{prefix}{prettify(exp)}" (no color, parentheses)
.Lpl_pretty_after:
        sub rsp, 40
        mov [rsp], rdi
        mov [rsp + 8], rsi
        mov [rsp + 24], rdx
        call sb_new
        mov [rsp + 16], rax
        mov rdi, rax
        mov rsi, [rsp]
        call sb_append_c
        mov rdi, [rsp + 16]
        mov rsi, [rsp + 8]
        mov edx, PF_PARENS
        call sb_append_pret
        mov rdi, [rsp + 16]
        mov rsi, [rsp + 24]
        call .Lpl_yield_sb
        add rsp, 40
        ret

.Lpl_call:
        # ('call', gas, addr, wei, fname, fparams)
        cmp dword ptr [rbx + N_AUX], 6
        jne .Lpl_other
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
        mov rsi, [rbx + N_DATA + 24]
        mov rdx, r12
        call pretty_gas
        mov [rsp + PL_T3], rax          # gas
        # "call {addr} with:" / "call {addr}.{fname} with:" / + "   funct"
        call sb_new
        mov r14, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_call_sp]
        call sb_append_c
        mov rdi, r14
        mov rsi, [rsp + PL_T2]
        call sb_append_str
        mov rdi, [rbx + N_DATA + 32]
        call is_none
        test eax, eax
        jnz 5f
        mov rdi, [rbx + N_DATA + 32]
        mov rsi, r12
        xor edx, edx
        call pretty_fname
        mov [rsp + PL_T1], rax
        mov rdi, rax
        call is_str
        test eax, eax
        jz 4f
        mov rdi, [rsp + PL_T1]
        lea rsi, [rip + .Ls_0x0]
        call str_eq_c
        test eax, eax
        jnz 5f
        mov rdi, r14
        mov esi, '.'
        call sb_append_char
        mov rdi, r14
        mov rsi, [rsp + PL_T1]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        jmp 5f
4:      mov rdi, r14
        lea rsi, [rip + .Ls_sp_with]
        call sb_append_c
        mov rdi, r14
        mov rsi, [rsp + PL_OUT]
        call .Lpl_yield_sb
        call sb_new
        mov r14, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_funct]
        call sb_append_c
        mov rdi, r14
        mov rsi, [rsp + PL_T1]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, r14
        mov rsi, [rsp + PL_OUT]
        call .Lpl_yield_sb
        jmp 6f
5:      mov rdi, r14
        lea rsi, [rip + .Ls_sp_with]
        call sb_append_c
        mov rdi, r14
        mov rsi, [rsp + PL_OUT]
        call .Lpl_yield_sb
6:      mov rdi, [rbx + N_DATA + 24]
        mov rsi, [rsp + PL_OUT]
        call .Lpl_value_line
        lea rdi, [rip + .Ls_gas5]
        mov rsi, [rsp + PL_T3]
        mov rdx, [rsp + PL_OUT]
        call .Lpl_gas_line
        mov rdi, [rbx + N_DATA + 40]
        call is_none
        test eax, eax
        jnz .Lpl_ret
        mov rdi, [rbx + N_DATA + 40]
        mov rsi, r12
        call pretty_memory
        lea rdi, [rip + .Ls_args4]
        mov rsi, rax
        mov rdx, [rsp + PL_OUT]
        call .Lpl_args_line
        jmp .Lpl_ret

.Lpl_staticcall:
        # ('staticcall', gas, addr, wei, fname, fparams)
        cmp dword ptr [rbx + N_AUX], 6
        jne .Lpl_other
        mov rdi, [rbx + N_DATA + 16]
        call .Lpl_hex_addr
        mov rdi, rax
        PF_COLOR_OF rsi, r12
        call prettify
        mov [rsp + PL_T2], rax          # addr
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rbx + N_DATA + 24]
        mov rdx, r12
        call pretty_gas
        mov [rsp + PL_T3], rax          # gas
        call sb_new
        mov r14, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_static_call_sp]
        call sb_append_c
        mov rdi, r14
        mov rsi, [rsp + PL_T2]
        call sb_append_str
        mov rdi, [rbx + N_DATA + 32]
        call is_none
        test eax, eax
        jnz 5f
        mov rdi, [rbx + N_DATA + 32]
        mov rsi, r12
        xor edx, edx
        call pretty_fname
        mov [rsp + PL_T1], rax
        mov rdi, rax
        call is_str
        test eax, eax
        jz 4f
        mov rdi, [rsp + PL_T1]
        lea rsi, [rip + .Ls_0x0]
        call str_eq_c
        test eax, eax
        jnz 5f
        mov rdi, r14
        mov esi, '.'
        call sb_append_char
        mov rdi, r14
        mov rsi, [rsp + PL_T1]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        jmp 5f
4:      mov rdi, r14
        lea rsi, [rip + .Ls_sp_with]
        call sb_append_c
        mov rdi, r14
        mov rsi, [rsp + PL_OUT]
        call .Lpl_yield_sb
        call sb_new
        mov r14, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_funct5]
        call sb_append_c
        mov rdi, r14
        mov rsi, [rsp + PL_T1]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, r14
        mov rsi, [rsp + PL_OUT]
        call .Lpl_yield_sb
        jmp 6f
5:      mov rdi, r14
        lea rsi, [rip + .Ls_sp_with]
        call sb_append_c
        mov rdi, r14
        mov rsi, [rsp + PL_OUT]
        call .Lpl_yield_sb
6:      lea rdi, [rip + .Ls_gas8]
        mov rsi, [rsp + PL_T3]
        mov rdx, [rsp + PL_OUT]
        call .Lpl_gas_line
        mov rdi, [rbx + N_DATA + 40]
        call is_none
        test eax, eax
        jnz .Lpl_ret
        mov rdi, [rbx + N_DATA + 40]
        mov rsi, r12
        call pretty_memory
        lea rdi, [rip + .Ls_args7]
        mov rsi, rax
        mov rdx, [rsp + PL_OUT]
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
        # ('continue', jd, setvars): the setvars' first lines, then "continue "
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lpl_other
        mov r13, [rbx + N_DATA + 16]
        xor r14d, r14d
1:      cmp r14d, [r13 + N_AUX]
        jae 2f
        mov rdi, [r13 + N_DATA + r14*8]
        mov esi, PF_COLOR
        call pretty_line
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
        cmp rdi, -1                     # tagged -1
        jne 11f
        lea rsi, [rip + .Ls_minusminus]
        jmp .Lpl_set_suffix
11:     cmp rdi, 3                      # tagged 1
        jne 12f
        lea rsi, [rip + .Ls_plusplus]
        jmp .Lpl_set_suffix
12:     call int_sign
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
        lea rdi, [rip + .Ls_revert]
        cmp dword ptr [rbx + N_AUX], 1
        je 1f
        lea rdi, [rip + .Ls_revert_sp]
1:      call str_new_c
        mov rdi, [rsp + PL_OUT]
        mov rsi, rax
        call vec_push
        jmp .Lpl_ret

.Lpl_revert_return:
        cmp dword ptr [rbx + N_AUX], 2
        jne .Lpl_other
        mov r14, [rbx + N_DATA + 8]     # the parameter
        cmp r13d, OP_REVERT
        jne 2f
        # ('revert', 0) and ('revert', ('mem', 0, 0)): "revert"
        cmp r14, 1
        je 1f
        PAT rsi, "('mem', 0, 0)"
        mov rdi, r14
        call pat_match_nobind
        test eax, eax
        jz 2f
1:      lea rdi, [rip + .Ls_revert]
        call str_new_c
        mov rdi, [rsp + PL_OUT]
        mov rsi, rax
        call vec_push
        jmp .Lpl_ret
2:      # (op, ('mem', ('range', mem_idx, mem_len)))
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
        mov rsi, [rsp + PL_OUT]
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
        B rsi, 0
        lea rdi, [rip + .Ls_from2]
        mov rdx, [rsp + PL_OUT]
        call .Lpl_pret_after
        B rax, 1
        mov rsi, [rax + N_DATA + 8]
        lea rdi, [rip + .Ls_to]
        mov rdx, [rsp + PL_OUT]
        call .Lpl_pret_after
        jmp .Lpl_ret
5:      B rsi, 0
        lea rdi, [rip + .Ls_from1]
        mov rdx, [rsp + PL_OUT]
        call .Lpl_pret_after
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
# "{prefix}{pret(exp)}"
.Lpl_pret_after:
        sub rsp, 40
        mov [rsp], rdi
        mov [rsp + 8], rsi
        mov [rsp + 24], rdx
        call sb_new
        mov [rsp + 16], rax
        mov rdi, rax
        mov rsi, [rsp]
        call sb_append_c
        mov rdi, [rsp + 16]
        mov rsi, [rsp + 8]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, [rsp + 16]
        mov rsi, [rsp + 24]
        call .Lpl_yield_sb
        add rsp, 40
        ret
.Lpl_ret_data:
        # op = "return" / "revert with"; the memory as text
        mov rdi, r14
        mov esi, PF_COLOR
        call pretty_memory
        mov [rsp + PL_T1], rax          # res_mem
        lea rdi, [rip + .Ls_comma_sp]
        mov rsi, rax
        call str_join
        mov [rsp + PL_T2], rax          # ret_val
        lea rdi, [rip + .Ls_revert_with]
        cmp r13d, OP_REVERT
        je 1f
        mov rax, [rsp + PL_LINE]
        mov rdi, [rax + N_DATA]
        add rdi, N_DATA + 4             # "return"
1:      call str_new_c
        mov [rsp + PL_T3], rax          # op
        # a panic
        PAT rsi, "('revert', ('data', \"'NH{q'\", ':int:panic_code'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
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
        lea rsi, [rip + .Ls_hash_sp2]
        call sb_append_c
        mov rdi, r13
        mov rsi, r14
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        jmp .Lpl_yield_finish
2:      # short, or not a data: "{op} {ret_val}"
        mov rdi, [rsp + PL_T2]
        call clean_color
        mov rdi, rax
        call str_charlen
        cmp eax, 120
        jb 3f
        mov rdi, r14
        call opcode_of
        cmp eax, OP_DATA
        je 4f
3:      call sb_new
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
4:      # a long return split into lines; a leading "32" joins the next
        mov r14, [rsp + PL_T1]
        cmp dword ptr [r14 + N_AUX], 0
        je .Lpl_index
        mov rdi, [r14 + N_DATA]
        lea rsi, [rip + .Ls_32]
        call str_eq_c
        test eax, eax
        jz 5f
        cmp dword ptr [r14 + N_AUX], 1
        je .Lpl_index                   # (python: res_mem[0] on an empty list)
        lea rdi, [rip + .Ls_32_comma]
        call str_new_c
        mov rdi, rax
        mov rsi, [r14 + N_DATA + 8]
        call str_cat2
        mov rdi, r14
        mov esi, 2
        push rax
        push rax
        call list_from
        pop rsi
        pop rsi
        mov rdi, rsi
        push rax
        push rax
        call mk_list1
        pop rsi
        pop rsi
        mov rdi, rax
        call list_concat
        mov r14, rax
5:      # "{op} {res_mem[0]}, " then the others under it
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
        mov rsi, [rsp + PL_OUT]
        call .Lpl_yield_sb
        mov qword ptr [rsp + PL_I], 1
6:      mov rcx, [rsp + PL_I]
        cmp ecx, [r14 + N_AUX]
        jae .Lpl_ret
        call sb_new
        mov r13, rax
        mov rax, [rsp + PL_T3]
        mov esi, [rax + N_DATA]
        inc esi
        mov rdi, r13
        call sb_append_spaces
        mov rcx, [rsp + PL_I]
        mov rdi, r13
        mov rsi, [r14 + N_DATA + rcx*8]
        call sb_append_str
        mov rcx, [rsp + PL_I]
        inc ecx
        cmp ecx, [r14 + N_AUX]
        je 7f
        mov rdi, r13
        mov esi, ','
        call sb_append_char
7:      mov rdi, r13
        mov rsi, [rsp + PL_OUT]
        call .Lpl_yield_sb
        inc qword ptr [rsp + PL_I]
        jmp 6b
# a local: the explanation of a panic code (an int value), or 0
.Lpl_panic_text:
        sub rsp, 8
        call int_to_i64
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

.Lpl_yield_finish:
        mov rdi, r13
        call sb_finish
        mov rdi, [rsp + PL_OUT]
        mov rsi, rax
        call vec_push
.Lpl_ret:
        mov rdi, [rsp + PL_OUT]
        call vec_to_list
        add rsp, MATCH_BINDINGS_SIZE + 96
        LEAVE
.Lpl_assert_log:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_log]
        call err_throw
.Lpl_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_index]
        call err_throw
ENDF pretty_line

        .section .rodata
.Ls_index: .asciz "pretty_line: an empty list"
        .text

# prettify_plain_cb(exp, arg): prettify without color nor parentheses
FUNC prettify_plain_cb
        xor esi, esi
        jmp prettify
ENDF prettify_plain_cb

# fname_force_cb(e, arg): pretty_fname(e, force=True), the hex names cut
# to their first 10 characters
FUNC fname_force_cb
        ENTER
        xor esi, esi
        mov edx, 1
        call pretty_fname
        mov rbx, rax
        mov rdi, rax
        call is_str
        test eax, eax
        jz 1f
        mov rdi, rbx
        lea rsi, [rip + .Ls_0x]
        call str_startswith_c
        test eax, eax
        jz 1f
        mov rdi, rbx
        xor esi, esi
        mov edx, 10
        call str_slice
        LEAVE
1:      mov rax, rbx
        LEAVE
ENDF fname_force_cb

        .section .rodata
.Ls_0x: .asciz "0x"
        .text

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

# --- the traces ---

# pprint_logic(exp, indent) -> list of str: a trace (or a line) as
# indented lines of text
FUNC pprint_logic
        STACK_CHECK
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 48
        .set PP_OUT, MATCH_BINDINGS_SIZE
        .set PP_INDENT, MATCH_BINDINGS_SIZE + 8
        .set PP_I, MATCH_BINDINGS_SIZE + 16
        .set PP_T1, MATCH_BINDINGS_SIZE + 24
        mov rbx, rdi
        mov [rsp + PP_INDENT], rsi
        call vec_new
        mov [rsp + PP_OUT], rax
        mov rdi, rbx
        call opcode_of
        mov r12d, eax
        JT_SWITCH pprint_logic, OP_COUNT, .Lpp_other
        JT_CASE pprint_logic, OP_WHILE, .Lpp_while
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
        mov rdx, [rsp + PP_OUT]
        call .Lpp_indented
        inc r14d
        jmp 1b

.Lpp_while:
        # the setvars, "while cond:", the body
        cmp dword ptr [rbx + N_AUX], 3
        jb .Lpp_line
        cmp dword ptr [rbx + N_AUX], 5
        jne 2f
        mov r13, [rbx + N_DATA + 32]    # vars
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
        mov rdi, [rsp + PP_INDENT]
        mov rsi, [rax + N_DATA]
        mov rdx, [rsp + PP_OUT]
        call .Lpp_indented
        inc r14d
        jmp 1b
2:      call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + C_GREEN]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + .Ls_while_sp]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        mov rdi, r13
        mov rsi, [rbx + N_DATA + 8]
        mov edx, PF_COLOR | PF_REM_BOOL
        call sb_append_pret
        mov rdi, r13
        lea rsi, [rip + C_GREEN]
        call sb_append_c
        mov rdi, r13
        mov esi, ':'
        call sb_append_char
        mov rdi, r13
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        mov rdi, r13
        call sb_finish
        mov rdi, [rsp + PP_INDENT]
        mov rsi, rax
        mov rdx, [rsp + PP_OUT]
        call .Lpp_indented
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, [rsp + PP_INDENT]
        add rsi, 4
        mov rdx, [rsp + PP_OUT]
        call .Lpp_extend
        jmp .Lpp_ret

.Lpp_require:
        cmp dword ptr [rbx + N_AUX], 2
        jne .Lpp_line
        mov rdi, [rbx + N_DATA + 8]
        call .Lpp_require_line
        jmp .Lpp_ret

.Lpp_if:
        cmp dword ptr [rbx + N_AUX], 3
        je .Lpp_if1
        cmp dword ptr [rbx + N_AUX], 4
        jne .Lpp_line
        # ('if', cond, if_true, if_false)
        mov rdi, [rbx + N_DATA + 24]
        call .Lpp_is_revert_block
        test eax, eax
        jz 1f
        # require cond; if_true at the same level
        mov rdi, [rbx + N_DATA + 8]
        call .Lpp_require_line
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, [rsp + PP_INDENT]
        mov rdx, [rsp + PP_OUT]
        call .Lpp_extend
        jmp .Lpp_ret
1:      mov rdi, [rbx + N_DATA + 16]
        call .Lpp_is_revert_block
        test eax, eax
        jz 2f
        mov rdi, [rbx + N_DATA + 8]
        call is_zero
        mov rdi, rax
        call .Lpp_require_line
        mov rdi, [rbx + N_DATA + 24]
        mov rsi, [rsp + PP_INDENT]
        mov rdx, [rsp + PP_OUT]
        call .Lpp_extend
        jmp .Lpp_ret
2:      mov rdi, [rbx + N_DATA + 8]
        call .Lpp_if_line
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, [rsp + PP_INDENT]
        add rsi, 4
        mov rdx, [rsp + PP_OUT]
        call .Lpp_extend
        lea rdi, [rip + .Ls_else]
        call str_new_c
        mov rdi, [rsp + PP_INDENT]
        mov rsi, rax
        mov rdx, [rsp + PP_OUT]
        call .Lpp_indented
        mov rdi, [rbx + N_DATA + 24]
        mov rsi, [rsp + PP_INDENT]
        add rsi, 4
        mov rdx, [rsp + PP_OUT]
        call .Lpp_extend
        jmp .Lpp_ret
.Lpp_if1:
        # ('if', cond, if_true): a require when it just reverts
        mov rdi, [rbx + N_DATA + 16]
        call .Lpp_is_revert_block
        test eax, eax
        jz 1f
        mov rdi, [rbx + N_DATA + 8]
        call is_zero
        mov rdi, rax
        call .Lpp_require_line
        jmp .Lpp_ret
1:      mov rdi, [rbx + N_DATA + 8]
        call .Lpp_if_line
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, [rsp + PP_INDENT]
        add rsi, 4
        mov rdx, [rsp + PP_OUT]
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
        mov rdx, [rsp + PP_OUT]
        call .Lpp_extend
3:      inc r14d
        jmp 1b

.Lpp_or:
        cmp dword ptr [rbx + N_AUX], 1
        jbe .Lpp_line
        lea rdi, [rip + .Ls_if]
        call str_new_c
        mov rdi, [rsp + PP_INDENT]
        mov rsi, rax
        mov rdx, [rsp + PP_OUT]
        call .Lpp_indented
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rsp + PP_INDENT]
        add rsi, 4
        mov rdx, [rsp + PP_OUT]
        call .Lpp_extend
        mov r14d, 2
1:      cmp r14d, [rbx + N_AUX]
        jae .Lpp_ret
        lea rdi, [rip + .Ls_or]
        call str_new_c
        mov rdi, [rsp + PP_INDENT]
        mov rsi, rax
        mov rdx, [rsp + PP_OUT]
        call .Lpp_indented
        mov rdi, [rbx + N_DATA + r14*8]
        mov rsi, [rsp + PP_INDENT]
        add rsi, 4
        mov rdx, [rsp + PP_OUT]
        call .Lpp_extend
        inc r14d
        jmp 1b

.Lpp_ret:
        mov rdi, [rsp + PP_OUT]
        call vec_to_list
        add rsp, MATCH_BINDINGS_SIZE + 48
        LEAVE

# locals of pprint_logic
# " " * rdi + rsi, appended to the lines
.Lpp_indented:
        sub rsp, 40
        mov [rsp], rdi
        mov [rsp + 8], rsi
        mov [rsp + 24], rdx
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
        mov rdi, [rsp + 24]
        mov rsi, rax
        call vec_push
        add rsp, 40
        ret
# the lines of pprint_logic(rdi, rsi) appended to rdx
.Lpp_extend:
        sub rsp, 8
        mov [rsp], rdx
        call pprint_logic
        mov rdi, [rsp]
        mov rsi, rax
        call vec_extend_seq
        add rsp, 8
        ret
# "require " + prettify(rdi, color, rem_bool), indented
.Lpp_require_line:
        sub rsp, 24
        mov [rsp], rdi
        call sb_new
        mov [rsp + 8], rax
        mov rdi, rax
        lea rsi, [rip + .Ls_require_sp]
        call sb_append_c
        mov rdi, [rsp + 8]
        mov rsi, [rsp]
        mov edx, PF_COLOR | PF_REM_BOOL
        call sb_append_pret
        mov rdi, [rsp + 8]
        call sb_finish
        mov rdi, [rsp + 24 + 8 + PP_INDENT]
        mov rsi, rax
        mov rdx, [rsp + 24 + 8 + PP_OUT]
        call .Lpp_indented
        add rsp, 24
        ret
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
        mov rdx, [rsp + 24 + 8 + PP_OUT]
        call .Lpp_indented
        add rsp, 24
        ret
# eax: the block rdi is a single ('revert', 0) or invalid line
.Lpp_is_revert_block:
        sub rsp, 8
        cmp dword ptr [rdi + N_AUX], 1
        jne 1f
        mov rdi, [rdi + N_DATA]
        mov [rsp], rdi
        call py_truthy
        test eax, eax
        jz 1f
        mov rdi, [rsp]
        PAT rsi, "('revert', 0)"
        call pat_match_nobind
        test eax, eax
        jnz 2f
        mov rdi, [rsp]
        call opcode_of
        cmp eax, OP_INVALID
        jne 1f
2:      mov eax, 1
        add rsp, 8
        ret
1:      xor eax, eax
        add rsp, 8
        ret
ENDF pprint_logic

        .section .note.GNU-stack,"",@progbits
