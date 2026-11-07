//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./AaveSupplyStrategy.sol";

contract AaveSupplyStrategyMainnet_ETH is AaveSupplyStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address aToken = address(0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    address aArb = address(0x6533afac2E7BCCB20dca161449A13A32D391fb00);
    AaveSupplyStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      aToken,
      arb
    );
    rewardTokens = [aArb];
    distributionTime[aArb] = 86400;
  }

  function finalizeUpgrade() override external onlyGovernance {
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    address aArb = address(0x6533afac2E7BCCB20dca161449A13A32D391fb00);
    _setRewardToken(arb);
    rewardTokens = [aArb];
    distributionTime[aArb] = 86400;
    _finalizeUpgrade();
  }
}