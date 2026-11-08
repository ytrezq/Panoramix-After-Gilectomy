//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./SiloLendStrategy.sol";

contract SiloLendStrategyMainnet_USDC_PENDLE is SiloLendStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    address silo = address(0x86B1C293e56cBAC04D9C15A1Af2Ef1d2050ff6Cd);
    SiloLendStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      silo
    );
  }
}