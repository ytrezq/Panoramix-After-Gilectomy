//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./MorphoLendStrategy.sol";

contract MorphoLendStrategyMainnet_GauntletDAI is MorphoLendStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address morphoVault = address(0x500331c9fF24D9d11aee6B07734Aa72343EA74a5);
    MorphoLendStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      morphoVault
    );
  }
}