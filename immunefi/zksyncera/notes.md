# ZKsync Era

- Scope: 111 smart contract assets and 21 Blockchain/DLT assets. 91 are files of matter-labs/era-contracts pinned at commit
  7b75e11e (l1-contracts 56, system-contracts 31 incl. Yul, da-contracts 4); 19 are Ethereum/ZKsync addresses (Bridgehub,
  DiamondProxy, ChainTypeManager, L1Nullifier, L1ERC20Bridge, L2SharedBridge proxies; the ZK governance contracts).
- Copied matter-labs/era-contracts at 7b75e11e (the scope's commit; MIT; 978 .sol + 25 .yul, its submodules and the
  gas-bound-caller npm imports included); scope paths l1-contracts, system-contracts, da-contracts recorded.
- Governance addresses (ProtocolUpgradeHandler, SecurityCouncil, Guardians, EmergencyUpgradeBoard on L1; ZkToken,
  ZkProtocolGovernor, ZkTokenGovernor, TimelockControllers on ZKsync) matched to zksync-association/zk-governance: default
  branch master, 58df93fc, MIT. The proxies are OpenZeppelin TransparentUpgradeableProxy (in both repos' OZ submodules).
- Left out (Rust, no EVM sources): matter-labs/zksync-protocol (zkevm_circuits), zksync-crypto (snark-wrapper); the
  out-of-scope era-* Rust repos; the Tally proposal link.
- Deployed versions of the address-only governance contracts not checked against the explorers.
