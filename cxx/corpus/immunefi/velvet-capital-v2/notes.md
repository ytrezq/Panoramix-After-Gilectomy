# Velvet Capital V2

- Scope: 13 Base addresses: DepositBatch, DepositManager, WithdrawBatch, WithdrawManager, EnsoHandler, Portfolio,
  TokenExclusionManager, Rebalancing, AssetManagementConfig and FeeModule implementations, PortfolioFactory, ProtocolConfig,
  PriceOracle; plus primacy of impact. No repository linked (only Velvet-Capital/audits).
- Matched to Velvet-Capital/velvet-core (contracts/bundle/DepositBatch, WithdrawManager, PortfolioFactory, config/protocol/
  ProtocolConfig, core/management/TokenExclusionManager...): copied at its default branch main (bd2b8a1d, 2025-09-04,
  BUSL-1.1), 103 .sol with its npm imports (OpenZeppelin 4.8.2/4.9.6 aliases, Chainlink, Uniswap lib, Gnosis zodiac).
- Default branch taken (no doc ties a commit to the deployment); not checked against the Base explorer.
