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

The comparison covers each project's largest own contract in every build of it: 895 artifacts. It used the release build of the cxx23 branch at 0d986fed75 (`pancxx`, `stagecheck`, `text_check`, and that build's signature database):

    compare_largest.py --build BUILD --out OUT --bin DIR --sigdb DB    (again until "== all done")
    compare_largest.py --build BUILD --out OUT --bin DIR --sigdb DB --summary

It took 77 minutes of one CPU. `summary.md` is the result, and `results.jsonl` has one line per artifact.

### Results

**stagecheck:** no call different, out of 238,643 calls same.

**text_check:** 3 calls different and 33 lines not parsed, each in one text.

- **The 3 calls different** are in ListaStakeManager (solc 0.8.4 istanbul), `skipDelegateOrNot`. The SafeMath rewrite moved an overflow check into the right side of an `and`, so the subtraction's Panic(0x11) is skipped when the left side is 0. The asm prints the same line.
- **The 33 lines not parsed** are in Voting (lido aragon-apps, solc 0.4.24). They involve a storage variable named `delegate` (from its getter): the text's reader took `delegate` for the keyword of `delegate call`.

**The interface:** 27,087 of the 27,129 ABI functions are found in the dispatchers.

- **The 42 missing** all belong to one Vyper 0.3.1 contract. The 6 distinct Vyper 0.3.1 bytecodes come out as one default function. Their dispatcher tests the call value once, before the non-payable selectors. The asm doesn't split them either.
- **The 85 selectors not in the ABI** are library functions. solc leaves a library's non-view functions out of its ABI: 72 in DssExecLib, 4 in each MarketUtils build, 1 in a silo library.
- **A library's selector** names its structs (`Market.Props`), where a contract's selector spells the struct out as a tuple. `compare_source.py` computes library selectors this way since this run, and the four library artifacts were compared again with it.
