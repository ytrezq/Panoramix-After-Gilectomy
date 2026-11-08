//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./PenpieStrategy.sol";

contract PenpieStrategyMainnet_sUSDe2612 is PenpieStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xa0ab94DeBB3cC9A7eA77f3205ba4AB23276feD08); //sUSDe Pendle Market
    address rewardPool = address(0x16296859C15289731521F199F0a5f762dF6347d0); //MasterPenpie
    address susde = address(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);
    address sysusde = address(0xD288755556c235afFfb6316702719C32bD8706e8);
    address pendle = address(0x808507121B80c02388fAd14726482e061B8da827);
    PenpieStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      pendle,
      susde,
      sysusde
    );
    rewardTokens = [pendle];
  }
}
