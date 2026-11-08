# The whole corpus (8 Nov 2026)

## The build

`tools/build_corpus.py` over every repository of `immunefi/`. It reads every
project's Foundry profiles and Hardhat/Truffle configs and builds for the EVM
versions each compiler and each piece of code allow:

- 37,946 artifacts, 17,872 distinct bytecodes;
- 304 of the 306 repositories, 107 programs;
- compilers: solc 0.4.22 to 0.8.38 (52 releases), Vyper 0.2.12 to 0.4.2 (7 releases, 150 artifacts);
- EVM versions: constantinople to osaka (paris 11,034 artifacts, shanghai 10,224, cancun 9,175, istanbul 2,908, london 2,846, prague 863, constantinople 466, osaka 363, petersburg 67).

The errors are 3,694 lines of the build's `errors.jsonl`, not kept here:

| Errors | Count | What they are |
|---|---|---|
| EVM version | 1,827 | Code that can't target an older EVM version |
| Missing imports | 837 | Missing upstream: private packages, generated files, Soldeer or ape dependencies |
| Other | 601 | |
| Stack too deep | 87 | |
| No release fits | 71 | No compiler release fits the pragmas |
| Retries | 271 | Notes on groups compiled again without the sources their errors reach |

Two repositories gave nothing:

- agglayer vault-bridge: its Soldeer dependencies are not redistributable, so they aren't copied.
- rhinofi: it uses OpenZeppelin without declaring it.

## The comparison

The comparison covers each project's largest own contract in every build of it: 895 artifacts.

    compare_largest.py --build BUILD --out OUT --bin DIR --sigdb DB    (again until "== all done")
    compare_largest.py --build BUILD --out OUT --bin DIR --sigdb DB --summary

DIR has the release builds of `pancxx`, `stagecheck` and `text_check` from the cxx23 branch, and DB is that build's signature database. `summary.md` is the final run's result, and `results.jsonl` has one line per artifact.

### The final run

It used the build of cxx23 at eafea47ccc.

The 895 artifacts were first compared with the build of 63d7037f25, which took 74 minutes of one CPU. eafea47ccc changes the text of 8 of them: a call's return data of more than 32 bytes, read after another call, now gets a variable per word. Those 8 were compared again with the eafea47ccc build. Each of the other 887 was decompiled again with that build, and its text came out the same.

| Calls | same | different | other |
|---|---|---|---|
| stagecheck, every stage | 238,647 | 0 | 0 bugs, 899 inconclusive |
| text_check, empty world | 119,654 | 0 | 78 inconclusive, 41 unsupported |
| text_check, random world | 118,929 | 0 | 734 inconclusive, 93 unsupported |

- **Parsing:** the text's reader parses every line of the 895 texts.
- **The interface:** the dispatchers have all 27,129 ABI functions. The 85 selectors not in the ABI are library functions, as explained below.
- **Unsupported calls** are those text_check can't run from the text alone. Their reasons include:
  - mostly, a `bytes` or `string` storage value whose encoding is invalid, since a random world puts arbitrary words in storage;
  - storage or parameter places whose printed type doesn't say where they are;
  - lines `Decompilation aborted`, which mark paths the VM gave up, as the asm does (209 such lines, in 29 texts);
  - reads of `msize`.

### The first run and its fixes

The first run used the build of 0d986fed75 and took 77 minutes of one CPU. Its numbers:

- **stagecheck:** no call different, out of 238,643 calls the same.
- **text_check:** 3 calls different and 33 lines not parsed, each group in one text.
- **The interface:** 27,087 of the 27,129 ABI functions were found in the dispatchers.

Every problem it found has been fixed since:

- **The 3 calls different** were in ListaStakeManager (solc 0.8.4 istanbul), `skipDelegateOrNot`.
  - The cause: the SafeMath rewrite moved an overflow check into the right side of an `and`, so the subtraction's Panic(0x11) was skipped when the left side was 0. The asm prints the same line.
  - The fix: a check now folds only into a use that every run evaluates.
- **The 33 lines not parsed** were in Voting (lido aragon-apps, solc 0.4.24).
  - The cause: they involve a storage variable named `delegate` (from its getter), and the text's reader took `delegate` for the keyword of `delegate call`.
  - The fix: the reader now takes such keywords for names where a name can stand.
- **The 42 missing functions** all belonged to one Vyper 0.3.1 contract.
  - The cause: the 6 distinct Vyper 0.3.1 bytecodes came out as one default function, as the asm's do. Their dispatcher copies the selector to `mem[28]` with `calldatacopy(28, 0, 4)` and reads the word at 0, and the VM didn't know the value of a copy that short.
  - The fix: the VM now knows a copy of fewer than 32 bytes of call data as its value, so the selector tests are read.
- **Library selectors:** a library's selector names its structs (`Market.Props`), where a contract's selector spells the struct out as a tuple. `compare_source.py` now computes library selectors this way. The four library artifacts were compared again with it.

The 85 selectors not in the ABI are library functions: solc leaves a library's non-view functions out of its ABI. There are 72 in DssExecLib, 4 in each MarketUtils build and 1 in a silo library.
