# PancakeSwap

- Scope: 5 GitHub repositories as smart contract assets (no ref named) and the pancakeswap.finance website; no addresses.
- All 5 copied at their default branches: pancakeswap/infinity-core (main, 3c5ef1be), infinity-periphery (main, 56a7a4f5),
  infinity-universal-router (main, 1b6d479e), pancake-v3-contracts (main, 98684794: v3-core, v3-periphery, v3-lm-pool,
  masterchef-v3 projects with their npm imports), pancake-swap-periphery (V2 periphery, master, d769a6d1).
- infinity-universal-router and pancake-v3-contracts have no root LICENSE nor package.json license: copied per file from
  their SPDX headers (MIT/GPL); the UNLICENSED ones were left out (36 and 57 files, mostly tests, scripts and
  contracts/test helpers: manifest `skipped_unlicensed`).
- Left out: the website; Uniswap/v4-periphery (linked from the page, not in scope).
