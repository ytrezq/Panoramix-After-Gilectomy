# python's --explain (prettify.explain, explain_text): the trace printed
# at every stage of a function's decompilation, and the traits the
# function's analysis found.
#
# In python these print as they come, the functions one after the other;
# here each function's job prints into a builder of its own
# (CTX_EXPLAIN_SB of its context), and decompile() puts them one after
# the other in the order of the jobs - with python's one global
# prev_trace: a trace equal to the one printed last isn't printed again,
# which across two jobs concerns the first trace of the second one
# (CTX_EXPLAIN_FIRST, and what its text took: CTX_EXPLAIN_CUT).
#
# The lines of assembly the VM puts in the traces for --verbose and
# --explain are in vm.s (vm_trace_asm).

.include "defs.inc"

        .section .rodata
.Ls_title_sep:  .asciz ": "
.Ls_stop_line:  .asciz "  stop\n"
.Ls_traits:     .asciz "function traits"
.Ls_returns:    .asciz "possible return values"
.Ls_payable:    .asciz "payable"
.Ls_read_only:  .asciz "read_only"
.Ls_const:      .asciz "const"
.Ls_getter_for: .asciz "getter for"
.Ls_true:       .asciz "True"
.Ls_false:      .asciz "False"
        .globl explain_s_initial, explain_s_no_asm, explain_s_final, explain_s_folded
        .hidden explain_s_initial, explain_s_no_asm, explain_s_final, explain_s_folded
explain_s_initial:  .asciz "Initial decompiled trace"
explain_s_no_asm:   .asciz "Without assembly"
explain_s_final:    .asciz "final"
explain_s_folded:   .asciz "folded"
        .text

# explain(title, trace): python's explain(title, trace) - with "--explain"
# (and a builder to print into), "\n" + the title on green + "\n", then
# pprint_trace(trace): the lines of pprint_logic(make_ast(trace)) ("  stop"
# for none) and two empty lines; unless the trace is the one printed last.
# title: a C string. Returns nothing; everything else is kept.
FUNC explain
        test qword ptr [r15 + CTX_VERBOSE], VB_EXPLAIN
        jz 9f
        cmp qword ptr [r15 + CTX_EXPLAIN_SB], 0
        jne explain_print
9:      ret
ENDF explain

FUNC explain_print
        push rdi
        push rsi
        push rdx
        push rcx
        push r8
        push r9
        push rax
        ENTER
        sub rsp, 8
        mov rbx, rdi                    # title
        mov r12, rsi                    # trace
        mov rax, [r15 + CTX_EXPLAIN_PREV]
        test rax, rax
        jz 1f
        mov rdi, r12
        mov rsi, rax
        call values_equal               # python: trace == prev_trace
        test eax, eax
        jnz 9f
1:      mov r13, [r15 + CTX_EXPLAIN_SB]
        mov rdi, r13
        mov rsi, rbx
        lea rdx, [rip + C_GREEN_BACK]
        call explain_title
        # pprint_trace: make_ast (prettify's), pprint_ast
        mov rdi, r12
        call explain_make_ast
        mov rdi, rax
        mov esi, 2
        call pprint_logic
        mov r14, rax
        xor ebx, ebx
2:      cmp ebx, [r14 + N_AUX]
        jae 3f
        mov rdi, r13
        mov rsi, [r14 + N_DATA + rbx*8]
        call sb_append_str
        mov rdi, r13
        mov esi, 10
        call sb_append_char
        inc ebx
        jmp 2b
3:      test ebx, ebx
        jnz 4f
        mov rdi, r13
        lea rsi, [rip + .Ls_stop_line]
        call sb_append_c
4:      mov rdi, r13
        mov esi, 10
        call sb_append_char
        mov rdi, r13
        mov esi, 10
        call sb_append_char
        mov [r15 + CTX_EXPLAIN_PREV], r12
        cmp qword ptr [r15 + CTX_EXPLAIN_FIRST], 0
        jne 9f
        mov [r15 + CTX_EXPLAIN_FIRST], r12
        mov rax, [r13 + SB_LEN]
        mov [r15 + CTX_EXPLAIN_CUT], rax
