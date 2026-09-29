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
.set K_WILD, 7              # a compiled wildcard of a pattern (matcher.s): aux = slot | type << 8 | repeat << 16

# The top byte of a node's N_HASH holds "mention" flags: which of these
# strings the value contains, anywhere in its tree - what python tests with
# `"mem" in str(exp)` (a walk of the whole expression, every time).
.set HF_MEM, 1 << 56
.set HF_MSIZE, 1 << 57
.set HF_STORAGE, 1 << 58
.set HF_VAR, 1 << 59        # a ('var', ...): the string "var" itself (find_op_list's pruning)
.set HF_SETVAR, 1 << 60     # a ('setvar', ...): the string "setvar" itself (rename_var's)
.set HF_GOTO, 1 << 61       # a ('goto', ...): the string "goto" itself (whiles' goes_to)
.set HF_CONTINUE, 1 << 62   # a ('continue', ...): the string "continue" itself (find_conts)
.set HF_VOLATILE, 1 << 63   # a string naming volatile state (STR_VOLATILE: is_volatile)
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
.set CTX_DEADLINE, 168      # the watchdog's deadline, monotonic ns (0: none; rt_watch.s)
.set CTX_TIMED_OUT, 176     # set by the watchdog: CTX_STACK_LOW taken away
.set CTX_STACK_LOW_REAL, 184  # CTX_STACK_LOW meanwhile
.set CTX_LV_SET, 192        # a scratch set (an emap, reused: line_vars, vec_extend_unique), or 0
.set CTX_DATA_SB, 200       # a builder for python's decompilation.json (data.s), or 0
.set CTX_DATA_MODE, 208     # its form: DATA_BINARY (0) or DATA_JSON (1)
.set CTX_RV_MAP, 216        # rename_var's memo (an emap, reused: cleanup.s), or 0
.set CTX_VERBOSE, 224       # python's --verbose / --explain: VB_ASM, VB_EXPLAIN (explain.s)
.set CTX_EXPLAIN_SB, 232    # the builder --explain prints into (malloc'd), or 0
.set CTX_EXPLAIN_PREV, 240  # the trace explain() printed last (python's prev_trace), or 0
.set CTX_EXPLAIN_FIRST, 248 # the first trace explained in this context, or 0
.set CTX_EXPLAIN_CUT, 256   # the builder's length after that first one's text
.set CTX_ASM_SB, 264        # a scratch builder for the lines of assembly (vm.s), or 0
.set CTX_FOLD_THREADS, 272  # the threads fold_many may use (folder.s; 0 or 1: none)
# 280..295: free
.set CTX_VM, 296            # the VM this thread runs (vm.s)
.set CTX_ERR_BUF, 304       # the innermost error handler (rt_err.s)
.set CTX_ERR_CODE, 312      # what was thrown
.set CTX_ERR_MSG, 320
.set CTX_FUNC, 328          # the function being printed (sigs.s, function.s)
.set CTX_STACK_LOW, 336     # the lowest rsp the recursions may reach (0: no limit)
.set CTX_MEM_LIMIT, 344     # the bytes the arena may take (0: no limit)
.set CTX_EVAL_POOL, 352     # 32 scratch mpz_t, one per depth, for variant_eval
.set EVAL_POOL_DEPTH, 32
.set CTX_ARENA_PEAK, 352 + 32 * MPZ_SIZEOF     # the most the arena took
.set CTX_CHILD_LIMIT, CTX_ARENA_PEAK + 8        # CTX_MEM_LIMIT of the contexts it makes
.set CTX_MEMO, CTX_ARENA_PEAK + 16              # the memo tables, 32 slots (see MEMO_*)
.set CTX_AGZ, CTX_MEMO + 32 * 8                 # 8 scratch mpz_t for add_ge_zero's sums
.set CTX_SIZE, CTX_AGZ + 8 * MPZ_SIZEOF

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
.set E_MEMORY, 8            # python's MemoryError: the arena passed CTX_MEM_LIMIT
.set E_RECURSION, 9         # python's RecursionError: the stack passed CTX_STACK_LOW
.set E_VALUE, 10            # python's ValueError
.set E_KEY, 11              # python's KeyError

.set ARENA_CHUNK_DEFAULT, 0x400000     # 4 MiB
.set COMPACT_THRESHOLD, 0x10000000      # 256 MiB of arena: simplify_trace compacts

