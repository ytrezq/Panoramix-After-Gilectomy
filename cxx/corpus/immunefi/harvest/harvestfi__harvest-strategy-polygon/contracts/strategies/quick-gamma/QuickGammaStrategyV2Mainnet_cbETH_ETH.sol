//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./QuickGammaStrategyV2.sol";

contract QuickGammaStrategyV2Mainnet_cbETH_ETH is QuickGammaStrategyV2 {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x0668331b4606bEb78A1c8314e08d8B07653fbD3C);
    address quick = address(0xB5C064F955D8e7F38fE0460C556a72987494eE17);
    address masterChef = address(0x20ec0d06F447d550fC6edee42121bc8C1817b97D);
    QuickGammaStrategyV2.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      masterChef,
      78,
      quick,
      address(0xA42d55074869491D60Ac05490376B74cF19B00e6) //UniProxy
    );
    rewardTokens = [quick];
  }
}
