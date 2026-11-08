//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./AaveFoldStrategy.sol";

contract AaveFoldStrategyMainnet_ETH is AaveFoldStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address aToken = address(0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8);
    address debtToken = address(0xeA51d7853EEFb32b6ee06b1C12E6dcCA88Be0fFE);
    address usdc = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    AaveFoldStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      aToken,
      debtToken,
      usdc,
      0,
      804,
      1000,
      false
    );
    rewardTokens = [usdc];
  }
}
