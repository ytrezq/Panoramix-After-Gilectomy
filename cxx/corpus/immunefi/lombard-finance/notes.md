# lombard-finance

- Scope: 51 smart-contract assets: GitHub links into five repositories (all @main) and 10 Etherscan addresses (LBTC,
  Proxy Upgrade Timelock, Consortium, BasculeV1, GMPBasculeV1, BTC.b, AssetRouter, Mailbox, BridgeV2, StakedLBTCOracle),
  plus Primacy of Impact and the website / dApp.
- Copied: lombard-finance/evm-smart-contracts @ main (23 scope files: LBTC, AssetRouter, Consortium, Bascule, bridge and
  its providers, GMP mailbox, strategies, stake-and-bake depositors, StakedLBTCOracle) and Liquid-Bitcoin/BARD @ main
  (contracts/BARD: the BARD token and TokenDistributor), both from the scope links.
- Left out (not EVM): lombard-finance/sui-move-contracts (Move), starknet-cairo-contracts (Cairo),
  sol-svm-contracts (Solana programs).
- The explorer addresses map to evm-smart-contracts (LBTC/NativeLBTC/StakedLBTC, consortium/Consortium and
  LombardTimeLock, bridge/BridgeV2, gmp mailbox, AssetRouter, StakedLBTCOracle). main holds Bascule, BasculeV2/V3 and
  GMPBasculeV2 rather than the deployed "BasculeV1" / "GMPBasculeV1"; BTC.b is not obviously covered (only a BTCBMock).
