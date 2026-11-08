//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./PenpieStrategy.sol";

contract PenpieStrategyMainnet_stETH2512 is PenpieStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xC374f7eC85F8C7DE3207a10bB1978bA104bdA3B2); //stETH Pendle Market
    address rewardPool = address(0x16296859C15289731521F199F0a5f762dF6347d0); //MasterPenpie
    address wsteth = address(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    address systeth = address(0xcbC72d92b2dc8187414F6734718563898740C0BC);
    address pendle = address(0x808507121B80c02388fAd14726482e061B8da827);
    PenpieStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      pendle,
      wsteth,
      systeth
    );
    rewardTokens = [pendle];
  }
}
