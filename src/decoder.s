# The decoder: a code's instructions, and the idioms among them, as the
# automaton of spec/evm_decoder.rl reads them - NaCl's validator's way:
# the instructions from their description (spec/evm.def), the automaton
# from ragel, its tables (src/evm_dfa.s) generated, and proven to decode
# what the description says (tools/verify_dfa.py). The automaton reads a
# byte at a time, and says what happens on it with its actions: an
# instruction starts (DA_INSN_START), ends (DA_INSN_END), an idiom ends
# with it (DA_STATIC_JUMP...).

.include "defs.inc"
.include "evm_ops.inc"
.include "evm_dfa.inc"

        .section .rodata
# the idioms' lengths, in instructions, by DA_* code
idiom_lengths:
        .byte 0, 0, 0
        .byte 2                         # DA_STATIC_JUMP: push, jump
        .byte 2                         # DA_STATIC_JUMPI: push, jumpi
        .byte 5                         # DA_SELECTOR: dup1, push4, eq, push, jumpi
        .byte 3                         # DA_FMP: push1, push1 0x40, mstore

        .text

# evm_decode(loader): python's load_binary on the code (LD_CODE,
# LD_CODELEN) - its instructions into LD_INSTRS (LD_NINSTR of them, each
# one's index at its place in LD_PC2IDX), the jumpdests into LD_JUMPDESTS
# (LD_NJUMPDESTS), the tables allocated and empty - and the idioms into
# LD_IDIOMS (LD_FMP set by solidity's free memory pointer, where the code
# begins). A push the end of the code cuts has zeroes for its missing
# bytes, as the EVM reads them. Its values are made on the current (r15)
# context.
FUNC evm_decode
        ENTER
        sub rsp, 48
        .set ED_STATE, 0                # the automaton's state
        .set ED_START, 8                # where the instruction open starts, -1: none
        .set ED_PROG, 16                # the action being run
        .set ED_INSN, 24                # the instruction open
        mov rbx, rdi
        mov r12, [rbx + LD_CODE]
        mov r13, [rbx + LD_CODELEN]
        xor r14d, r14d                  # the place in the code
        mov qword ptr [rsp + ED_STATE], DFA_START
        mov qword ptr [rsp + ED_START], -1
        mov qword ptr [rbx + LD_NIDIOMS], 0
        mov byte ptr [rbx + LD_FMP], 0
.Led_byte:
        cmp r14, r13
        jae .Led_eof
        movzx eax, byte ptr [r12 + r14]
        mov ecx, [rsp + ED_STATE]
        lea rdx, [rip + dfa_states]
        mov rdx, [rdx + rcx*8]          # its first transition | the mask << 32
        mov rcx, rdx
        shr rcx, 32
        and eax, ecx
        add eax, edx
        lea rdx, [rip + dfa_trans]
        mov eax, [rdx + rax*4]          # the next state | its actions << 16
        movzx ecx, ax
        mov [rsp + ED_STATE], rcx
        shr eax, 16
        jnz .Led_actions
.Led_next:
        inc r14
        jmp .Led_byte
.Led_actions:
        lea rdx, [rip + dfa_programs]
        add rax, rdx
        mov [rsp + ED_PROG], rax
.Led_action:
        mov rax, [rsp + ED_PROG]
        movzx ecx, byte ptr [rax]
        inc rax
        mov [rsp + ED_PROG], rax
        test ecx, ecx
        jz .Led_next
        cmp ecx, DA_INSN_START
        je .Led_start
        cmp ecx, DA_INSN_END
        je .Led_end
        # an idiom, ending with the instruction that just ended
        mov rdi, rbx
        mov esi, ecx
        call decoder_add_idiom
        jmp .Led_action

.Led_start:
        # an instruction starts here: its entry, its index at its place
        mov rax, [rbx + LD_NINSTR]
        mov rcx, [rbx + LD_PC2IDX]
        mov [rcx + r14*4], eax
        shl rax, 4
        add rax, [rbx + LD_INSTRS]
        mov [rsp + ED_INSN], rax
        mov [rax + IN_PC], r14d
        movzx ecx, byte ptr [r12 + r14]
        mov [rax + IN_OP], cl
        inc qword ptr [rbx + LD_NINSTR]
        mov [rsp + ED_START], r14
        jmp .Led_action

.Led_end:
        # it ends here, its immediate whole
        mov rdi, rbx
        mov rsi, [rsp + ED_INSN]
        mov rdx, [rsp + ED_START]
        mov rcx, r13
        call decoder_end_insn
        mov qword ptr [rsp + ED_START], -1
        jmp .Led_action

