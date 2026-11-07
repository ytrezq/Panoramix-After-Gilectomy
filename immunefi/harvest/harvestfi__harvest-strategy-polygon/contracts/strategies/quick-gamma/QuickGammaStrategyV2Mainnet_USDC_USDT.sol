//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./QuickGammaStrategyV2.sol";

contract QuickGammaStrategyV2Mainnet_USDC_USDT is QuickGammaStrategyV2 {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x795f8c9B0A0Da9Cd8dea65Fc10f9B57AbC532E58);
    address quick = address(0xB5C064F955D8e7F38fE0460C556a72987494eE17);
    address wmatic = address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    address masterChef = address(0x20ec0d06F447d550fC6edee42121bc8C1817b97D);
    QuickGammaStrategyV2.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      masterChef,
      11,
      wmatic,
      address(0xA42d55074869491D60Ac05490376B74cF19B00e6) //UniProxy
    );
    rewardTokens = [quick, wmatic];
  }
}
