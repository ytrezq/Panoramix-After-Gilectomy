//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./PenpieStrategy.sol";

contract PenpieStrategyMainnet_ETHx2612 is PenpieStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xFf262396f2A35Cd7Aa24b7255E7d3f45f057Cdba); //ETHx Pendle Market
    address rewardPool = address(0x16296859C15289731521F199F0a5f762dF6347d0); //MasterPenpie
    address ethx = address(0xA35b1B31Ce002FBF2058D22F30f95D405200A15b);
    address syethx = address(0xcb166f0148Ae815313039d735E28FCeC617B21Fe);
    address pendle = address(0x808507121B80c02388fAd14726482e061B8da827);
    PenpieStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      pendle,
      ethx,
      syethx
    );
    rewardTokens = [pendle];
  }
}
