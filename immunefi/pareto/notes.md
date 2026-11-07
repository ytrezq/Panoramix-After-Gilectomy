# Pareto Credit

- Scope: the docs page docs.pareto.credit/developers/addresses/product/credit-vaults and 23 Ethereum addresses of credit vaults
  (Fasanara, Adaptive Frontier, FalconX, RockawayX, M1 Capital, TwoPrime): vault contract, strategy, LP token, queue each.
- The docs give the vaults' ABI as Idle-Labs/idle-tranches abi/IdleCDOEpochVariant.json; that repository holds
  IdleCDOEpochVariant (vault), strategies/idle/IdleCreditVault (strategy), IdleCDOEpochQueue (queue), IdleCDOTranche (LP
  token), IdleCreditVaultFactory, write-off escrow...
- Copied Idle-Labs/idle-tranches at its default branch master (539dba67, MIT per package.json): 265 .sol (the older Idle
  tranche strategies included) with 20 submodules and its npm imports.
- Default branch taken (no doc ties a commit to the deployments); not checked against Etherscan.
