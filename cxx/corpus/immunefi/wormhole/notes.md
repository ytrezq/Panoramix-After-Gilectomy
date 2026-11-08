# Wormhole

- Scope: wormhole-foundation/wormhole at main by directory (ethereum, solana, cosmwasm, algorand, aptos, sui, near, plus
  node/ and wormchain/ as Blockchain/DLT), wormhole-circle-integration ("EVM, excluding the Circle Bridge"),
  native-token-transfers, and the docs' mainnet contract address list.
- Copied (all Apache-2.0), EVM sources only:
  - wormhole-foundation/wormhole at main (4725d906): ethereum/ (core bridge, token bridge, NFT bridge, relayer) and the few
    other .sol files of the monorepo (testing/), with their @openzeppelin/contracts npm imports; scope path ethereum.
  - wormhole-circle-integration at main (23420254): evm/; scope path evm.
  - native-token-transfers at main (5e56c0a0): evm/ with its submodules; scope path evm.
- Left out (non-EVM): the Solana, CosmWasm, Algorand, Aptos, Sui and Near contracts, the Go guardian node and wormchain.
  The Circle bridge contracts themselves are Circle's (out of scope by the program).
- The EVM addresses of the docs page were not checked one by one against these sources.
