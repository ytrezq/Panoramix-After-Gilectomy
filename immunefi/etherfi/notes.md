# Ether.fi

- Scope: 57 addresses - staking protocol on Ethereum (LiquidityPool, eETH, weETH,
  StakingManager, NodesManager, Liquifier, Restaker, oracle, admin...), ether.fi
  Cash on Scroll and its Ethereum top-up adapters, weETH on Optimism/Arbitrum/
  zkEVM with the L1 sync pool and OFT adapter, one "Liquid Vault" - plus websites.
- Copied at default branches (no deployment tags): etherfi-protocol/smart-contracts
  and cash-v3 (linked by the page), etherfi-protocol/weETH-cross-chain (OFTs,
  EtherfiL1SyncPoolETH; found by code search), PeggyJV/cellar-contracts (the
  Liquid Vault 0xeA1A6307...a221 is a Sommelier Cellar on Etherscan).
- cash-v3's default branch has refactored deployed contracts (SettlementDispatcherV2,
  CashModuleCore, DebtManagerCore, TopUpFactory); PixWalletAutoTopup,
  TopUpSourceFactory, LiquidUSDLiquifierModule are not found under those names.
- smart-contracts and cash-v3 have no license file: only sources with an open SPDX
  header are copied (46 and 3 skipped: UNLICENSED or header-less).
