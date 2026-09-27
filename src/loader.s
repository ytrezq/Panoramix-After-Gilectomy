# Loader: bytecode -> instructions, jumpdests. The function discovery
# (running the dispatcher symbolically) is in the VM.

.include "defs.inc"

        .section .data.rel.ro
        .align 8
        .globl evm_opnames
        .hidden evm_opnames
evm_opnames:
        .quad .Lo00, .Lo01, .Lo02, .Lo03, .Lo04, .Lo05, .Lo06, .Lo07
        .quad .Lo08, .Lo09, .Lo0a, .Lo0b, 0, 0, 0, 0
        .quad .Lo10, .Lo11, .Lo12, .Lo13, .Lo14, .Lo15, .Lo16, .Lo17
        .quad .Lo18, .Lo19, .Lo1a, .Lo1b, .Lo1c, .Lo1d, 0, 0
        .quad .Lo20, 0, 0, 0, 0, 0, 0, 0
        .quad 0, 0, 0, 0, 0, 0, 0, 0
        .quad .Lo30, .Lo31, .Lo32, .Lo33, .Lo34, .Lo35, .Lo36, .Lo37
        .quad .Lo38, .Lo39, .Lo3a, .Lo3b, .Lo3c, .Lo3d, .Lo3e, .Lo3f
        .quad .Lo40, .Lo41, .Lo42, .Lo43, .Lo44, .Lo45, .Lo46, .Lo47
        .quad .Lo48, 0, 0, 0, 0, 0, 0, 0
        .quad .Lo50, .Lo51, .Lo52, .Lo53, .Lo54, .Lo55, .Lo56, .Lo57
        .quad .Lo58, .Lo59, .Lo5a, .Lo5b, 0, 0, 0, .Lo5f
        .quad .Lo60, .Lo61, .Lo62, .Lo63, .Lo64, .Lo65, .Lo66, .Lo67
        .quad .Lo68, .Lo69, .Lo6a, .Lo6b, .Lo6c, .Lo6d, .Lo6e, .Lo6f
        .quad .Lo70, .Lo71, .Lo72, .Lo73, .Lo74, .Lo75, .Lo76, .Lo77
        .quad .Lo78, .Lo79, .Lo7a, .Lo7b, .Lo7c, .Lo7d, .Lo7e, .Lo7f
        .quad .Lo80, .Lo81, .Lo82, .Lo83, .Lo84, .Lo85, .Lo86, .Lo87
        .quad .Lo88, .Lo89, .Lo8a, .Lo8b, .Lo8c, .Lo8d, .Lo8e, .Lo8f
        .quad .Lo90, .Lo91, .Lo92, .Lo93, .Lo94, .Lo95, .Lo96, .Lo97
        .quad .Lo98, .Lo99, .Lo9a, .Lo9b, .Lo9c, .Lo9d, .Lo9e, .Lo9f
        .quad .Loa0, .Loa1, .Loa2, .Loa3, .Loa4, 0, 0, 0
        .quad 0, 0, 0, 0, 0, 0, 0, 0
        .quad 0, 0, 0, 0, 0, 0, 0, 0
        .quad 0, 0, 0, 0, 0, 0, 0, 0
        .quad 0, 0, 0, 0, 0, 0, 0, 0
        .quad 0, 0, 0, 0, 0, 0, 0, 0
        .quad 0, 0, 0, 0, 0, 0, 0, 0
        .quad 0, 0, 0, 0, 0, 0, 0, 0
        .quad 0, 0, 0, 0, 0, 0, 0, 0
        .quad 0, 0, 0, 0, 0, 0, 0, 0
        .quad .Lof0, .Lof1, .Lof2, .Lof3, .Lof4, .Lof5, 0, 0
        .quad 0, 0, .Lofa, 0, 0, .Lofd, .Lofe, .Loff
