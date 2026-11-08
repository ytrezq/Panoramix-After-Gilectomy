# Hyperlane

- Scope: 217 addresses on Arbitrum, Avalanche, Base, BNB, Celo, Ethereum,
  Gnosis, Moonbeam, Optimism, Polygon (Mailbox, ISMs and their factories,
  hooks, InterchainGasPaymaster, ValidatorAnnounce, InterchainAccountRouter,
  ProxyAdmin) and the warp-route frontend; no repository linked.
- Copied: hyperlane-xyz/hyperlane-monorepo at its default branch (main); only
  its EVM sources (solidity/) are kept. Mailbox, ISMs, hooks, IGP, gas
  oracle, ValidatorAnnounce, ICA router are there; not in this tree:
  InterchainAccountIsm (deployed from an older release, since removed) and
  Celo's create2Factory; ProxyAdmin is OpenZeppelin's (a Soldeer dependency).
- solidity/ uses Soldeer: its 10 dependencies (OpenZeppelin 4.9.3, LayerZero
  v2, wormhole sdk, permit2, ...) are copied under solidity/dependencies/.
- Left out: the monorepo's TypeScript, Rust (agents), Starknet parts.
