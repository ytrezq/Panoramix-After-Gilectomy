# panasm decode: what the decoder (decoder.s) finds in a code, NaCl's ncval
# for the EVM - the code's size, its instructions and jumpdests; solidity's
# free memory pointer set first; a push the end of the code cuts; the bytes
# that aren't opcodes; the jumps to a number (the static_jump and
# static_jumpi idioms), the ones of them to no jumpdest - the jump of the
# EVM fails there -, the jumps to a computed place; the functions solc's
# dispatcher compares the selector with (the selector idiom).

.include "defs.inc"
.include "evm_ops.inc"
.include "evm_dfa.inc"

        .section .rodata
.Lf_code:       .asciz "%u bytes of code, %u instructions, %u jumpdests\n"
.Lf_fmp:        .asciz "the free memory pointer is set first: mem[0x40] = "
.Lf_cut:        .asciz "the code ends in a %s at %x: %u of its %u bytes\n"
.Lf_unknown:    .asciz "%u bytes that aren't opcodes:\n"
.Lf_unknown1:   .asciz "  %x: %x\n"
.Lf_static:     .asciz "%u jumps to a number, %u of them to no jumpdest\n"
.Lf_bad_jump:   .asciz "  %x: %s to "
.Lf_dynamic:    .asciz "%u jumps to a computed place\n"
.Lf_selectors:  .asciz "%u functions solc's dispatcher compares the selector with:\n"
.Ls_indent:     .asciz "  "
.Ls_arrow:      .asciz " -> "

        .text

# decoder_report(loader, sb): the report of panasm decode on the loader's
# code into sb
FUNC decoder_report
        ENTER
        sub rsp, 64
        .set DR_ARGS, 0                 # sb_format's arguments (4)
        .set DR_STATIC, 32              # the jumps to a number
        .set DR_BAD, 40                 # those to no jumpdest
        .set DR_JUMPS, 48               # all the jumps
        mov rbx, rdi
        mov r12, rsi
        mov rax, [rbx + LD_CODELEN]
        mov [rsp], rax
        mov rax, [rbx + LD_NINSTR]
        mov [rsp + 8], rax
        mov rax, [rbx + LD_NJUMPDESTS]
        mov [rsp + 16], rax
        mov rdi, r12
        lea rsi, [rip + .Lf_code]
        mov rdx, rsp
        call sb_format
        # solidity's free memory pointer
        cmp byte ptr [rbx + LD_FMP], 0
        je 1f
        mov rdi, r12
        lea rsi, [rip + .Lf_fmp]
        call sb_append_c
        mov rax, [rbx + LD_INSTRS]
        mov rsi, [rax + IN_PARAM]       # (the first push1's)
        mov rdi, r12
        mov edx, 16
        call sb_append_int
        mov rdi, r12
        mov esi, '\n'
        call sb_append_char
1:      # a push the end of the code cuts: the last instruction's
        mov rax, [rbx + LD_NINSTR]
        test rax, rax
        jz 2f
        dec rax
        shl rax, 4
        add rax, [rbx + LD_INSTRS]
        movzx ecx, byte ptr [rax + IN_OP]
        lea rdx, [rip + evm_opinfo]
        mov edx, [rdx + rcx*4]
        cmp dl, EK_PUSH
        jne 2f
        movzx edx, dh                   # its immediate's size
        mov esi, [rax + IN_PC]
        mov rdi, [rbx + LD_CODELEN]
        sub rdi, rsi
        dec rdi                         # the bytes of it the code has
        cmp rdi, rdx
        jae 2f
        mov [rsp + 16], rdi
        mov [rsp + 24], rdx
        mov [rsp + 8], rsi
        mov edi, ecx
        call evm_opname
        mov [rsp], rax
        mov rdi, r12
        lea rsi, [rip + .Lf_cut]
        mov rdx, rsp
        call sb_format
2:      # the bytes that aren't opcodes
        xor r13d, r13d                  # how many
        xor r14d, r14d
3:      cmp r14, [rbx + LD_NINSTR]
        jae 4f
        mov rax, r14
        shl rax, 4
        add rax, [rbx + LD_INSTRS]
        inc r14
        movzx ecx, byte ptr [rax + IN_OP]
        lea rdx, [rip + evm_opinfo]
        cmp byte ptr [rdx + rcx*4], EK_UNKNOWN
        jne 3b
        inc r13
        jmp 3b
4:      test r13, r13
        jz 6f
        mov [rsp], r13
        mov rdi, r12
        lea rsi, [rip + .Lf_unknown]
        mov rdx, rsp
        call sb_format
        xor r14d, r14d
5:      cmp r14, [rbx + LD_NINSTR]
        jae 6f
        mov rax, r14
        shl rax, 4
        add rax, [rbx + LD_INSTRS]
        inc r14
        movzx ecx, byte ptr [rax + IN_OP]
        lea rdx, [rip + evm_opinfo]
        cmp byte ptr [rdx + rcx*4], EK_UNKNOWN
        jne 5b
        mov edx, [rax + IN_PC]
        mov [rsp], rdx
        mov [rsp + 8], rcx
        mov rdi, r12
        lea rsi, [rip + .Lf_unknown1]
        mov rdx, rsp
        call sb_format
        jmp 5b
6:      # the jumps: all of them, those to a number (and to no jumpdest)
        xor eax, eax
        mov [rsp + DR_STATIC], rax
        mov [rsp + DR_BAD], rax
        mov [rsp + DR_JUMPS], rax
        xor r14d, r14d