9:      add rsp, 8
        LEAVE_NORET
        pop rax
        pop r9
        pop r8
        pop rcx
        pop rdx
        pop rsi
        pop rdi
        ret
ENDF explain_print

# explain_title(sb, title, back): python's print("\n" + back + f" {title}: "
# + C.end + "\n")
FUNC explain_title
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov esi, 10
        call sb_append_char
        mov rdi, rbx
        mov rsi, r13
        call sb_append_c
        mov rdi, rbx
        mov esi, ' '
        call sb_append_char
        mov rdi, rbx
        mov rsi, r12
        call sb_append_c
        mov rdi, rbx
        lea rsi, [rip + .Ls_title_sep]
        call sb_append_c
        mov rdi, rbx
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        mov rdi, rbx
        mov esi, 10
        call sb_append_char
        mov rdi, rbx
        mov esi, 10
        call sb_append_char
        LEAVE
ENDF explain_title

# explain_make_ast(trace) -> list: prettify.make_ast - the stores made sets
# (replace_lines), every ('stor', size, off, idx) masked:
# ('mask_shl', size, 0, 0, stor)
FUNC explain_make_ast
        ENTER
        call explain_replace_lines
        mov rdi, rax
        lea rsi, [rip + explain_mask_storage]
        xor edx, edx
        call replace_f
        LEAVE
ENDF explain_make_ast

# explain_replace_lines(trace) -> list: helpers.replace_lines(trace,
# store_to_set): store_to_set on every line, the whiles' conditions and
# setvars, the ifs' conditions; the branches and bodies recursed into
FUNC explain_replace_lines
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        call vec_new
        mov r12, rax
        xor r13d, r13d
.Lrl_next:
        cmp r13d, [rbx + N_AUX]
        jae .Lrl_done
        mov r14, [rbx + N_DATA + r13*8]
        inc r13d
        mov rdi, r14
        OPCODE_OF_RDI
        cmp eax, OP_WHILE
        je .Lrl_while
        cmp eax, OP_IF
        jne .Lrl_line
        cmp dword ptr [r14 + N_AUX], 4
        jne .Lrl_line
        # ('if', f(cond), branches)
        mov rdi, [r14 + N_DATA + 8]
        xor esi, esi
        call store_to_set
        mov [rsp], rax
        mov rdi, [r14 + N_DATA + 16]
        call explain_replace_lines
        mov [rsp + 8], rax
        mov rdi, [r14 + N_DATA + 24]
        call explain_replace_lines
        mov rcx, rax
        mov rdx, [rsp + 8]
        mov rsi, [rsp]
        mov rdi, [r14 + N_DATA]
        call mk4
        jmp .Lrl_push
.Lrl_while:
        # ('while', f(cond), path, jds, f(setvars)) - python unpacks five
        cmp dword ptr [r14 + N_AUX], 5
        jne .Lrl_unpack
        mov rdi, [r14 + N_DATA + 8]
        xor esi, esi
        call store_to_set
        mov [rsp], rax
        mov rdi, [r14 + N_DATA + 16]
        call explain_replace_lines
        mov [rsp + 8], rax
        mov rdi, [r14 + N_DATA + 32]
        xor esi, esi
        call store_to_set
        mov r8, rax
        mov rcx, [r14 + N_DATA + 24]
        mov rdx, [rsp + 8]
        mov rsi, [rsp]
        mov rdi, [r14 + N_DATA]
        call mk5
        jmp .Lrl_push
.Lrl_line:
        mov rdi, r14
        xor esi, esi
        call store_to_set
.Lrl_push:
        mov rdi, r12
        mov rsi, rax
        call vec_push
        jmp .Lrl_next
.Lrl_done:
        mov rdi, r12
        call vec_to_list
        add rsp, 16
        LEAVE
