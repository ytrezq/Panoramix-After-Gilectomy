# `make coverage`: every function's calls counted (FUNC's COV_COUNT), and
# written at exit to $PANORAMIX_COVERAGE (appended: "count name" lines),
# for the functions no test reaches. Empty in the ordinary build.
.include "defs.inc"

.ifdef COVERAGE
        .text
cov_dump:
        push rbx
        push r12
        push r13
        lea rdi, [rip + .Lcov_env]
        call getenv@PLT
        test rax, rax
        jz 9f
        mov rdi, rax
        lea rsi, [rip + .Lcov_mode]
        call fopen@PLT
        test rax, rax
        jz 9f
        mov r12, rax
        lea rbx, [rip + __start_covtab]
1:      lea rax, [rip + __stop_covtab]
        cmp rbx, rax
        jae 2f
        mov rdi, r12
        lea rsi, [rip + .Lcov_fmt]
        mov rdx, [rbx]
        mov rdx, [rdx]
        mov rcx, [rbx + 8]
        xor eax, eax
        call fprintf@PLT
        add rbx, 16
        jmp 1b
2:      mov rdi, r12
        call fclose@PLT
9:      pop r13
        pop r12
        pop rbx
        ret
        .section .fini_array, "aw"
        .p2align 3
        .quad cov_dump
        .section .rodata
.Lcov_env:  .asciz "PANORAMIX_COVERAGE"
.Lcov_mode: .asciz "a"
.Lcov_fmt:  .asciz "%ld %s\n"
.endif

        .section .note.GNU-stack,"",@progbits
