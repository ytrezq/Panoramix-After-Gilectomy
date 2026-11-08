# Katana

- Scope: 21 addresses, mostly on Katana: KAT, vault bridge tokens (WETH/vbETH, vbWBTC, vbUSDC, vbUSDT, vbUSDS) and their
  NativeConverters, the Agglayer bridge, avKAT, vKAT and its escrow, KAT OFT adapter, JitoSOL OFT; on Ethereum KAT OFT,
  OptimismPortal and AggchainFEP; on Base KAT OFT. Plus primacy of impact. Matched by name to repositories (default branches,
  2026-11-07, unless noted):
  - katana-network/kat-token (54894989, Apache-2.0): KatToken.
  - katana-network/katana-governance (2fe29c49): AvKATVault, vKAT factory/metadata; vKAT escrow = aragon/ve-governance
    VotingEscrowIncreasing (submodule, with aragon osx). No repository license: copied per file, 8 unlicensed files skipped.
  - katana-network/lz-kat-upgradeable (fe5979e1, MIT): KAT OFT / OFT adapter (upgradeable LayerZero V2 OFT; its README says
    Katana-BSC, the Ethereum/Base deployments are assumed to be the same code).
  - agglayer/agglayer-contracts (110bda5a, AGPL-3.0; = 0xPolygonHermez/zkevm-contracts): AgglayerBridge, AggchainFEP.
- Recorded by reference only: agglayer/vault-bridge at v1.0.0 (bd3ea7b4; tag linked by the program's audit link): vbTokens,
  custom tokens and NativeConverters, under LicenseRef-PolygonLabs-Source-Available.
- Not covered: OptimismPortal (standard OP Stack contract, ethereum-optimism/optimism, which the optimism program copies;
  version not determined); JitoSOL OFT (no repository found). Left out: agglayer/ulxly-contracts and lxly-bridge-and-call
  (linked for audits; superseded / not in the asset list), yearn-vaults-v3 (audits link).
