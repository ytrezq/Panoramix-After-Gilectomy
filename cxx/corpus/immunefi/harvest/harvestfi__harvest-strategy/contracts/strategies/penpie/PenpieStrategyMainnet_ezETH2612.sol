//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./PenpieStrategy.sol";

contract PenpieStrategyMainnet_ezETH2612 is PenpieStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xD8F12bCDE578c653014F27379a6114F67F0e445f); //ezETH Pendle Market
    address rewardPool = address(0x16296859C15289731521F199F0a5f762dF6347d0); //MasterPenpie
    address ezeth = address(0xbf5495Efe5DB9ce00f80364C8B423567e58d2110);
    address syezeth = address(0x22E12A50e3ca49FB183074235cB1db84Fe4C716D);
    address pendle = address(0x808507121B80c02388fAd14726482e061B8da827);
    PenpieStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      pendle,
      ezeth,
      syezeth
    );
    rewardTokens = [pendle];
  }
}
