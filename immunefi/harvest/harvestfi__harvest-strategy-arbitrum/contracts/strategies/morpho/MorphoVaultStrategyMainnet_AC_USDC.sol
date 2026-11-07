//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./MorphoVaultStrategy.sol";

contract MorphoVaultStrategyMainnet_AC_USDC is MorphoVaultStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    address morphoVault = address(0x64A651D825FC70Ebba88f2E1BAD90be9A496C4b9);
    address weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    MorphoVaultStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      morphoVault,
      weth
    );
    rewardTokens = [arb];
    distributionTime[arb] = 86400;
  }
}
