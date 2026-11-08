//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./FluidLendStrategy.sol";

contract FluidLendStrategyMainnet_USDC is FluidLendStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address fToken = address(0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33);
    address weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    FluidLendStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      fToken,
      weth
    );
  }
}