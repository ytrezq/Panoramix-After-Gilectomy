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
.set K_VMNODE, 6            # a node of the symbolic execution (vmnode.s)

# The top byte of a node's N_HASH holds "mention" flags: which of these
# strings the value contains, anywhere in its tree - what python tests with
# `"mem" in str(exp)` (a walk of the whole expression, every time).
.set HF_MEM, 1 << 56
.set HF_MSIZE, 1 << 57
.set HF_STORAGE, 1 << 58
.set HF_SHIFT, 56
.set HF_MASK, 0xff << 56

.set STR_VOLATILE, 0x80000000  # in a string's aux: mentions volatile state
.set STR_FLOAT, 0x40000000     # in a string's aux: a python float ("0.5"), printed bare
.set STR_ID_MASK, 0x3fffffff

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
# 168..295: memo tables, 16 slots (see CTX_MEMO)
.set CTX_VM, 296            # the VM this thread runs (vm.s)
.set CTX_ERR_BUF, 304       # the innermost error handler (rt_err.s)
.set CTX_ERR_CODE, 312      # what was thrown
.set CTX_ERR_MSG, 320
.set CTX_FUNC, 328          # the function being printed (sigs.s, function.s)
.set CTX_EVAL_POOL, 352     # 32 scratch mpz_t, one per depth, for variant_eval
.set EVAL_POOL_DEPTH, 32
.set CTX_SIZE, 352 + 32 * MPZ_SIZEOF

# error handler buffer (rt_err.s)
.set ERR_RBX, 0
.set ERR_RBP, 8
.set ERR_R12, 16
.set ERR_R13, 24
.set ERR_R14, 32
.set ERR_RSP, 40
.set ERR_RIP, 48
.set ERR_PREV, 56
.set ERR_SIZEOF, 64

# error codes
.set E_STACK_UNDERFLOW, 1
.set E_TIMEOUT, 2
.set E_ASSERT, 3
.set E_CANNOT_COMPARE, 4
.set E_TYPE, 5              # python's TypeError (an int operation on an expression)
.set E_NOT_IMPLEMENTED, 6
.set E_INDEX, 7

.set ARENA_CHUNK_DEFAULT, 0x400000     # 4 MiB
.set COMPACT_THRESHOLD, 0x10000000      # 256 MiB of arena: simplify_trace compacts

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
.set LD_FUNCS, 64           # list of (hash string, target, stack) (funcs.s)
.set LD_FALLBACK_KNOWN, 72  # tuple: what holds in the default function
.set LD_SIZEOF, 80

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

# hash map (rt_map.s)
.set MAP_ENTRIES, 0
.set MAP_CAP, 8
.set MAP_COUNT, 16
.set MAP_SIZEOF, 24

# memo tables in the context (created lazily by memo_table)
.set CTX_MEMO, 168          # 16 slots
.set MEMO_SIMPLIFY, 0
.set MEMO_GE_ZERO, 1
.set MEMO_LT, 2
.set MEMO_LE, 3
.set MEMO_MASK, 4
.set MEMO_ADD, 5
.set MEMO_TO_MASK, 6
.set MEMO_ADD_GE_ZERO, 7
.set MEMO_STACK_SIMPLIFY, 8
.set MEMO_TEST_NODES, 9
.set MEMO_SIMPLIFY_EXP, 10
.set MEMO_FIND_MEMS, 11
.set MEMO_REPLACE_MEM_EXP, 12
.set MEMO_RANGE_OVERLAPS, 13
.set MEMO_SIGDB, 14         # selector -> abi entry (sigdb.s)
.set MEMO_IMPORT, 15        # value_import: a VM node -> its copy here
.set MEMO_COUNT, 16
# sentinel values stored in memo tables for python's None / False (values
# and pointers are never 2 or 4)
.set MEMO_NONE, 2
.set MEMO_FALSE, 4
.set MEMO_TRUE, 6
.set MEMO_CANNOT, 8
.set SIGN_NONE, 0x40000000     # get_sign: unknown (python None)

# --- the symbolic VM (vmnode.s, vm.s) ---

