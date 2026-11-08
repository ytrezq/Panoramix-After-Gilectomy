# The decompiler's source corpus

The sources of the EVM projects of [Immunefi's bug bounty
programs](https://immunefi.com/bug-bounty/), with their directory structure,
so that their contracts can be compiled for several versions of the EVM (and
of their compilers) and the decompiled code compared with the code it came
from: the interface, the storage, the semantics (by execution) and how much
the decompiler simplifies.

It lives in the C++ branch, in `cxx/corpus/` (GitHub's size limit is the
repository's, not a branch's). Every repository is a git subtree: its commit,
filtered - only its EVM sources, build files, license files and symbolic
links kept; documentation, server-side code, JavaScript / TypeScript and data
left out - added with `git subtree add --squash`, and each of its submodules
the same way at its own path (`tools/subtree_corpus.py`).

## Layout

| path | what |
|---|---|
| `immunefi/programs.json` | the programs listed on immunefi.com/bug-bounty (scraped with a headless browser on 2026-11-07: `tools/immunefi/`), their scope's assets, whether they are EVM programs |
| `immunefi/assign/` | the EVM programs split between the searches, and `not_evm.txt` (other chains) |
| `immunefi/STATUS.md` | per program: the repositories found and added (`tools/corpus_stats.py`) |
| `immunefi/SLUG/manifest.json` | per repository: its URL and commit, its subtrees (prefix, URL, commit, files kept), its submodules and Soldeer dependencies (with their commits), the npm packages fetched for its imports (with their versions), its license and the verdict, its languages |
| `immunefi/SLUG/notes.md` | how the repositories were found (the program's assets, its GitHub organization), what was left out and why |
| `immunefi/SLUG/OWNER__REPO/` | the repository's subtree: its EVM sources (`.sol .vy .vyi .yul .huff .fe .lll .se`), build files (`foundry.toml`, `remappings.txt`, `package.json`, `hardhat.config.*`, ...) and license files at their own paths; its submodules' and dependencies' at the paths a build finds them (`lib/...`, `node_modules/...`, `dependencies/...`) |
| `results/` | runs of the tools: the builds' errors, `compare_source.py`'s summary and per-artifact results (`results/sample-2026-11-08/`: 168 artifacts of 11 programs, solc 0.4.24 to 0.8.38 and Vyper 0.3.6 to 0.4.2 on five EVM versions) |

## What is in it

Every repository of a program's scope found on GitHub (or another git host
the proxy reaches), at a commit the manifest records: a git subtree of the
filtered commit (`git subtree add --squash` of a parentless commit made from
the upstream tree without a checkout, dated as the upstream commit - the same
repository and commit always give the same subtree), its submodules and
Soldeer dependencies from git as subtrees at the paths a build finds them,
the npm packages and Soldeer zips its sources import as plain files
(`node_modules/...`, `dependencies/...`: not git repositories). A submodule
that couldn't be fetched is there as files from an earlier copy.

Licenses: every repository is in, its license files with it; the manifest
records each license and whether it allows redistribution - those that don't
(proprietary texts, "all rights reserved", source-available or
non-commercial licences, UNLICENSED headers) are in at the owner's request
(`license_note` in the manifest).

The code is untrusted: nothing of it was run. Repositories were fetched with
git; npm packages one by one with `npm pack --ignore-scripts` (no install, no
lifecycle script); the tools only read the sources and give them to the
compilers.

## Tools

```sh
# record one repository in a program and fetch what it needs (clone,
# submodules, Soldeer, the npm packages its imports need, the license
# verdict, the manifest) into a work copy OLD (its --root)
tools/copy_repo.py --program SLUG --repo https://github.com/OWNER/REPO [--ref REF] [--note TEXT] --root OLD

# the manifests' repositories as filtered git subtrees here (a clean work
# tree; resumable; each step a commit), the npm packages from OLD
tools/subtree_corpus.py --from OLD [--program SLUG]... [--jobs 4]

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
