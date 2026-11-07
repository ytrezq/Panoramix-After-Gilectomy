//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./FluidLendStrategy.sol";

contract FluidLendStrategyMainnet_USDT is FluidLendStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    address fToken = address(0x5C20B550819128074FD538Edf79791733ccEdd18);
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