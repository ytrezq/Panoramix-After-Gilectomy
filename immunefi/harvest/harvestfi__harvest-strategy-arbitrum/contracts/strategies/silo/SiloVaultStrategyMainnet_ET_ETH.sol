//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./SiloVaultStrategy.sol";

contract SiloVaultStrategyMainnet_ET_ETH is SiloVaultStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address fToken = address(0xd8c989aB5f5b2ABDc76a8D3Acec165300BF30ecD);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    SiloVaultStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      fToken,
      arb
    );
    rewardTokens = [arb];
    distributionTime[arb] = 86400;
  }
}