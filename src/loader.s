# Loader: bytecode -> instructions, jumpdests (the decoder, decoder.s: the
# automaton of spec/evm_decoder.rl). The function discovery (running the
# dispatcher symbolically) is in the VM.

.include "defs.inc"

        .section .rodata
.Ls_unknown: .asciz "UNKNOWN"
.Ls_comma_sp: .asciz ", "

        .text

# evm_opname(op) -> rax: C string, "UNKNOWN" for undefined opcodes (the
# names of spec/evm.def: evm_opnames, src/evm_ops.s)
FUNC evm_opname
        movzx edi, dil
        lea rax, [rip + evm_opnames]
        mov rax, [rax + rdi*8]
        test rax, rax
        jnz 1f
        lea rax, [rip + .Ls_unknown]
1:      ret
ENDF evm_opname

# hex_decode(src, len, out) -> rax: number of bytes, or -1 on a bad
# character. Skips a 0x prefix and whitespace.
FUNC hex_decode
        ENTER
        mov r12, rdi                    # src
        mov r13, rsi                    # len
        mov r14, rdx                    # out
        xor ebx, ebx                    # out count
        xor r8d, r8d                    # position
        mov r9d, -1                     # pending high nibble (-1 = none)
        # 0x prefix
        cmp r13, 2
        jb 1f
        cmp byte ptr [r12], '0'
        jne 1f
        mov al, [r12 + 1]
        or al, 0x20
        cmp al, 'x'
        jne 1f
        mov r8d, 2
1:      cmp r8, r13
        jae .Lhex_end
        movzx eax, byte ptr [r12 + r8]
        inc r8
        cmp al, ' '
        je 1b
        cmp al, '\n'
        je 1b
        cmp al, '\r'
        je 1b
        cmp al, '\t'
        je 1b
        # nibble value
        sub al, '0'
        cmp al, 9
        jbe 2f
        or al, 0x20
        sub al, 'a' - '0'
        cmp al, 5
        ja .Lhex_bad
        add al, 10
2:      test r9d, r9d
        js 3f
        shl r9d, 4
        or r9d, eax
        mov [r14 + rbx], r9b
        inc rbx
        mov r9d, -1
        jmp 1b
3:      mov r9d, eax
        jmp 1b
.Lhex_end:
        test r9d, r9d
        jns .Lhex_bad                   # odd number of digits
        mov rax, rbx
        LEAVE
.Lhex_bad:
        mov rax, -1
        LEAVE
ENDF hex_decode

# loader_new() -> rax: an empty loader (malloc'ed, shared by the threads)
FUNC loader_new
        ENTER
        mov edi, 1
        mov esi, LD_SIZEOF
        call xcalloc
        LEAVE
ENDF loader_new

# loader_load(loader, bytes, len): disassemble. Push values become integer
# values allocated on the current (r15) context.
FUNC loader_load
        ENTER
        sub rsp, 32
        mov rbx, rdi                    # loader
        mov r12, rsi                    # bytes
        mov r13, rdx                    # len
        # copy the code
        lea rdi, [r13 + 1]
        call xmalloc
        mov [rbx + LD_CODE], rax
        mov rdi, rax
        mov rsi, r12
        mov rdx, r13
        call memcpy@PLT
        mov r12, [rbx + LD_CODE]
        mov [rbx + LD_CODELEN], r13
        mov [rbx + LD_LASTLINE], r13
        # instruction table: at most len entries
        lea rdi, [r13 + 1]
        mov esi, IN_SIZEOF
        call xcalloc
        mov [rbx + LD_INSTRS], rax
        # pc -> index
        lea rdi, [r13 + 1]
        mov esi, 4
        call xcalloc
        mov [rbx + LD_PC2IDX], rax
        mov rdi, rax
        mov esi, 0xff
        lea rdx, [r13*4 + 4]
        call memset@PLT
        # jumpdest flags
        lea rdi, [r13 + 1]
        mov esi, 1
        call xcalloc
        mov [rbx + LD_JUMPDESTS], rax
        mov qword ptr [rbx + LD_NINSTR], 0
        mov rdi, rbx
        call evm_decode
        # solidity sets its free memory pointer, mem[64], before anything
        # else (but a library's check that it's called with a delegatecall):
        # what the memory model takes it for (python's
        # variants.set_free_memory_pointer, which forgets the caches when
        # it changes: what the context took it for, see vr_free_memory_pointer)
        call vr_free_memory_pointer
        mov r12d, eax
        mov eax, 1                      # (the decoder saw the usual prologue,
        cmp byte ptr [rbx + LD_FMP], 0  # where the stack's run would have
        jne 2f                          # ended the same: its fmp idiom)
        mov rdi, rbx
        call sets_free_memory_pointer
