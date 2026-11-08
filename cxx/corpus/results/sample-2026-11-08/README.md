# A sample run (8 Nov 2026)

What `tools/build_corpus.py` and `tools/compare_source.py` give on a sample
of the corpus, with the decompiler of the cxx23 branch at 0e5aa93 (its
release build, `pancxx`, `stagecheck`, `text_check`, the signature database
of its build).

The build, each project for byzantium, istanbul, london, shanghai and cancun
(each compiler gets the versions it knows, and the code those it can target):

    aave aave-dao__aave-v3-origin             compoundfinance compound-finance__compound-protocol
    sushiswap sushiswap__v2-core              lido lidofinance__core
    cowprotocol cowprotocol__contracts        sky sky-ecosystem__dss
    1inch-SmartContracts 1inch__limit-order-protocol
    gmx gmx-io__gmx-contracts                 ens ensdomains__ens-contracts
    olympus OlympusDAO__olympus-v3            rocketpool rocket-pool__rocketpool
    yearnfinance yearn__yearn-vaults-v3       yearnfinance yearn__styfi
    lido lidofinance__lido-vesting-escrow     lido lidofinance__mev-boost-relay-allowed-list

    build_corpus.py --program P --repo R --evm byzantium,istanbul,london,shanghai,cancun --out sample

2,200 artifacts (solc 0.4.24 to 0.8.38, Vyper 0.3.6 to 0.4.2); the errors
(`build_errors.jsonl`) are mostly code that can't target an old EVM version
(SHL, CHAINID, PUSH0, MCOPY), and olympus-v3, copied file by file, missing
the sources its license headers didn't cover. The comparison, each
project's 5 largest own contracts in every build:

    compare_source.py sample --own --per-project 5 --blind -j 2 --timeout 300

`summary.md` is the result; `results.jsonl` has a line per artifact.