# arena chunk header
.set CHUNK_NEXT, 0
.set CHUNK_SIZE, 8          # the whole mapping
.set CHUNK_USED, 16         # the payload bytes used (once the chunk isn't the current one)
.set CHUNK_DATA, 32
.set HUGE_PAGE, 0x200000   # 2 MiB: the chunks of the default size are aligned on it
.set CHUNK_POOL_MAX, 256    # chunks of ARENA_CHUNK_DEFAULT kept for reuse (1 GiB)
.set CHUNK_POOL_KEEP, 16    # kept between two decompilations (64 MiB)

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

# API name: an exported function (the C interface of the library,
# include/panoramix_asm.h); everything else is hidden
.macro API name
        .text
        .globl \name
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

# STACK_CHECK: at the entry of every recursive function (the cycles of the
# call graph, see tools/recursion.py): E_RECURSION instead of running off
# the thread's stack. Threads that decompile set CTX_STACK_LOW
# (ctx_set_stack) a margin above the end of their stack.
.set STACK_MARGIN, 0x100000             # 1 MiB: what the deepest non-recursive calls need
.macro STACK_CHECK
        cmp rsp, [r15 + CTX_STACK_LOW]
        jb stack_overflow
.endm

# tagged small int helpers
.macro TAG reg
        lea \reg, [\reg + \reg + 1]
.endm

.macro UNTAG reg
        sar \reg, 1
.endm

.include "opcodes.inc"

# --- jump tables: a switch on a small integer (an opcode id, a kind, a
# byte) instead of a chain of compares ---
#
#       call opcode_of
#       JT_SWITCH ge_zero, OP_COUNT, .Lgz_none     # eax: the value
#       JT_CASE ge_zero, OP_MUL, .Lgz_mul
#       JT_CASE ge_zero, OP_ADD, .Lgz_add
#       JT_END ge_zero, OP_COUNT, .Lgz_none        # the table (after its cases)
#
# JT_SWITCH jumps to the label of eax's case, or to the default when eax
# (unsigned) is above `bound` or has no case; it clobbers rax and rcx.
# The table holds 32-bit offsets from itself, in .rodata: no relocation
# at load time. The cases may come in any order; the names are local to
# the file.

.macro JT_SWITCH name, bound, default
        cmp eax, \bound
        ja \default
        lea rcx, [rip + .Ljt_\name]
        movsxd rax, dword ptr [rcx + rax*4]
        add rax, rcx
        jmp rax
.endm

.macro JT_CASE name, value, label
        .altmacro
        JT_CASE_ \name, %(\value), \label
        .noaltmacro
.endm

.macro JT_CASE_ name, id, label
        .set .Ljt_\name\()_\id, \label
.endm

.macro JT_ENTRY_ name, default, i
        .ifdef .Ljt_\name\()_\i
        .long .Ljt_\name\()_\i - .Ljt_\name
        .else
        .long \default - .Ljt_\name
        .endif
.endm

.macro JT_END name, bound, default
        .section .rodata
        .align 4
.Ljt_\name:
        .set .Ljt_i, 0
        .rept \bound + 1
        .altmacro
        JT_ENTRY_ \name, \default, %(.Ljt_i)
        .noaltmacro
        .set .Ljt_i, .Ljt_i + 1
        .endr
        .text
.endm

# Sets of small integers (opcode ids...), as a byte per value:
#
#       OPSET_MEMBER array_ops, OP_CALL_DATA
#       OPSET_MEMBER array_ops, OP_CODE_DATA
#       OPSET_END array_ops, OP_COUNT               # the label .Lset_array_ops
#       ...
#       lea rcx, [rip + .Lset_array_ops]
#       movzx eax, byte ptr [rcx + rax]             # 1 for a member

# IN_OPSET name, idx64: the flags of `cmp member, 0` - jne when idx is
# in the set (idx at most the bound); clobbers rcx
.macro IN_OPSET name, idx
        lea rcx, [rip + .Lset_\name]
        cmp byte ptr [rcx + \idx], 0
.endm

# OPSET_FUNC fname, name: fname(id) -> eax: 1 when the id (edi) is in
# the set `name`, else 0
.macro OPSET_FUNC fname, name
FUNC \fname
        xor eax, eax
        mov edi, edi
        cmp edi, OP_COUNT
        ja 1f
        lea rax, [rip + .Lset_\name]
        movzx eax, byte ptr [rax + rdi]
1:      ret
ENDF \fname
.endm

.macro OPSET_MEMBER name, value
        .altmacro
        OPSET_MEMBER_ \name, %(\value)
        .noaltmacro
