# polygon

- Scope: 8 smart-contract and 5 Blockchain/DLT assets. The contracts come from three scope documents in
  0xPolygon/security@main (scope-spol-contracts.md, scope-pos-contracts.md, scope-pol-token.md: each names a repository
  and lists deployed addresses) and 4 Etherscan addresses of the LXLY AggLayer (Gateway, PolygonRollupManager,
  PolygonBridgeV2, PolygonGlobalExitRoot); plus Primacy of Impact.
- Copied, the repositories the documents name: 0xPolygon/sPOL-contracts@main, 0xPolygon/pos-contracts (default branch:
  Plasma / staking contracts, StateSender, predicates, StateReceiver), 0xPolygon/pol-token@main (POL, emission manager,
  migration); and for addresses those documents list: maticnetwork/pos-portal@master (RootChainManager,
  ChildChainManager) and 0xPolygon/genesis-contracts@master (BorValidatorSet, StateReceiver).
- AggLayer: agglayer/agglayer-contracts@main (no doc ties a tag to the deployment). main renamed the contracts
  (AgglayerGateway, AgglayerManager, AgglayerBridge, AgglayerGER); the scope's names are those of releases up to
  v11.0.0 (contracts/v2/AggLayerGateway, PolygonRollupManager, PolygonZkEVMBridgeV2, PolygonZkEVMGlobalExitRootV2).
- Left out: bor, heimdall-v2, cometbft and cosmos-sdk forks (Blockchain/DLT assets: Go node software).
- Not obviously covered: EIP1559Burn (L1 and Polygon) and WMATIC from the PoS list.
