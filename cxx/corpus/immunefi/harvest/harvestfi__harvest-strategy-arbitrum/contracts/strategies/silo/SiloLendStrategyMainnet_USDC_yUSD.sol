//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./SiloLendStrategy.sol";

contract SiloLendStrategyMainnet_USDC_yUSD is SiloLendStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    address silo = address(0x1cf4649a2b38747F8E3E70e00f6FA5AEB14A12ba);
    SiloLendStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      silo
    );
  }
}