.endm

.macro OPSET_MEMBER_ name, id
        .set .Lset_\name\()_\id, 1
.endm

.macro OPSET_ENTRY_ name, i
        .ifdef .Lset_\name\()_\i
        .byte 1
        .else
        .byte 0
        .endif
.endm

.macro OPSET_END name, bound
        .section .rodata
.Lset_\name:
        .set .Ljt_i, 0
        .rept \bound + 1
        .altmacro
        OPSET_ENTRY_ \name, %(.Ljt_i)
        .noaltmacro
        .set .Ljt_i, .Ljt_i + 1
        .endr
        .text
.endm

# LOADS reg, NAME: load the interned string node for opcode NAME
# OP_N_CHECK op, n, fail: falls through if rdi is a tuple of n elements
# (n > 0, a register or an immediate) with opcode op (a register or an
# immediate); jumps to fail otherwise. Only rax is used.
# OPCODE_INLINE src, dst32, tmp: opcode_of(src) without the call (the id
# of a tuple's head string, 0 for anything else); src kept, tmp clobbered
.macro OPCODE_INLINE src, dst32, tmp
        xor \dst32, \dst32
        test \src, 1
        jnz .Lopi_done\@
        test \src, \src
        jz .Lopi_done\@
        cmp dword ptr [\src + N_KIND], K_TUPLE
        jne .Lopi_done\@
        cmp dword ptr [\src + N_AUX], 0
        je .Lopi_done\@
        mov \tmp, [\src + N_DATA]
        test \tmp, 1
        jnz .Lopi_done\@
        test \tmp, \tmp
        jz .Lopi_done\@
        cmp dword ptr [\tmp + N_KIND], K_STR
        jne .Lopi_done\@
        mov \dst32, [\tmp + N_AUX]
        and \dst32, STR_ID_MASK
.Lopi_done\@:
.endm

# OPCODE_OF_RDI: `call opcode_of` inline - eax the opcode id of the tuple
# rdi, 0 for anything else; like the call, only rax (and the flags)
# change
.macro OPCODE_OF_RDI
        test dil, 1
        jnz .Loor_zero\@
        test rdi, rdi
        jz .Loor_zero\@
        cmp dword ptr [rdi + N_KIND], K_TUPLE
        jne .Loor_zero\@
        cmp dword ptr [rdi + N_AUX], 0
        je .Loor_zero\@
        mov rax, [rdi + N_DATA]
        test al, 1
        jnz .Loor_zero\@
        test rax, rax
        jz .Loor_zero\@
        cmp dword ptr [rax + N_KIND], K_STR
        jne .Loor_zero\@
        mov eax, [rax + N_AUX]
        and eax, STR_ID_MASK
        jmp .Loor_done\@
.Loor_zero\@:
        xor eax, eax
.Loor_done\@:
.endm

# IS_SEQ_RDI: `call is_seq` inline - eax 1 if rdi is a tuple or a list,
# else 0; like the call, only rax and rcx (and the flags) change
.macro IS_SEQ_RDI
        xor eax, eax
        test dil, 1
        jnz .Lisq_done\@
        test rdi, rdi
        jz .Lisq_done\@
        mov ecx, [rdi + N_KIND]
        sub ecx, K_TUPLE
        cmp ecx, K_LIST - K_TUPLE
        setbe al
.Lisq_done\@:
.endm

.macro OP_N_CHECK op, n, fail
        test dil, 1
        jnz \fail
        test rdi, rdi
        jz \fail
        cmp dword ptr [rdi + N_KIND], K_TUPLE
        jne \fail
        cmp dword ptr [rdi + N_AUX], \n
        jne \fail
        mov rax, [rdi + N_DATA]
        test al, 1
        jnz \fail
        test rax, rax
        jz \fail
        cmp dword ptr [rax + N_KIND], K_STR
        jne \fail
        mov eax, [rax + N_AUX]
        and eax, STR_ID_MASK
        cmp eax, \op
        jne \fail
.endm

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
.set EMAP_EPOCH, 24         # an emap's current epoch (rt_map.s)
.set EMAP_SIZEOF, 32

