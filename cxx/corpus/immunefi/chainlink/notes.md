# Chainlink

- Scope: GitHub paths (CCIP EVM and Solana contracts, Chainlink EVM contracts,
  CCIP owner contracts, Sui and Aptos Move contracts) plus off-chain software
  (node, plugins, relayers, keystore, external adapters, operator UI) and
  websites.
- Copied, at the refs the scope links name: smartcontractkit/chainlink-ccip
  @main (scope chains/evm/contracts; the repository's other EVM sources come
  along), smartcontractkit/chainlink-evm @develop (scope contracts/),
  smartcontractkit/ccip-owner-contracts @main.
- Left out: chainlink-solana (Solana), chainlink-sui and chainlink-aptos
  (Move), chainlink core node, libocr, chainlink-common (Go), CCIP commit/
  execute plugins (Go, off-chain), external-adapters-js and operator-ui
  (TypeScript), websites.
- chainlink-ccip and ccip-owner-contracts are BUSL-1.1, chainlink-evm MIT/BUSL.
- No addresses in scope (deployments are per network in Chainlink's docs).
