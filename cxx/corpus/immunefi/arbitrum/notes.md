# arbitrum

- Scope: 170 smart-contract assets, all GitHub file links at main into four repositories; no explorer address.
- Copied, from the scope links (@main): OffchainLabs/nitro-contracts (95 files: rollup, bridge, inbox/outbox,
  one-step proofs, BoLD challengeV2, assertion staking pools, precompile interfaces, NodeInterface),
  OffchainLabs/token-bridge-contracts (43: L1/L2 gateways, routers, standard token, libraries),
  ArbitrumFoundation/governance (30: ARB token, governors, timelocks, upgrade executor, security council management),
  OffchainLabs/fund-distribution-contracts (2: RewardDistributor, Util).
- nitro-contracts also holds one Yul file; the precompiles in src/precompiles are interfaces (implemented in the Go node).
- Nothing left out: the Nitro node itself is not in this program's scope.
