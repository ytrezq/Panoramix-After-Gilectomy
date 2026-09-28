# The vectorized loops, chosen at run time from the ISA (cpuid): the hash
# of a long sequence (hash_seq, rt_node.s) hashes 8 elements at a time
# with AVX-512 (vpmullq, vpgatherqq, vprolq) or 4 with AVX2 (vpmuludq and
# the gather). The scalar loop of hash_seq stays for short sequences and
# for machines without them (SSE2 is the baseline).
#
# A hash only has to be the same for the same sequence within a process:
# the implementation is chosen once, and by the length only.
#
# PANORAMIX_ISA=scalar|avx2|avx512 forces a level (for the tests).

.include "defs.inc"

        .section .data
        .align 8
        .globl hash_seq_vec
        .hidden hash_seq_vec
hash_seq_vec:       .quad 0             # the vector hash, or 0
        .globl hash_seq_vec_min
        .hidden hash_seq_vec_min
hash_seq_vec_min:   .quad 0x7fffffff    # the length from which it is used
        .globl isa_level
        .hidden isa_level
isa_level:          .quad 0             # 0 scalar, 2 avx2, 3 avx512

        .section .rodata
        .align 64
.Lk_one:    .quad 1, 1, 1, 1, 1, 1, 1, 1
.Lk_hfmask: .quad HF_MASK, HF_MASK, HF_MASK, HF_MASK, HF_MASK, HF_MASK, HF_MASK, HF_MASK
.Lk_mul1:   .quad 0xff51afd7ed558ccd, 0xff51afd7ed558ccd, 0xff51afd7ed558ccd, 0xff51afd7ed558ccd
            .quad 0xff51afd7ed558ccd, 0xff51afd7ed558ccd, 0xff51afd7ed558ccd, 0xff51afd7ed558ccd
.Lk_mul2:   .quad 0xc4ceb9fe1a85ec53, 0xc4ceb9fe1a85ec53, 0xc4ceb9fe1a85ec53, 0xc4ceb9fe1a85ec53
            .quad 0xc4ceb9fe1a85ec53, 0xc4ceb9fe1a85ec53, 0xc4ceb9fe1a85ec53, 0xc4ceb9fe1a85ec53
            # the lanes start apart: j * golden ratio
.Lk_seeds:  .quad 0, 0x9e3779b97f4a7c15, 0x3c6ef372fe94f82a, 0xdaa66d2c7ddf743f
            .quad 0x78dde6e5fd29f054, 0x1715609d7c746c69, 0xb54cda54fbbee87e, 0x5384540c7b096493
.Ls_env_isa:    .asciz "PANORAMIX_ISA"
.Ls_scalar:     .asciz "scalar"
.Ls_avx2:       .asciz "avx2"
.Ls_avx512:     .asciz "avx512"
.Ls_logname:    .asciz "panoramix.simd"
.Lf_isa:        .asciz "vector loops: %s"
.Ls_names:      .quad .Ls_scalar, .Ls_scalar, .Ls_avx2, .Ls_avx512

        .text

# simd_init(): the ISA level from cpuid (and the OS: xgetbv), or from
# PANORAMIX_ISA; the vector hash chosen
FUNC simd_init
        ENTER
        sub rsp, 16
        xor r12d, r12d                  # the level
        # cpuid 1: OSXSAVE (ecx 27), then xgetbv: XMM/YMM (bits 1, 2),
        # opmask/ZMM (5, 6, 7); cpuid 7: AVX2 (ebx 5), AVX512F (16), DQ (17)
        mov eax, 1
        xor ecx, ecx
        cpuid
        bt ecx, 27
        jnc 3f
        xor ecx, ecx
        xgetbv
        mov r13d, eax                   # XCR0
        mov eax, 7
        xor ecx, ecx
        cpuid
        mov r14d, ebx
        mov eax, r13d
        and eax, 6
        cmp eax, 6
        jne 3f                          # no YMM state
        bt r14d, 5
        jnc 3f
        mov r12d, 2                     # AVX2
        mov eax, r13d
        and eax, 0xe0
        cmp eax, 0xe0
        jne 3f                          # no ZMM state
        bt r14d, 16
        jnc 3f
        bt r14d, 17
        jnc 3f
        mov r12d, 3                     # AVX-512 F + DQ
