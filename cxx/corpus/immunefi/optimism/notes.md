# optimism

- Scope: 19 smart-contract assets (Etherscan addresses of the OP Mainnet L1 contracts: OptimismPortal and its
  implementation, SystemConfig, L1CrossDomainMessenger, L1StandardBridge, L1ERC721Bridge, OptimismMintableERC20Factory,
  ProxyAdmin, AddressManager, DisputeGameFactory, FaultDisputeGame, PermissionedDisputeGame, AnchorStateRegistry,
  DelayedWETH, PreimageOracle, MIPS, L2OutputOracle; PolicyEngineStaking on OP Mainnet), 4 Blockchain/DLT assets
  (op-node, op-dispute-mon, op-reth in the monorepo @develop, Primacy of Impact) and 13 websites.
- Copied: ethereum-optimism/optimism @ develop (the ref the scope links name). Its EVM sources are
  packages/contracts-bedrock (src: L1, L2, dispute, cannon, governance, legacy, periphery/staking/PolicyEngineStaking,
  safe, universal...; tests and scripts; lib/ submodules: OpenZeppelin, solmate, solady, safe-contracts, forge-std,
  lib-keccak) plus a few test contracts elsewhere in the monorepo (op-e2e, op-chain-ops, op-service, op-reth tests).
- The Go / Rust node software (op-node, op-dispute-mon, op-reth) is in scope but not EVM: its sources are not copied.
- Not covered on develop: L2OutputOracle (removed from contracts-bedrock; the deployed one is from an older
  op-contracts release).
- Left out: ethereum-optimism/superchain-registry (configuration), paradigmxyz/reth and ethereum/devp2p (node software / spec).
