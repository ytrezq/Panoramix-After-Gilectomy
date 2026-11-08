//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CompoundBlueStrategy.sol";

contract CompoundBlueStrategyMainnet_USDT is CompoundBlueStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xc2132D05D31c914a87C6611C10748AEb04B58e8F);
    address market = address(0xfD06859A671C21497a2EB8C5E3fEA48De924D6c8);
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
