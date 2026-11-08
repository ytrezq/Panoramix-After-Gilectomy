//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./SiloLendStrategy.sol";

contract SiloLendStrategyMainnet_USDC_sUSDX is SiloLendStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    address silo = address(0x2433D6AC11193b4695D9ca73530de93c538aD18a);
    SiloLendStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      silo
    );
  }
}