.section .rodata
.Lo00: .asciz "stop"
.Lo01: .asciz "add"
.Lo02: .asciz "mul"
.Lo03: .asciz "sub"
.Lo04: .asciz "div"
.Lo05: .asciz "sdiv"
.Lo06: .asciz "mod"
.Lo07: .asciz "smod"
.Lo08: .asciz "addmod"
.Lo09: .asciz "mulmod"
.Lo0a: .asciz "exp"
.Lo0b: .asciz "signextend"
.Lo10: .asciz "lt"
.Lo11: .asciz "gt"
.Lo12: .asciz "slt"
.Lo13: .asciz "sgt"
.Lo14: .asciz "eq"
.Lo15: .asciz "iszero"
.Lo16: .asciz "and"
.Lo17: .asciz "or"
.Lo18: .asciz "xor"
.Lo19: .asciz "not"
.Lo1a: .asciz "byte"
.Lo1b: .asciz "shl"
.Lo1c: .asciz "shr"
.Lo1d: .asciz "sar"
.Lo20: .asciz "sha3"
.Lo30: .asciz "address"
.Lo31: .asciz "balance"
.Lo32: .asciz "origin"
.Lo33: .asciz "caller"
.Lo34: .asciz "callvalue"
.Lo35: .asciz "calldataload"
.Lo36: .asciz "calldatasize"
.Lo37: .asciz "calldatacopy"
.Lo38: .asciz "codesize"
.Lo39: .asciz "codecopy"
.Lo3a: .asciz "gasprice"
.Lo3b: .asciz "extcodesize"
.Lo3c: .asciz "extcodecopy"
.Lo3d: .asciz "returndatasize"
.Lo3e: .asciz "returndatacopy"
.Lo3f: .asciz "extcodehash"
.Lo40: .asciz "blockhash"
.Lo41: .asciz "coinbase"
.Lo42: .asciz "timestamp"
.Lo43: .asciz "number"
.Lo44: .asciz "difficulty"
.Lo45: .asciz "gaslimit"
.Lo46: .asciz "chainid"
.Lo47: .asciz "selfbalance"
.Lo48: .asciz "basefee"
.Lo50: .asciz "pop"
.Lo51: .asciz "mload"
.Lo52: .asciz "mstore"
.Lo53: .asciz "mstore8"
.Lo54: .asciz "sload"
.Lo55: .asciz "sstore"
.Lo56: .asciz "jump"
.Lo57: .asciz "jumpi"
.Lo58: .asciz "pc"
.Lo59: .asciz "msize"
.Lo5a: .asciz "gas"
.Lo5b: .asciz "jumpdest"
.Lo5f: .asciz "push0"
.Lo60: .asciz "push1"
.Lo61: .asciz "push2"
.Lo62: .asciz "push3"
.Lo63: .asciz "push4"
.Lo64: .asciz "push5"
.Lo65: .asciz "push6"
.Lo66: .asciz "push7"
.Lo67: .asciz "push8"
.Lo68: .asciz "push9"
.Lo69: .asciz "push10"
.Lo6a: .asciz "push11"
.Lo6b: .asciz "push12"
.Lo6c: .asciz "push13"
.Lo6d: .asciz "push14"
.Lo6e: .asciz "push15"
.Lo6f: .asciz "push16"
.Lo70: .asciz "push17"
.Lo71: .asciz "push18"
.Lo72: .asciz "push19"
.Lo73: .asciz "push20"
.Lo74: .asciz "push21"
.Lo75: .asciz "push22"
.Lo76: .asciz "push23"
.Lo77: .asciz "push24"
.Lo78: .asciz "push25"
.Lo79: .asciz "push26"
.Lo7a: .asciz "push27"
.Lo7b: .asciz "push28"
.Lo7c: .asciz "push29"
.Lo7d: .asciz "push30"
.Lo7e: .asciz "push31"
.Lo7f: .asciz "push32"
.Lo80: .asciz "dup1"
.Lo81: .asciz "dup2"
.Lo82: .asciz "dup3"
.Lo83: .asciz "dup4"
.Lo84: .asciz "dup5"
.Lo85: .asciz "dup6"
.Lo86: .asciz "dup7"
.Lo87: .asciz "dup8"
.Lo88: .asciz "dup9"
.Lo89: .asciz "dup10"
.Lo8a: .asciz "dup11"
.Lo8b: .asciz "dup12"
.Lo8c: .asciz "dup13"
.Lo8d: .asciz "dup14"
.Lo8e: .asciz "dup15"
.Lo8f: .asciz "dup16"
.Lo90: .asciz "swap1"
.Lo91: .asciz "swap2"
.Lo92: .asciz "swap3"
.Lo93: .asciz "swap4"
.Lo94: .asciz "swap5"
.Lo95: .asciz "swap6"
.Lo96: .asciz "swap7"
.Lo97: .asciz "swap8"
.Lo98: .asciz "swap9"
.Lo99: .asciz "swap10"
.Lo9a: .asciz "swap11"
.Lo9b: .asciz "swap12"
.Lo9c: .asciz "swap13"
.Lo9d: .asciz "swap14"
.Lo9e: .asciz "swap15"
.Lo9f: .asciz "swap16"
.Loa0: .asciz "log0"
.Loa1: .asciz "log1"
.Loa2: .asciz "log2"
.Loa3: .asciz "log3"
.Loa4: .asciz "log4"
.Lof0: .asciz "create"
.Lof1: .asciz "call"
.Lof2: .asciz "callcode"
.Lof3: .asciz "return"
.Lof4: .asciz "delegatecall"
.Lof5: .asciz "create2"
.Lofa: .asciz "staticcall"
.Lofd: .asciz "revert"
.Lofe: .asciz "invalid"
.Loff: .asciz "selfdestruct"
.Ls_unknown: .asciz "UNKNOWN"
.Ls_comma_sp: .asciz ", "

        .text