.Lrl_unpack:
        mov edi, E_VALUE
        lea rsi, [rip + .Ls_unpack]
        call err_throw
ENDF explain_replace_lines

        .section .rodata
.Ls_unpack:     .asciz "not enough values to unpack (a while of other than 5 elements)"
        .text

# explain_mask_storage(exp, arg): prettify.make_ast's mask_storage
FUNC explain_mask_storage
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        PAT rsi, "('stor', ':size', ':off', ':idx')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        mov r8, rbx
        mov ecx, 1                      # (0, tagged)
        mov edx, 1
        mov rsi, [rsp]                  # size
        LOADS rdi, MASK_SHL
        call mk5
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
1:      mov rax, rbx
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
ENDF explain_mask_storage

# explain_drop_asm(line, arg, out): the rewrite of "Without assembly" -
# the strings (the lines of assembly) dropped
FUNC explain_drop_asm
        test dil, 1
        jnz 1f
        test rdi, rdi
        jz 1f
        cmp dword ptr [rdi + N_KIND], K_STR
        jne 1f
        ret
1:      mov rsi, rdi
        mov rdi, rdx
        jmp vec_push
ENDF explain_drop_asm

# explain_traits(fn): python's explain_text("function traits", exp_text)
# at the end of Function.analyse - with "--explain" (and a builder):
# "\n" + the title on blue, then " name: value" for the possible return
# values, payable, read_only, the constant (when truthy) and what it's a
# getter for (when there's one), and an empty line
FUNC explain_traits
        test qword ptr [r15 + CTX_VERBOSE], VB_EXPLAIN
        jz 9f
        cmp qword ptr [r15 + CTX_EXPLAIN_SB], 0
        jne 1f
9:      ret
1:      ENTER
        mov rbx, rdi
        mov r12, [r15 + CTX_EXPLAIN_SB]
        mov rdi, r12
        lea rsi, [rip + .Ls_traits]
        lea rdx, [rip + C_BLUE_BACK]
        call explain_title
        lea rdi, [rip + .Ls_returns]
        call .Lxt_name
        mov rdi, [rbx + FN_RETURNS]     # prettify(self.returns)
        mov esi, PF_PARENS
        call prettify
        mov rdi, r12
        mov rsi, rax
        call sb_append_str
        call .Lxt_newline
        lea rdi, [rip + .Ls_payable]
        call .Lxt_name
        mov rdi, [rbx + FN_PAYABLE]
        call .Lxt_bool
        lea rdi, [rip + .Ls_read_only]
        call .Lxt_name
        mov rdi, [rbx + FN_READ_ONLY]
        call .Lxt_bool
        mov rdi, [rbx + FN_CONST]       # (0: None)
        test rdi, rdi
        jz 2f
        call py_truthy
        test eax, eax
        jz 2f
        lea rdi, [rip + .Ls_const]
        call .Lxt_name
        mov rdi, [rbx + FN_CONST]       # str(self.const)
        call value_str
        mov rdi, r12
        mov rsi, rax
        call sb_append_str
        call .Lxt_newline
2:      mov rdi, [rbx + FN_GETTER]
        test rdi, rdi
        jz 3f
        call py_truthy
        test eax, eax
        jz 3f
        lea rdi, [rip + .Ls_getter_for]
        call .Lxt_name
        mov rdi, [rbx + FN_GETTER]
        mov esi, PF_PARENS
        call prettify
        mov rdi, r12
        mov rsi, rax
        call sb_append_str
        call .Lxt_newline
3:      call .Lxt_newline
        LEAVE
# locals: f" {C.gray}{name}{C.end}: "
.Lxt_name:
        push rdi
        mov rdi, r12
        mov esi, ' '
        call sb_append_char
        mov rdi, r12
        lea rsi, [rip + C_GRAY]
        call sb_append_c
        mov rdi, r12
        mov rsi, [rsp]
        call sb_append_c
        mov rdi, r12
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        mov rdi, r12
        lea rsi, [rip + .Ls_title_sep]
        call sb_append_c
        pop rdi
        ret
