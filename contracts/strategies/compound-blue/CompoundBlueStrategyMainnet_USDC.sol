//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CompoundBlueStrategy.sol";

contract CompoundBlueStrategyMainnet_USDC is CompoundBlueStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359);
    address market = address(0x781FB7F6d845E3bE129289833b04d43Aa8558c42);
    address comp = address(0x8505b9d2254A7Ae468c0E9dd10Ccea3A837aef5c);
    address wpol = address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    CompoundBlueStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      market,
      wpol
    );
    rewardTokens = [wpol, comp];
  }
}
