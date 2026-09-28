# panoramix-asm — design notes

An x86-64 assembly port of the [panoramix](https://github.com/palkeo/panoramix)
EVM decompiler. The only Python left is a thin CPython wrapper
(`src/pymod.c`) that hands the bytecode to the library and returns the text.
The library depends on libc, GMP (integers) and, for the signature
database, liblzma. Everything else is assembly (GNU as, Intel syntax).

## Layout

    include/defs.inc      constants, struct offsets, macros (read this first)
    include/opcodes.inc   generated: OP_* ids of the well-known strings
    src/rt_mem.s          thread contexts, arena allocator, compaction, GMP memory hooks
    src/rt_simd.s         the ISA detection and the vector loops (long hashes)
    src/rt_node.s         values, tuples/lists (hash-consed), big ints, value_import
    src/rt_str.s          global string interning, arena strings, builders, formatting
    src/rt_print.s        python-repr-like printing of values (tests, debug)
    src/rt_parse.s        python literals -> values (the tests)
    src/rt_log.s          logging (coloredlogs' format)
    src/rt_err.s          errors: python's exceptions (err_catch / err_throw)
    src/rt_map.s          pointer-keyed hash maps, memo tables
    src/rt_vec.s          growable arrays
    src/rt_io.s           files
    src/pyutil.s          python's sorts (CPython's comparison order), ordered dicts, sets
    src/matcher.s         the pattern matcher (matcher.py), PAT literals
    src/loader.s          bytecode -> instructions, jumpdests, push values
    src/funcs.s           function discovery (Loader.run)
    src/arith.s           256-bit arithmetic, is_zero, eval_bool (core/arithmetic.py)
    src/algebra.s         add_op, mask_op, lt_op, ge_zero... (core/algebra.py, variants.py)
    src/masks.s           to_mask, find_mask (core/masks.py)
    src/stack.s           the symbolic stack (stack.py)
    src/vmnode.s, vm.s    the symbolic VM (vm.py): nodes, jump tables of the opcodes
    src/whiles.s          loops to whiles (whiles.py)
    src/memloc.s          memory locations (core/memloc.py)
    src/simplify_exp.s    simplify_exp and its helpers
    src/loops.s, cleanup.s, rewriter.s, simplify.s   the simplifier (simplify.py, postprocess.py)
    src/folder.s          the folder (folder.py)
    src/sigs.s            signatures as the printer needs them, get_param_name, colors
    src/sigdb.s           the signature database: abi_dump.xz -> a flat mmap'ed file
    src/prettify.s, pretty_line.s   the printer (prettify.py)
    src/function.s        Function (function.py)
    src/sparser.s         the storage (sparser.py)
    src/contract.s        Contract (contract.py)
    src/decompiler.s      decompile(): the thread pool, the contract's text (decompiler.py)
    src/api.s             the C interface (pan_*, include/panoramix_asm.h), exported
                          by build/libpanoramix_asm.so
    src/main.s            the `panasm` command line tool
    src/pymod.c           the CPython module `panoramix_asm`
    src/testapi.s         the hooks of the differential tests (`panoramix_asm._test`)
    tools/gen_opcodes.py  generates opcodes.inc / opcodes_table.s
    tests/                comparisons with the python implementation

Build: `make` (needs python3 headers for the module). `build/panasm`
is the CLI, `build/panoramix_asm*.so` the module.

    panasm build-db panoramix/data/abi_dump.xz    # once: the signature database
    panasm decompile contract.hex [-j N] [--function NAME] [--no-color]
    python3 -c 'import panoramix_asm; print(panoramix_asm.decompile(open("contract.hex").read()))'

## Conventions

- System V ABI everywhere. `r15` = the thread context (`CTX_*`) in all
  the decompiler code; it is never used for anything else. Code called
  back by foreign code (GMP's memory hooks) gets the context from a
  pthread key (`ctx_current`).
- `ENTER`/`LEAVE` give a standard frame with rbx, r12, r13, r14 free and
  the stack 16-byte aligned; `sub rsp, 16*k` for locals.
- Values are tagged words: `(n << 1) | 1` small ints, otherwise a node
  pointer (16-byte aligned), 0 = NIL. Nodes: 16-byte header (kind, aux,
  hash) + payload. See defs.inc.
- Tuples and lists are hash-consed per thread (`mk_seq`): equal
  structures are the same pointer, so structural equality is `cmp`,
  and memo tables can be keyed by pointer. Strings are interned
  globally, big ints (`K_INT`, GMP mpz inside) per context (the same
  table as the tuples), small ints are inline. Only the process-wide
  constants (made on the global context) need `values_equal`.
- Memory: each function is decompiled on a context of its own, whose
  arena (4 MiB chunks, bump allocation) holds every node it makes; GMP's
  allocations are routed to it. The context is freed at once when the
  function is done: its chunks go back to a pool (zeroed where they were
  used), where the next contexts take them from - fresh pages cost a
  fault each, which was half of the time on the bigger contracts; new
  chunks are aligned on 2 MiB and advised as huge pages. Text results
  are malloc'ed and freed by the caller (`pan_free`).
- Opcode strings (tuple heads like `add`, `mask_shl`, `if`...) carry an
  id in their node (`N_AUX`), so dispatch on a tuple's opcode is a jump
  table: `opcode_of(v)` then `JT_SWITCH` / `JT_CASE` / `JT_END` (a table
  of 32-bit offsets the assembler builds from the cases), and a
  membership test is a byte table (`OPSET_MEMBER` / `OPSET_END`,
  `IN_OPSET`, `OPSET_FUNC`). `LOADS reg, NAME` loads the string node of
  an opcode.
- `FUNC` functions are hidden; `API` ones (api.s) are the exported C
  interface.

## Errors, threads, strings

- Where python raises, `err_throw(code, msg)` unwinds to the innermost
  `err_catch` (setjmp-like, `rt_err.s`); every place python has a
  try/except has one. The test entry point reports them as
  `<exc code: message>`. Two come from the runtime: `E_RECURSION`
  (python's `RecursionError`) from `STACK_CHECK`, at the entry of every
  recursive function (`tools/recursion.py` finds them: the cycles of
  the call graph, callbacks included, and `make check` verifies that
  none lacks it), when the stack gets within 1 MiB of its end; and
  `E_MEMORY` (`MemoryError`) when a function's context passes
  `CTX_MEM_LIMIT`. A third one is python's time limit of a function
  (a SIGALRM there): a watchdog thread (`rt_watch.s`) takes the stack's
  limit of a worker past its deadline away, and the next `STACK_CHECK`
  throws `E_TIMEOUT` - which the handlers of python's `except
  Exception` let through, as python's `TimeoutInterrupt` is a
  `BaseException`. Where python lets an exception through (the
  postprocessing), `decompile_run` catches it and the text is the
  error's message; the decompilation runs on a thread of its own, with
  a stack as big as the workers' (64 MiB).
- `decompile()` runs the functions on a pool of threads: each function
  gets a context of its own, and its trace is imported into the main
  thread's context (`value_import`: hash-consed again, big ints copied)
  as soon as it is done, then the worker's arena is freed. The loader
  is shared read-only; strings are global (a spinlock).
- Two kinds of strings: interned ones (global, forever: opcodes, names
  that go into expressions - equal text, same node) and arena strings
  (`str_new`: the text being built for display, freed with the arena).
  Anything compared by pointer inside expressions must be interned.
- Python's floats appear in a few places (2 ** shl below zero, in
  prettify and sparser's mask_to_mul); they are carried as the interned
  text of their repr, flagged `STR_FLOAT` (printed bare, parsed from the
  tests' literals), which is all that is done with them.
- The top byte of a node's hash holds the "mention" flags (`HF_MEM`,
  `HF_MSIZE`, `HF_STORAGE`): which of these words a value contains
  anywhere in its tree. A string gets them when it is made (one
  table-driven pass over its text, which also gives `STR_VOLATILE`),
  `hash_seq` ORs them up. `mentions(exp, HF_x)` is what python does with
  `"mem" in str(exp)` (a walk, every time): the simplifier asks it
  millions of times.
- The folder (`fold_isolated`) runs on a context of its own too: python
  slices its lists of paths at every level and frees the slices, an
  arena keeps them (n nested ifs: n^3 bytes), so its garbage goes with
  that context, and past 1 GiB (700 nested ifs, where python stops at
  a RecursionError) the trace is left unfolded, as python does when
  folding fails. The corpora's folds take 24 MiB at most.
- Python's floats: `2 ** k` for a negative k (the masks' printing), as
  the shortest decimal that reads back as the double (`float_repr`,
  python's repr), carried as a string flagged `STR_FLOAT`.
- The variants of an expression (`add_ge_zero`) substitute all the
  variables at once (`replace_many`), an outer expression before the ones
  it contains; python did them one by one in the order of a set, so its
  answer depended on the hash seed (fixed on the python side too).

## Roadmap

1. [x] runtime: arena, hash-consing, ints, strings, logging, printing
2. [x] loader: disassembly (identical to `Loader.disasm()` on the corpus)
3. [x] literal parser (python repr subset) for the tests
4. [x] arithmetic: 256-bit EVM semantics, `is_zero`, `eval_bool`...
5. [x] masks + algebra (`add_op`, `mask_op`, `lt_op`, `ge_zero`...)
6. [x] symbolic stack (`Stack.simplify` / `cleanup`)
7. [x] VM: nodes, symbolic execution, loops, merges, path conditions
8. [x] function discovery, signature database (xz + json -> flat file)
9. [x] whiles, simplify passes, folder, prettify, storage naming
10. [x] threads: one per function, shared read-only loader
11. [x] `decompile()` in the module, CLI parity with `python -m panoramix`
12. [x] vectorization where it pays, chosen from the ISA at run time
    (`rt_simd.s`: cpuid + xgetbv; `PANORAMIX_ISA=scalar|avx2|avx512`
    forces a level). What pays is little: the profile is tree walks over
    small tuples (pointer chasing) and the hash-consing of them, and the
    only long loops are the hashes of the traces (lists of hundreds of
    lines), done 8 elements a step with AVX-512 (`vpmullq`,
    `vpgatherqq`, `vprolq`) or 4 with AVX2, and the scan of the text of
    every string made for the mention flags (`str_scan_flags`: the
    printed lines, hundreds of bytes), 32 bytes a step with AVX2 - the
    positions where the first two bytes of one of the names are, found
    with `vpcmpeqb` and checked one by one (a third of the scalar
    loop's instructions). The wins came from the algorithms instead,
    see below.
13. [x] memory: the hash-cons table gives one node per distinct value on
    a thread, and `ctx_compact` drops the garbage of the rewrites between
    the rounds of `simplify_trace` once the arena passes 256 MiB (the
    trace is copied into a fresh arena, the comparison memos with it).
    Sharing the table across threads (a lock-free one, with a global
    arena) was considered and rejected: `mk_seq` is the hottest
    function, and a global arena could never be freed per function,
    which is what keeps the memory bounded (~300 MiB per thread on the
    worst contracts of the corpus, where python takes GBs).

## Testing

`make check` runs the C example, `tests/run_corpus.sh`,
`tests/robustness.sh` and `tests/test_watchdog.py`. The first compares the 30 contracts of
`tests/corpus` (mainnet bytecode, see `SOURCES`) and the programs of
`tests/synthetic` (each one a difference the port had) with python's
output in their `expected` directories (pypy's `python -m panoramix`,
colors removed, with the signature database, which the script builds
from panoramix's `data/abi_dump.xz`). The second feeds it inputs that
must not take it down (thousands of nested ifs, a 20000-deep
expression, a function past its memory limit). The third checks that a
pass that would take forever (a random trace whose simplification
doubles an expression at every variable inlined) is cut at its deadline
by the watchdog, and cuts a real simplification at deadlines all along
it, with a compaction at every round (`PANORAMIX_COMPACT_MIB=1`, the
arena's size past which `simplify_trace` compacts): a compaction cut
midway puts the old arena back (`ctx_compact` has a handler), and every
call comes back whole or with the timeout, on a context that stays
sound. The corpus gives the same text with `PANORAMIX_COMPACT_MIB=1`.

`tests/difffuzz.py SEED COUNT` is a differential fuzzer: random
solidity-like programs (a selector dispatch; functions of storage and
memory writes, ifs, requires, loops, logs, calls, returns over random
expressions; for half of them internal functions, dynamic arrays,
calldata copies, static calls and the signed and modular operations)
decompiled by pypy and by the port, the texts compared, the programs
that differ kept in `build/difffuzz`; with `--mutate`, small contracts
of the corpora with a few instructions changed instead. It found the
loops without an exit condition, masks with offsets past 2^62, python's
floats in `Mask(-744, ...)`, the TypeErrors python raises on parameters
whose size is an expression (a crash here), and an `except
AssertionError` that caught everything. Python's timeouts make a case
inconclusive.

The random unit tests (`tests/test_algebra.py` - with `BIG=1`, masks
with numbers past 2^62 -, `test_arith.py`, `test_memloc.py`,
`test_stack.py`, `test_simplify_exp.py`, `test_prettify_random.py`,
`test_agz.py`: sums of many terms sharing variables, for `add_ge_zero`;
`test_trace_random.py`: random traces through every pass of the
simplifier and the whole `simplify_trace`)
take a seed; run over many seeds, they found the negative exponents of
`exp` (python's modular inverse), the order of the terms of a max
(python sorts them by `str()`, which has no quotes around a string), an
assertion of `flatten_adds`, a `try_add` that gives a number (python's
assertion in `add_op`, a crash here), rules of `simplify_exp` that
read numbers past 2^62 as small ones, conditions that simplify to None
(`mem[x len 0]`: python's `eval_bool` can't decide them, the port took
them for true) and the ValueError of a negative shift. The cases they found are kept in
their `REGRESSIONS` lists.

Every layer also has a differential test against the python
implementation on the corpus (`tests/test_*.py`, run with the system
python3, the module in `build/` and the python repository in
`$PANORAMIX_PY` or next to this one): the raw traces of the VM, the
functions found, the whiles, every simplifier pass on every corpus
trace, the folder, every sub-expression through prettify with every
combination of its flags, the function analysis, the whole contract
postprocessing. `tests/compare_output.py` compares the final text with
`decompile_bytecode`'s (both without the signature database);
`corpus/run_one.sh` produces the references with the database, from
pypy, to diff against `panasm decompile --no-color`.

Python's nondeterminism had to be removed on its side first (the order
of the terms of a max, the variants of an expression, the substitution
order of the variants, the names of unnamed inputs of a signature):
commits on the `fix-branch-pruning` branch of the python repository. Its
timeouts (60 s per step, 180 s per function) are scaled by
`PANORAMIX_TIMEOUT` there, so that a reference can be made without
the timeouts pypy hits and the assembly doesn't (Wyvern: 20x).

The whole corpus (30 contracts) decompiles identically to pypy's
references with the signature database; `panasm` takes 15.6 s of CPU
for all of them (one thread each) where pypy takes ~12 minutes.

A second corpus comes from the compiled artifacts npm packages ship
(`tests/corpus_from_npm.py`: OpenZeppelin 2/3/4, Uniswap v2/v3, Aave v3,
Gnosis Safe, 0x - 407 runtime bytecodes, from solc 0.5 to 0.8, with
libraries, mocks and proxies). All of them decompile identically to
pypy's output (70 s of CPU against 57 minutes), with one intended
difference:
python 3.11 (and pypy) refuse `str()` of an integer of more than 4300
digits, which `replace_mem` does on the lines of a trace, so python
fails on the functions that deploy a contract whose code is inlined
(`create2 ... code: 0x...`); the port prints them, exactly as python
does with `PYTHONINTMAXSTRDIGITS=0`. The fuzzer found another one:
`SHL` of two constants is `exp << off` in python's VM, which runs out
of memory (or overflows) for a shift of 2^255 before the result is
reduced to 256 bits; the port gives 0, and python reports the function
as a failure. And `BALANCE` of a constant address (`address(0x..).balance`)
makes python's VM slice an int (`addr[:4]`, a TypeError): the function
fails there, the port prints `eth.balance(0x..)`. Python's caches (`@cached`, dicts, sets) take `True` for `1`: a
storage of size 1 can come back from one as a storage of size `True`
(made from a boolean elsewhere), and its type can't be printed (an
AssertionError that ends the decompilation); the port, whose `True`
isn't the number 1, prints the `bool` of size 1. `SAR` of two constants
by 256 or more of a negative value names `UINT_255_NEGATIVE_ONE`, which
python's arithmetic doesn't define (a NameError): the port gives -1. A
string in memory data whose length is -64 to -95 makes python's
`pretty_memory` loop forever (its index goes back by as much as it goes
forward): the port raises the IndexError python raises for the longer
negative lengths.

`tests/test_threads.py` decompiles the corpus from several python
threads at once (each call with its own workers, 1 to 3) and compares
every text with the contract decompiled alone.

`tests/stage_compare.py contract.hex FUNCTION` finds the first stage of
python's `simplify_trace` whose port differs, replaying each stage on
python's input of that stage.

## Performance notes

Profiled with callgrind (`valgrind --tool=callgrind build/panasm ...`,
`callgrind_annotate --inclusive=yes`). What mattered, in order:
`"mem" in str(exp)` walks (the mention flags), the `required_after`
lists of `cleanup_vars` (a chain of maps), the variants of
`add_ge_zero` (evaluated with mpz scratches instead of built and
simplified), `hash_seq`/`seq_equal` without calls per element, the
walkers keeping a node whose elements came back unchanged
(`mk_seq_like`: 95% of the tuples built already existed), `try_add`
examining a term instead of building thirty patterns to compare with
it. What is left is python's own algorithms: `cleanup_vars` and
`cleanup_mems` rewrite the rest of the trace for every variable and
memory write (quadratic), and the printer.

Later, on Wyvern: `add_ge_zero` evaluates the terms of the sum by
groups that share no variable (the min and the max of each group over
its own variables' assignments, summed: the same tri-state as python's
3^k variants of the whole sum); the predicates `is_op_n`/`is_mul_int`
are leaves (60M calls with a frame each); `range_overlaps` is memoized
as python's `@cached` one is, and so are `try_add` and `mul_op` of two
terms (pure functions that python recomputes: `add_op` tries every pair
of its terms, at ~1000 instructions a pair); the memos of the functions
of two expressions hash the pair instead of making its tuple
(`memo2_get`); the pattern matcher's wildcards are compiled at startup
(the slot of the binding, the type) instead of their text read at every
match, and the hottest patterns (`('setmem', x, Any)` on every line)
are an opcode and arity check; `contains` skips the tuples that lack
the mention flags of what it looks for; the chunks of the pool are no
longer zeroed when released (up to 9% of the instructions, `memset` of
what had been used): `arena_alloc` zeroes the block it gives, in the
cache, and the nodes, vectors and strings, which are written whole,
take `arena_alloc_raw` (`PANORAMIX_POISON=1` fills the released chunks
with garbage instead, for the tests: the corpora give the same text
with it); the walker of the pure callbacks (`replace_f_memo`: the
trace is a DAG, hash-consed, that python walks as a tree at every round
of `simplify_trace`) remembers what each subtree gave, in one map per
context emptied by an epoch; `replace` skips the tuples that lack the
mention flags of what it replaces (a variable); the folder finds the
prefix and the suffix its paths share in one pass, and sorts its ors
with a merge sort. Without time limits (`PANORAMIX_TIMEOUT=0`: under
valgrind python's limits cut the simplification short, and the counts
of two builds weren't comparable), Wyvern went from 16.2G instructions
to 7.2G, zx_Exchange (the slowest of the npm corpus) from 58.6G to
43.2G.
