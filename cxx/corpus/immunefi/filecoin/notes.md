# filecoin: no in-scope EVM contracts

- Scope (30 assets, all Blockchain/DLT): the Filecoin protocol software in Go and Rust: Lotus (node and miner),
  Boost, builtin-actors (the chain's built-in actors, Rust compiled to Wasm), ref-fvm, go-f3, the proofs crates
  (rust-fil-proofs, bellperson, neptune...), go-* IPLD/CBOR libraries, plus Primacy of Impact on filecoin.io.
- No smart_contract asset and no explorer address: the program is tagged EVM only through the Filecoin ecosystem (FEVM).
- Nothing copied. The in-scope repositories are node/VM software; the only EVM sources in them are FEVM test
  contracts (checked 2026-11-07 on the default branches):
  - filecoin-project/builtin-actors @ 5bc19c5: 13 .sol in actors/evm/tests/contracts/ (EVM actor tests: MCOPY,
    transient storage, selfdestruct, precompiles...);
  - filecoin-project/ref-fvm @ 23290a4: 16 .sol in tools/contracts/ and tools/solidity-tests/;
  - filecoin-project/lotus @ 079b532: 38 .sol in itests/contracts/ (FEVM integration tests).
  Left out by the brief's rule (node software); they could be added as FEVM test material if wanted.
- go-f3, boost and the other in-scope repositories hold no EVM source.
