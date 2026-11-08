# ZKsync OS

- Scope: 230 GitHub links, all at fixed commits: the ZKsync OS state
  transition (zksync-os, Rust, with its EVM interpreter), the Airbender prover
  and verifiers (airbender-platform, zksync-airbender, zkos-wrapper,
  zksync-crypto, Rust), and 57 paths of matter-labs/era-contracts.
- Copied: matter-labs/era-contracts @e8e5d893b74363f9ef47bb139c06e78663ad17ed
  (the scope commit), with its submodules; the 57 scope paths (L1 contracts,
  DA validators, L2/system contracts) are recorded in the manifest.
- l1-contracts and da-contracts target the EVM; system-contracts (Solidity and
  Yul) and l2-contracts are built with zksolc for ZKsync's L2.
- Left out: the five Rust repositories (no EVM sources).
- l1-, l2-, system- and da-contracts/lib/* are symlinks to the root lib/
  submodules; they are recreated as symlinks in the copy.
