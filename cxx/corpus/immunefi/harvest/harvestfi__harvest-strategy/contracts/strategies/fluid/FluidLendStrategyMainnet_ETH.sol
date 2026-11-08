//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./FluidLendStrategy.sol";

contract FluidLendStrategyMainnet_ETH is FluidLendStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address fToken = address(0x90551c1795392094FE6D29B758EcCD233cFAa260);
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