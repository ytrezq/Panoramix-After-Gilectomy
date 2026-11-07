//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./FluidLendStrategy.sol";

contract FluidLendStrategyMainnet_USDT is FluidLendStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    address fToken = address(0x4A03F37e7d3fC243e3f99341d36f4b829BEe5E03);
    address weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    FluidLendStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      fToken,
      weth
    );
  }

  function finalizeUpgrade() override external onlyGovernance {
    address fluid = address(0x61E030A56D33e8260FdD81f03B162A79Fe3449Cd);
    _setRewardToken(fluid);
    rewardTokens = [fluid];
    distributionTime[fluid] = 0;
    _finalizeUpgrade();
  }
}