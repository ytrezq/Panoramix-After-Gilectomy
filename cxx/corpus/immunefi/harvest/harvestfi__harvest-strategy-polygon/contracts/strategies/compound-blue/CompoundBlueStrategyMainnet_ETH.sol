//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CompoundBlueStrategy.sol";

contract CompoundBlueStrategyMainnet_ETH is CompoundBlueStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619);
    address market = address(0xF5C81d25ee174d83f1FD202cA94AE6070d073cCF);
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
