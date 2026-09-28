# A parser for the python-literal subset used in the tests: tuples, lists,
# ints (decimal, 0x hex, negative), 'strings' / "strings", True, False, None.
#
#   parse_literal(text, len) -> rax: the value, or NIL on a syntax error
#   (parse_error_pos then holds the offset of the error)

.include "defs.inc"

.set PS_TEXT, 0
.set PS_LEN, 8
.set PS_POS, 16
.set PS_SIZEOF, 24

        .section .bss
        .align 8
        .globl parse_error_pos
        .hidden parse_error_pos
parse_error_pos: .quad 0

        .section .rodata
.Ls_True:  .asciz "True"
.Ls_False: .asciz "False"
.Ls_None:  .asciz "None"
.Ls_Node:  .asciz "Node("

        .text

FUNC parse_literal
        ENTER
        sub rsp, 32
        mov [rsp + PS_TEXT], rdi
        mov [rsp + PS_LEN], rsi
        mov qword ptr [rsp + PS_POS], 0
        mov rdi, rsp
        call pv_value
        test rax, rax
        jz 1f
        mov rbx, rax
        mov rdi, rsp
        call pv_skip_ws
        mov rax, [rsp + PS_POS]
        cmp rax, [rsp + PS_LEN]
        jne 2f
        mov rax, rbx
        add rsp, 32
        LEAVE
2:      mov rax, [rsp + PS_POS]
        mov [rip + parse_error_pos], rax
1:      xor eax, eax
        add rsp, 32
        LEAVE
ENDF parse_literal

# pv_peek(ps) -> eax: the current char, or -1 at the end
FUNC pv_peek
        mov rax, [rdi + PS_POS]
        cmp rax, [rdi + PS_LEN]
        jae 1f
        mov rcx, [rdi + PS_TEXT]
        movzx eax, byte ptr [rcx + rax]
        ret
1:      mov eax, -1
        ret
ENDF pv_peek

FUNC pv_skip_ws
1:      mov rax, [rdi + PS_POS]
        cmp rax, [rdi + PS_LEN]
        jae 2f
        mov rcx, [rdi + PS_TEXT]
        movzx eax, byte ptr [rcx + rax]
        cmp al, ' '
        je 3f
        cmp al, '\n'
        je 3f
        cmp al, '\t'
        je 3f
        cmp al, '\r'
        jne 2f
3:      inc qword ptr [rdi + PS_POS]
        jmp 1b
2:      ret
ENDF pv_skip_ws

# pv_fail(ps): record the position, return NIL
FUNC pv_fail
        mov rax, [rdi + PS_POS]
        mov [rip + parse_error_pos], rax
        xor eax, eax
        ret
ENDF pv_fail

# pv_value(ps) -> rax
FUNC pv_value
        STACK_CHECK
        ENTER
        mov rbx, rdi
        call pv_skip_ws
        mov rdi, rbx
        call pv_peek
        cmp eax, '('
        je .Lpv_tuple
        cmp eax, '['
        je .Lpv_list
        cmp eax, '\''
        je .Lpv_str
        cmp eax, '"'
        je .Lpv_str
        cmp eax, '-'
        je .Lpv_num
        cmp eax, '0'
        jb .Lpv_word
        cmp eax, '9'
        jbe .Lpv_num
.Lpv_word:
        mov rdi, rbx
        call pv_word
        LEAVE
.Lpv_num:
        mov rdi, rbx
        call pv_number
        LEAVE
.Lpv_str:
        mov rdi, rbx
        call pv_string
        LEAVE
.Lpv_tuple:
        inc qword ptr [rbx + PS_POS]
        mov rdi, rbx
        mov esi, ')'
        mov edx, K_TUPLE
        call pv_seq
        LEAVE
.Lpv_list:
        inc qword ptr [rbx + PS_POS]
        mov rdi, rbx
        mov esi, ']'
        mov edx, K_LIST
        call pv_seq
        LEAVE
ENDF pv_value

# pv_seq(ps, closer, kind) -> rax: elements up to the closer
FUNC pv_seq
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12d, esi
        mov r13d, edx
        call vec_new
        mov r14, rax
1:      mov rdi, rbx
        call pv_skip_ws
        mov rdi, rbx
        call pv_peek
        cmp eax, r12d
        je .Lseq_close
        cmp eax, -1
        je .Lseq_fail
        mov rdi, rbx
        call pv_value
        test rax, rax
        jz .Lseq_nil
        mov rdi, r14
        mov rsi, rax
        call vec_push
        mov rdi, rbx
        call pv_skip_ws
        mov rdi, rbx
        call pv_peek
        cmp eax, ','
        jne 2f
        inc qword ptr [rbx + PS_POS]
        jmp 1b
2:      cmp eax, r12d
        jne .Lseq_fail
