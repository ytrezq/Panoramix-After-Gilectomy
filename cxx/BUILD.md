# Building the C++ decompiler

`make` runs in `cxx/` (`make -C cxx` from the repository's root). It needs
g++-14 / gcc-14 / gcc-ar-14, GNU make >= 4.2, ragel 6.10, python3 with its
headers, liblzma. The machine is shared: **`-j2` at most**, and each worker
builds in its own directory, `B=build-NAME` (`build*/` is ignored by git).

    make -j2 B=build-me            # the library, the CLI, the python modules
    make -j2 B=build-me check      # the unit tests (doctest) and tests/*.py
    make help                      # the targets and the variables

## Targets

| target     | what |
|------------|------|
| `all`      | `$(B)/libpanoramix_cxx.a`, the CLI `$(B)/pancxx`, the python module `$(B)/panoramix_cxx<EXT_SUFFIX>`, and the same module named `panoramix_asm` in `$(B)/compat/` (the repository's scripts: `PANASM_BUILD=cxx/$(B)/compat`) |
| `check`    | `$(B)/pancxx_test` (every `tests/*_test.cpp` + `libvalidate.a` + `libevmone.a` + the library), run with `$(TEST_ARGS)` (doctest's: `-tc='sigdb*'`, `-s`...); then every `tests/*.py`, run as `python3 tests/X.py $(B)` |
| `unit`     | only the doctest binary, built and run |
| `validate` | the validation tools (`$(B)/evmrun`...), `libvalidate.a`, `libevmone.a` |
| `sigdb`    | `$(SIGDB)` (`$(B)/sigdb2.bin`): `pancxx build-db $(ABI_DUMP)` |
| `pgo`      | the PGO build in `$(B)/pgo/` (below) |
| `debug`    | `$(B)/debug/`: `-O1 -g`, ASan + UBSan (`-fno-sanitize-recover=all`), `_GLIBCXX_ASSERTIONS`, no LTO; builds the CLI and the unit tests and runs them. Any target in that build: `make VARIANT=debug validate` |
| `bench`    | `tools/bench.py`: the asm, `$(B)/pancxx`, `$(B)/pgo/pancxx` over `$(CORPUS)` |
| `readability` | `$(CORPUS)` decompiled into `$(B)/readability/texts/`, its readability compared with `$(READABILITY_BASE)` (below); fails on a regression `$(READABILITY_ALLOW)` doesn't allow |
| `readability-baseline` | `$(READABILITY_BASE)` moved forward: function by function, the best of it and of the texts of the last `make readability` (with no texts yet, `$(CORPUS)` decompiled by this build first) |
| `clean`    | `rm -rf $(B)` |

## Variables

| variable | default | |
|----------|---------|---|
| `B` | `build` | the build directory |
| `V` | `0` | `V=1` shows the commands |
| `VARIANT` | `release` | `debug`; `pgo-gen` / `pgo-use` are `make pgo`'s phases |
| `JOBS` | `2` | contracts decompiled at once by the PGO training |
| `CORPUS` | `corpus-npm/all_hex.txt`, made by `tools/fetch_corpus.sh corpus-npm` (861 contracts) | a list of `.hex` paths, a directory, or `.hex` files |
| `ABI_DUMP` | `$PANORAMIX_ABI_DUMP`, else `/home/claude/panoramix/panoramix/data/abi_dump.xz` | for `sigdb`: python panoramix's `panoramix/data/abi_dump.xz` |
| `SIGDB` | `$(B)/sigdb2.bin` | the C++ CLI's database (not the asm's format) |
| `ASM`, `ASM_SIGDB` | `../build/panasm`, `../build/abi_db.bin` | the asm, for `bench` |
| `READABILITY_BASE` | `tests/readability/npm.jsonl.xz` | the readability baseline: the measures of the npm corpus's texts |
| `READABILITY_ALLOW` | `tests/readability/allow.txt` | the regressions `make readability` accepts |
| `TEST_ARGS`, `BENCH_ARGS` | | passed to the doctest binary, to `bench.py` |
| `EXTRA_CXXFLAGS`, `EXTRA_LDFLAGS` | | experiments only |

## The flags

Always (the user's rule): `-std=gnu++23 -march=native -mtune=native -Ofast
-flto -fmerge-all-constants -fweb`, `-flto=auto` at the link (the links'
recipes start with `+` so that LTO shares make's job slots: `make -n` still
runs them); `-Wall -Wextra` for our code (ragel's output also
`-Wno-implicit-fallthrough`; third-party code gets none of our warnings).
Every object is `-fPIC`: the python module is a shared object made of the
library's objects, and at the link LTO turns the CLI's code into PIE code.
`NDEBUG` is not defined: `assert` stays on. The module exports `PyInit_*`
only (a version script), so LTO internalizes everything else.
`pancxx --version` shows the build (`src/version.hpp`:
`panoramix::build_info()`; the Makefile writes `$(B)/obj/build_info.h`).

A change of the flags (the variant, `EXTRA_*`, `validate/Makefile.inc`)
rebuilds the objects concerned: the stamps `$(B)/obj/flags.*`,
`$(B)/obj/ldflags`; the member lists `$(B)/obj/*.list` rebuild an archive or
the test binary when a source disappears.

## Adding a module: no edit of the Makefile

- **C++**: `src/NAME.cpp` (+ `NAME.hpp`) is in the library: everything in
  `src/` is, but `main.cpp` (the CLI) and `pymod.cpp` (the module, compiled
  twice: `-DPAN_PYMODULE=panoramix_cxx` and `=panoramix_asm`). POSIX-only
  code: `NAME_posix.cpp`; the MinGW port's: `NAME_win32.cpp`.
- **Ragel**: `src/NAME.rl` -> `ragel -G2` -> `$(B)/gen/src/NAME.cpp`,
  compiled with `-Isrc` (it includes `"NAME.hpp"`); `#line`s point to the
  `.rl`. A fragment only included by other machines: `NAME.rlh` (every `.rl`
  is regenerated when a `.rlh` changes).
- **Assembly**: `src/NAME.S`, GNU as through the C preprocessor;
  position-independent (RIP-relative: `-Wl,-z,text` rejects text
  relocations).
- **Tests**: `tests/NAME_test.cpp`, `#include <doctest/doctest.h>`
  (`tests/main_test.cpp` holds doctest's `main`); include paths `-Isrc -I.`
  and validate's. `tests/NAME.py`: run by `make check` with `$(B)` as
  `argv[1]`.
- **Validation**: `validate/NAME.cpp` / `.rl` -> `libvalidate.a`; a tool is
  `validate/NAME_main.cpp` or listed in `VALIDATE_TOOLS` -> `$(B)/NAME`.
  evmone's sources and flags: `validate/Makefile.inc`.
- **Third-party code**: `third_party/NAME` (a tag at least two weeks old, a
  NOTICE); its `include/` is on every include path (`-isystem`).
- **System libraries**: `LDLIBS` in the Makefile (today `-llzma`): ask.

## PGO (`make pgo`)

1. the release CLI and `$(SIGDB)` (`make sigdb`); the old `.gcda` deleted;
2. `VARIANT=pgo-gen`: `-fprofile-generate -fprofile-update=prefer-atomic`,
   the instrumented `$(B)/pgo/pancxx`;
3. the training: `tools/corpus.py --train` over `$(CORPUS)`, `$(JOBS)` at a
   time (`PANORAMIX_TIMEOUT=0`): each object's `.gcda` lands next to it;
4. `VARIANT=pgo-use`: `-fprofile-use -fprofile-partial-training`, the same
   object paths (`$(B)/pgo/obj/`): `$(B)/pgo/pancxx`, the modules.

A source changed between 2 and 4 only loses its profile (a warning).

## The scripts (`tools/`, python3)

- `corpus.py [LIST|DIR|X.hex...] [--cli P] [-j N] [--threads T] [--out DIR]
  [--json F] [--limit N] [--kill-after S] [--train] [-- CLI ARGS]`:
  `CLI decompile X --no-color` for each contract, N at a time, with
  `PANORAMIX_TIMEOUT=0` and `PANORAMIX_SIGDB` (`--sigdb`, default
  `$(B)/sigdb2.bin`): a line per contract, then the counts (ok, failed,
  crashed, timeouts), the CPU time (total, median, p90, p99, max), the peak
  RSS, the slowest, the failures. Exit 1 when one is not ok.
- `bench.py [LIST...] [--runs R] [-j N] [--limit N] [--bin LABEL=PATH[:DB]]`:
  the asm, `$(B)/pancxx`, `$(B)/pgo/pancxx` on the same contracts (one
  thread each, turns rotated): total CPU, median and percentiles per
  contract, peak RSS, the ratios to the asm.

Try them on a few contracts first (`--limit 20`): the whole corpus is long.

## The readability check (`make readability`)

The execution checks prove that a text does what the bytecode does. They
can't see a text get harder to read: a revert string printed as raw memory
again, a copy back to a loop, a value written out in full where a name was.
`make readability` is the automatic form of what the manual review looked
for (`corpus/review/`). It decompiles `$(CORPUS)` with `$(B)/pancxx` into
`$(B)/readability/texts/`, measures each function of each text
(`tools/readability.py`, whose docstring lists the rules), and compares the
measures with the baseline `$(READABILITY_BASE)`, committed in the
repository. It fails on a regression that `$(READABILITY_ALLOW)` doesn't
allow, and writes:

- `$(B)/readability/report.md`: the regressions by rule, the totals before
  and after, the texts with the most;
- `$(B)/readability/regressions.jsonl`: one per line (`name`, `function`,
  `rule`, `old`, `new`, `allowed`).

```
make readability CORPUS=corpus-npm/all_hex.txt
```

The baseline is keyed by the `.hex` files' names: `CORPUS` must name the
files of `tools/fetch_corpus.sh corpus-npm` (in any directory). Another
corpus needs its own baseline (`READABILITY_BASE=...`).

A function of the new text is compared with the same function of the old
one (the same name; overloads paired by their parameters' types). A
regression is:

- a revert string, called function, event, custom error or decoded form
  (`Array(len=...)`) that the old function showed and the new one doesn't,
  unless the text shows it elsewhere (moved to a call site, into a helper's
  def);
- a count past its tolerance: raw memory in reverts, returns, call
  arguments, call targets and event data; free-pointer differences left
  unfolded; storage keys hashed from raw memory; arguments split in byte
  slices; copies left as loops; `while True` loops, loop labels, rotated
  loops; GAS reads nothing uses; lines over 240 characters or with four
  rounded lengths; raw memory writes; the nesting; the size. A line's
  nesting is its statement's (a wrapped statement's lines are no deeper
  than the statement), and the mean nesting counts only when the summed
  nesting grew too (a mean that rose because shallow lines left the text
  is no regression).

What to do with one:

1. Fix it. A change that makes a text less readable is a regression even
   when it is exact.
2. When the old form was readable only because it was inexact, or when
   exactness needs the new form, allow it: a line `NAME FUNCTION RULE MOST
   # why` in the proven part of `tests/readability/allow.txt`, with the
   proof (the first three are shell patterns, `*` for any; MOST is the most
   the count may reach, for a `lost_` rule the number of items lost).
3. When the tool counts something that isn't a loss, fix the tool and add
   the case to its selftest (`python3 tools/readability.py selftest`, run
   by `make check` through `tests/readability_selftest.py`). Rules are about
   the printed text, never about a language or a compiler.

`allow.txt` has two parts: the proven exceptions, and the regressions not
fixed yet ("to fix"), each with today's count as its MOST, so it can't grow.
The goal is as few lines as possible: a fix removes its lines, and `make
readability` lists the lines no regression needs any more and those whose
count can go down.

After a change that makes texts more readable, move the baseline forward:
`make readability`, read its report, then `make readability-baseline`, and
commit the baseline with the change. The baseline is a ratchet: for each
function it keeps the best of what it held and of the new text - each count
its least, each string, call, event, error and form shown in either
(`tools/readability.py best`). A regression is fixed or allowed; it never
gets into the baseline, so an allowed one stays listed until it is fixed.
The baseline was made from the texts of three builds (the build before
round 2's fixes, round 2's, round 3's): what any of them showed is what the
texts must show.

## Sanitizers and the optimized builds

ASan and UBSan are only in `VARIANT=debug`. The optimized builds (release, the
PGO instrumented build `pgo-gen`, its training run, the PGO build `pgo-use`)
never use them: the Makefile stops with an error if `-fsanitize` appears in
their flags (`EXTRA_CXXFLAGS`/`EXTRA_LDFLAGS` included).

## The core and the stages

Every directory `src/<dir>/` is compiled into the library (`*.cpp`, `*.rl`
through `ragel -G2`, `*.S`; the other platform's `*_posix`/`*_win32` files
left out). The op table is generated: `tools/gen_ops.py` reads
`../spec/evm.def` and `../spec/ops.def` and writes
`$(B)/gen/src/core/ops_gen.hpp` (included as `core/ops.hpp`); every object
waits for it. The library links GMP (`-lgmpxx -lgmp`).

The storage analysis' table of the hashes compilers write as numbers
(keccak of the first 4096 slots, of the first 16 keys of the first 64
mappings, solidity's and vyper's orders) is made at the build:
`tools/gen_storage_htab.cpp`, compiled with `$(HOSTCXX)` (the build
machine's compiler: it runs during the build, even for a cross build) and
exec's keccak, writes `$(B)/gen/src/storage/htab_gen.hpp` - not computed by
every process at its first storage constant (~15 ms).

