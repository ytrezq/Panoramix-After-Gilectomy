# Balancer

- Scope: 24 Ethereum addresses: V2 (Vault, Authorizer, AuthorizerAdaptor, BalancerRelayer and BatchRelayerLibrary V6) and V3
  (Vault, VaultAdmin, VaultExtension, Router, BatchRouter, BufferRouter, CompositeLiquidityRouter, ProtocolFeeController,
  Weighted/Stable/StableSurge/LBP/FixedPriceLBP/Gyro 2-CLP/Gyro E-CLP/ReClamm pool factories, LP oracle factories).
- Every name matched to the three repositories the page links (for their audits), copied at their default branches:
  - balancer/balancer-v2-monorepo (master e91a2b64; GPL-3.0 per package.json, root license read as AGPL-3.0): 424 .sol + 8 .vy.
  - balancer/balancer-v3-monorepo (main 2b9ce4b1): vault, pool-weighted (LBP, fixed-price LBP), pool-stable, pool-gyro,
    pool-hooks (StableSurge), oracles; 579 .sol with its npm imports.
  - balancer/reclamm (default branch reclamm-2.1, 6a13f2c9; the page's audit link names main): ReClammPoolFactory.
- The factories' "(V2)/(V3)/(V4)" deployment versions were not checked against the explorer; the copies are branch heads.
