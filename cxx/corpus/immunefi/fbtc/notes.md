# FBTC

- Scope: 36 addresses, the same contract set on Mantle, Ethereum, BNB Chain, Arbitrum, BOB and Base: FireBridge, Minter,
  FToken (FBTC), FeeModel, GovernorModule, Factory.
- Copied fbtc-xyz/fbtc-contract (linked from the page for its audits) at its default branch main (4e4288a4): FireBridge,
  FBTC/FToken, FBTCMinter, FeeModel, FBTCGovernorModule and their bases; no repository license, copied per file from SPDX
  headers (4 unlicensed files skipped).
- Dependencies missing: remappings.txt points @openzeppelin/contracts(-upgradeable) and forge-std into lib/, which the
  repository does not commit (no .gitmodules, no package.json): the copy is not compilable as is (OpenZeppelin 5.x judging by
  the import paths, solc 0.8.20).
- Not located: the "Factory Contract" addresses (no factory in the repository; perhaps a Safe/CREATE3 deployer).