3:      # PANORAMIX_ISA caps or sets the level
        lea rdi, [rip + .Ls_env_isa]
        call getenv@PLT
        test rax, rax
        jz 5f
        mov rbx, rax
        mov rdi, rbx
        lea rsi, [rip + .Ls_scalar]
        call strcmp@PLT
        test eax, eax
        jnz 31f
        xor r12d, r12d
        jmp 5f
31:     mov rdi, rbx
        lea rsi, [rip + .Ls_avx2]
        call strcmp@PLT
        test eax, eax
        jnz 32f
        cmp r12d, 2
        cmovg r12d, [rip + .Lk_two]
        jmp 5f
32:     mov rdi, rbx
        lea rsi, [rip + .Ls_avx512]
        call strcmp@PLT
        test eax, eax
        jnz 5f
        # (asked for avx512: only if the machine has it)
5:      mov [rip + isa_level], r12
        cmp r12d, 3
        jne 6f
        lea rax, [rip + hash_seq_avx512]
        mov [rip + hash_seq_vec], rax
        mov qword ptr [rip + hash_seq_vec_min], 16
        jmp 8f
6:      cmp r12d, 2
        jne 8f
        lea rax, [rip + hash_seq_avx2]
        mov [rip + hash_seq_vec], rax
        mov qword ptr [rip + hash_seq_vec_min], 8
8:      add rsp, 16
        LEAVE
ENDF simd_init

# simd_log(): DEBUG: the level chosen (once the log level is known)
FUNC simd_log
        ENTER
        mov edi, LOG_DEBUG
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Lf_isa]
        lea rax, [rip + .Ls_names]
        mov rcx, [rip + isa_level]
        mov rcx, [rax + rcx*8]
        call log_fmt
        LEAVE
ENDF simd_log

        .section .rodata
        .align 4
.Lk_two:    .long 2
        .text

# hash_seq_avx512(kind, count, elems) -> rax: hash_seq for count >= 16,
# 8 elements per step
FUNC hash_seq_avx512
        push rbx
        movabs rax, 0x9e3779b97f4a7c15
        imul rax, rdi
        xor rax, rsi                    # (kind, count), the seed of lane 0
        vpbroadcastq zmm4, rax
        vpaddq zmm4, zmm4, [rip + .Lk_seeds]   # the accumulators, one per lane
        vmovdqa64 zmm5, [rip + .Lk_one]
        vmovdqa64 zmm6, [rip + .Lk_mul1]
        vmovdqa64 zmm7, [rip + .Lk_mul2]
        vmovdqa64 zmm8, [rip + .Lk_hfmask]
        vpxorq zmm9, zmm9, zmm9         # the flags
        mov r8d, N_HASH
        mov rcx, rsi
        and rcx, -8                     # the vector part
        xor r9d, r9d
1:      cmp r9, rcx
        jae 2f
        vmovdqu64 zmm0, [rdx + r9*8]    # 8 elements
        vptestmq k1, zmm0, zmm5         # k1: the small ints
        vptestmq k2, zmm0, zmm0         # k2: the non-NIL
        kandnw k2, k1, k2               # k2: the nodes
        vpmullq zmm1{k1}{z}, zmm0, zmm6 # a small int: multiplied
        kmovw k3, k2
        vpgatherqq zmm1{k2}, [r8 + zmm0*1]     # a node: its hash
        vpandq zmm2{k3}{z}, zmm1, zmm8
        vporq zmm9, zmm9, zmm2          # the flags of the nodes
        vpxorq zmm4, zmm4, zmm1
        vpmullq zmm4, zmm4, zmm7
        vprolq zmm4, zmm4, 31
        add r9, 8
        jmp 1b
