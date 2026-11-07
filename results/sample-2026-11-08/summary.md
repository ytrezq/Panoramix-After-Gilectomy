# Decompiled code against the sources

168 artifacts, 168 decompiled, 0 failed.

## Interface

| | |
|---|---|
| ABI functions found in the dispatcher | 6505 / 6505 (100.0%) |
| selectors not in the ABI | 0 |
| names and types as the ABI (signature database) | 62.5% |
| payable as the ABI | 100.0% |
| static parameter types (with the database) | 98.2% of 6396 |
| static parameter types (inferred, --blind) | 89.9% of 6396 |

## Storage

| | |
|---|---|
| layout places found | 1739 / 1838 (94.6%) |
| their kind as the compiler's | 98.1% |
| named (from a getter) | 974, the source's name 89.0% |

## Semantics (execution against evmone)

| | same | different | inconclusive |
|---|---|---|---|
| stagecheck, every stage (calls) | 52409 | 0 (0 contracts; bugs 0) | 179 |
| text_check, empty world (calls) | 26695 | 0 | 13 (+ 0 unsupported) |
| text_check, random world (calls) | 26509 | 0 | 196 (+ 3 unsupported) |

Texts with lines not parsed: 0 (empty world).

## Size (functions matched on both sides: 4806)

| | source | decompiled |
|---|---|---|
| statements / lines | 63278 | 383482 (x6.06) |
| loops | 704 | 3959 |
| conditions | 8921 | 41453 |
| reverts and requires | 7040 | 54963 |

(Source statements: the function, its modifiers and the internal functions it calls, each once;
decompiled lines: the function's, comments aside.)

## Across EVM versions (the same source and settings)

| builds | pairs | functions | identical | lines changed |
|---|---|---|---|---|
| byzantium -> istanbul | 13 | 534 | 97.4% | 9.9% |
| istanbul -> london | 25 | 1119 | 98.9% | 0.1% |
| london -> shanghai | 31 | 1292 | 94.9% | 9.5% |
| shanghai -> cancun | 31 | 1292 | 71.4% | 63.4% |

## Builds

| compiler, EVM | artifacts | with a difference |
|---|---|---|
| solc-0.4.24 byzantium | 3 | 0 |
| solc-0.5.12 byzantium | 1 | 0 |
| solc-0.6.12 byzantium | 5 | 0 |
| solc-0.6.12 istanbul | 14 | 0 |
| solc-0.7.6 istanbul | 11 | 0 |
| solc-0.8.18 byzantium | 2 | 0 |
| solc-0.8.18 istanbul | 2 | 0 |
| solc-0.8.18 london | 2 | 0 |
| solc-0.8.26 cancun | 5 | 0 |
| solc-0.8.26 istanbul | 5 | 0 |
| solc-0.8.26 london | 5 | 0 |
| solc-0.8.26 shanghai | 5 | 0 |
| solc-0.8.27 cancun | 5 | 0 |
| solc-0.8.27 istanbul | 5 | 0 |
| solc-0.8.27 london | 5 | 0 |
| solc-0.8.27 shanghai | 5 | 0 |
| solc-0.8.30 cancun | 9 | 0 |
| solc-0.8.30 istanbul | 4 | 0 |
| solc-0.8.30 london | 9 | 0 |
| solc-0.8.30 shanghai | 9 | 0 |
| solc-0.8.38 byzantium | 2 | 0 |
| solc-0.8.38 cancun | 5 | 0 |
| solc-0.8.38 istanbul | 5 | 0 |
| solc-0.8.38 london | 5 | 0 |
| solc-0.8.38 shanghai | 5 | 0 |
| solc-0.8.9 istanbul | 2 | 0 |
| solc-0.8.9 london | 2 | 0 |
| vyper-0.3.10 cancun | 2 | 0 |
| vyper-0.3.10 istanbul | 2 | 0 |
| vyper-0.3.10 london | 2 | 0 |
| vyper-0.3.10 shanghai | 2 | 0 |
| vyper-0.3.6 byzantium | 1 | 0 |
| vyper-0.3.6 istanbul | 1 | 0 |
| vyper-0.3.7 byzantium | 3 | 0 |
| vyper-0.3.7 istanbul | 3 | 0 |
| vyper-0.4.2 cancun | 5 | 0 |
| vyper-0.4.2 london | 5 | 0 |
| vyper-0.4.2 shanghai | 5 | 0 |
