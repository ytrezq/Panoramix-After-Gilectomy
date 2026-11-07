# The decompiler's source corpus

The sources of the EVM projects of [Immunefi's bug bounty
programs](https://immunefi.com/bug-bounty/), copied with their directory
structure, so that their contracts can be compiled for several versions of
the EVM (and of their compilers) and the decompiled code compared with the
code it came from: the interface, the storage, the semantics (by execution)
and how much the decompiler simplifies.

This branch (`corpus`) shares no history with the decompiler's branches: it
only holds data and the tools that make and use it.

## Layout

| path | what |
|---|---|
| `immunefi/programs.json` | the programs listed on immunefi.com/bug-bounty (scraped with a headless browser on 2026-11-07: `tools/immunefi/`), their scope's assets, whether they are EVM programs |
| `immunefi/assign/` | the EVM programs split between the searches, and `not_evm.txt` (other chains) |
| `immunefi/STATUS.md` | per program: the repositories found, copied, by reference only (`tools/corpus_stats.py`) |
| `immunefi/SLUG/manifest.json` | per repository: its URL and commit, its submodules and Soldeer dependencies (with their commits), the npm packages fetched for its imports (with their versions), its license and the verdict, its languages, the files copied |
| `immunefi/SLUG/notes.md` | how the repositories were found (the program's assets, its GitHub organization), what was left out and why |
| `immunefi/SLUG/OWNER__REPO/` | the copy: every EVM source (`.sol .vy .vyi .yul .huff .fe .lll .se`) and build configuration (`foundry.toml`, `remappings.txt`, `package.json`, `hardhat.config.*`, ...) at the repository's own paths, its submodules' and dependencies' at the paths a build finds them (`lib/...`, `node_modules/...`, `dependencies/...`), the links of a workspace; or, for a repository whose license doesn't allow redistribution, the whole repository as a git subtree (below) |
| `results/` | runs of the tools: the builds' errors, `compare_source.py`'s summary and per-artifact results (`results/sample-2026-11-08/`: 168 artifacts of 11 programs, solc 0.4.24 to 0.8.38 and Vyper 0.3.6 to 0.4.2 on five EVM versions) |
| `reference/` | (ignored by git) local copies made by `tools/fetch_reference.py`, for a repository that isn't on GitHub |

## What is copied

A repository is copied when its license allows redistribution: the license
file at its root when it has one (an open license: MIT, Apache, GPL family,
BSD, MPL, ISC, the Unlicense, CC0, BUSL...; anything else, a proprietary text
or a licence for non-commercial use, means *reference only*), else its
`package.json`'s license, else each file's SPDX header (then only the sources
whose own header is an open license are copied, when the contracts' headers
are mostly open; a root license that defers to the files' headers is read the
same way). Files over 2 MB and build outputs (`out/`, `artifacts/`,
`cache/`, ...) are left out of a copy.

A repository on GitHub whose license doesn't allow redistribution (a
proprietary text, "all rights reserved", a source-available or
non-commercial licence, UNLICENSED headers) is not copied file by file: it
is added whole with `git subtree add --squash` (`tools/subtree_repo.py`, at
the owner's request) - its tree at its commit, its license files with it,
one squashed commit, so `git subtree pull --prefix=...` updates it; its
submodules on GitHub become subtrees at their own paths and commits, and the
npm packages its sources import are added as files. The manifest says
`"via": "git subtree"` and lists the subtrees. A repository that isn't on
GitHub would be recorded by URL and commit only (`tools/fetch_reference.py`
makes a local copy outside git).

The copied code is untrusted: nothing of it was run. Repositories were cloned
with git; npm packages were fetched one by one with `npm pack
--ignore-scripts` (no install, no lifecycle script); the tools only read the
sources and give them to the compilers.

## Tools

```sh
# copy one repository into a program (clone, submodules, Soldeer, the npm
# packages its imports need, the license verdict, the manifest)
tools/copy_repo.py --program SLUG --repo https://github.com/OWNER/REPO [--ref REF] [--note TEXT]

# or add it whole as git subtrees (itself, its submodules), its npm packages
# as files (a clean work tree; each step a commit)
tools/subtree_repo.py --program SLUG --repo https://github.com/OWNER/REPO [--commit SHA]

# compile: each project (foundry, hardhat, truffle, brownie, a src/ or
# contracts/ of sources) with the compiler its configuration or pragmas ask,
# for each EVM version that compiler knows; runtime bytecode, ABI, storage
# layout, AST
tools/build_corpus.py [--program SLUG] [--evm paris,shanghai,cancun] [--optimizer auto|on|off|both] --out BUILD

# compare the decompiled code with the sources (pancxx, stagecheck and
# text_check from the cxx23 branch's build)
tools/compare_source.py BUILD --pancxx .../pancxx --stagecheck .../stagecheck \
    --text-check .../text_check --sigdb .../sigdb2.bin [--blind] -j 2

tools/corpus_stats.py   # immunefi/STATUS.md
```

`build_corpus.py` downloads the solc releases it needs from
binaries.soliditylang.org (checked against their published SHA-256) and the
Vyper releases from PyPI (a virtualenv per version), into
`~/.cache/panoramix-corpus`. Remappings are made as forge makes them (the
project's own, then every library's under `lib/`, nested ones too, as context
remappings); `node_modules/` is an include path.

`compare_source.py` writes `results.jsonl` (a line per artifact) and
`summary.md`:

- **interface**: the ABI's functions found in the decompiled dispatcher, the
  selectors that aren't in the ABI, the names and parameter types as the
  ABI's (with the signature database, and with `--blind` inferred from the
  code alone), payable as the ABI says;
- **storage**: the compiler's storage layout (slot, offset, kind) against the
  decompiled storage definitions;
- **semantics**: `stagecheck` (each stage's internal trace run against evmone
  on the same calls) and `text_check` (the printed text parsed again and run
  against evmone): calls the same, different, inconclusive;
- **size**: each function's decompiled lines against its source statements
  (its body, its modifiers', the internal functions it calls, each once), and
  the loops, conditions and reverts on each side;
- **across EVM versions**: the same contract built for consecutive EVM
  versions, its decompiled functions identical or not.