2:      # the lanes folded into one, then the tail as the scalar loop
        vmovdqu64 [rsp - 64 - 64], zmm4 # (below the red zone's 128 bytes: fine, leaf code)
        vextracti64x4 ymm2, zmm9, 1
        vporq ymm9, ymm9, ymm2
        vextracti64x2 xmm2, ymm9, 1
        vporq xmm9, xmm9, xmm2
        vpextrq r10, xmm9, 1
        vmovq r11, xmm9
        or r10, r11                     # the flags
        vzeroupper
        mov rax, [rsp - 128]
        mov ebx, 1
3:      cmp ebx, 8
        jae 4f
        xor rax, [rsp - 128 + rbx*8]
        movabs rdi, 0xc4ceb9fe1a85ec53
        imul rax, rdi
        rol rax, 31
        inc ebx
        jmp 3b
4:      pop rbx
        mov rdi, r10                    # the flags so far
        jmp hash_seq_tail               # the elements from rcx on, the finalizer
ENDF hash_seq_avx512

# hash_seq_avx2(kind, count, elems) -> rax: hash_seq for count >= 8, 4
# elements per step (no 64-bit multiply: the low halves, mixed first)
FUNC hash_seq_avx2
        push rbx
        movabs rax, 0x9e3779b97f4a7c15
        imul rax, rdi
        xor rax, rsi
        vmovq xmm4, rax
        vpbroadcastq ymm4, xmm4
        vpaddq ymm4, ymm4, [rip + .Lk_seeds]
        vmovdqa ymm5, [rip + .Lk_one]
        vmovdqa ymm6, [rip + .Lk_mul1]
        vmovdqa ymm7, [rip + .Lk_mul2]
        vmovdqa ymm8, [rip + .Lk_hfmask]
        vpxor ymm9, ymm9, ymm9          # the flags
        vpxor ymm10, ymm10, ymm10       # zero
        mov r8d, N_HASH
        mov rcx, rsi
        and rcx, -4
        xor r9d, r9d
1:      cmp r9, rcx
        jae 2f
        vmovdqu ymm0, [rdx + r9*8]      # 4 elements
        vpand ymm1, ymm0, ymm5
        vpcmpeqq ymm1, ymm1, ymm5       # ymm1: the small ints (all ones)
        vpcmpeqq ymm2, ymm0, ymm10
        vpor ymm2, ymm2, ymm1
        vpcmpeqq ymm3, ymm2, ymm2       # all ones
        vpxor ymm2, ymm2, ymm3          # ymm2: the nodes (not NIL, not small)
        # a small int: (v ^ v >> 32) * K1 (the low halves)
        vpsrlq ymm3, ymm0, 32
        vpxor ymm3, ymm3, ymm0
        vpmuludq ymm3, ymm3, ymm6
        vpand ymm3, ymm3, ymm1
        vpgatherqq ymm3, [r8 + ymm0*1], ymm2   # a node: its hash (ymm2 is consumed)
        vpcmpeqq ymm2, ymm0, ymm10
        vpor ymm2, ymm2, ymm1
        vpandn ymm2, ymm2, ymm8         # HF_MASK on the nodes' lanes
        vpand ymm2, ymm2, ymm3
        vpor ymm9, ymm9, ymm2           # the flags
        vpxor ymm4, ymm4, ymm3
        vpsrlq ymm2, ymm4, 32
        vpxor ymm4, ymm4, ymm2
        vpmuludq ymm4, ymm4, ymm7
        vpsllq ymm2, ymm4, 31           # rol 31
        vpsrlq ymm4, ymm4, 33
        vpor ymm4, ymm4, ymm2
        add r9, 4
        jmp 1b
2:      vmovdqu [rsp - 128], ymm4
        vextracti128 xmm2, ymm9, 1
        vpor xmm9, xmm9, xmm2
        vpextrq r10, xmm9, 1
        vmovq r11, xmm9
        or r10, r11
        vzeroupper
        mov rax, [rsp - 128]
        mov ebx, 1
3:      cmp ebx, 4
        jae 4f
        xor rax, [rsp - 128 + rbx*8]
        movabs rdi, 0xc4ceb9fe1a85ec53
        imul rax, rdi
        rol rax, 31
        inc ebx
        jmp 3b
4:      pop rbx
        mov rdi, r10
        jmp hash_seq_tail
ENDF hash_seq_avx2

        .section .note.GNU-stack,"",@progbits
