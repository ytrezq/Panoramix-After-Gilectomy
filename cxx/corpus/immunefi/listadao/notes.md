# Lista DAO (listadao)

- Scope: 57 addresses (56 on BSC, ListaOFT on Ethereum): the lisUSD CDP (lisUSD, GemJoins, clipCE/Clipper, collateral oracles, ResilientOracle), clisBNB/slisBNB and ListaStakeManager, MasterVault and its strategies, the lisUSD PSM (PSM, VaultManager, VenusAdapter, LisUSDPoolSet, EarnPool), LISTA distributors and veLISTA revenue/rebate contracts, ListaOFT/ListaOFTAdapter, and the Moolah lending protocol (Moolah, providers, PublicLiquidator, LendingRewardsDistributor). No repository is linked in the scope.
- Copied (all default branch; no release tags tie them to the deployments), from the lista-dao GitHub organization, matched by contract names:
  - lista-dao/lista-dao-contracts (archived; master 3e120da): CDP, lisUSD, clisBNB, oracles incl. ResilientOracle, MasterVault, strategies, contracts/psm (PSM, VaultManager, VenusAdapter, LisUSDPoolSet, EarnPool), SlisBNBProvider.
  - lista-dao/synclub-contracts (a8b7ca7): slisBNB, ListaStakeManager.
  - lista-dao/lista-token (28a3c02): ListaOFT, ListaOFTAdapter, Borrow/Collateral/StakeLisUSD Lista distributors, VeListaRevenueDistributor.
  - lista-dao/lista-new-contracts (5f4349d): LendingRewardsDistributor, VeListaInterestRebater.
  - lista-dao/moolah (abf1889): Moolah, PublicLiquidator, BNBProvider, SlisBNBProvider.
- Not obviously covered: "ERC20TokenProvider" (0x2725d733...): no file of that name (closest: lista-token's ERC20LpTokenProvider, lista-dao-contracts' BaseTokenProvider).
- Not taken: lista-v2/lista-v3 (DEX, not in scope), lista-eth-contracts (an airdrop distributor), lista-smart-contracts_deprecated (older copy of the CDP), SDKs and bots.
