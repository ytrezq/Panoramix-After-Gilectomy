# The C++23 decompiler - design notes

`cxx/` is an EVM decompiler in C++23 (g++-14, `-std=gnu++23`): an
idiomatic, high-level re-implementation of this repository's x86-64
assembly decompiler (`../src/*.s`, `../docs/DESIGN.md`), itself a port of
the python decompiler panoramix. It prints a contract's functions in
panoramix's language, in the asm's display style: the command line
`pancxx`, the python module `panoramix_cxx` (and the same module named
`panoramix_asm`, in `$(B)/compat/`, for the repository's scripts).

## What it is

A re-implementation, not a transliteration: the asm and python are
references for the algorithms - what to find, in which order, with which
caps - and for the display, not for the exact output. What python did with
text is done on the structure (an operation is an integer in a node's
header, "reads memory" a bit of its hash, a pattern a `switch`, a sort the
structural order); where its algorithms were quadratic or unsound they
were replaced (forward and backward walks instead of a rewrite of the
trace per variable, sums compared as integers only under a proven no-wrap
condition, induction variables proven), and its rewrites that execution
doesn't confirm are off.

The user's rules, binding here, are `AGENTS.md`'s: no string processing
but the contract's own strings (opcodes, names, flags are integers;
True/False/None immediates; nothing ordered by text); every parser a Ragel
machine (6.10, `-G2`), the bytecode decoded over its opcode bytes as NaCl's
validator decodes x86, `switch` on integer ids elsewhere; the standard
library's threads, POSIX only in `*_posix.cpp`; always the same flags
(`-march=native -mtune=native -Ofast -flto -fmerge-all-constants -fweb`,
PGO on top), sanitizers only in the debug build, no floating point, no
reliance on distinct addresses of constants; correctness by execution;
doctest; the command line and the python module kept (without `_test`),
the C API and the JSON free; the protections against hostile contracts
kept; high-level C++ (RAII, value types, `std::optional`, `std::variant`,
structs instead of tuples, an exception hierarchy).

Validated by execution: the bytecode runs in evmone, the decompiler's
result in this project's own interpreters, on the same calls against the
same world, and the effects must agree - return data or revert, storage
written, logs, external calls and creations. The result is every stage's
trace, from the VM's raw trace to the folded ast (the trace machine,
`src/exec/`), and the printed text, parsed back (`validate/text_*`). A
difference is the bug of the first stage that shows it; an exhausted
budget, a path the VM left unfinished or a construct a machine can't run
makes a call inconclusive, never "the same". The asm's texts are a
reference for readability only.

A main session wrote the core, the shared files (`src/core/`,
`spec/ops.def`, the Makefile) and the integration; about twenty workers
wrote the rest, each owning a directory: the twelve lots the comments
name, the evmone harness, the typed calldata, the text parser and
interpreter, the signature database, the front ends, the build.

| lot | directory | |
|---|---|---|
| 1 | `src/evm/` | the decoder |
| 2 | `src/algebra/` construct, eval, masks, linear | normal forms, concrete evaluation |
| 3 | `src/algebra/` ranges, compare, facts | ranges, decisions, path facts |
| 4 | `src/mem/` | the memory model |
| 5 | `src/vm/` | the symbolic VM, discovery, recursive internal functions |
| 6 | `src/loops/` | whiles, loop summaries, induction, loop rewrites |
| 7 | `src/simplify/` | the simplifier, the effect summaries |
| 8 | `src/analysis/` | the function traits, SafeMath |
| 9 | `src/storage/` | the storage analysis |
| 10 | `src/output/` | the folder, the printer, the JSON, --explain |
| 11 | `src/exec/`, `validate/stage_check*` | the trace machine, stagecheck |
| 12 | `src/driver/` | the pipeline, the jobs, the limits |