.Led_eof:
        # a push the end of the code cuts (the only instruction an automaton
        # can be in the middle of at the end, tools/verify_dfa.py)
        mov rdx, [rsp + ED_START]
        test rdx, rdx
        js 9f
        mov rdi, rbx
        mov rsi, [rsp + ED_INSN]
        mov rcx, r13
        call decoder_end_insn
9:      add rsp, 48
        LEAVE
ENDF evm_decode

# decoder_end_insn(loader, insn, start, end): the instruction starting at
# `start` ends - its parameter and its jumpdest, by its opcode's kind; a
# push's immediate is the bytes between start + 1 and end at most, the
# missing ones zeroes
FUNC decoder_end_insn
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov r14, rcx
        movzx eax, byte ptr [r12 + IN_OP]
        lea rcx, [rip + evm_opinfo]
        mov eax, [rcx + rax*4]
        movzx ecx, al                   # the kind
        cmp ecx, EK_PLAIN
        je 9f
        cmp ecx, EK_JUMPDEST
        je 4f
        cmp ecx, EK_UNKNOWN
        je 5f
        cmp ecx, EK_DUPSWAP
        je 6f
        # a push: its immediate (the bytes the code has of it), shifted by
        # the missing ones
        movzx ecx, ah                   # its size
        mov rdi, [rbx + LD_CODE]
        lea rdi, [rdi + r13 + 1]
        mov rsi, r14
        sub rsi, r13
        dec rsi                         # the bytes after the opcode
        cmp rsi, rcx
        cmova rsi, rcx
        sub rcx, rsi
        shl rcx, 3
        mov [rsp], rcx                  # (the bits of the missing ones)
        call mk_int_bytes_be
        mov rsi, [rsp]
        test rsi, rsi
        jz 1f
        mov rdi, rax
        call int_shl_bits
1:      mov [r12 + IN_PARAM], rax
        mov byte ptr [r12 + IN_FLAGS], IF_PARAM
        jmp 9f
4:      mov rax, [rbx + LD_JUMPDESTS]
        mov byte ptr [rax + r13], 1
        inc qword ptr [rbx + LD_NJUMPDESTS]
        jmp 9f
5:      movzx eax, byte ptr [r12 + IN_OP]       # python's UNKNOWN: the byte
        lea rax, [rax + rax + 1]
        mov [r12 + IN_PARAM], rax
        mov byte ptr [r12 + IN_FLAGS], IF_PARAM
        jmp 9f
6:      shr eax, 16                     # dup n, swap n: n
        lea rax, [rax + rax + 1]
        mov [r12 + IN_PARAM], rax
        mov byte ptr [r12 + IN_FLAGS], IF_PARAM
9:      add rsp, 16
        LEAVE
ENDF decoder_end_insn

# decoder_add_idiom(loader, code): the idiom of the DA_* code ends with the
# instruction that just ended: its code | that instruction's index << 8
# into LD_IDIOMS; LD_FMP for solidity's free memory pointer
FUNC decoder_add_idiom
        ENTER
        mov rbx, rdi
        mov r12d, esi
        cmp r12d, DA_FMP
        jne 1f
        mov byte ptr [rbx + LD_FMP], 1
1:      mov rax, [rbx + LD_NIDIOMS]
        cmp rax, [rbx + LD_CAPIDIOMS]
        jb 2f
        lea rsi, [rax + rax + 16]       # (twice as many)
        push rsi
        push rsi
        shl rsi, 3
        mov rdi, [rbx + LD_IDIOMS]
        call xrealloc
        mov [rbx + LD_IDIOMS], rax
        pop rsi
        pop rsi
        mov [rbx + LD_CAPIDIOMS], rsi
2:      mov rax, [rbx + LD_NINSTR]
        dec rax
        shl rax, 8
        or rax, r12
        mov rcx, [rbx + LD_NIDIOMS]
        mov rdx, [rbx + LD_IDIOMS]
        mov [rdx + rcx*8], rax
        inc qword ptr [rbx + LD_NIDIOMS]
        LEAVE
ENDF decoder_add_idiom

# decoder_idiom(loader, i) -> rax: the DA_* code of the i-th idiom, rdx: the
# index of its first instruction, rcx: of its last
FUNC decoder_idiom
        mov rax, [rdi + LD_IDIOMS]
        mov rax, [rax + rsi*8]
        mov rcx, rax
        shr rcx, 8
        movzx eax, al
        lea rdx, [rip + idiom_lengths]
        movzx edx, byte ptr [rdx + rax]
        neg rdx
        lea rdx, [rcx + rdx + 1]
        ret
ENDF decoder_idiom

        .section .note.GNU-stack,"",@progbits