# a node: a point in the symbolic execution, with the trace from there
# until the next jump. K_VMNODE, hash = a unique id.
.set ND_TRACE, 16           # vec* of lines, 0 while not run yet (python None)
.set ND_PREV, 24            # node*, 0 for the root
.set ND_NEXT, 32            # vec* of nodes
.set ND_START, 40           # value: the pc, or a symbolic jump target
.set ND_SAFE, 48            # 0/1: reached by falling through (no jumpdest needed)
.set ND_STACK, 56           # tuple: the stack on arrival
.set ND_DEPTH, 64
.set ND_LABEL, 72           # node*: the loop head this node is the body of
.set ND_CONDITION, 80       # value: the condition under which the parent gets here
.set ND_KNOWN, 88           # tuple of the conditions holding on the path here
.set ND_MERGED, 96          # 0/1: the paths were merged below (merge_branches)
.set ND_JD, 104             # tuple (start, stack length, (jumpdests on the stack...))
.set ND_BEGIN_VARS, 112     # tuple: on a loop head, its variables
.set ND_SIZEOF, 128

.set VM_LOADER, 0
.set VM_JUST_FDESTS, 8
.set VM_COUNTER, 16         # for the _1, _2... names
.set VM_KNOWN, 24           # tuple: what holds at the current point of _run
.set VM_STACK, 32           # vec: the symbolic stack of _run
.set VM_TRACE, 40           # vec: the trace _run builds
.set VM_NODE_COUNT, 48
.set VM_TIME_START, 56      # CLOCK_MONOTONIC nanoseconds
.set VM_TIMEOUT, 64         # nanoseconds, 0 = none
.set VM_SIZEOF, 80

.set MAX_NODE_COUNT, 5000
.set MAX_EXP_SIZE, 150

# --- pattern matching (matcher.s) ---
.set MATCH_MAX, 16
.set MATCH_NAMES_SIZE, 8 + 8*MATCH_MAX
.set MATCH_BINDINGS_SIZE, 8*MATCH_MAX

# PAT reg, "python literal with wildcards": reg := the pattern value.
# The literals are collected in the pattern_table section and parsed
# once at startup (patterns_init).
.macro PAT reg, text
        .section .rodata
.Lpat_s\@: .asciz "\text"
        .section pattern_table,"aw",@progbits
        .align 8
.Lpat_v\@: .quad 0, .Lpat_s\@
        .text
        mov \reg, [rip + .Lpat_v\@]
.endm

# --- the counters of a loop (loops.s parse_counters); 0 = absent ---
.set PC_SETVARS, 0          # tuple of ('setvar', idx, value): the values before the loop
.set PC_JDS, 8              # the loop's id
.set PC_STEPVARS, 16        # list of (idx, value): the values at a continue
.set PC_COUNTER, 24         # the counter variable's index
.set PC_START, 32
.set PC_STOP, 40
.set PC_STEP, 48
.set PC_NUM_LOOPS, 56
.set PC_ENDVARS, 64         # list of (idx, value): the values after the loop
.set PC_SIZEOF, 80

# prettify flags (prettify.s)
.set PF_REM_BOOL, 1         # rem_bool=True
.set PF_PARENS, 2           # parentheses=True
.set PF_TOP, 4              # top_level=True
.set PF_COLOR, 8            # add_color=True

# a decompiled function (function.s)
.set FN_HASH, 0             # str: "0x12345678" or "_fallback"
.set FN_NAME, 8             # str
.set FN_COLOR_NAME, 16      # str
.set FN_ABI_NAME, 24        # str
.set FN_ABI, 32             # (name, inputs) - the abi entry
.set FN_INPUTS, 40          # list of (type, name), or 0 until known
.set FN_TRACE, 48
.set FN_ORIG_TRACE, 56
.set FN_PARAMS, 64          # list of (idx, kind, name): the inferred params
.set FN_CONST, 72           # value, or 0 (None)
.set FN_READ_ONLY, 80
.set FN_PAYABLE, 88
.set FN_GETTER, 96          # value, or 0
.set FN_RETURNS, 104        # list
.set FN_AST, 112            # list, or 0
.set FN_IS_REGULAR, 120
.set FN_PRINT, 128          # the printed text (str), once printed
.set FN_PRIORITY, 136       # the priority + 2, once computed (0 = not yet)
.set FN_SIZEOF, 144

# ordered dicts (pyutil.s)
.set OD_KEYS, 0             # a vec
.set OD_VALS, 8             # a vec
.set OD_MAP, 16             # key -> index + 1
.set OD_SIZEOF, 24

# a contract (contract.s)
.set CT_FUNCS, 0            # a vec of functions (FN_*)
.set CT_STOR_DEFS, 8        # list of ('def', name, loc, type)
.set CT_CONSTS, 16          # a vec of the constant functions, in display order
.set CT_PROBLEMS, 24        # list of the names of the functions that failed
.set CT_SIZEOF, 32
