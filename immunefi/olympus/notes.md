# olympus

- Scope: 71 smart-contract assets, explorer addresses on Ethereum (53), Arbitrum, Base, Berachain, Optimism, Polygon,
  Fantom, Avalanche: the Olympus v3 (Bophades) Kernel, modules and policies (Operator, Heart, Clearinghouse,
  EmissionManager, YRF, Cooler v2, CD facility / auctioneers, DepositManager, CCIP and cross-chain bridges), Governor
  Bravo, Timelock, CoolerFactory, Boosted Liquidity, and the v2 tokens (OHM, sOHM, gOHM, Staking, Treasury, v1 Migrator).
- No in-scope repository link (the page links OlympusDAO/olympus-contracts). Copied:
  OlympusDAO/olympus-v3 @ develop (default branch; master also exists, no doc ties a ref to the deployment): Kernel,
  modules, policies (BondManager, BondCallback, TreasuryCustodian, Emergency...), periphery, external/cooler,
  external/governance, with its Soldeer dependencies; and OlympusDAO/olympus-contracts @ main (v2: OHM, sOHM, gOHM,
  Staking, Treasury, migrators).
- olympus-v3 has no licence file nor package.json licence: its sources were copied per file by their own open SPDX
  headers (132 UNLICENSED / header-less / non-open files skipped, manifest skipped_unlicensed).
- Not obviously covered: "BondTeller" (Bond Protocol's external teller, not an Olympus source).
