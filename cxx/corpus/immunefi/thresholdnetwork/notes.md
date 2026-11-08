# Threshold Network (tBTC)

- Scope: 46 smart contract assets: ~38 EVM addresses (Ethereum: Bank, Bridge, TBTC, TBTCVault, LightRelay, MaintainerProxy,
  RedemptionWatchtower, WalletProposalValidator, DonationVault, L1 bitcoin depositors/redeemer proxies, WalletRegistry,
  EcdsaDkgValidator, ReimbursementPool, T, TokenholderGovernor...; tBTC tokens and gateways on Arbitrum, Base, Optimism,
  Polygon), the BOB cross-chain contracts (GitHub link), the tBTC TypeScript SDK, and Starknet/Sui/Solana contracts.
- Copied at their default branch main (keep-network/* redirects to threshold-network/*):
  - threshold-network/tbtc-v2 (5d2af6cd, AGPL-3.0): solidity/contracts (bridge, vault, relay, maintainer...) and
    cross-chain/* (bob in scope by link; arbitrum, base, optimism, polygon, starknet, sui depositors...), with the npm packages
    its projects import (@keep-network/ecdsa and random-beacon at tbtc-v2's pinned versions, bitcoin-spv-sol, OZ, thesis).
  - threshold-network/solidity-contracts (25e3b753, GPL-3.0-or-later): T token, TokenStaking, TokenholderGovernor.
  - threshold-network/keep-core (b6964c86, MIT; Go node, only solidity/ecdsa and solidity/random-beacon have EVM sources):
    WalletRegistry, EcdsaDkgValidator, WalletRegistryGovernance, ReimbursementPool.
- Left out (non-EVM): the TypeScript SDK (tbtc-v2/typescript), the Starknet (Cairo), Sui (Move) and Solana contracts.
- Deployed versions not checked against the explorers (scope gives addresses only).