2:      xor ecx, ecx
        test eax, eax
        sete cl
        mov [rbx + LD_NO_FREE_MEM], cl
        call vr_free_memory_pointer
        cmp eax, r12d
        je 1f
        call clear_caches
1:      add rsp, 32
        LEAVE
ENDF loader_load

# sets_free_memory_pointer(loader) -> eax: python's loader.sets_free_memory_pointer
# - the code starts as solidity's does: its first mstore writes a number
# of at least 0x60 (below 2^16) at 0x40, the stack before it made of
# pushes, dups and swaps, and of the few instructions of STACK_EFFECTS (a
# library checks its address), within the first 32 instructions. The
# stack's unknown words are NIL (python's None).
FUNC sets_free_memory_pointer
        ENTER
        sub rsp, 272                    # the stack: 32 words at most
        mov rbx, rdi
        mov r12, [rbx + LD_NINSTR]
        cmp r12, 32
        jbe 1f
        mov r12d, 32
1:      xor r13d, r13d                  # the instruction
        xor r14d, r14d                  # the stack's depth
.Lsf_next:
        cmp r13, r12
        jae .Lsf_no
        mov rax, r13
        shl rax, 4
        add rax, [rbx + LD_INSTRS]
        inc r13
        movzx ecx, byte ptr [rax + IN_OP]
        cmp ecx, 0x5f
        jb .Lsf_other
        cmp ecx, 0x7f
        ja 2f
        mov rdx, [rax + IN_PARAM]       # a push (python's `param or 0`)
        mov [rsp + r14*8], rdx
        inc r14
        jmp .Lsf_next
2:      cmp ecx, 0x8f
        ja 3f
        sub ecx, 0x7f                   # dup n
        cmp r14, rcx
        jb .Lsf_no
        mov rdx, r14
        sub rdx, rcx
        mov rdx, [rsp + rdx*8]
        mov [rsp + r14*8], rdx
        inc r14
        jmp .Lsf_next
3:      cmp ecx, 0x9f
        ja .Lsf_no
        sub ecx, 0x8f                   # swap n
        cmp r14, rcx
        jbe .Lsf_no
        mov rdx, r14
        sub rdx, rcx
        dec rdx
        mov rsi, [rsp + rdx*8]
        mov rdi, [rsp + r14*8 - 8]
        mov [rsp + rdx*8], rdi
        mov [rsp + r14*8 - 8], rsi
        jmp .Lsf_next
.Lsf_other:
        cmp ecx, 0x52
        jne 4f
        cmp r14, 2                      # mstore: of a number at 0x40?
        jb .Lsf_no
        cmp qword ptr [rsp + r14*8 - 8], (0x40 << 1) | 1
        jne .Lsf_no
        mov rax, [rsp + r14*8 - 16]
        test al, 1
        jz .Lsf_no
        sar rax, 1
        cmp rax, 0x60
        jl .Lsf_no
        cmp rax, 0x10000
        jge .Lsf_no
        mov eax, 1
        add rsp, 272
        LEAVE
4:      # STACK_EFFECTS: (popped, pushed)
        mov edx, 0                      # popped
        cmp ecx, 0x30                   # address
        je 5f
        cmp ecx, 0x34                   # callvalue
        je 5f
        cmp ecx, 0x36                   # calldatasize
        je 5f
        mov edx, 1
        cmp ecx, 0x15                   # iszero
        je 5f
        mov edx, 2
        cmp ecx, 0x14                   # eq
        je 5f
        cmp ecx, 0x10                   # lt
        je 5f
        cmp ecx, 0x11                   # gt
        jne .Lsf_no
