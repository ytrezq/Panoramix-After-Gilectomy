# Decompiled code against the sources

895 artifacts, 895 decompiled, 0 failed.

## Interface

| | |
|---|---|
| ABI functions found in the dispatcher | 27087 / 27129 (99.8%) |
| selectors not in the ABI | 85 |
| names and types as the ABI (signature database) | 56.3% |
| payable as the ABI | 98.8% |
| static parameter types (with the database) | 94.0% of 22490 |
| static parameter types (inferred, --blind) | - of 0 |

## Storage

| | |
|---|---|
| layout places found | 7555 / 8995 (84.0%) |
| their kind as the compiler's | 97.8% |
| named (from a getter) | 3209, the source's name 80.9% |

## Semantics (execution against evmone)

| | same | different | inconclusive |
|---|---|---|---|
| stagecheck, every stage (calls) | 238643 | 0 (0 contracts; bugs 0) | 899 |
| text_check, empty world (calls) | 119643 | 3 | 78 (+ 49 unsupported) |
| text_check, random world (calls) | 118919 | 3 | 734 (+ 100 unsupported) |

Texts with a call different: 1. Texts with lines not parsed: 1.

## Size (functions matched on both sides: 25564)

| | source | decompiled |
|---|---|---|
| statements / lines | 317578 | 1763620 (x5.55) |
| loops | 4329 | 25152 |
| conditions | 50858 | 238974 |
| reverts and requires | 34691 | 277464 |

