//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./MorphoVaultV2Strategy.sol";

contract MorphoVaultStrategyMainnet_SHHY_USDC_V2 is MorphoVaultV2Strategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    address morphoVault = address(0xbeeff1D5dE8F79ff37a151681100B039661da518);
    address weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address morpho = address(0x40BD670A58238e6E230c430BBb5cE6ec0d40df48);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    MorphoVaultV2Strategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      morphoVault,
      weth
    );
    rewardTokens = [morpho, arb];
    _setDistributionTime(morpho, 172_800); // 48 hours
    _setDistributionTime(arb, 172_800); // 48 hours
  }
}
