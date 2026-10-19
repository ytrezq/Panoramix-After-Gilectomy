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
| `sigdb`    | `$(SIGDB)` (`$(B)/sigdb1.bin`): `pancxx build-db $(ABI_DUMP)` |
| `pgo`      | the PGO build in `$(B)/pgo/` (below) |
| `debug`    | `$(B)/debug/`: `-O1 -g`, ASan + UBSan (`-fno-sanitize-recover=all`), `_GLIBCXX_ASSERTIONS`, no LTO; builds the CLI and the unit tests and runs them. Any target in that build: `make VARIANT=debug validate` |
| `bench`    | `tools/bench.py`: the asm, `$(B)/pancxx`, `$(B)/pgo/pancxx` over `$(CORPUS)` |
| `clean`    | `rm -rf $(B)` |

## Variables

| variable | default | |
|----------|---------|---|
| `B` | `build` | the build directory |
| `V` | `0` | `V=1` shows the commands |
| `VARIANT` | `release` | `debug`; `pgo-gen` / `pgo-use` are `make pgo`'s phases |
| `JOBS` | `2` | contracts decompiled at once by the PGO training |
| `CORPUS` | the scratchpad's `prof/all_hex.txt` (1121 contracts) | a list of `.hex` paths, a directory, or `.hex` files |
| `ABI_DUMP` | `/home/claude/panoramix/panoramix/data/abi_dump.xz` | for `sigdb` |
| `SIGDB` | `$(B)/sigdb1.bin` | the C++ CLI's database (not the asm's format) |
| `ASM`, `ASM_SIGDB` | `../build/panasm`, `../build/abi_db.bin` | the asm, for `bench` |
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
  `$(B)/sigdb1.bin`): a line per contract, then the counts (ok, failed,
  crashed, timeouts), the CPU time (total, median, p90, p99, max), the peak
  RSS, the slowest, the failures. Exit 1 when one is not ok.
- `bench.py [LIST...] [--runs R] [-j N] [--limit N] [--bin LABEL=PATH[:DB]]`:
  the asm, `$(B)/pancxx`, `$(B)/pgo/pancxx` on the same contracts (one
  thread each, turns rotated): total CPU, median and percentiles per
  contract, peak RSS, the ratios to the asm.

Try them on a few contracts first (`--limit 20`): the whole corpus is long.
