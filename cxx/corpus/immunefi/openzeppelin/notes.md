# OpenZeppelin

- Scope: 6 smart contract assets, all GitHub (no addresses).
- openzeppelin-contracts, openzeppelin-contracts-upgradeable and uniswap-hooks: the scope names no version, so their default
  branch (master) was taken: efaa6f78, 64dd3a63 (its lib/openzeppelin-contracts submodule included), b5f10574.
  The latest releases on 2026-11-07 were v5.7.0 and uniswap-hooks v1.2.1, not copied separately.
- openzeppelin-confidential-contracts: "only the latest release v0.5.3 (4a4f6c71) is in scope, mocks and examples out of scope":
  copied at tag v0.5.3 (whole repo's EVM sources, mocks included; @fhevm/solidity and encrypted-types npm packages included).
- openzeppelin-community-contracts: only AxelarGatewayAdapter.sol and ERC7786OpenBridge.sol "at commit 0361935d" are in scope:
  copied at that commit with those two scope paths recorded.
- All MIT, all copied. Nothing left out.
