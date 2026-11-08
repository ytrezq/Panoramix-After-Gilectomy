//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./MorphoLendStrategy.sol";

contract MorphoLendStrategyMainnet_GauntletUSDC is MorphoLendStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address morphoVault = address(0x8eB67A509616cd6A7c1B3c8C21D48FF57df3d458);
    MorphoLendStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      morphoVault
    );
  }
}