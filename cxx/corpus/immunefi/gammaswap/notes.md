# GammaSwap

- Scope: 27 addresses on Arbitrum: GammaPoolFactory and beacon proxies, Vault
  pool and strategies (borrow, repay, short, rebalance, liquidation), CPMMMath,
  PositionManager, DeltaSwap (factory, router, pair), staking (StakingRouter,
  RewardTracker, RewardDistributor, BonusDistributor, FeeTracker, Vester,
  BeaconProxyFactory), GSTimelockController, the GS token and an Airdrop.
- No repository linked; matched by contract names in the gammaswap org (code
  search). Copied at their default branches (no deployment tags): v1-core,
  v1-implementations (BUSL-1.1), v1-deltaswap, v1-periphery (AGPL/GPL),
  v1-staking, timelock, gs-token (MIT).
- Not found: the Airdrop contract (0x4c02a44b...0f98) in any public repository.
- The repositories import each other as @gammaswap/* npm packages, published on
  GitHub Packages (needs credentials): not fetched (npm_errors); the sibling
  copies hold those sources, at their default branches.