Dependencies: GMP and gmpxx, liblzma (the signature dump), python3's
headers (the module); g++-14, GNU make, ragel 6.10 and python3 to build.
Vendored in `third_party/` at pinned versions, each with a NOTICE (origin,
version, license, local changes): doctest v2.5.3; evmone v0.24.0 with the
evmc of its tree (ABI 19) and intx v0.15.0, for the validation only (never
in `pancxx` or the module; one local change, `EVMONE_FIXED_GAS`: GAS
pushes a constant, the one the trace machine reads); sha256-simd (commit
df94ecd9, the repository's only one),
whose Go assembly `src/sha256_*.S` translates into GNU as - nothing of it
is compiled.

## Layout

Paths relative to `cxx/`.

    AGENTS.md, BUILD.md, DESIGN.md  the user's rules; the build; this file
    Makefile, .gitignore    the build (every source found by a glob); build*/ ignored
    ../spec/evm.def         the EVM's instructions (the asm's): immediate, stack words, fork
    ../spec/ops.def         every operation of the IR: number, name, arity, sort, properties

    src/decompile.hpp       the library's interface: decompile(), Decompilation, the log
    src/main.cpp, cli.hpp, cli.rl  pancxx: panasm's commands and options (Ragel readings)
    src/pymod.cpp           the python module, compiled as panoramix_cxx and panoramix_asm
    src/hex.hpp, hex.rl     hex text into bytes, the first thing done to any bytecode; escapes
    src/fetch.hpp, fetch.rl an address's code from a node (web3's provider, JSON-RPC)
    src/net.hpp, net_posix.cpp, io.hpp, io_posix.cpp  sockets; files, streams, signals
    src/log.cpp, version.hpp, version.cpp  the log lines; the version and build flags
    src/sigdb.hpp, sigdb.cpp, sigdb_impl.hpp  the signature database: format, build, lookups
    src/sigdb_dump.rl, sigdb_type.rl  the dump's JSON lines; ABI type texts (Ragel)
    src/sigdb_posix.cpp     the mapping, the cache directory, the write-then-rename
    src/sha256.hpp, sha256.cpp  SHA-256: the block function chosen by cpuid, generic code
    src/sha256_{shani,avx2,avx,ssse3}.S, sha256_asm.h  sha256-simd's blocks in GNU as

    src/core/               the core (main's), namespace pan
      base.hpp, smallvec.hpp, sync.hpp  integer aliases, hints; SmallVec, Tri; SpinLock
      ops.hpp               Op, OpInfo, info(), has(), op_name() (over ops_gen.hpp)
      value.hpp, node.hpp   Value, NodeHeader, the kinds, NameKind; payloads, content hashes
      context.hpp, context.cpp  Arena, chunk pool, HashCons, PcMap, Context, mk*, Importer
      memo.hpp              Memo, MemoSet, Key2/Key3, MemCharge, ModuleState
      budget.hpp, budget.cpp, env.rl  limits, the environment (Ragel), Budget, check_stack
      errors.hpp            the exception hierarchy
      evmint.hpp, evmint.cpp  EvmInt (python's ints on gmpxx), Word256 (EVM words)
      intops.hpp, value_int.cpp  python's arithmetic on int Values; ints to and from Values
      order.hpp, order.cpp  compare(), StructuralLess
      dump.hpp, dump.cpp, sexpr.rl  S-expressions: dump(), dump_trace(), parse_sexpr()
      platform.hpp, platform_posix.cpp  threads, stacks, clock, memory, mappings, fork
      watchdog.hpp, watchdog.cpp, jobs.hpp, jobs.cpp  the watchdog; parallel_for
      contract.hpp          ContractShared, ParamInfo, EntryCondition, FunctionInfo...

    src/evm/                lot 1, the decoder
      decoder.hpp, decoder.cpp  Bitset, Insn, BlockEnd, Idiom, CodeMap, analyse(), metadata()
      analysis.rl           the linear pass: the CodeMap
      listing.rl, exec_ref.rl  every instruction in order; a block through a callback
      metadata.rl, classes.rl  the CBOR metadata tail; (tests) the class of each opcode
      text.cpp              disasm and decode: panasm's texts

    src/algebra/            lots 2 and 3, namespace pan::alg
      construct.hpp, construct.cpp  the normal-form constructors, apply(), normalize()
      eval.hpp, eval.cpp    eval_op() (the word operations), eval_const(), Evaluator
      masks.*, linear.*     MaskShl, mask constants, bit bounds; the linear form of sums
      ranges.*, compare.*   intervals of words (Range, Top); decisions (Tri), eval_bool
      facts.hpp, facts.cpp  path facts: a persistent list

    src/mem/memory.hpp, memory.cpp  lot 4: widths, ranges, MemState, fill, splits

    src/vm/                 lot 5, namespace pan::vm
      vm.hpp, vm.cpp, entry.hpp  the raw trace's format; discover(), run_function()
      vm_impl.hpp           Node, Link, End, LoopVar, CallMerge, Vm
      vm_exec.rl            the exec machine with the VM's handlers
      vm_core.cpp, vm_rounds.cpp  a node's run, handlers, effects; the rounds, make_trace
      discover.cpp          the dispatcher's run: selector tests, entry conditions

    src/loops/              lot 6, namespace pan::loops
      loops.hpp, internal.hpp, util.cpp  make_whiles(), Induction, LoopSummary; helpers
      whiles.cpp, analysis.cpp, rewrite.cpp  whiles; summaries, inductions; the rewrites

    src/simplify/           lot 7, namespace pan::simplify
      simplify.hpp, internal.hpp  simplify_exp(), simplify_trace(), the passes; helpers
      effects.hpp, effects.cpp  EffectSummary, summary(), affects(), independent()
      simplify.cpp          the driver: rounds, final passes, compaction
      exp.cpp, lines.cpp    simplify_exp's local rules; the line-level rules
      vars.cpp, mems.cpp, conds.cpp  cleanup_vars; cleanup_mems; cleanup_conds, min_ifs
      passes.cpp            the other passes of python's _simplify_trace

    src/analysis/           lot 8
      traits.hpp, traits.cpp  params, payable, read_only, const, getter
      safemath.hpp, safemath.cpp  SafeMathTable; checked arithmetic made SAFEMATH calls

    src/storage/            lot 9
      storage.hpp, internal.hpp  StorageType, StorageVar, StorageLayout; Access...
      analyse.cpp, paths.cpp  the analysis, the rewrite; slot paths, hashes as numbers
      types.cpp, forms.cpp  types and packed variables; the printed forms
      check.*, regroup.*, getters.*  forms checked; split stores regrouped; getters
      names.hpp, names.rl   whether a getter's name names its variable (Ragel)
      semantics.cpp         locate(): the forms on concrete values

    src/output/             lot 10, namespace pan::output
      output.hpp, print.hpp the entries; Out, names, Printer
      fold.hpp, fold.cpp, ast.cpp  the folder; make_ast, ast_stage
      ast_passes.cpp        the ast's own passes; the text's view
      exp.cpp, lines.cpp, names.cpp  expressions; lines and loops; names from the ids
      contract.cpp, json.cpp, text.cpp, output.cpp  the contract's text; JSON; numbers
      escape.rl             text from outside made printable (Ragel)

    src/exec/               lot 11: machine.hpp, machine.cpp (the trace machine), keccak.cpp

    src/driver/             lot 12, namespace pan::driver
      pipeline.hpp, internal.hpp  Stage, ContractResult, run_pipeline(); Run, messages
      pipeline.cpp          the run: discovery, jobs, waves, contract phase
      decompile.cpp, api.cpp  decompile(): thread, context, limits, outputs; the interface

    validate/               the validation by execution, namespace validate
      Makefile.inc          evmone's sources and flags, the tools
      world.*, session.*, precompiles.cpp  the world; a call against it; precompiles
      effects.*, evm_runner.*  Effects and compare(); evmone over a Session
      calls.*, probe.cpp, scan.*  the planned calls; selectors by probing; scans (Ragel)
      abi_encode.*          typed calldata from the database (AbiEncoder)
      evmrun.cpp            evmrun: a bytecode's calls in evmone
      stage_check.*, stagecheck_main.cpp  check_contract(), SessionHost; stagecheck
      text_lexer.*, text_lines.hpp, text_parser.*, text_ast.hpp  the text parsed (Ragel)
      text_interp.*, text_check.*, text_check_main.cpp  the text run; text_check

    tests/                  doctest suites and black-box tests
      main_test.cpp core_test.cpp evm_decoder_test.cpp evm_dfa_proof.py ranges_test.cpp
      algebra_a_construct_test.cpp algebra_a_eval_test.cpp mem_model_test.cpp
      mem_corpus_test.cpp vm_basic_test.cpp vm_corpus_test.cpp output_print_test.cpp
      loops_{whiles,analysis,rewrite,fuzz,corpus}_test.cpp storage_{forms,analysis,corpus}_test.cpp
      simplify_{exp,trace,dump,scratch}_test.cpp traits_basic_test.cpp safemath_basic_test.cpp
      exec_machine_test.cpp stagecheck_session_test.cpp driver_pipeline_test.cpp
      sigdb_test.cpp sha256_test.cpp cli_test.cpp hex_test.cpp fetch_test.cpp
      validate_{world,effects,runner,calls,abi}_test.cpp validate_test_util.hpp
      text_parser_test.cpp text_interp_test.cpp
      cli_surface.py pymod_surface.py driver_robustness.py driver_threads.py

    tools/
      gen_ops.py, gen_grammar.py  spec/*.def -> ops_gen.hpp; evm.def -> evm_grammar.rlh
      gen_storage_htab.cpp  the storage's hash table -> htab_gen.hpp
      corpus.py, bench.py   the CLI over a corpus (and PGO's training); the asm compared

    third_party/            each with its NOTICE and LICENSE
      doctest/ evmone/ evmc/ intx/  doctest v2.5.3; evmone v0.24.0, its evmc; intx v0.15.0
      sha256-simd/          the Go sources of src/sha256_*.S (not compiled)

    $(B)/gen/               generated (shared by a build's variants)
      src/core/ops_gen.hpp, src/evm/evm_grammar.rlh  the op table; the decoder's grammar
      src/**/*.cpp, validate/*.cpp  ragel -G2's output of each .rl
      tools/gen_storage_htab, src/storage/htab_gen.hpp  the generator; the hash table
    $(D)/obj/               objects and stamps (D: $(B), $(B)/debug, $(B)/pgo)

A build makes `libpanoramix_cxx.a`, `pancxx`, `panoramix_cxx<EXT_SUFFIX>`,
`compat/panoramix_asm<EXT_SUFFIX>`, `pancxx_test`, `libvalidate.a`,
`libevmone.a`, `evmrun`, `stagecheck`, `text_check`, and `sigdb2.bin`
(`make sigdb`).

## Conventions

- **Values** (`core/value.hpp`) are one 64-bit word:

      ...1      a small signed int, 63 bits: v = i64(w) >> 1
      ...0000   a node pointer, 16-aligned; 0 is NIL ("no value", never None)
      ...010    an immediate: [15:3] ImmKind, [31:16] sub, [63:32] payload

  The immediates are Bool, None, Name(kind, id) and Leaf(op, n), an
  operation without operands whose n numbers a call's result
  (`Leaf(CALL_SUCCESS, 3)`) or a read equal to no other (each GAS read).
- **Nodes** (`core/node.hpp`): a 16-byte header {u16 kind, u16 op, u32
  size, u64 hash}, then the operands (EXPR), items (LIST, whose op says
  values or trace), limbs (BIGINT) or bytes (BYTES). The hash is
  content-based, the same in every context and run; its top byte holds the
  content flags (F_MEM F_MSIZE F_STORAGE F_STATE F_VAR F_CALLDATA F_LOOPCTL
  F_WRITES), the OR of the operands' and the op's: python's `"mem" in
  str(exp)`, a walk, is `v.has_flags(F_MEM)`.
- **Operations are integers** (`core/ops.hpp`): an EVM instruction is its
  byte (ADD 0x01, SSTORE 0x55) with the IR's operands (SHA3 takes byte
  expressions, a call's first operand is its id), the decompiler's ops are
  0x100-0x1ff. `info(op)` (O(1), any u16) gives the arity, the sort, the
  property bits (COMM, ASSOC, R_* reads, W_* writes, HALT, CONTROL,
  NUMBERED...) and the content flags derived from them, generated by
  `tools/gen_ops.py` from `spec/evm.def` and `spec/ops.def` (the build
  fails on an unknown name, a duplicate, a decompiler op below 0x100;
  numbers are never reused). Code dispatches with `switch (v.op())`;
  `op_name()` is for dumps and the printer, which keeps its own
  precedences (`OpInfo::prec` is 0).
- **Names are integer ids** (`NameKind`: TMP, LOOP, MSIZE_VAR, PRECOMPILE,
  PARAM, STORVAR, FUNC, FALLBACK, INTERNAL, LOOP_ID, SAFEMATH_PARAM), read
  as themselves (`ADD(Name(TMP, 3), 1)`), text only when printed. The
  contract's strings are BYTES nodes, the database's names raw bytes, both
  escaped when printed; no `std::regex`, nothing keyed or sorted by text.
- **Parsers are Ragel machines** (`src/X.rl` -> `$(B)/gen/src/X.cpp`): the
  decoder's, the environment's, the S-expressions, the command line, hex,
  a node's answers, the signature dump and its types, getters' names,
  escapes, the CBOR metadata; in `validate/` the scans, the tools'
  options, the printed text's lexer and parser.
- **Integers only**: PANORAMIX_TIMEOUT is read in thousandths, limits are
  integer nanoseconds, python's float `2 ** -k` prints as a division.
- **Determinism**: the output depends on the code and the database only -
  values ordered by `compare()`, never by pointer; memo tables never
  iterated for output; parallel results placed by index.
- **Errors** (`core/errors.hpp`):

      std::exception
      +-- Error                 the decompiler's: the stages catch them
      |   +-- Unsupported       an analysis can't: the stage degrades
      |   +-- InvalidInput      malformed input
      |   +-- InternalError     a broken invariant (a bug)
      |   +-- LimitExceeded
      |       +-- MemoryLimit   a function's memory (PANORAMIX_MAX_MEMORY)
      |       +-- DepthLimit    recursion too deep for the stack
      |       +-- SizeLimit     a structural cap (nodes, bytes, a shift)
      +-- Abort                 not an Error: `catch (const Error&)` lets it by
          +-- Timeout           the watchdog's

  A job catches Error, Abort and `std::bad_alloc` ("out of memory: the
  system gave no more"): its function becomes a problem, the others go on;
  what fails the contract phase fails the decompilation (`DecompileError`).
- **Threads**: the standard library's; the system is behind
  `core/platform.hpp`, `io.hpp`, `net.hpp`, `sigdb_impl.hpp`, implemented
  in `*_posix.cpp` (a MinGW port adds `*_win32.cpp`, the Makefile picking
  the platform's files).
- **Protections in the code**: `check_stack()` at the entry of every
  function recursing on the input, `poll()` in loops over nodes, lines and
  rounds, caps from `limits` (the asm's values) - the stages' rules; no
  tool checks them as the asm's `recursion.py` does.

## The core

**Contexts and arenas** (`core/context.hpp`). A Context is an Arena, a
HashCons table, a Budget, a PcMap, the contract's read-only
`ContractShared` and the modules' states; each function, the discovery,
each fold and the contract have their own. The current one is `cx()`, a
`thread_local` set by an RAII `ContextScope`; `mk(op, args...)` (arity
checked), `mk_list`, `mk_int*`, `mk_bytes` make nodes on it, and
`mk_like(orig, args)` returns `orig` when nothing changed, so a walk that
changes nothing returns the same Value (fixpoints and memos rely on it).
The arena bumps through 4 MiB chunks freed with the context, from a
process-wide pool (256 kept, 16 after a decompilation): 2 MiB-aligned
huge pages, reused without zeroing (`alloc()` zeroes, `alloc_raw()`'s
callers write all), each charged to the budget before it is mapped.

**Hash-consing.** Open addressing, a slot the node's pointer (48 bits) and
16 bits of its hash: every node goes through it, so `==` is structural
equality and a Value keys a memo. The global context is a frozen first
layer: `init()` interns the frequent big constants (2^k, 2^k - 1, -2^k
for k in 62, 63, 64, 128, 160, 192, 224, 255, 256), then nothing writes it
and every table looks it up first, lock-free.

**Imports and compaction.** Values never cross contexts by pointer: an
`Importer` rebuilds one on `cx()`, memoized by source word (a shared
subtree once). A job imports its FunctionInfo at its start (reading
immutable nodes, never another context's table) and its results into the
contract's context at its end, under a mutex, with no deadline.
`Context::compact(roots)` moves a context to a fresh arena - the roots
imported, each module state kept (`compact_prepare`) or dropped, the PcMap
re-keyed, the old arena put back on an exception; the simplifier compacts
between rounds past `compact_threshold()` (PANORAMIX_COMPACT_MIB, else
min(256 MiB, a quarter of the limit)).

**Memo tables** (`core/memo.hpp`): `ctx.state<T>()` makes a module's state
on first use, `clear_caches()` is python's; `Memo<K, V>`, open addressing
keyed by a Value or a `Key2`/`Key3` of raw words, never erased, is
charged to the context's budget. Per context: no locks.

**The budget** (`core/budget.hpp`) bounds a job's memory, stack and time.
Memory: a `CountingResource` (`std::pmr`) throws MemoryLimit before it
takes bytes past the limit - `resource()` for per-job containers,
`charge()` for chunks and tables. Stack: `attach_thread()` sets a mark at
the thread's stack low bound plus min(1 MiB, half the stack), and
`check_stack()` is one compare of the stack pointer with it (DepthLimit);
`poll()` is the same, for loops. Time: the watchdog's `expire()` raises
the mark to the top, so the next check throws Timeout - a deadline costs
nothing on the hot path. `half_budget()` halves what is left (the asm's
phases). `core/env.rl` reads the environment once; `scaled_timeout(base)`
is base x factor (128 bits; none at 0 or less); `job_memory_limit` is
PANORAMIX_MAX_MEMORY, else the machine's memory (the cgroup's if lower) /
(threads + 1), 1 GiB at least.

**The watchdog** (`core/watchdog.hpp`), python's SIGALRM: one thread,
started by the first `Watchdog::Watch` and never destroyed, waking every
50 ms while a watch (an intrusive list) is linked; past a deadline it
calls `expire()` once, under the lock `~Watch` takes too, so a budget only
has to outlive its watch. A forked child forgets its parent's watches.

**Jobs** (`core/jobs.hpp`): `parallel_for(n, threads, fn)` runs `fn(i)` on
min(threads, n, 1024) threads - the caller's and workers with 64 MiB
stacks - from an atomic index; `fn(i)` stores its result at index i, so
nothing depends on the thread count; the first exception is rethrown
after the joins; `fn` sets up its own budget and context. As the caller
works too, `decompile()` runs on a thread with a worker's stack: on an
8 MiB main thread a job could hit DepthLimit where a worker wouldn't.

**The platform** (`core/platform_posix.cpp`): `spawn(fn, stack_size)`
keeps the asm's 64 MiB stacks with `std::thread` by setting the default
thread attributes around its constructor, under a lock, and blocks the
asynchronous signals in the new thread - chosen over bounding the
recursion depth, which would fail 4000 nested ifs earlier than the asm.
Also stack bounds, clock, memory (the cgroup's limit), peak RSS, CPUs,
huge-page mappings, fork handlers (the chunk pool's and `spawn`'s locks
held across a fork; the watchdog reset in the child).

**Integers** (`core/evmint.hpp`): `EvmInt` is python's int - an inline
i64, an `mpz_class` only past it - with floor division and shifts and
two's complement bitwise ops; shifts, exponents and mask widths past 2^20
bits throw SizeLimit, so no number of the contract reaches GMP unclamped.
`Word256` (four limbs, `mpn_*`, `__int128`) has the yellow paper's
operations in EVM stack order (`shl(shift, x)`; x / 0 = 0).

**Order and dumps.** `compare()` (`core/order.hpp`) is the structural
order - NIL < ints < False < True < None < Leaf < Name < Bytes < Expr <
List, then by contents - wherever python sorted by `str`. `dump()` and
`dump_trace()` write S-expressions (`(add 1 (mask_shl 160 0 0 caller))`,
`{...}` for a trace) that `parse_sexpr()` (`sexpr.rl`) reads back: the
tests build values with `V("...")`.

**The plan's choices, and why.** The current context is a `thread_local`,
not a parameter: constructors run deep in recursions, and a job runs on
one thread. A line's pc is kept beside it (`PcMap`), not as an operand:
equal lines stay one node, which the folder's sharing of prefixes by
pointer needs. Call results are numbered by call id, so the IR never says
"the last call". The core declares only what several lots share
(`core/contract.hpp`): the storage layout, the SafeMath table and the
contract's result are their lots'.

## The decoder

The front ends make the hex bytes (`hex.hpp`) first; the bytes are
decoded as NaCl decodes x86, by Ragel automata made from a description of
the instructions. `gen_grammar.py` writes `$(B)/gen/src/evm/evm_grammar.rlh`
from `spec/evm.def`: `insn`, an alternative per opcode (a PUSHn's n bytes
firing `$imm_byte`), whose last byte fires its class's action
(`insn_plain`, `insn_push`, `insn_dup`, `insn_swap`, `insn_jump`,
`insn_jumpi`, `insn_jumpdest`, `insn_halt`, `insn_unknown`), which each
consumer defines before the include: one grammar, several machines.

- `analysis.rl` (51 states), the linear pass, makes the `CodeMap`, all
  that persists besides the bytes: bitmaps of instruction starts,
  jumpdests (not a 0x5b of push data) and static destinations, the idioms
  (NaCl's superinstructions: PUSH then JUMP or JUMPI, solc's DUP1 PUSH4
  EQ PUSH JUMPI), the free memory pointer set first, a push the end cuts,
  static jumps to a non-JUMPDEST, where the CBOR metadata starts.
- `listing.rl` and `exec_ref.rl` (33 states, the start their only final
  state): the instructions in order, and a block through a callback - the
  skeleton of `vm/vm_exec.rl`. Entered at any instruction start, they
  decode as the linear pass does.
- `metadata.rl` (71 states) reads the CBOR tail (the contract's `Lang`).

A cut push reads zeroes; an unknown byte ends a block as the EVM's
invalid; past 2^32 - 1 bytes every entry throws SizeLimit.
`tests/evm_dfa_proof.py` (in `make check`) proves the automata on `ragel
-x`'s output as the asm's `verify_dfa.py` does: totality, each
instruction's class on its last byte and back to the start, the idioms
exactly where `../tools/evm_spec.py`'s patterns end. `disasm` and `decode`
are byte-identical to panasm's on the 1121 corpus contracts and 1535 other
codes; the analysis takes 4.9-6.0 ns/byte on Seaport15 (lot 1).

## What the stages share

**The algebra** (lots 2, 3). Every expression is built by its
constructors in normal forms - flattened sums with the constant first and
the terms in `compare()` order, products `MUL(k, ...)`, every mask a
canonical `MASK_SHL(size, off, shl, x)`, ISZERO pushed through
comparisons - so the same operations on the same operands are the same
node; `apply(op, args)` is the VM's entry. A constructor never changes the
value (lot 2's property tests); `eval_op` is the one definition of the
word operations, shared with the trace machine. `linear(v)` reads a sum
as `constant + sum(coeff * term) mod 2^256`, an integer only when a range
proves it can't wrap: `range(v, top, facts)` holds v's word for every
value of its leaves, so `x + 1 > x` stays undecided until something like
`x < 10` is known. `Top::Word` assumes only what every execution
guarantees (calldatasize, gas, msize below 2^64) and is all the VM's
pruning uses; `Top::Memory` adds that a memory address's words are below
2^64 but what the contract is given unchecked. Decisions are `Tri`.
`Facts` - a path's conditions, known memory, bit lengths - are a
persistent list in the arena: a child path adds one in O(1). A variable's
value enters a decision only when stable (one value, no state read).

**The memory model** (lot 4, `src/mem/memory.hpp`). Every byte element
carries its width (`SIZED(n, v)`), never guessed from a mask. Ranges are
compared under `Top::Memory`; `overlaps`, `contains`, `overwrites` answer
Tri, an unknown being a "may", so an unresolved read stays a MEM read.
`MemState`, forward known memory, keeps a piece only while no later write
may change what it reads (msize never kept); `fill` makes a read a DATA of the
writes' slices; `split_setmem`, `split_store` take a line and give lines.

**The effect summaries** (lot 7, `src/simplify/effects.hpp`) answer "may
this line change what that expression reads" for lots 6, 7, 8 and 10: per
node, memoized, the state classes read and written (memory, msize,
storage, transient, accounts, call results, gas, variables, logs,
calldata, context) with their places (ranges, slots, keys, names, call
ids; "anywhere" past 32) and how the paths end; `affects`, `independent`
(the folder's hoisting), `ends`, `storage_may_alias` are conservative.

## The pipeline

`driver::run_pipeline(code, options)` (`src/driver/pipeline.hpp`) runs a
contract through the stages into a `ContractResult`; `run_until` stops at
a stage; `driver::decompile()`, behind `pan::decompile`, runs it all and
makes the outputs.

| stage | made by | where |
|---|---|---|
| Raw | lot 5's VM: IF, LABEL / GOTO | the jobs |
| Whiles | lot 6: WHILE / CONTINUE | the jobs |
| Simplified | lot 7 (python's orig_trace) | the jobs |
| Analysed | lot 8's traits; lot 9's storage forms (python's func.trace) | the jobs; the contract phase |
| Folded | lot 10's asts, then lot 8's SafeMath (python's func.ast) | the contract phase |

What a trace loses and execution needs is kept beside it
(`core/contract.hpp`): a `FunctionInfo` has its kind, selector, entry pc,
`EntryCondition`, params (`ParamInfo`: the calldata offset `Name(PARAM,
k)` reads, ABI kind, bits), call sites, loops, traits, problem and trace;
an `EntryCondition`, the selector, the checks that held on the
dispatcher's path (facts, never evaluated again), the non-payable check
lot 8 takes out of the body with its halting line (`value_fails`), and the
dispatcher's lines before the body (`entry_lines`). A `ContractResult`
has, per stage, the same functions in the same order (the dispatcher's,
the fallback; internal functions by entry), the problems, the storage
layout and the SafeMath table.

**Discovery**: the VM on the dispatcher alone (`vm::discover`), on a
context of its own with half a function's memory and (60 + 180) s scaled.
A selector test is recognised on the JUMPI's condition (EQ or XOR of the
selector word with a 4-byte number, their difference, ISZERO negations,
Vyper's AND / OR, `iszero(selector)`), its paths giving the
EntryCondition; the fallback is where no selector leads (lot 5: the asm's
selectors on 1121 of 1121 contracts). A failed discovery logs python's
"Loader issue: ..." and leaves the fallback alone.

**Jobs**: one per function (`--function`: those whose name starts with
it) on `parallel_for`, each with its own budget (a function's memory, 180
s scaled), watch and context: `vm::run_function`,
`loops::whiles_function`, `simplify::simplify_function`,
`traits::analyse_function`, the deadline checked between them, each
stage's FunctionInfo imported into the contract's context at the end.
**Waves**: the recursive internal functions a wave found that aren't known
yet (by entry) are the next wave - python's semantics. **Problems**: a
function failing at a stage keeps the traces before it, has no trace from
it on, and its `problem` indexes `ContractResult::problems` (job order):
"Problem with NAME: message" in the log, `I failed with these:` in the
text, the other functions going on.

**The contract phase**, on the contract's context: lot 9's storage (half
of what the limit leaves; on an Error, python's "Storage postprocessing
failed. This is very bad!" and the raw forms), lot 10's asts (a context
per function, on threads), lot 8's SafeMath (on an Error, "SafeMath
failed: the arithmetic stays as it is."), the `StageObserver` for the
stage checks. Under `decompile()` it has the asm's limits (base + imports
+ one function's) and deadline (180 s scaled), then `print_contract`
(each function's text on a thread), `to_json`, the disassembly.

### The VM (lot 5, `src/vm/`)

The VM (python's vm.py) explores a function's paths as a tree of nodes,
breadth first by rounds. A node is a block (start pc, symbolic stack, the
path's `alg::Facts`, lines, its `End`, children); the tree's links are a
contiguous `Link` array (parent, depth, a skew-binary jump pointer for
O(log n) ancestors, the subtree's stamp and summary), so walks up don't
read the nodes. A block runs in `vm_exec.rl`, lot 1's grammar with the
VM's handlers inlined (pure ops push `alg::apply(op, args)`, effects are a
`switch`). A JUMPI is decided by `alg::eval_bool(cond, facts)`: only
branches no execution takes are pruned. A round (20 of 200 steps at most)
runs the frontier, finds loops (an ancestor at the same pc, stack length
and jumpdest words) and recursive internal functions, makes loops LABEL /
GOTO with loop variables and merges branches that meet again; the asm's
subtree summaries, generation stamps and an incremental frontier spare
the merges' walks (`PANORAMIX_VM_CHECK=1` checks them against python's
full walks). Past 20000 nodes (5000 with a frontier over a sixteenth of
them, 5000 for the dispatcher) or 60 s scaled, the paths left end in
`UNDEFINED(UNFINISHED, pc)`.

The raw trace (`vm.hpp`): SETVAR, SETMEM(RANGE(p, n), v) with explicit
widths, STORE, TSTORE, LOGs, numbered calls and creations, PRECOMPILED,
INTERNAL; IF with both branches; LABEL(Name(LOOP_ID, k), setvars) and
GOTO, the setvars simultaneous; the halts, LEAVE, UNDEFINED(reason, pc). A
call's results are `Leaf(CALL_SUCCESS, id)`, `Leaf(RETURNDATASIZE, id)`,
`RETURNDATA_BYTES(id, off, len)`, `Leaf(CREATE_ADDRESS, id)`; when paths
whose last calls differ merge and the return data is read after, a
`CallMerge` sets a temporary on each path and a copy becomes an IF on the
id. State reads an SSTORE, TSTORE or call may change are snapshotted into
variables before it; an expression past 150 nodes gets a variable; GAS
reads are numbered; a CODECOPY of at most 1024 known bytes is read from
the code; a push past 1024 words is `INVALID(STACK_OVERFLOW)`;
`--verbose` adds ASM lines. A recursive internal function (a jump to an
ancestor's start with its return address on the stack) is decompiled
apart, its params `Name(PARAM, k)`, its calls INTERNAL lines, its returns
LEAVE.

### Loops and whiles (lot 6, `src/loops/`)

`make_whiles` makes each LABEL and its GOTOs `WHILE(cond, body, id,
setvars)` with `CONTINUE(id, setvars)`: `while True` with the exits inside
(always equivalent), or python's nicer form when equivalent - the exit
test the first IF after the label with a branch looping back, the lines
before it rotated only when they set no loop variable, hold no jump and
change nothing a setvar reads (a copied call keeps its id), the exit's
merge variables renamed or the exit run after the loop, a loop left only
by a failing check `while not check`. A GOTO outside its LABEL is
Unsupported, as python failed. `summary(while)` gives a loop's variables,
names set, effects, the memory an iteration may write and read, breaks;
`induction()` is python's parse_counters as a proof (a counter, a
constant step, an invariant bound), with trips and end values only when
the counter can't wrap. The rewrites are sound by construction:
`loop_to_setmem` (zero fills, copies whose source and destination can't
overlap the wrong way, calldata copies; under the path's facts; 0 or 1
trips unrolled), `propagate_storage_in_loops` (an exact change of
variables), `rename_var`. On the corpus (lot 6, before its second round):
14,281 loops, 95.5% with a `while cond`; 3,353 trip counts proven of
10,659 counters.

The second round (triage issue 8, `analysis.cpp`, `rewrite.cpp`) gave
`loops_to_setmems` the path's facts (IF conditions and requires, each
dropped once a line changes what it mentions; the trip count's no-wrap
proof also uses the memory model's bounds: `require len <= 2^32`, then a
copy to `ceil32(len) + k`), sets each loop variable's last value before
the single memory write (solc <= 0.5's `while idx >= 32` copies whose
length is read from memory the copy overwrites), accepts addresses and
bounds read from memory when the loop's writes over all its iterations
provably miss what they read, and gives `LoopSummary::mem_writes` one range
over all iterations for writes at the free memory pointer (the simplifier
trusts it: mem[64] stays known past such loops). Copy-loop lines printed
in the corpus: 1,403 in 164 contracts before, 1,055 in 92 after (the asm:
242 in 19); `while` lines 11,071 -> 10,144 (the asm: 7,645); stagecheck
folded on the 153 contracts concerned, 0 different at every stage.

What stays a loop is mostly a copy into a fresh allocation at mem[64] from
a pointer loaded from memory - an earlier allocation (UniversalResolver's
abi.decode copies, zx_Coordinator's `bytes[]` signatures, most of
zx_Exchange): that the two don't overlap follows from solc's allocation
discipline (earlier allocations lie below the current mem[64]), which the
loop alone can't show. The asm converts them with python's unchecked rule,
which execution showed unsound on overlapping copies; no assumption is
made here instead. Future work, with the simplifier: carry a lower bound F,
mem[64] >= F, along the trace - kept where mem[64] is written with a value
proven at least its old one (solc's overflow checks give it) and across
writes and loops that provably miss [64, 96), F the new value; an ABI
check placing a source inside an earlier allocation puts it below F, and a
destination at or above F is then provably disjoint.

### The simplifier (lot 7, `src/simplify/`)

`simplify_trace` installs the trace's variables in the algebra, then runs
at most 40 rounds of python's passes in python's order until one changes
nothing (or 60 s scaled: less simplified, not wrong) - simplify_exps,
cleanup_vars, cleanup_mems, precompiled_results, min_ifs, split_lines,
cleanup_conds, loops_to_setmems... - then the final passes (max_to_add,
ABI arrays, fix_storages, readability); a pass given its last input
returns its last output. `simplify_exp` is python's local rules as a
memoized bottom-up rewrite, each rule tested by evaluation. `cleanup_vars`
is two walks, not a rewrite per variable: forward, a variable's value
replaces its reads (up to 150 nodes) where nothing since changed what it
reads; backward, unread SETVARs dropped. `cleanup_mems` likewise with
MemState (forward, reads replaced by what reaching writes wrote, under the
conditions known on the path; backward, unread writes dropped), changing
nothing a msize read would see. `cleanup_conds` keeps up to 32 known
conditions as facts and removes what they decide. Python's `small_words`
is made sound (`SmallWords`, `simplify.cpp`): a word the contract is
given counts as below 2^64 in memory positions only past a check bounding
it on the lines every execution that goes on runs. Off unless execution
confirms them (`SimplifyOptions::dubious`): python's rewrites known to be
unsound (postprocess_trace's `len % 32` branches assumed equal,
replace_var into setmems past clobbers).

### Traits (lot 8, `src/analysis/traits.hpp`)

`analyse_function` is python's Function(): the params (a known selector's
head words from its `Entry::known()` entry, else inferred from
`CALLDATALOAD(4 + 32k)`: masks give uintN, address, bytesN, a truth value
bool, an offset an array, solc >= 0.8's validation and its mask forms the
type), those reads then `Name(PARAM, k)`; `cleanup_masks` past a param's
validation; payable (the leading `if callvalue: revert`, or the
dispatcher's hoisted one, taken out: `nonpayable` and `value_fails`,
which the trace machine checks first); `read_only` (no write line);
`const` (read only, one RETURN of nothing that varies, one path);
`getter`. Internal functions are left alone.

### Storage (lot 9, `src/storage/`)

`storage::analyse` parses the slot of every access (`STORAGE` read,
`STORE` written) as a path from a variable - a root, a mapping
(keccak(key . slot); Vyper's slot . key), an array's data, offsets,
lengths - the hashes compilers write as numbers found in a table made at
build time (`gen_storage_htab.cpp`: keccak(n) for n < 4096, keccak(k . n)
for k < 16 and n < 64, both orders). The language is the CBOR metadata's,
else the mapping hashes' vote. Split stores are regrouped, types chosen by
most accesses, names taken from getters with a good name (`names.rl`).
The accesses become the printer's forms - `SV(Name(STORVAR, i))`,
`SI(base, key)`, `SL`, `SBL`, `SF(base, n)`, `SR(slot)` locations;
`ST(size, loc, width)` reads, `SET` writes, `SALL(loc)` bytes - each
checked: by `storage::locate`, which the trace machine runs too, the form
must denote the access's slot and bits in four worlds of random values
keyed by structural hash, else it is printed raw. A bytes getter becomes
`return name[all]` only when the trace machine runs both the same on
storage worlds. Everything is made aside and swapped in at the end.

### The folder and the ast (lot 10, `src/output/`)

`make_ast` runs on a context and budget of its own (1 GiB; past it, the
trace stays unfolded): the entry's checks and the SETMEMs the body may
read first, the ast passes, `short_circuits`, the folder. The folder is
python's - `as_paths` (the branchless paths, an IF followed by lines one
MERGED_IF item), `fold_paths` (what a level's paths share at their
beginnings and ends taken off, the rest grouped by first condition,
recursively, on stretches of the paths rather than copies: n^2 for n
nested ifs where python's slices cost n^3), `flatten`, `cleanup_ors`,
`make_ifs`, `merge_ifs` (hoisting by the effect summaries), `fold_aux` -
and a failed assert leaves the trace as it was. The ast passes keep the
text faithful where python's can't name what the IR numbers: a call's
result read where another call may have run since, and a gas read printed
with or after another, get a variable (python's snapshots: `_1 =
ext_call.return_data[0]`); an if whose branches differ only by call ids
is its lines; every `UNDEFINED(UNFINISHED, pc)` is one line. The ast stays
executable: REQUIRE, ASSERT, LAND, LOR, MERGED_IF are IR ops.

### SafeMath (lot 8, `src/analysis/safemath.hpp`)

`safemath::rewrite` makes checked arithmetic calls of `def SafeMath:`
functions (OpenZeppelin, ds-math, solidity >= 0.8's Panic(0x11) and
Panic(0x12), increments, Vyper): a run of checks (failing with
REVERT(None), an Error(string), a Panic or INVALID where their condition
holds) followed by a line using the checked result - past lines that
can't fail or change what the checks read, and checks failing the same
way - loses the checks, the result becoming `SAFEMATH(n, a, b,
messages...)`. A site's checks are abstracted over a and b and verified
on random values; equal sites are one function of the `SafeMathTable`.
Caps (8 checks a group, 512 lines of uses, 8 checks passed) only narrow
the search; an Error leaves every ast as it was.

### The printer (lot 10, `src/output/`)

The only place values become text, in the asm's display: python's
precedences and forms (`mem[a len n]`, `stor[...]`, Error and Panic
decoded, `log Event(...)` named by topic), `while` with sequential
setvars, names made from the ids (`_N`, NICE_NAMES, the ABI's names or
`_paramN`, storage names made unique). `Out` counts the characters
python's color codes take, so the functions' priority (self-destructing
first, then python's colored length) holds with `--no-color`. Text from
outside is escaped (`escape.rl`): the database's names keep their valid
UTF-8, their C0, DEL, C1, bidi controls and invalid bytes written `\xNN`;
a contract's bytes print as a literal only when text, `\\ \' \n \r \t`
escaped. The
`--explain` sections come from the jobs, in job order (1 GiB at most).
When printing, an if whose branches print the same and whose condition
can't fail prints as its then-branch.

## The signature database

`src/sigdb.hpp`: functions, events and errors by selector, from
panoramix's `abi_dump.xz`, built once into a file of our own format,
mapped and read in place (`Entry`, `Type`, `Field` are views into the
mapping). Version 2: a 136-byte header ("PANSIGDB", version, sections,
the dump's SHA-256, size, mtime, path), buckets `u32[2^B + 1]` by the
selector's top B bits (the entries' bit length - 4: 17 on panoramix's
dump), an index `{u32 selector, u32 record offset}`, the
records (kind, trust, an event's topic0, name, parameters' names and type
codes, indexed flags, the dump's type texts), a string pool. A type is a
prefix code: a byte for each elementary type, then arrays, tuples,
storage/memory/calldata references, named types. Opening is O(1): the
header and the sections' bounds; a bucket or a record is checked when a
lookup reads it.

**Trust.** A selector's entry is its best line: `verified` (it hashes to
the selector: python's fetch_sig), `repaired` (a variant does: IERC20 as
address, an enum as uint8, `T storage` without spaces...), else
`unverified`; among equals the last, as python. `Entry::known()` is
verified or repaired, and `event()` returns only those. The decompiler
names functions, params and storage variables from `known()` entries only
(`driver::function_name`, `traits.cpp`, `storage/analyse.cpp`,
`output/names.cpp`); the validation's AbiEncoder types calldata from any.
On panoramix's dump (the sigdb report): 1,535,063 lines; 1,146,310 entries
verified, 0 repaired, 388,708 unverified, 82,955 events; 51.3 MB (the
asm's file 97.7 MB), built in 3.7 s; 150-200 ns a lookup. The 388,708
unverified are all panoramix's placeholders `unknownXXXXXXXX(...)`,
236,019 with guessed types (used only to type the validation's calldata);
nothing needed repair: every real signature hashes, some only without
spaces (old libraries' `T storage`).

**Building** (`pancxx build-db`, the module's `build_signature_db`, `make
sigdb`): liblzma on a second thread, `sigdb_dump.rl` and `sigdb_type.rl`
(strict, and lenient for the repairs, `Builder::repair` trying up to 256
variants), the file written beside its place (`O_EXCL | O_NOFOLLOW`) and
renamed. It is $PANORAMIX_SIGDB, else $XDG_CACHE_HOME/panoramix/sigdb2.bin
or ~/.cache/panoramix/sigdb2.bin; `sigdb::get()` opens it once per
process, rebuilt first when its dump changed ($PANORAMIX_ABI_DUMP's, else
the recorded one: size and mtime, then SHA-256 by sha256-simd's code
chosen at run time), built when absent and $PANORAMIX_ABI_DUMP names a
dump. Without one, every function is unknown.

## Validation by execution

**The trace machine** (`src/exec/machine.hpp`, whose header defines the
IR's operational semantics) runs any stage's trace on `Word256`s. It is in
the library (lot 9 runs getters with it) and sees the world through a
`Host` (`validate::SessionHost` converts to intx; `SimpleHost` is in
memory). A call: dispatch by selector, else the fallback; the entry lines;
the non-payable check (`value_fails`); the body. It runs every line kind -
SETVAR, SETMEM, STORE, TSTORE, IF, WHILE, CONTINUE, BREAK, LABEL, GOTO,
LOGs, calls, creations, PRECOMPILED, INTERNAL (a fresh frame), LEAVE, the
halts, REQUIRE, ASSERT, MERGED_IF - storage forms through
`storage::locate`, SAFEMATH through lot 8's table, pure ops through
`alg::eval_op`; call results are records per id, `Name(PARAM, k)` the raw
calldata word at its offset. Outcomes: the four halts; Exhausted,
Undefined, Unsupported (inconclusive); Bug (a variable read before it is
set, a record never written...); byte elements without SIZED are counted.
Limits: 4 million steps, 16 MiB a byte string, 256 MiB of them, 32 MiB of
memory, 1024 nested INTERNAL calls (`MachineLimits`; lot 9's checks:
20000 steps, 1 MiB of memory).

**The evmone harness** (`validate/`). `SeededWorld` makes every value
keccak(seed, kind, key), empty or random, so answers don't depend on the
order of reads; `State` carries storage, balances, nonces and created
accounts along a sequence; `Session` is the one place where both sides
read the world and record effects, with the EVM's rules (value credited
first, light failures, a call to no code a success, precompiles
0x01-0x09 and 0x100 computed with evmone's code, CREATE addresses from
the nonce, SELFDESTRUCT per EIP-6780; not modelled: the caller paying,
address collisions, re-entrance). `EvmRunner`: evmone's baseline
interpreter, Osaka, 100M gas, GAS 30,000,000 on both sides. `compare()`:
same, different or inconclusive over the end, the storage diff and the
order of logs, calls, creations; exhausted is inconclusive. The calls:
selectors scanned (Ragel) and probed (the dispatcher run in evmone with a
tracer), 4 variants a selector, 3 fallback calls, values on 10%, callers
among the world's actors; `AbiEncoder` types the calldata of the selectors
the database knows (10% malformed on purpose). On the corpus (the
harness's report): 1121 contracts, 0 errors, deterministic; 45,307 calls
on the empty world, 45,311 on a random one.

**stagecheck** (`validate/stage_check.*`, `make stagecheck`): per
contract, with its own budget, context and watchdog, in parallel by
contract, one `driver::run_until` keeping every stage's traces, the
storage layout and the SafeMath table; the calls - sequences on the empty
world (each machine call from the state evmone's previous calls left) and
isolated calls on random worlds - by evmone and by the machine on each
stage. Per stage: the calls the same, different (end status, end data,
events, storage), the bugs, the unsized, the inconclusive (evmone, the
machine's limits, UNDEFINED, unsupported), and the first divergent stage.

**text_check** (`validate/text_*`): `text_lexer.rl` scans the printed text
into tokens in logical lines; `text_parser.rl`, 11 machines (statements,
expressions by an operator-precedence machine with explicit stacks,
signatures, blocks by indentation), makes a `Program` with integer names;
`text_interp` runs a call as the text says, through a Session; what the
text doesn't say precisely (msize, an aborted line...) is unsupported. The
text doesn't print where an unknown function's params are in calldata
(the user's decision: the display stays the asm's; the place is
`ParamInfo::calldata_offset`): `--params DIR` reads that side information
from files `0xSELECTOR OFFSET[:TYPE] ...` made from a decompiler's JSON;
without it param i is read at 4 + 32 i and its calls are counted apart.

**Milestones**: M1 the raw traces (lots 1-5); M2 whiles and simplified (6,
7); M3 traits, storage, SafeMath, folded asts (8, 9, 10); M4 the printed
text reparsed, and the CLI and module's parity (10, 12). The reports'
numbers, each from its own run and build (typed calldata unless said):

| stage | report | contracts | calls | same | different | bugs | inconclusive (evm / exhausted / undefined) |
|---|---|---|---|---|---|---|---|
| raw | lot 11, first M1, untyped | 1119 | 90,150 | 89,805 | 0 | 0 | 309 / 28 / 8 |
| raw | lot 11, first M1 | 1119 | 90,150 | 89,776 | 0 | 0 | 318 / 40 / 16 |
| raw | lot 3 | 1121 | 90,618 | 90,244 | 0 | 0 | 318 / 40 / 16 |
| raw, whiles | lot 5, after issue 2, untyped | 1121 | 90,618 | 90,273 | 0 | 0 | 309 / 28 / 8 |
| raw + memory model | lot 4's corpus test | 1121 | 90,618 | 90,244 | 0 | 0 | 374 |
| whiles | lot 6 | 1121 | 90,618 | 90,244 | 0 | 0 | 318 / 40 / 16 |
| simplified | lot 7 | 1121 | 90,614 | 90,243 | 0 | 0 | 315 / 40 / 16 |
| analysed | lot 8 | 1121 | | | 0 | 0 | |
| folded | lot 8 | 395 | 47,725 | 47,560 | 0 | 0 | 117 / 40 / 8 |
| folded | lot 9, three samples | 30; 112; 112 | | 7,006; 8,880; 9,305 | 0 | 0 | 10; 32; 23 |
| folded | lot 12 | 30 | 7,016 | 6,961 | 0 | 0 | 55 / 0 / 0 |
| raw to folded | lot 10 (M3) | 230 | | 23,680 | 0 | 0 | 112 / 0 / 0 |

Lot 11's first run missed zx_Exchange and DNSSECImpl (past its 300 s then;
lot 5 made them fast). Lot 9's own test ran raw and rewritten traces on 8
storage worlds: 6,861, 8,561 and 9,105 calls the same, 0 different. M4:
the triage (text_check on the whole corpus with the asm's param side
information) had 45,299 calls of the printed texts, 6 different (3
contracts: triage issues 4 and 5), 0 lines unparsed - without the side
information 15 contracts differed, 12 only where params' places were
guessed; after the fixes, lot 10's text_check on 70 contracts had 0 lines
unparsed and 0 different (empty world: 5,102 calls, 5,067 the same, 7
unsupported, 28 inconclusive on evmone's side; random world: 5,106, 5,016,
37, 53), apart from 6 calls a world whose params' places were guessed, all
in the synthetic fuzz_3_94. Parity: lot 12's `cli_surface.py` (0 failures),
`pymod_surface.py` (161 checks, 0 failures), `driver_threads.py` (80
decompilations, 0 differences), 30 contracts with the same text and JSON
at -j 1, 2, 8; the triage's 1121 texts identical at -j 1 and the default,
136 contracts under ASan and UBSan with no report.

**The final whole-corpus run** (20 Oct, tree abd917c then d44fbe0, release build,
`stagecheck --stage folded --timeout 300`, seed 0, the empty world's sequence and a random
world, 4 calls per selector typed by the signature database): 1,121 contracts, none failed;
at every stage (raw, whiles, simplified, analysed, folded) 0 different, 0 bugs. Raw: 90,580
calls, 90,221 the same, 359 inconclusive (evm 311, exhausted 40, undefined 8); folded:
90,579 calls, 90,221 the same, 358 inconclusive; one contract stopped at the time limit
(safe_MockContract, on evmone's side). The 18 contracts whose text d44fbe0 changes,
rechecked: 2,564 calls, 0 different at every stage. The printed text of all 1,121 contracts
(`text_check`, the params' places from pancxx's own JSON for all 11,135 functions, none
guessed): 0 unparsed lines; empty world 45,307 calls, 45,241 the same, 0 different (24
unsupported, 42 evm inconclusive); random world 45,311 calls, 44,803 the same, 0 different
(243 unsupported - 220 of them storage bytes the random world fills with invalid encodings -
and 265 evm inconclusive). Unit tests: 317 cases, 241,362 assertions; the python tests
(surfaces, robustness, threads, the decoder's proof): 0 failures.

## Hostile input

Whoever sends the bytecode chooses it: a server decompiling what it is
sent runs on an attacker's input. The asm's protections are kept:

| protection | limit | enforced by |
|---|---|---|
| a function's memory | PANORAMIX_MAX_MEMORY MiB, else the memory / (threads + 1), 1 GiB at least | the job's Budget: chunks, tables, memos, pmr containers charged first (MemoryLimit); `std::bad_alloc` a problem; the process lives on |
| the phases' memory | discovery: half a function's; contract: base + imports + one function's; storage: half of what is left; a fold: 1 GiB | `driver/pipeline.cpp`, `output/ast.cpp` |
| time | a function 180 s, the discovery 60 + 180 s, the post-processing 180 s, x PANORAMIX_TIMEOUT | the watchdog's `expire()`: Timeout at the next `check_stack()`/`poll()`, the asm's messages |
| the VM | 20000 nodes; 5000 with a wide frontier; 5000 for the dispatcher; 20 x 200 steps; 60 s | `should_quit()`: UNDEFINED(UNFINISHED), not a failure |
| the simplifier | 40 rounds; 60 s | the rounds stop |
| recursion | the stack's low bound + 1 MiB, 64 MiB stacks | `check_stack()`: DepthLimit |
| expressions | 150 nodes; a sum of 20000 terms | a VM variable; nothing inlined; SizeLimit |
| numbers | 2^20 bits of shift, exponent, mask | EvmInt: SizeLimit |
| bytes | constant strings 2^24 bytes; fresh zeroes 64 KiB; CODECOPY from the code 1024 bytes | `mem/memory.cpp` (MemoryLimit), `facts.cpp`, `vm_core.cpp` |
| code | 2^32 - 1 bytes; the CLI's input 256 MiB of text | `check_code_size()`; `io::max_input` (a refusal, not a cut) |
| the EVM stack | 1024 words | INVALID(STACK_OVERFLOW) |
| threads | 1024 | `parallel_for`, `run_pipeline` |
| the trace machine | steps, bytes, work, memory, depth | Exhausted (inconclusive) |
| --explain | 1 GiB | the rest cut, a line says so |
| a node's answer | 60 s in all, 10 s a wait, 256 MiB; no TLS | `fetch.hpp`, `net.hpp` |
| the database | sections checked at open, buckets and records at lookup; lines 256 MiB, types 64 deep, xz 1 GiB | `sigdb.cpp`; `O_EXCL \| O_NOFOLLOW` then rename |
| text from outside | escaped | `escape.rl`, `pretty_text`, `hex::escape`: no terminal escape, no forged line |
| signals, fork | async signals blocked in library threads; SIGPIPE ignored by the CLI; fork handlers | `platform_posix.cpp`, `io_posix.cpp` |

`tests/driver_robustness.py` and `cli_surface.py` port the asm's
`robustness.sh` and `security.sh`: 2000 nested ifs (4500 with `--full`),
a 20000-deep expression, a truncated push, security.sh's empty and
past-the-end copies, an absurd `-j`, a string constant of newlines and
`def` lines, returns of 16 MiB zero regions under a 128 MiB limit, a 1 MiB
limit (every function a problem, the text made, exit 0); with `--full`
the big contracts, 2400 selectors under a 0.004 timeout factor, functions
whose walks blow up, address-space limits, a fork during a decompilation.

The environment: PANORAMIX_MAX_MEMORY (MiB; 0 none), PANORAMIX_TIMEOUT
(the factor; 0 or less none), PANORAMIX_COMPACT_MIB, PANORAMIX_SIGDB,
PANORAMIX_ABI_DUMP, XDG_CACHE_HOME and HOME (the database's directory;
HOME also the IPC sockets), WEB3_PROVIDER_URI and WEB3_HTTP_PROVIDER_URI
(the node), PANORAMIX_LOG, PANORAMIX_VM_CHECK and PANORAMIX_VM_STATS. The
opt-in corpus tests read PANORAMIX_{VM,MEM,LOOPS,STORAGE}_CORPUS,
PANCXX_CORPUS (the decoder's), PANORAMIX_LOOPS_FUZZ,
PANORAMIX_SIMPLIFY_DUMP, PANORAMIX_SIMPLIFY_SCRATCH (each with `_LIMIT`,
`_SKIP`... of its own), PANORAMIX_TEST_ABI_DUMP, PANORAMIX_TEST_FULL,
PANORAMIX_TESTS_DIR; `cli_surface.py` reads PANASM.

## Testing

`make check` builds `$(B)/pancxx_test` (every `tests/*_test.cpp`,
`libvalidate.a`, `libevmone.a`, the library), runs it with `$(TEST_ARGS)`
(doctest's, e.g. `-tc='algebra*'`: a case's name starts with its suite's
prefix), then every `tests/*.py` as `python3 tests/X.py $(B)`; `make unit`
is the doctest binary alone. The suites: `core`; `evm` (the grammar's
classes against the op table, the CodeMap against a plain walk on random
codes and the corpus); `algebra`, `ranges` (soundness by evaluation and
sampling, the wrap cases undecided); `mem` (reads assembled from random
writes, run by the trace machine); `vm`; `loops` (6000 random raw traces,
each case run before and after); `simplify`; `traits`; `safemath`;
`storage`; `output`; `exec` (every op on hand-made traces); `stagecheck`
(the machine and evmone on hand-assembled bytecode); `driver` (one run's
stages, determinism at 1, 2, 8 threads, limits, waves); `sigdb`, `sha256`
(NIST vectors through every implementation the CPU has); the front ends';
`validate`; `text`, `text interp`. The corpus suites do nothing unless
their variable names a corpus. The python tests: `cli_surface.py` (inputs,
options, messages, exit codes, a fetch from a node of its own, panasm's
answers when it is there), `pymod_surface.py` (both builds of the module),
`driver_robustness.py`, `driver_threads.py` (python threads decompiling at
once, each result compared with the contract decompiled alone),
`evm_dfa_proof.py`. Lot 10's last debug run of every suite: 312 cases (4
skipped), 241,362 assertions, 0 failures; `driver_robustness.py`: 27
checks, 0 failures.

The variants: `release` (the user's flags, `-fPIC` everywhere,
`-flto=auto` at the link, `NDEBUG` never defined); `debug` (`$(B)/debug/`,
`make debug`: `-O1 -g`, ASan and UBSan with `-fno-sanitize-recover=all`,
`_GLIBCXX_ASSERTIONS`, no LTO, no python tests); `pgo-gen` and `pgo-use`,
`make pgo`'s phases - `-fprofile-generate -fprofile-update=prefer-atomic`
builds `$(B)/pgo/pancxx`, `tools/corpus.py --train` runs it over
`$(CORPUS)` without time limits, `-fprofile-use
-fprofile-partial-training` rebuilds the same objects. The optimized
builds never use sanitizers: the Makefile stops if `-fsanitize` is in
their flags, `EXTRA_*` included. `make validate` builds the tools; `make
stagecheck` runs stagecheck over `$(CORPUS)`, niced, `-j $(JOBS)`; `make
bench` runs `tools/bench.py` over `$(CORPUS)`: the asm, `$(B)/pancxx` and
`$(B)/pgo/pancxx`, each with its own database.

## Front ends

**The command line** (`src/main.cpp`, `cli.rl`) has panasm's commands,
options, messages and exit codes:

    pancxx disasm <file.hex|->
    pancxx decode <file.hex|-|address|bytecode>
    pancxx decompile <file.hex|-|address|bytecode>[,...] [-j threads] [--function name]
           [--no-color] [--json] [-v level] [--verbose] [--explain] [--repr] [--returns]
    pancxx build-db <abi_dump.xz> [out.bin]
    pancxx --version

An input is tried as `-` (standard input), an address (0x and 40 hex
digits: fetched from a node, python's decompile_address), hex bytecode,
then a file of hex (regular, 256 MiB at most): a server running `pancxx
decompile <what it was sent>` never opens a path it was sent as bytecode.
A comma-separated list that isn't a file's name is decompiled in turn.
Exit codes: 0; 1 when an input can't be had or a decompilation fails
("decompilation failed: ..." on stderr); 2 for the usage. Messages escape
what comes from outside; the log is coloredlogs' format, the asm's lines.

**The python module** (`src/pymod.cpp`) is the asm's `panoramix_asm`
without `_test`: `decompile(code, threads=0, function=None, color=True,
verbose=False, explain=False) -> str`, `decompile_bytecode(code,
only_func_name=None, ...) -> Decompilation(text, asm, json, explain)`,
`decompile_address`, `disasm`, `set_log_level`, `build_signature_db`,
`__version__`; `code` is bytes or hex. The GIL is released while the core
works; errors are ValueError, TypeError, ConnectionError (the fetch),
MemoryError, RuntimeError (a failed decompilation). It is built twice from
one source (`-DPAN_PYMODULE`) and exports `PyInit_*` only.

**The library's interface** (`src/decompile.hpp`) is C++ - the C API is
free and none is exported: `pan::decompile(bytes, DecompileOptions)`
(threads, only_function, color, verbose, explain, repr, returns, json,
asm_lines) gives a `Decompilation` (text, asm_lines, json, explain) or
throws `DecompileError` (with what --explain had printed); calls may run
at once from any threads. Also `disassemble`, `decode_report`, the log,
and `build_signature_db` (`sigdb.hpp`).

**The JSON** (`output/json.cpp`, our format) has python's
decompilation.json's keys (`problems`, `stor_defs`, `lang`, `functions`
with names, traits, text, params by calldata offset and trace, `safemath`,
`internal`). A trace is a table of its distinct nodes, operands first,
referred to by index: as big as its nodes, never as deep as it nests. The
module returns `json.loads` of it.

## Differences from the asm and python

Intended, stated by a report or the code, and checked by execution (the
stagechecks above: 0 different at every stage they ran):

- **const on one path only** (lot 8): only SETMEM and SETVAR lines before
  the RETURN, so a condition on the context (`require this.address ==
  SELF`) never hides a revert behind `const` - one function in the corpus
  (accoun060_BrokenBLSAccount's `proxiableUUID`, a const in the asm's).
- **Param types from solc >= 0.8's mask-form validation** (lot 8): `require
  not Mask(96, 160, x)` makes x an address where the asm says uint256 - 452
  functions.
- **SafeMath calls past checks that fail alike** (lot 8): past checks of
  other operations failing the same way (same panic, same revert data,
  both INVALID), an order no call can tell. 412 contracts have a `def
  SafeMath:` (the asm 425: 11 whose checks the simplifier proved redundant,
  6 whose message is built in memory, 2 sized-int or folder-variable cases;
  6 blocks the asm lacks).
- **The storage SALL copy** (lot 9): a bytes read reads what solidity's
  copy to memory reads whatever the slot holds - short or long by the
  decoded length, exactly that many bytes - so a getter's rewrite holds on
  any storage. Storage copy loops: 32 left in the corpus, the asm's 185.
- **Call results and gas reads kept apart in the text** (lot 10, triage
  issues 3 and 9): a call's result read where another call may have run
  since, and a gas read printed with or after another, get a variable, as
  python's VM snapshots did; where the asm, whose IR equates two gas reads,
  prints `return 0`, NoDelegateCallTest, HooksTest_2 and TickMathTest print
  `return SafeMath.sub(_1, gas_remaining)`. Over the corpus (lot 10's
  count) lines mixing two calls' results went from 894 in 60 contracts to
  0, lines printing two gas reads from 289 in 16 to 0; the 36 reads left
  (9 contracts) are lot 5's per-path dispatch, each branch its own call's.
- **One unfinished end per function** (lot 10, triage issue 1): the IR's
  UNDEFINED has a pc, so the folder kept apart the paths the VM gave up
  (the triage: 3028 leaves in 6 contracts, the asm 526; lot 5 showed its
  VM matches python's); `one_unfinished` (`ast_passes.cpp`) makes them one
  before folding, as python's equal lines were: "didn't finish" lines from
  2,278 to 136, zx_Staking's moveStake from 82 to 1 (the asm 1).
  COMPUTED_JUMP and AMBIGUOUS_CALL keep their pc.
- **The VM's per-path last call after merges** (lot 5): return data read
  after a merge of paths whose last calls differ is each path's call's;
  55 functions in 20 contracts used to stop there ("return data of a call
  that depends on the path"); the text prints `_19 = return_data.size` on
  each branch and the copy chosen by id.
- **Dead branches proven** (lots 3, 5, 7): ranges, chained facts and
  MAX/MIN decided 30,858 of the VM's conditions python's is_known couldn't
  (57% more than the facts' 54,458: lot 3's probe), cleanup_conds decides
  ifs under the path's conditions; most functions lacking one of the asm's
  revert strings, logs or calls (a revert string: 488 functions in 166
  contracts, the triage) lack a branch no execution takes (non-payable
  means callvalue 0, immutables are 0 in these bytecodes, a check
  repeated).
- **Sums never integers for free** (lots 2, 3): python read ADD as an
  integer (`x + 1 > x`); here that needs a proven no-wrap condition.
- **Loops** (lot 6): a loop whose exit code python inlined at the test
  (`while True`) is `while not test:` with the code after it (`while True`
  from 23% to 5% of the first 20 contracts' loops); a copy loop is a SETMEM
  only when provably the same (python's rule would rewrite 555 more of 4000
  random copy loops, 172 wrongly: behind `dubious`);
  `propagate_storage_in_loops` is exact for any step.
- **The EVM's stack limit** (lot 5): `INVALID(STACK_OVERFLOW)` past 1024
  words; python had no such check. **Python's floats** (lot 10): `2 ** -k`
  printed as a division.
- **The signature database**: a verified line beats a later unverified one,
  where python knew nothing; lines python can't read are skipped (neither
  occurs in panoramix's dump).
- **The timeout factor** (core): a positive PANORAMIX_TIMEOUT below 0.001
  still counts; a hex float (`0x10`) reads as 0, no limit (strtod: 16).

## Performance notes

By design: hash-consing (equality a word compare, memos keyed by pointer,
a walk that changes nothing allocates nothing, content flags instead of
walks); arenas (bump allocation, chunks reused unzeroed from a pool, huge
pages, a function's garbage gone with its context, compaction between the
simplifier's rounds); memo tables per context, without locks (normal
forms, ranges, `simplify_exp`, effect summaries, overlaps, loop summaries,
the passes' last input); the storage hash table generated at build time;
the O(1) signature database open; threads for the functions, the folds
and the texts. The reports' gains, each under load: the asm's subtree
summaries and the Link array took zx_Exchange's VM from 254 s to about 9 s
(lot 5); facts' bounds gathered only for what is asked took
`nested_ifs_2000`'s VM from 12 s to 0.18 s, `eval_bool` under 2% of the
VM's time (lot 3); the simplifier's memos took zx_Exchange's
simplification from 32.5 s to 9.6 s wall (lot 7); SafeMath on
`nested_ifs_2000` went from 31 s to 0.41 s (lot 8); the build-time hash
table took vy043_wallet from 24.5 to 9.4 ms and the corpus' median CPU per
contract from 23.6 to 10.4 ms, for 400 KB of binary (lot 9); at lot 10's
end (release, -j 1) nested_ifs_2000 took 1.5 s, Seaport15 6.0 s,
UniV4PoolManager 2.2 s. The RSS the database seemed to cost (median 29
against 17 MiB in the triage, its issue 12) is the page cache's large
folios, a whole folio mapped per fault, shared and clean (main's
measurement: 20 random page reads, 29.5 MiB of RssFile, RssAnon unchanged);
the asm shows the same (39.8 against 17.6 MiB on WETH), so benchmarks
compare both with their databases.

The triage's measurements (the whole corpus; 2 CPUs shared, load 6 to 13;
the asm and pancxx interleaved contract by contract at -j 1; CPU = user +
sys). Build A was HEAD 7cc5d27 with lot 8's traits, before storage and
SafeMath; build B, 75a7d08, with them:

| | asm | cxx A | cxx B |
|---|---|---|---|
| total CPU | 90.6 s / 86.7 s (runs A / B) | 69.9 s (0.77x) | 109.6 s (1.26x; 0.93x without nested_ifs_2000) |
| median per contract | 13.1 / 11.9 ms | 10.6 ms | 24.0 ms |
| p99 | 987 / 956 ms | 884 ms | 1012 ms |
| max | 15.5 s (zx_Exchange) | 12.3 s (zx_Exchange) | 31.2 s (nested_ifs_2000) |
| peak RSS | 397 MiB | 140 MiB | 139 MiB |

In run A, over the contracts of 50 ms or more, the ratio to the asm had a
median of 0.72 and a worst of 1.43 (uniswa410_ActionsRouter: the
simplifier, hash-consing and the algebra under it); the twenty worst were
mostly the simplifier's or the VM's merge walks, and part of A's gain on
zx_Exchange and zx_Staking came from paths given up (triage issue 1). B's
two regressions - SafeMath on nested ifs and the storage table built by
every process - were fixed after the triage (lots 8 and 9, above).

**Not run yet:** the PGO build trained on the corpus (`make pgo`) and the final benchmark
against the asm (`make bench`) - the work stopped at the user's request before them. The
triage's measurements above are the latest; since then the storage hash table moved to the
build (the corpus' median 23.6 -> 10.4 ms per contract, total 79.2 -> 70.0 s at -j 2) and
the memory forwarding of triage issues 6 and 7 added about 15% (73.4 -> 84.6 s).
