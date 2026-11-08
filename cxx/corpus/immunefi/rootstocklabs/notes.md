# RootstockLabs

- Scope: Flyover (fast BTC peg-in/peg-out) contracts on Rootstock given as explorer addresses (PegInContract, PegOutContract,
  CollateralManagementContract, FlyoverDiscovery, PauseRegistry, Quotes, BtcUtils, SignatureValidator), the RIF token, plus
  Blockchain/DLT and web assets (rskj, powpeg-node, rsk-powhsm, bridges-core-sdk, flyover-sdk, liquidity-provider-server).
- Copied rsksmart/liquidity-bridge-contract at tag v2.0.1 (commit 4066b8fb, the latest release, which has all the split
  Flyover contracts; master was newer by two months): MIT. BtcUtils comes with it as the npm package
  @rsksmart/btc-transaction-solidity-helper 0.3.0 (node_modules/).
- RIF Token (0x2acc9575...): riflabs/RIF-Token (RIFToken.sol, 2018-era): recorded by reference only, no license file nor
  SPDX headers.
- Left out (no EVM contracts: Java node with a native Bridge precompile, HSM firmware, TypeScript SDKs, Go LP server): rskj,
  powpeg-node, rsk-powhsm, bridges-core-sdk, flyover-sdk, liquidity-provider-server.
- Deployed versions not checked against the explorer (the scope gives addresses only).
