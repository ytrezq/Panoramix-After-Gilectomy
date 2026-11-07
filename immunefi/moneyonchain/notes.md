# moneyonchain

- Scope: 53 named Rootstock (RSK) addresses (MoC v1, Stable Protocol v2 / RIF on Chain, OMoC oracle, governance, splitters,
  rewards buffers, auctions, price providers), Primacy of Impact, the app. Only stable-protocol-core-v2 is linked in scope.
- Repositories matched by contract name among the 14 money-on-chain repositories the page links (default branches):
  stable-protocol-core-v2 (MocCore, MocCARC20, queues, MultiCollateralGuard, swappers, reverse auctions),
  main-RBTC-contract (MoC v1: MoC, MoCConnector, MoCState, MoCExchange, MoCInrate, DoC / BPro / MoC tokens,
  CommissionSplitter V2/V3), stable-protocol-roc-v2 (MocRif, USDRIF), OMoC-Decentralized-Oracle (CoinPairPrice,
  OracleManager, Delay/Staking/Vesting/VotingMachine, MocRegistry), MoC-Periphery (MocToken, Governor),
  Areopagus-Governance (Governor, UpgradeDelegator), price_oracle_interfaces (price providers, UniswapV3OracleUSD).
- Copied: Areopagus-Governance (AGPL-3.0) and price_oracle_interfaces (MIT). Recorded by reference only: the first four
  (MOC Investments Corp.'s proprietary LICENSE: all rights reserved, non-commercial use only) and MoC-Periphery (UNLICENSED).
- Left out: stable-protocol-interface-v3 (front end), automators, moc_prices_source, OMoC-Node (bots),
  proposals-changers (governance changers), Amphiraos-Oracle (old medianizer, not in the list), known-issues.
- Not obviously covered: RewardsBuffers, Coiner, PriceProviderRegistry, Oracle Info, Admin (no public repository found).