# "True" / "False", and the end of the line
.Lxt_bool:
        sub rsp, 8
        lea rsi, [rip + .Ls_true]
        test rdi, rdi
        jnz 1f
        lea rsi, [rip + .Ls_false]
1:      mov rdi, r12
        call sb_append_c
        add rsp, 8
.Lxt_newline:
        sub rsp, 8
        mov rdi, r12
        mov esi, 10
        call sb_append_char
        add rsp, 8
        ret
ENDF explain_traits

# --- python's --repr and --returns (decompiler.py, from sys.argv) ---

# pprint_repr(sb, trace, indent): prettify.pprint_repr - a line a line of
# the trace, as python's print(indent * " ", text) writes it: the ifs
# and whiles opened and closed around their bodies, every other line
# format_exp'ed and followed by a gray ", "
FUNC pprint_repr
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov [rsp], rdx                  # indent
        xor r13d, r13d
.Lpr_next:
        cmp r13d, [r12 + N_AUX]
        jae .Lpr_done
        mov r14, [r12 + N_DATA + r13*8]
        inc r13d
        mov rdi, r14
        OPCODE_OF_RDI
        cmp eax, OP_IF
        je .Lpr_if
        cmp eax, OP_WHILE
        je .Lpr_while
        call .Lpr_indent
        mov rdi, rbx
        mov rsi, r14
        call format_exp
        mov rdi, rbx
        lea rsi, [rip + C_GRAY]
        call sb_append_c
        mov rdi, rbx
        lea rsi, [rip + .Ls_comma_sp]
        call sb_append_c
        mov rdi, rbx
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        call .Lpr_newline
        jmp .Lpr_next
.Lpr_if:
        # cond, if_true, if_false = line[1:]
        cmp dword ptr [r14 + N_AUX], 4
        jne .Lpr_unpack
        call .Lpr_indent
        mov rdi, rbx
        lea rsi, [rip + .Ls_repr_if]
        call sb_append_c
        mov rdi, rbx
        mov rsi, [r14 + N_DATA + 8]
        call format_exp
        mov rdi, rbx
        lea rsi, [rip + .Ls_repr_open]
        call sb_append_c
        call .Lpr_newline
        mov rdi, rbx
        mov rsi, [r14 + N_DATA + 16]
        mov rdx, [rsp]
        add rdx, 2
        call pprint_repr
        call .Lpr_indent
        mov rdi, rbx
        lea rsi, [rip + .Ls_repr_else]
        call sb_append_c
        call .Lpr_newline
        mov rdi, rbx
        mov rsi, [r14 + N_DATA + 24]
        mov rdx, [rsp]
        add rdx, 2
        call pprint_repr
        call .Lpr_indent
        mov rdi, rbx
        lea rsi, [rip + .Ls_repr_end_if]
        call sb_append_c
        call .Lpr_newline
        jmp .Lpr_next
.Lpr_while:
        # cond, tr = line[1], line[2]
        cmp dword ptr [r14 + N_AUX], 3
        jb .Lpr_index
        call .Lpr_indent
        mov rdi, rbx
        lea rsi, [rip + .Ls_repr_while]
        call sb_append_c
        mov rdi, rbx
        mov rsi, [r14 + N_DATA + 8]
        call format_exp
        mov rdi, rbx
        lea rsi, [rip + .Ls_repr_open]
        call sb_append_c
        call .Lpr_newline
        mov rdi, rbx
        mov rsi, [r14 + N_DATA + 16]
        mov rdx, [rsp]
        add rdx, 2
        call pprint_repr
        call .Lpr_indent
        mov rdi, rbx
        lea rsi, [rip + .Ls_repr_end_while]
        call sb_append_c
        call .Lpr_newline
        jmp .Lpr_next