# memo tables in the context (created lazily by memo_table)
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
.set MEMO_REPLACE_MEM_EXP, 12  # (a map of triples: memo3_get)
.set MEMO_RANGE_OVERLAPS, 13
.set MEMO_SIGDB, 14         # selector -> abi entry (sigdb.s)
.set MEMO_IMPORT, 15        # value_import: a VM node -> its copy here
.set MEMO_LINE_VARS, 16     # a line -> the ('var', ...) in it (cleanup_vars' required_after)
.set MEMO_TRY_ADD, 17       # (self, other) -> try_add's result (sp_none for None)
.set MEMO_MUL2, 18          # (a, b) -> mul_op(a, b)
.set MEMO_PARSE_COUNTERS, 19 # a while -> its PC struct (read only)
.set MEMO_EXTRACT_SETMEMS, 20 # a while -> extract_setmems' list
.set MEMO_OVERWRITES, 21    # (an if or a while, mem_idx) -> overwrites_mem's (pairs)
.set MEMO_IS_ZERO, 22       # a tuple -> is_zero of it
.set MEMO_ARITH_EVAL, 23    # a tuple -> arith_eval of it
.set MEMO_RFM, 24           # (exp, f) -> replace_f_memo's result (pairs)
.set MEMO_RFS, 25           # (exp, f) -> replace_f_stop_memo's result (pairs)
.set MEMO_CLEANUP_MEMS, 26  # (trace, used_after) -> cleanup_mems' result (pairs)
.set MEMO_PP_CLEANUP, 27    # a list -> pp_cleanup_mul_1 of it, a tuple -> pp_cleanup_exp of it
.set MEMO_REPLACE_MEM, 28   # (trace, mem_idx, mem_val) -> replace_mem's list (triples)
.set MEMO_MEMLOC_OVERWRITE, 29 # (memloc, split) -> memloc_overwrite's list (pairs)
.set MEMO_COUNT, 30
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
.set ND_STAMP, 120          # the VM's generation when it or a node below last changed (node_touch)
.set ND_VC_JD, 128          # merge_visit's answer for its subtree: the jd asked (0: none),
.set ND_VC, 136             #   and the stamp then << 2 | the answer (MC_*)
.set ND_JUMP, 144           # node*: an ancestor, for vm_common_ancestor's skips (see there)
.set ND_SIZEOF, 152

.set VM_LOADER, 0
.set VM_JUST_FDESTS, 8
.set VM_COUNTER, 16         # for the _1, _2... names
.set VM_KNOWN, 24           # tuple: what holds at the current point of _run
.set VM_STACK, 32           # vec: the symbolic stack of _run
.set VM_TRACE, 40           # vec: the trace _run builds
.set VM_NODE_COUNT, 48
.set VM_TIME_START, 56      # CLOCK_MONOTONIC nanoseconds
.set VM_TIMEOUT, 64         # nanoseconds, 0 = none
.set VM_SCR_VISIT, 72       # find_nodes' stack (a vec, reused; 0 until needed)
.set VM_SCR_ALL, 80         # merge_branches' scratch, reused at every round: the nodes,
.set VM_SCR_NEXT, 88        #   the next index at the same jd (-1: the last),
.set VM_SCR_HEADS, 96       #   the (first, last) index of each jd,
.set VM_SCR_BYJD, 104       #   jd -> its group + 1 (an emap)
.set VM_SCR_UNEXP, 112      #   and the nodes not run yet
.set VM_LOOPS, 120          # the nodes replace_loops made loops, for continue_loops (a vec)
.set VM_CLEAN, 128          # the bottom of the stack stack_cleanup leaves alone (see there)
.set VM_GEN, 136            # the generation of the nodes' changes (node_touch), from 1
.set VM_VISITED, 144        # 1: merge_visit remembered an answer since the last one began
.set VM_STALE_DEPTHS, 152   # 1: a node with children was hung elsewhere (vm_common_ancestor)
.set VM_CHECK_LCA, 160      # 1: PANORAMIX_CHECK_LCA - both walks, compared (vm_common_ancestor)
.set VM_SIZEOF, 168

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

# python's "--verbose" / "--explain" in sys.argv (CTX_VERBOSE; explain.s)
.set VB_ASM, 1              # the lines of assembly in the VM's traces (both)
.set VB_EXPLAIN, 2          # the traces printed at every stage (--explain)
.set VB_REPR, 4             # each function's trace after its text (--repr)
.set VB_RETURNS, 8          # each regular function's returns after it (--returns)

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
.set CT_PROBLEMS, 24        # list of (hash, name) of the functions that failed
.set CT_STOR_FAILED, 32     # the storage postprocessing failed (python's stor_defs = {})
.set CT_SIZEOF, 40