.Lseq_close:
        inc qword ptr [rbx + PS_POS]
        mov edi, r13d
        mov rsi, [r14 + VEC_LEN]
        mov rdx, [r14 + VEC_DATA]
        call mk_seq
        LEAVE
.Lseq_fail:
        mov rdi, rbx
        call pv_fail
.Lseq_nil:
        xor eax, eax
        LEAVE
ENDF pv_seq

# pv_number(ps) -> rax
FUNC pv_number
        ENTER
        sub rsp, 16
        mov rbx, rdi
        xor r14d, r14d                  # 1 if negative
        mov rdi, rbx
        call pv_peek
        cmp eax, '-'
        jne 1f
        inc qword ptr [rbx + PS_POS]
        mov r14d, 1
1:      mov r13d, 10                    # base
        mov rdi, rbx
        call pv_peek
        cmp eax, '0'
        jne 2f
        mov rax, [rbx + PS_POS]
        inc rax
        cmp rax, [rbx + PS_LEN]
        jae 2f
        mov rcx, [rbx + PS_TEXT]
        mov al, [rcx + rax]
        or al, 0x20
        cmp al, 'x'
        jne 2f
        mov r13d, 16
        add qword ptr [rbx + PS_POS], 2
2:      mov r12, [rbx + PS_POS]         # digits start
3:      mov rdi, rbx
        call pv_peek
        cmp eax, '0'
        jb 4f
        cmp eax, '9'
        jbe 5f
        cmp r13d, 16
        jne 4f
        or al, 0x20
        cmp al, 'a'
        jb 4f
        cmp al, 'f'
        ja 4f
5:      inc qword ptr [rbx + PS_POS]
        jmp 3b
4:      mov rax, [rbx + PS_POS]
        sub rax, r12                    # number of digits
        jz .Lnum_fail
        # a float (digits.digits): kept as its text, flagged (see float_str)
        mov rdi, rbx
        call pv_peek
        cmp eax, '.'
        je .Lnum_float
        mov rax, [rbx + PS_POS]
        sub rax, r12
        lea rdi, [rax + 2]
        call xmalloc
        mov [rsp], rax
        mov rdi, rax
        test r14d, r14d
        jz 6f
        mov byte ptr [rdi], '-'
        inc rdi
6:      mov [rsp + 8], rdi
        mov rsi, [rbx + PS_TEXT]
        add rsi, r12
        mov rdx, [rbx + PS_POS]
        sub rdx, r12
        mov r12, rdx
        call memcpy@PLT
        mov rdi, [rsp + 8]
        mov byte ptr [rdi + r12], 0
        lea rdi, [r15 + CTX_TMPZ]
        mov rsi, [rsp]
        mov edx, r13d
        call __gmpz_set_str@PLT
        mov r12d, eax
        mov rdi, [rsp]
        call free@PLT
        test r12d, r12d
        jnz .Lnum_fail
        lea rdi, [r15 + CTX_TMPZ]
        call mk_int_mpz
        add rsp, 16
        LEAVE
.Lnum_float:
        inc qword ptr [rbx + PS_POS]
7:      mov rdi, rbx
        call pv_peek
        cmp eax, '0'
        jb 8f
        cmp eax, '9'
        ja 8f
        inc qword ptr [rbx + PS_POS]
        jmp 7b
8:      test r14d, r14d
        jz 9f
        dec r12                         # the '-' is part of the text
9:      mov rdi, [rbx + PS_TEXT]
        add rdi, r12
        mov rsi, [rbx + PS_POS]
        sub rsi, r12
        call str_intern
        or dword ptr [rax + N_AUX], STR_FLOAT
        add rsp, 16
        LEAVE
.Lnum_fail:
        mov rdi, rbx
        call pv_fail
        add rsp, 16
        LEAVE
ENDF pv_number

# pv_string(ps) -> rax: an interned string (python's escapes: \n \r \t
# \\ \' \" \xHH \uHHHH \UHHHHHHHH, the code points as UTF-8)
FUNC pv_string
        ENTER
        mov rbx, rdi
        call pv_peek
        mov r12d, eax                   # the quote
        inc qword ptr [rbx + PS_POS]
        call sb_new
        mov r13, rax
1:      mov rdi, rbx
        call pv_peek
        cmp eax, -1
        je .Lstr_fail
        cmp eax, r12d
        je .Lstr_end
        inc qword ptr [rbx + PS_POS]
        cmp eax, '\\'
        jne 2f
        mov rdi, rbx
        call pv_peek
        cmp eax, -1
        je .Lstr_fail
        inc qword ptr [rbx + PS_POS]
        mov ecx, '\n'
        cmp eax, 'n'
        je 5f
        mov ecx, '\t'
        cmp eax, 't'
        je 5f
        mov ecx, '\r'
        cmp eax, 'r'
        je 5f
        mov ecx, 0
        cmp eax, '0'
        je 5f
        mov r14d, 2
        cmp eax, 'x'
        je 6f
        mov r14d, 4
        cmp eax, 'u'
        je 6f
        mov r14d, 8
        cmp eax, 'U'
        je 6f
        jmp 2f                          # (\\ \' \": the character)