5:      cmp r14, rdx
        jb .Lsf_no
        sub r14, rdx
        mov qword ptr [rsp + r14*8], 0  # one pushed: unknown
        inc r14
        jmp .Lsf_next
.Lsf_no:
        xor eax, eax
        add rsp, 272
        LEAVE
ENDF sets_free_memory_pointer

# loader_instr_at(loader, pc) -> rax: the instruction starting at pc, or 0
FUNC loader_instr_at
        cmp rsi, [rdi + LD_CODELEN]
        jae 1f
        mov rax, [rdi + LD_PC2IDX]
        mov eax, [rax + rsi*4]
        cmp eax, -1
        je 1f
        shl rax, 4
        add rax, [rdi + LD_INSTRS]
        ret
1:      xor eax, eax
        ret
ENDF loader_instr_at

# loader_next_line(loader, pc) -> rax: the pc of the next instruction, or
# the code length when there is none (that's what the python version does:
# the VM then treats it as an invalid jumpdest), or -1 past that.
FUNC loader_next_line
        mov rcx, [rdi + LD_CODELEN]
        mov rdx, [rdi + LD_PC2IDX]
1:      inc rsi
        cmp rsi, rcx
        jae 2f
        cmp dword ptr [rdx + rsi*4], -1
        je 1b
        mov rax, rsi
        ret
2:      mov rax, rcx
        cmp rsi, rcx
        jbe 3f
        mov rax, -1
3:      ret
ENDF loader_next_line

# loader_is_jumpdest(loader, pc) -> eax
FUNC loader_is_jumpdest
        xor eax, eax
        cmp rsi, [rdi + LD_CODELEN]
        jae 1f
        mov rcx, [rdi + LD_JUMPDESTS]
        movzx eax, byte ptr [rcx + rsi]
1:      ret
ENDF loader_is_jumpdest

# loader_disasm(loader, sb): "0x1, push1, 0x80" lines like Loader.disasm()
FUNC loader_disasm
        ENTER
        mov rbx, rdi
        mov r12, rsi
        xor r13d, r13d
1:      cmp r13, [rbx + LD_NINSTR]
        jae 9f
        mov r14, r13
        shl r14, 4
        add r14, [rbx + LD_INSTRS]
        mov rdi, r12
        mov esi, [r14 + IN_PC]
        call sb_append_hex
        mov rdi, r12
        lea rsi, [rip + .Ls_comma_sp]
        call sb_append_c
        movzx edi, byte ptr [r14 + IN_OP]
        call evm_opname
        mov rdi, r12
        mov rsi, rax
        call sb_append_c
        mov rdi, r12
        lea rsi, [rip + .Ls_comma_sp]
        call sb_append_c
        # parameter: pushes and unknown opcodes only (dup/swap print nothing)
        test byte ptr [r14 + IN_FLAGS], IF_PARAM
        jz 2f
        movzx eax, byte ptr [r14 + IN_OP]
        cmp al, 0x80
        jb 3f
        cmp al, 0x9f
        jbe 2f
3:      mov rsi, [r14 + IN_PARAM]
        mov rdi, r12
        mov edx, 16
        call sb_append_int
2:      mov rdi, r12
        mov esi, '\n'
        call sb_append_char
        inc r13
        jmp 1b
9:      LEAVE
ENDF loader_disasm

# loader_free(loader)
FUNC loader_free
        ENTER
        mov rbx, rdi
        mov rdi, [rbx + LD_CODE]
        call free@PLT
        mov rdi, [rbx + LD_INSTRS]
        call free@PLT
        mov rdi, [rbx + LD_PC2IDX]
        call free@PLT
        mov rdi, [rbx + LD_JUMPDESTS]
        call free@PLT
        mov rdi, [rbx + LD_IDIOMS]
        call free@PLT
        mov rdi, rbx
        call free@PLT
        LEAVE
ENDF loader_free

        .section .note.GNU-stack,"",@progbits
