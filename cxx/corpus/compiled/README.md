# The compiled corpus (8 Nov 2026)

`tools/build_corpus.py` compiled every repository of `immunefi/`, which took
hours. Its output is kept here so that nothing has to be compiled again:

- 37,946 artifacts, 17,872 distinct bytecodes;
- 304 of the 306 repositories;
- solc 0.4.22 to 0.8.38 and Vyper 0.2.12 to 0.4.2;
- EVM versions from constantinople to osaka.

`../results/full-2026-11-08/README.md` describes the build and its errors.

The build takes 3.6 GB unpacked. It is packed here as one `PROGRAM.tar.xz` per program, 176 MB in all:

| File | What |
|---|---|
| `PROGRAM.tar.xz` | the program's directory of the build (below), packed with a fixed order, owner and time |
| `index.jsonl` | one line per artifact: its program, repository, project, build and artifact path |
| `errors.jsonl` | the build's errors: compilations that failed and why, and retries |

To unpack the whole build, or some programs, into a directory:

    tools/unpack_build.sh BUILD [PROGRAM...]

Then `tools/compare_largest.py --build BUILD ...` and `tools/compare_source.py BUILD ...` read it.
`tools/pack_build.sh BUILD compiled/` packs a new build the same way.

## The layout of a program's directory

    PROGRAM/OWNER__REPO[/PROJECT]/BUILD/SOURCE__PATH.sol:Contract.hex
    PROGRAM/OWNER__REPO[/PROJECT]/BUILD/SOURCE__PATH.sol:Contract.json
    PROGRAM/OWNER__REPO[/PROJECT]/ast-COMPILER/SOURCE__PATH.sol.json

- **BUILD** names the compiler, the EVM version and the code generator, for example `solc-0.8.23-paris-ir` or `vyper-0.3.10-shanghai`.
- **`.hex`** is the runtime bytecode in hex.
- **`.json`** holds the artifact's description:
  - `abi`, `storageLayout`;
  - `source` and `contract`;
  - `compiler`, `evm`, `optimizer`, `via_ir`;
  - `ast`, the directory of the compiler run's ASTs, which the builds of one compiler share;
  - `linked`, the libraries linked in and their placeholder addresses.
- **`ast-COMPILER/`** has the AST of each source unit, as the compiler gives it.

Artifact names contain `:`, so the archives can't be unpacked on a file system that refuses it, such as Windows'.
