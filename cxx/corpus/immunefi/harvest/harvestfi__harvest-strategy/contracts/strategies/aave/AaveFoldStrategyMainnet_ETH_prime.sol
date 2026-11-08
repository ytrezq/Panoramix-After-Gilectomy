//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./AaveFoldStrategy.sol";

contract AaveFoldStrategyMainnet_ETH_prime is AaveFoldStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address aToken = address(0xfA1fDbBD71B0aA16162D76914d69cD8CB3Ef92da);
    address debtToken = address(0x91b7d78BF92db564221f6B5AeE744D1727d1Dd1e);
    address usdc = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    AaveFoldStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      aToken,
      debtToken,
      usdc,
      0,
      1,
      1000,
      false
    );
    rewardTokens = [aToken];
  }
}