5:      mov eax, ecx
        jmp 2f
6:      # a code point of r14 hex digits, as UTF-8
        mov rdi, rbx
        mov esi, r14d
        call pv_hexn
        cmp eax, -1
        je .Lstr_fail
        mov rdi, r13
        mov esi, eax
        call sb_append_utf8
        jmp 1b
2:      mov rdi, r13
        mov esi, eax
        call sb_append_char
        jmp 1b
.Lstr_end:
        inc qword ptr [rbx + PS_POS]
        mov rdi, [r13 + SB_BUF]
        mov rsi, [r13 + SB_LEN]
        call str_intern
        mov r14, rax
        mov rdi, r13
        call sb_free
        mov rax, r14
        LEAVE
.Lstr_fail:
        mov rdi, r13
        call sb_free
        mov rdi, rbx
        call pv_fail
        LEAVE
ENDF pv_string

# pv_hexn(ps, n) -> eax: n hex digits, or -1
FUNC pv_hexn
        ENTER
        mov rbx, rdi
        xor r12d, r12d
        mov r13d, esi
1:      mov rdi, rbx
        call pv_peek
        cmp eax, -1
        je 9f
        inc qword ptr [rbx + PS_POS]
        sub eax, '0'
        cmp eax, 9
        jbe 2f
        or al, 0x20
        sub eax, 'a' - '0'
        cmp eax, 5
        ja 9f
        add eax, 10
2:      shl r12d, 4
        or r12d, eax
        dec r13d
        jnz 1b
        mov eax, r12d
        LEAVE
9:      mov eax, -1
        LEAVE
ENDF pv_hexn

# pv_word(ps) -> rax: True / False / None
FUNC pv_word
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov rdi, [rbx + PS_TEXT]
        add rdi, [rbx + PS_POS]
        lea rsi, [rip + .Ls_True]
        mov edx, 4
        call strncmp@PLT
        test eax, eax
        jnz 1f
        add qword ptr [rbx + PS_POS], 4
        lea rax, [rip + sp_true]
        LEAVE
1:      mov rdi, [rbx + PS_TEXT]
        add rdi, [rbx + PS_POS]
        lea rsi, [rip + .Ls_False]
        mov edx, 5
        call strncmp@PLT
        test eax, eax
        jnz 2f
        add qword ptr [rbx + PS_POS], 5
        lea rax, [rip + sp_false]
        LEAVE
2:      mov rdi, [rbx + PS_TEXT]
        add rdi, [rbx + PS_POS]
        lea rsi, [rip + .Ls_None]
        mov edx, 4
        call strncmp@PLT
        test eax, eax
        jnz 3f
        add qword ptr [rbx + PS_POS], 4
        lea rax, [rip + sp_none]
        LEAVE
3:      mov rdi, [rbx + PS_TEXT]
        add rdi, [rbx + PS_POS]
        lea rsi, [rip + .Ls_Node]
        mov edx, 5
        call strncmp@PLT
        test eax, eax
        jnz 4f
        # Node(jd): a stand-in for a VM node in the tests, printed the
        # same way. Made once per jd.
        add qword ptr [rbx + PS_POS], 5
        mov rdi, rbx
        call pv_value
        test rax, rax
        jz 5f
        mov r12, rax
        mov rdi, rbx
        call pv_skip_ws
        mov rdi, rbx
        call pv_peek
        cmp eax, ')'
        jne 4f
        inc qword ptr [rbx + PS_POS]
        mov rdi, r12
        call test_node_for_jd
        LEAVE
4:      mov rdi, rbx
        call pv_fail
5:      LEAVE
ENDF pv_word

# test_node_for_jd(jd) -> rax: the K_VMNODE with this jd (memoized)
FUNC test_node_for_jd
        ENTER
        mov rbx, rdi
        mov edi, MEMO_TEST_NODES
        mov rsi, rbx
        call memo_get
        test rax, rax
        jnz 1f
        mov edi, ND_SIZEOF
        call arena_alloc
        mov r12, rax
        mov dword ptr [r12 + N_KIND], K_VMNODE
        mov rdi, r12
        call hash_mix
        mov [r12 + N_HASH], rax
        mov [r12 + ND_JD], rbx
        mov edi, MEMO_TEST_NODES
        mov rsi, rbx
        mov rdx, r12
        call memo_put
        mov rax, r12
1:      LEAVE
ENDF test_node_for_jd

        .section .note.GNU-stack,"",@progbits
