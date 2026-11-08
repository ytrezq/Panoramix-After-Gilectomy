// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

enum StablecoinType {
  EUR,
  USD
}

enum ContractType {
  EURp,
  USDp,
  LZEURp,
  LZUSDp,
  PRL,
  sEURp,
  sUSDp,
  Timelock,
  DaoMultisig,
  ProxyAdmin,
  GuardianMultisig,
  ParallelizerEURp,
  ParallelizerUSDp,
  TreasuryEURp,
  TreasuryUSDp,
  FlashLoan,
  MultiBlockRebalancer,
  GenericRebalancer,
  Harvester,
  Rebalancer,
  MulticallWithFailure,
  OracleNativeUSD,
  Swapper
}

library Constants {
  uint256 constant CHAIN_FORK = 0;
  uint256 constant CHAIN_ETHEREUM = 1;
  uint256 constant CHAIN_ARBITRUM = 42_161;
  uint256 constant CHAIN_AVALANCHE = 43_114;
  uint256 constant CHAIN_POLYGON = 137;
  uint256 constant CHAIN_FANTOM = 250;
  uint256 constant CHAIN_BASE = 8453;
  uint256 constant BASE_18 = 1e18;
  uint256 constant BASE_9 = 1e9;

  address constant IMMUTABLE_CREATE2_FACTORY_ADDRESS = 0x0000000000FFe8B47B3e2130213B802212439497;
}
