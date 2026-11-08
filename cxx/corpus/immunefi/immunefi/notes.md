# Immunefi: EVM, no public source repository for the in-scope contracts

- Scope: two Ethereum addresses labelled "Vault" (0x03fd3d61...) and "Splitter" (0x323498d3...), plus websites
  (immunefi.com, bugs.immunefi.com, ironscore) and primacy of impact.
- Both addresses are verified on Etherscan as contract `Splitter` (Foundry layout: src/Splitter.sol, src/Withdrawable.sol,
  lib/openzeppelin-contracts, solc 0.8.18).
- Not in immunefi-team/vaults (the Safe-module vault system: ImmunefiModule, RewardSystem, WithdrawalSystem... no Splitter),
  and no splitter repository found under immunefi-team: nothing copied. Main may fetch the verified source from Etherscan.