(Source statements: the function, its modifiers and the internal functions it calls, each once;
decompiled lines: the function's, comments aside.)

## Across EVM versions (the same source and settings)

| builds | pairs | functions | identical | lines changed |
|---|---|---|---|---|
| cancun -> osaka | 1 | 95 | 100.0% | 0.0% |
| cancun -> prague | 10 | 177 | 100.0% | 0.0% |
| paris -> shanghai | 210 | 6860 | 97.3% | 9.1% |
| shanghai -> cancun | 153 | 4784 | 89.7% | 34.1% |

## Builds

(an artifact with a difference: a call different in stagecheck or text_check)

| compiler, EVM | artifacts | with a difference | with lines not parsed |
|---|---|---|---|
| solc-0.4.23 constantinople | 1 | 0 | 0 |
| solc-0.4.24 constantinople | 8 | 0 | 1 |
| solc-0.4.26 constantinople | 3 | 0 | 0 |
| solc-0.5.1 constantinople | 1 | 0 | 0 |
| solc-0.5.10 petersburg | 2 | 0 | 0 |
| solc-0.5.12 petersburg | 6 | 0 | 0 |
| solc-0.5.16 istanbul | 1 | 0 | 0 |
| solc-0.5.17 istanbul | 10 | 0 | 0 |
| solc-0.6.2 istanbul | 1 | 0 | 0 |
| solc-0.6.6 istanbul | 2 | 0 | 0 |
| solc-0.6.11 istanbul | 1 | 0 | 0 |
| solc-0.6.12 istanbul | 22 | 0 | 0 |
| solc-0.6.12 istanbul noopt | 1 | 0 | 0 |
| solc-0.7.0 istanbul | 1 | 0 | 0 |
| solc-0.7.1 istanbul | 8 | 0 | 0 |
| solc-0.7.3 istanbul | 2 | 0 | 0 |
| solc-0.7.5 istanbul | 1 | 0 | 0 |
| solc-0.7.6 istanbul | 20 | 0 | 0 |
| solc-0.8.4 istanbul | 4 | 1 | 0 |
| solc-0.8.7 london | 58 | 0 | 0 |
| solc-0.8.7 london noopt | 12 | 0 | 0 |
| solc-0.8.9 london | 19 | 0 | 0 |
| solc-0.8.10 london | 12 | 0 | 0 |
| solc-0.8.11 london | 2 | 0 | 0 |
| solc-0.8.13 london | 1 | 0 | 0 |
| solc-0.8.14 london | 3 | 0 | 0 |
| solc-0.8.15 london | 3 | 0 | 0 |
| solc-0.8.15 london via-IR | 2 | 0 | 0 |
| solc-0.8.16 london | 15 | 0 | 0 |
| solc-0.8.16 london noopt | 1 | 0 | 0 |
| solc-0.8.16 london via-IR | 1 | 0 | 0 |
| solc-0.8.17 london | 10 | 0 | 0 |
| solc-0.8.17 london via-IR | 1 | 0 | 0 |
| solc-0.8.18 paris | 9 | 0 | 0 |
| solc-0.8.18 paris noopt | 1 | 0 | 0 |
| solc-0.8.19 paris | 11 | 0 | 0 |
| solc-0.8.19 paris via-IR | 1 | 0 | 0 |
| solc-0.8.20 paris | 8 | 0 | 0 |
| solc-0.8.20 paris via-IR | 2 | 0 | 0 |
| solc-0.8.20 shanghai | 8 | 0 | 0 |
| solc-0.8.20 shanghai via-IR | 2 | 0 | 0 |
| solc-0.8.21 paris | 23 | 0 | 0 |
| solc-0.8.21 paris via-IR | 1 | 0 | 0 |
| solc-0.8.21 shanghai | 23 | 0 | 0 |
| solc-0.8.21 shanghai via-IR | 1 | 0 | 0 |
| solc-0.8.22 paris | 8 | 0 | 0 |
| solc-0.8.22 paris via-IR | 1 | 0 | 0 |
| solc-0.8.22 shanghai | 8 | 0 | 0 |
| solc-0.8.22 shanghai via-IR | 1 | 0 | 0 |
| solc-0.8.23 paris | 9 | 0 | 0 |
| solc-0.8.23 paris via-IR | 5 | 0 | 0 |
| solc-0.8.23 shanghai | 9 | 0 | 0 |
| solc-0.8.23 shanghai via-IR | 5 | 0 | 0 |
| solc-0.8.24 paris | 11 | 0 | 0 |
| solc-0.8.24 paris noopt | 2 | 0 | 0 |
| solc-0.8.24 paris via-IR | 3 | 0 | 0 |
| solc-0.8.24 shanghai | 11 | 0 | 0 |
| solc-0.8.24 shanghai noopt | 2 | 0 | 0 |
| solc-0.8.24 shanghai via-IR | 3 | 0 | 0 |
| solc-0.8.24 cancun | 11 | 0 | 0 |
| solc-0.8.24 cancun noopt | 2 | 0 | 0 |
| solc-0.8.24 cancun via-IR | 3 | 0 | 0 |
| solc-0.8.25 paris | 7 | 0 | 0 |
| solc-0.8.25 paris noopt | 2 | 0 | 0 |
| solc-0.8.25 paris via-IR | 1 | 0 | 0 |
| solc-0.8.25 shanghai | 7 | 0 | 0 |
| solc-0.8.25 shanghai noopt | 2 | 0 | 0 |
| solc-0.8.25 shanghai via-IR | 1 | 0 | 0 |
| solc-0.8.25 cancun | 9 | 0 | 0 |
| solc-0.8.25 cancun noopt | 2 | 0 | 0 |
| solc-0.8.25 cancun via-IR | 1 | 0 | 0 |
| solc-0.8.26 paris | 11 | 0 | 0 |
| solc-0.8.26 paris via-IR | 2 | 0 | 0 |
| solc-0.8.26 shanghai | 11 | 0 | 0 |
| solc-0.8.26 shanghai via-IR | 2 | 0 | 0 |
| solc-0.8.26 cancun | 11 | 0 | 0 |
| solc-0.8.26 cancun via-IR | 4 | 0 | 0 |
| solc-0.8.27 paris | 9 | 0 | 0 |
| solc-0.8.27 shanghai | 9 | 0 | 0 |
| solc-0.8.27 cancun | 22 | 0 | 0 |
| solc-0.8.27 cancun via-IR | 1 | 0 | 0 |
| solc-0.8.27 prague | 2 | 0 | 0 |
| solc-0.8.28 paris | 14 | 0 | 0 |
| solc-0.8.28 paris via-IR | 4 | 0 | 0 |
| solc-0.8.28 shanghai | 14 | 0 | 0 |
| solc-0.8.28 shanghai via-IR | 4 | 0 | 0 |
| solc-0.8.28 cancun | 25 | 0 | 0 |
| solc-0.8.28 cancun via-IR | 8 | 0 | 0 |
| solc-0.8.28 prague | 4 | 0 | 0 |
| solc-0.8.28 prague via-IR | 1 | 0 | 0 |
| solc-0.8.29 paris | 4 | 0 | 0 |
| solc-0.8.29 paris via-IR | 1 | 0 | 0 |
| solc-0.8.29 shanghai | 4 | 0 | 0 |
| solc-0.8.29 shanghai via-IR | 1 | 0 | 0 |
| solc-0.8.29 cancun | 5 | 0 | 0 |
| solc-0.8.29 cancun via-IR | 1 | 0 | 0 |
| solc-0.8.30 paris | 7 | 0 | 0 |
| solc-0.8.30 paris via-IR | 4 | 0 | 0 |
| solc-0.8.30 shanghai | 7 | 0 | 0 |
| solc-0.8.30 shanghai via-IR | 4 | 0 | 0 |
| solc-0.8.30 cancun | 8 | 0 | 0 |
| solc-0.8.30 cancun via-IR | 6 | 0 | 0 |
| solc-0.8.33 paris | 3 | 0 | 0 |
| solc-0.8.33 shanghai | 3 | 0 | 0 |
| solc-0.8.33 cancun | 3 | 0 | 0 |
| solc-0.8.33 prague | 1 | 0 | 0 |
| solc-0.8.33 osaka | 1 | 0 | 0 |
| solc-0.8.34 paris | 3 | 0 | 0 |
| solc-0.8.34 paris noopt | 1 | 0 | 0 |
| solc-0.8.34 paris via-IR | 2 | 0 | 0 |
| solc-0.8.34 shanghai | 3 | 0 | 0 |
| solc-0.8.34 shanghai noopt | 1 | 0 | 0 |
| solc-0.8.34 shanghai via-IR | 2 | 0 | 0 |
| solc-0.8.34 cancun | 5 | 0 | 0 |
| solc-0.8.34 cancun noopt | 1 | 0 | 0 |
| solc-0.8.34 cancun via-IR | 2 | 0 | 0 |
| solc-0.8.34 prague via-IR | 1 | 0 | 0 |
| solc-0.8.34 osaka via-IR | 1 | 0 | 0 |
| solc-0.8.35 paris | 2 | 0 | 0 |
| solc-0.8.35 shanghai | 2 | 0 | 0 |
| solc-0.8.35 cancun | 5 | 0 | 0 |
| solc-0.8.35 osaka | 2 | 0 | 0 |
| solc-0.8.36 paris | 1 | 0 | 0 |
| solc-0.8.36 paris noopt | 1 | 0 | 0 |
| solc-0.8.36 shanghai | 1 | 0 | 0 |
| solc-0.8.36 shanghai noopt | 1 | 0 | 0 |
| solc-0.8.36 cancun | 2 | 0 | 0 |
| solc-0.8.36 cancun noopt | 1 | 0 | 0 |
| solc-0.8.36 prague noopt | 1 | 0 | 0 |
| solc-0.8.37 paris via-IR | 2 | 0 | 0 |
| solc-0.8.37 shanghai via-IR | 2 | 0 | 0 |
| solc-0.8.37 cancun via-IR | 3 | 0 | 0 |
| solc-0.8.38 paris | 53 | 0 | 0 |
| solc-0.8.38 paris noopt | 1 | 0 | 0 |
| solc-0.8.38 shanghai | 53 | 0 | 0 |
| solc-0.8.38 shanghai noopt | 1 | 0 | 0 |
| solc-0.8.38 cancun | 56 | 0 | 0 |
| solc-0.8.38 cancun noopt | 1 | 0 | 0 |
| vyper-0.2.12 istanbul | 1 | 0 | 0 |
| vyper-0.3.1 istanbul | 1 | 0 | 0 |
| vyper-0.3.6 istanbul | 1 | 0 | 0 |
| vyper-0.3.7 paris | 1 | 0 | 0 |
| vyper-0.3.10 paris | 1 | 0 | 0 |
| vyper-0.3.10 shanghai | 1 | 0 | 0 |
| vyper-0.3.10 cancun | 1 | 0 | 0 |
| vyper-0.4.2 paris | 1 | 0 | 0 |
| vyper-0.4.2 shanghai | 1 | 0 | 0 |
| vyper-0.4.2 cancun | 1 | 0 | 0 |