.Lpr_done:
        add rsp, 16
        LEAVE
# locals: print's first argument (the indentation) and its separator
.Lpr_indent:
        sub rsp, 8
        mov rdi, rbx
        mov rsi, [rsp + 16]
        call sb_append_spaces
        mov rdi, rbx
        mov esi, ' '
        call sb_append_char
        add rsp, 8
        ret
.Lpr_newline:
        sub rsp, 8
        mov rdi, rbx
        mov esi, 10
        call sb_append_char
        add rsp, 8
        ret
.Lpr_unpack:
        mov edi, E_VALUE
        lea rsi, [rip + .Ls_repr_unpack]
        call err_throw
.Lpr_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_repr_index]
        call err_throw
ENDF pprint_repr

        .section .rodata
.Ls_comma_sp:       .asciz ", "
.Ls_repr_if:        .asciz "[if, "
.Ls_repr_while:     .asciz "[while, "
.Ls_repr_open:      .asciz ", ["
.Ls_repr_else:      .asciz "],["
.Ls_repr_end_if:    .asciz "] "
.Ls_repr_end_while: .asciz "], "
.Ls_repr_unpack:    .asciz "too many values to unpack (an if of other than 4 elements)"
.Ls_repr_index:     .asciz "tuple index out of range"
.Ls_repr_list:      .asciz "sequence item 0: expected str instance, NoneType found"
.Ls_empty_list:     .asciz "[]"
        .text

# format_exp(sb, exp): prettify.format_exp appended - a string quoted, an
# int in hex past 10**6 unless a multiple of 10**6, a list (only an empty
# one: python joins the None of opcode() for the others, a TypeError),
# anything else as python's str()
FUNC format_exp
        ENTER
        mov rbx, rdi
        mov r12, rsi
        test sil, 1
        jnz .Lfx_small
        test rsi, rsi
        jz .Lfx_str
        mov eax, [rsi + N_KIND]
        cmp eax, K_STR
        je .Lfx_string
        cmp eax, K_INT
        je .Lfx_big
        cmp eax, K_LIST
        jne .Lfx_str
        cmp dword ptr [rsi + N_AUX], 0
        jne .Lfx_list
        mov rdi, rbx
        lea rsi, [rip + C_GRAY]
        call sb_append_c
        mov rdi, rbx
        lea rsi, [rip + .Ls_empty_list]
        call sb_append_c
        mov rdi, rbx
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        LEAVE
.Lfx_string:
        mov rdi, rbx
        mov esi, '"'
        call sb_append_char
        mov rdi, rbx
        mov rsi, r12
        call sb_append_str
        mov rdi, rbx
        mov esi, '"'
        call sb_append_char
        LEAVE
.Lfx_small:
        mov rax, rsi
        sar rax, 1
        cmp rax, 1000000
        jle .Lfx_dec
        cqo
        mov ecx, 1000000
        idiv rcx
        test rdx, rdx
        jz .Lfx_dec
        jmp .Lfx_hex
.Lfx_big:
        cmp dword ptr [rsi + N_DATA + MPZ_SIZE], 0
        jle .Lfx_dec                    # (a negative one isn't past 10**6)
        lea rdi, [rsi + N_DATA]
        mov esi, 1000000
        call __gmpz_fdiv_ui@PLT
        test rax, rax
        jz .Lfx_dec
.Lfx_hex:
        mov rdi, rbx
        mov rsi, r12
        mov edx, 16
        call sb_append_int
        LEAVE
.Lfx_dec:
        mov rdi, rbx
        mov rsi, r12
        mov edx, 10
        call sb_append_int
        LEAVE
.Lfx_str:
        mov rdi, rbx                    # str(): the repr, but of a string
        mov rsi, r12
        call value_print
        LEAVE
.Lfx_list:
        mov edi, E_TYPE
        lea rsi, [rip + .Ls_repr_list]
        call err_throw
ENDF format_exp

        .section .note.GNU-stack,"",@progbits
