# Growable arrays of values, allocated in the arena (no free: they die with
# the arena; a grown buffer just leaves its old one behind).

.include "defs.inc"

        .text

# vec_new() -> rax
FUNC vec_new
        ENTER
        mov edi, VEC_SIZEOF + 16*8
        call arena_alloc
        lea rcx, [rax + VEC_SIZEOF]
        mov [rax + VEC_DATA], rcx
        mov qword ptr [rax + VEC_LEN], 0
        mov qword ptr [rax + VEC_CAP], 16
        LEAVE
ENDF vec_new

# vec_new_cap(n) -> rax: with room for n
FUNC vec_new_cap
        ENTER
        mov rbx, rdi
        cmp rbx, 4
        jae 1f
        mov ebx, 4
1:      lea rdi, [rbx*8 + VEC_SIZEOF]
        call arena_alloc
        lea rcx, [rax + VEC_SIZEOF]
        mov [rax + VEC_DATA], rcx
        mov qword ptr [rax + VEC_LEN], 0
        mov [rax + VEC_CAP], rbx
        LEAVE
ENDF vec_new_cap

# vec_push(vec, value)
FUNC vec_push
        mov rax, [rdi + VEC_LEN]
        cmp rax, [rdi + VEC_CAP]
        jae 1f
        mov rcx, [rdi + VEC_DATA]
        mov [rcx + rax*8], rsi
        inc qword ptr [rdi + VEC_LEN]
        ret
1:      ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rdi, [rbx + VEC_CAP]
        shl rdi, 1
        mov [rbx + VEC_CAP], rdi
        shl rdi, 3
        call arena_alloc
        mov rdi, rax
        mov r13, rax
        mov rsi, [rbx + VEC_DATA]
        mov rdx, [rbx + VEC_LEN]
        shl rdx, 3
        call memcpy@PLT
        mov [rbx + VEC_DATA], r13
        mov rax, [rbx + VEC_LEN]
        mov [r13 + rax*8], r12
        inc qword ptr [rbx + VEC_LEN]
        LEAVE
ENDF vec_push

# vec_extend(vec, values_ptr, count)
FUNC vec_extend
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        xor r14d, r14d
1:      cmp r14, r13
        jae 2f
        mov rdi, rbx
        mov rsi, [r12 + r14*8]
        call vec_push
        inc r14
        jmp 1b
2:      LEAVE
ENDF vec_extend

# vec_extend_seq(vec, tuple_or_list)
FUNC vec_extend_seq
        mov edx, [rsi + N_AUX]
        add rsi, N_DATA
        jmp vec_extend
ENDF vec_extend_seq

# vec_to_list(vec) -> rax / vec_to_tuple(vec) -> rax
FUNC vec_to_list
        mov rsi, [rdi + VEC_DATA]
        mov rdi, [rdi + VEC_LEN]
        jmp mk_list
ENDF vec_to_list

FUNC vec_to_tuple
        mov rsi, [rdi + VEC_DATA]
        mov rdi, [rdi + VEC_LEN]
        jmp mk_tuple
ENDF vec_to_tuple

# vec_pop(vec) -> rax (NIL if empty)
FUNC vec_pop
        mov rax, [rdi + VEC_LEN]
        test rax, rax
        jz 1f
        dec rax
        mov [rdi + VEC_LEN], rax
        mov rcx, [rdi + VEC_DATA]
        mov rax, [rcx + rax*8]
        ret
1:      xor eax, eax
        ret
ENDF vec_pop

        .section .note.GNU-stack,"",@progbits
