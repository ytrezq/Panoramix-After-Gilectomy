# panoramix-asm: common definitions.
#
# Conventions
# -----------
# - System V AMD64 ABI everywhere (args rdi, rsi, rdx, rcx, r8, r9; result rax;
#   rbx, rbp, r12-r15 callee-saved).
# - r15 holds the thread context (see CTX_* below) in all the decompiler
#   code. It is set up by the entry points and never used for anything else,
#   so it survives calls into libc and GMP. Code called *by* foreign code
#   (the GMP memory callbacks) gets the context from a pthread key instead.
# - Values are tagged 64-bit words:
#       (n << 1) | 1     a small integer n, -2^62 <= n < 2^62
#       pointer          a node (16-byte aligned), low bit clear
#       0                NIL: no value
# - Every node starts with a 16-byte header:
#       u32 kind, u32 aux, u64 hash
#   K_INT      aux unused, payload = mpz_t (16 bytes)
#   K_STR      aux = opcode id (0 if not an opcode), payload = u32 len, bytes, NUL
#   K_TUPLE    aux = count, payload = count tagged values
#   K_LIST     aux = count, payload = count tagged values
#   K_SPECIAL  aux = which (SP_NONE, SP_TRUE, SP_FALSE...), no payload
#   Tuples and lists are hash-consed per thread: two equal ones are the same
#   pointer. Strings are interned globally. Big ints are not shared (they are
#   compared by value, see values_equal).

.intel_syntax noprefix

.set K_INT, 1
.set K_STR, 2
.set K_TUPLE, 3
.set K_LIST, 4
.set K_SPECIAL, 5

.set STR_VOLATILE, 0x80000000  # in a string's aux: mentions volatile state
.set STR_ID_MASK, 0x7fffffff

.set SP_NONE, 1
.set SP_TRUE, 2
.set SP_FALSE, 3

.set N_KIND, 0
.set N_AUX, 4
.set N_HASH, 8
.set N_DATA, 16

.set NODE_INT_SIZE, 32

# mpz_t layout (GMP): int _mp_alloc; int _mp_size; mp_limb_t *_mp_d
.set MPZ_ALLOC, 0
.set MPZ_SIZE, 4
.set MPZ_D, 8
.set MPZ_SIZEOF, 16

.set SMALL_MAX, 0x3fffffffffffffff      # 2^62 - 1
.set SMALL_MIN, -0x4000000000000000

# thread context, pointed to by r15
.set CTX_ARENA_CUR, 0
.set CTX_ARENA_END, 8
.set CTX_ARENA_CHUNKS, 16
.set CTX_ARENA_CHUNKSZ, 24
.set CTX_ARENA_TOTAL, 32
.set CTX_HC_TABLE, 40
.set CTX_HC_CAP, 48
.set CTX_HC_COUNT, 56
.set CTX_NODE_COUNT, 64
.set CTX_VAR_COUNTER, 72
.set CTX_OUT, 80
.set CTX_MPZ_A, 96          # four scratch mpz_t (16 bytes each), initialized
.set CTX_MPZ_B, 112         # with the context: A/B/R for arithmetic,
.set CTX_MPZ_R, 128         # T for value_mpz views
.set CTX_MPZ_T, 144
.set CTX_TMPZ, CTX_MPZ_A    # used by mk_int_i64/u64/bytes_be and the parser
.set CTX_TMPZ2, CTX_MPZ_T   # used by value_mpz
.set CTX_LOADER, 160
.set CTX_SIZE, 256

.set ARENA_CHUNK_DEFAULT, 0x400000     # 4 MiB

# arena chunk header
.set CHUNK_NEXT, 0
.set CHUNK_SIZE, 8
.set CHUNK_DATA, 16

# string builder
.set SB_BUF, 0
.set SB_LEN, 8
.set SB_CAP, 16
.set SB_SIZEOF, 24

# loader
.set LD_CODE, 0
.set LD_CODELEN, 8
.set LD_INSTRS, 16
.set LD_NINSTR, 24
.set LD_PC2IDX, 32          # u32 per code offset: index of the instruction starting there, or -1
.set LD_JUMPDESTS, 40       # u8 per code offset: 1 if jumpdest
.set LD_LASTLINE, 48
.set LD_NJUMPDESTS, 56
.set LD_SIZEOF, 64

# one disassembled instruction
.set IN_PC, 0               # u32
.set IN_OP, 4               # u8 opcode byte
.set IN_FLAGS, 5            # u8: IF_PARAM if there's a parameter
.set IN_PARAM, 8            # tagged value (push value, dup/swap depth, unknown byte)
.set IN_SIZEOF, 16
.set IF_PARAM, 1

# log levels
.set LOG_DEBUG, 10
.set LOG_INFO, 20
.set LOG_WARNING, 30
.set LOG_ERROR, 40

# --- macros ---

.macro FUNC name
        .text
        .globl \name
        .hidden \name
        .type \name, @function
        .p2align 4
\name:
.endm

.macro ENDF name
        .size \name, .-\name
.endm

# Standard frame: after ENTER the stack is 16-byte aligned, and rbx, r12,
# r13, r14 are free to use. LEAVE restores and returns.
.macro ENTER
        push rbp
        mov rbp, rsp
        push rbx
        push r12
        push r13
        push r14
.endm

.macro LEAVE
        pop r14
        pop r13
        pop r12
        pop rbx
        pop rbp
        ret
.endm

# tagged small int helpers
.macro TAG reg
        lea \reg, [\reg + \reg + 1]
.endm

.macro UNTAG reg
        sar \reg, 1
.endm

.include "opcodes.inc"

# LOADS reg, NAME: load the interned string node for opcode NAME
.macro LOADS reg, name
        lea \reg, [rip + opcode_nodes]
        mov \reg, [\reg + 8*OP_\name]
.endm

# LEAVE without the ret (for functions that saved more registers)
.macro LEAVE_NORET
        pop r14
        pop r13
        pop r12
        pop rbx
        pop rbp
.endm

# growable vector (rt_vec.s)
.set VEC_DATA, 0
.set VEC_LEN, 8
.set VEC_CAP, 16
.set VEC_SIZEOF, 24

# LEAVE for functions that moved rsp by a dynamic amount after ENTER
.macro LEAVE_DYN
        lea rsp, [rbp - 32]
        LEAVE
.endm

# tri-state / four-state results
.set TRI_TRUE, 1
.set TRI_FALSE, 0
.set TRI_NONE, -1
.set TRI_CANNOT, -2
