# Cosmos

- Scope: 22 Blockchain/DLT assets, all GitHub repositories or crates, no refs named. Two of them hold EVM sources:
  - `cosmos/solidity-ibc-eureka` (IBC v2 light clients, ICS26 router, ICS20 transfer in Solidity; the repo also has Solana programs, not copied): default branch, commit df9d6c48.
  - `cosmos/evm` (Cosmos EVM framework, Go): its Solidity sources are the ERC20/WERC20 module contracts (`contracts/solidity`), the precompile interfaces (`precompiles/*`) and the test contracts: default branch, commit bd334caa. Its test submodules (OpenZeppelin, Uniswap v3, forge-std) came along.
- Both Apache-2.0, copied in full (EVM sources only).
- Left out (no EVM sources: Go/Rust/C node software, CosmWasm, relayer): cometbft, cosmos-sdk, gaia, iavl, ibc-go, ics23,
  ledger-cosmos, CosmWasm (cosmwasm, wasmvm, wasmd, serde-json-wasm, cw-storage-plus, cw-utils, rust-optimizer), hermes and its crates.
- No contract addresses in scope.