# evm_opname(op) -> rax: C string, "UNKNOWN" for undefined opcodes
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
        call calloc@PLT
        LEAVE
ENDF loader_new

# loader_load(loader, bytes, len): disassemble. Push values become integer
# values allocated on the current (r15) context.
FUNC loader_load
        ENTER
        sub rsp, 16
        mov rbx, rdi                    # loader
        mov r12, rsi                    # bytes
        mov r13, rdx                    # len
        # copy the code
        lea rdi, [r13 + 1]
        call malloc@PLT
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
        call calloc@PLT
        mov [rbx + LD_INSTRS], rax
        # pc -> index
        lea rdi, [r13 + 1]
        mov esi, 4
        call calloc@PLT
        mov [rbx + LD_PC2IDX], rax
        mov rdi, rax
        mov esi, 0xff
        lea rdx, [r13*4 + 4]
        call memset@PLT
        # jumpdest flags
        lea rdi, [r13 + 1]
        mov esi, 1
        call calloc@PLT
        mov [rbx + LD_JUMPDESTS], rax
        xor r14d, r14d                  # pc
        mov qword ptr [rbx + LD_NINSTR], 0
.Lld_loop:
        cmp r14, r13
        jae .Lld_done
        mov rax, [rbx + LD_NINSTR]
        mov rcx, [rbx + LD_PC2IDX]
        mov [rcx + r14*4], eax
        mov rcx, rax
        shl rcx, 4
        add rcx, [rbx + LD_INSTRS]      # rcx = instr
        mov [rcx + IN_PC], r14d
        movzx eax, byte ptr [r12 + r14]
        mov [rcx + IN_OP], al
        mov [rsp], rcx
        inc qword ptr [rbx + LD_NINSTR]
        # classify
        lea rdx, [rip + evm_opnames]
        cmp qword ptr [rdx + rax*8], 0
        jne 1f
        # unknown: param = the byte
        lea rdi, [rax + rax + 1]
        mov [rcx + IN_PARAM], rdi
        mov byte ptr [rcx + IN_FLAGS], IF_PARAM
        inc r14
        jmp .Lld_loop
1:      cmp al, 0x5b
        jne 2f
        mov rdx, [rbx + LD_JUMPDESTS]
        mov byte ptr [rdx + r14], 1
        inc qword ptr [rbx + LD_NJUMPDESTS]
        inc r14
        jmp .Lld_loop
2:      cmp al, 0x5f
        jb 3f
        cmp al, 0x7f
        ja 3f
        # push n: n = op - 0x5f bytes, fewer at the end of the code
        sub eax, 0x5f
        inc r14
        lea rdi, [r12 + r14]            # bytes start
        mov rsi, r13
        sub rsi, r14                    # remaining
        cmp rsi, rax
        cmovae rsi, rax
        add r14, rsi
        call mk_int_bytes_be
        mov rcx, [rsp]
        mov [rcx + IN_PARAM], rax
        mov byte ptr [rcx + IN_FLAGS], IF_PARAM
        jmp .Lld_loop
3:      cmp al, 0x80
        jb 4f
        cmp al, 0x9f
        ja 4f
        # dup n / swap n
        and eax, 0x0f
        inc eax
        lea rdi, [rax + rax + 1]
        mov [rcx + IN_PARAM], rdi
        mov byte ptr [rcx + IN_FLAGS], IF_PARAM
4:      inc r14
        jmp .Lld_loop
.Lld_done:
        add rsp, 16
        LEAVE
ENDF loader_load

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
3:      mov rdi, r12
        mov rsi, [r14 + IN_PARAM]
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
        mov rdi, rbx
        call free@PLT
        LEAVE
ENDF loader_free

        .section .note.GNU-stack,"",@progbits