7:      cmp r14, [rbx + LD_NINSTR]
        jae 8f
        mov rax, r14
        shl rax, 4
        add rax, [rbx + LD_INSTRS]
        inc r14
        movzx ecx, byte ptr [rax + IN_OP]
        sub ecx, 0x56                   # jump, jumpi
        cmp ecx, 1
        ja 7b
        inc qword ptr [rsp + DR_JUMPS]
        jmp 7b
8:      xor r14d, r14d
9:      cmp r14, [rbx + LD_NIDIOMS]
        jae 11f
        mov rdi, rbx
        mov rsi, r14
        call decoder_idiom
        inc r14
        cmp eax, DA_STATIC_JUMP
        je 10f
        cmp eax, DA_STATIC_JUMPI
        jne 9b
10:     inc qword ptr [rsp + DR_STATIC]
        mov rdi, rbx
        mov rsi, rdx                    # (the push)
        call decoder_jump_ok
        test eax, eax
        jnz 9b
        inc qword ptr [rsp + DR_BAD]
        jmp 9b
11:     mov rax, [rsp + DR_STATIC]
        mov [rsp], rax
        mov rax, [rsp + DR_BAD]
        mov [rsp + 8], rax
        mov rdi, r12
        lea rsi, [rip + .Lf_static]
        mov rdx, rsp
        call sb_format
        # those to no jumpdest
        xor r14d, r14d
12:     cmp r14, [rbx + LD_NIDIOMS]
        jae 14f
        mov rdi, rbx
        mov rsi, r14
        call decoder_idiom
        inc r14
        cmp eax, DA_STATIC_JUMP
        je 13f
        cmp eax, DA_STATIC_JUMPI
        jne 12b
13:     mov rdi, rbx
        mov rsi, rdx
        mov r13, rdx                    # the push
        call decoder_jump_ok
        test eax, eax
        jnz 12b
        mov rax, r13
        inc rax
        shl rax, 4
        add rax, [rbx + LD_INSTRS]      # the jump
        mov ecx, [rax + IN_PC]
        mov [rsp], rcx
        movzx edi, byte ptr [rax + IN_OP]
        call evm_opname
        mov [rsp + 8], rax
        mov rdi, r12
        lea rsi, [rip + .Lf_bad_jump]
        mov rdx, rsp
        call sb_format
        mov rax, r13
        shl rax, 4
        add rax, [rbx + LD_INSTRS]
        mov rsi, [rax + IN_PARAM]
        mov rdi, r12
        mov edx, 16
        call sb_append_int
        mov rdi, r12
        mov esi, '\n'
        call sb_append_char
        jmp 12b
14:     mov rax, [rsp + DR_JUMPS]
        sub rax, [rsp + DR_STATIC]
        mov [rsp], rax
        mov rdi, r12
        lea rsi, [rip + .Lf_dynamic]
        mov rdx, rsp
        call sb_format
        # the functions of solc's dispatcher
        xor r13d, r13d
        xor r14d, r14d
15:     cmp r14, [rbx + LD_NIDIOMS]
        jae 16f
        mov rdi, rbx
        mov rsi, r14
        call decoder_idiom
        inc r14
        cmp eax, DA_SELECTOR
        jne 15b
        inc r13
        jmp 15b
16:     test r13, r13
        jz 19f
        mov [rsp], r13
        mov rdi, r12
        lea rsi, [rip + .Lf_selectors]
        mov rdx, rsp
        call sb_format
        xor r14d, r14d
17:     cmp r14, [rbx + LD_NIDIOMS]
        jae 19f
        mov rdi, rbx
        mov rsi, r14
        call decoder_idiom
        inc r14
        cmp eax, DA_SELECTOR
        jne 17b
        mov r13, rdx                    # dup1, push4 selector, eq, push dest, jumpi
        mov rdi, r12
        lea rsi, [rip + .Ls_indent]
        call sb_append_c
        lea rax, [r13 + 1]
        shl rax, 4
        add rax, [rbx + LD_INSTRS]
        mov rdi, [rax + IN_PARAM]
        call padded_hex8
        mov rdi, r12
        mov rsi, rax
        call sb_append_str
        mov rdi, r12
        lea rsi, [rip + .Ls_arrow]
        call sb_append_c
        lea rax, [r13 + 3]
        shl rax, 4
        add rax, [rbx + LD_INSTRS]
        mov rsi, [rax + IN_PARAM]
        mov rdi, r12
        mov edx, 16
        call sb_append_int
        mov rdi, r12
        mov esi, '\n'
        call sb_append_char
        jmp 17b
19:     add rsp, 64
        LEAVE
ENDF decoder_report

# decoder_jump_ok(loader, push) -> eax: 1 if the number the instruction
# `push` pushes (a static jump's) is a jumpdest of the code
FUNC decoder_jump_ok
        shl rsi, 4
        add rsi, [rdi + LD_INSTRS]
        mov rax, [rsi + IN_PARAM]
        test al, 1
        jz 9f                           # (past 2^62: past the code)
        sar rax, 1
        js 9f
        cmp rax, [rdi + LD_CODELEN]
        jae 9f
        mov rcx, [rdi + LD_JUMPDESTS]
        movzx eax, byte ptr [rcx + rax]
        ret
9:      xor eax, eax
        ret
ENDF decoder_jump_ok

        .section .note.GNU-stack,"",@progbits
