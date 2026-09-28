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
    src/api.s             the C-callable entry points (pan_*)
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
  globally. Big ints (`K_INT`, GMP mpz inside) are compared by value
  (`values_equal`), small ints are inline.
- Memory: each thread has an arena (mmap'ed chunks, bump allocation)
  holding every node made while decompiling one function, and GMP's
  allocations are routed to it. `arena_reset` frees it all at once.
  Text results are malloc'ed and freed by the caller (`pan_free`).
- Opcode strings (tuple heads like `add`, `mask_shl`, `if`...) carry an
  id in their node (`N_AUX`), so dispatch on a tuple's opcode is a jump
  table: `opcode_of(v)` then `jmp [table + rax*8]`. `LOADS reg, NAME`
  loads the string node of an opcode.

## Errors, threads, strings

- Where python raises, `err_throw(code, msg)` unwinds to the innermost
  `err_catch` (setjmp-like, `rt_err.s`); every place python has a
  try/except has one. The test entry point reports them as
  `<exc code: message>`.
- `decompile()` runs the functions on a pool of threads: each function
  gets a context of its own, and its trace is imported into the main
  thread's context (`value_import`: hash-consed again, big ints copied)
  as soon as it is done, then the worker's arena is freed. The loader
  is shared read-only; strings are global (a spinlock).
- Two kinds of strings: interned ones (global, forever: opcodes, names
  that go into expressions - equal text, same node) and arena strings
  (`str_new`: the text being built for display, freed with the arena).
  Anything compared by pointer inside expressions must be interned.
- Python's floats appear in two places (2 ** shl below zero, in
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
    `vpgatherqq`, `vprolq`) or 4 with AVX2. The wins came from the
    algorithms instead, see below.
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

Every layer has a differential test against the python implementation
on a corpus of `.hex` files (`tests/test_*.py`, run with the system
python3 and the module in `build/`): the raw traces of the VM, the
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
references with the signature database; `panasm` takes ~16 s for all of
them on two cores where pypy takes ~12 minutes.

A second corpus comes from the compiled artifacts npm packages ship
(`tests/corpus_from_npm.py`: OpenZeppelin 2/3/4, Uniswap v2/v3, Aave v3,
Gnosis Safe, 0x - 407 runtime bytecodes, from solc 0.5 to 0.8, with
libraries, mocks and proxies). All of them decompile identically to
pypy's output (67 s against 57 minutes), with one intended difference:
python 3.11 (and pypy) refuse `str()` of an integer of more than 4300
digits, which `replace_mem` does on the lines of a trace, so python
fails on the functions that deploy a contract whose code is inlined
(`create2 ... code: 0x...`); the port prints them, exactly as python
does with `PYTHONINTMAXSTRDIGITS=0`.

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
