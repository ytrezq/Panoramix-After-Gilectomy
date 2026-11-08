//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./PenpieStrategy.sol";

contract PenpieStrategyMainnet_USDe2612 is PenpieStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x8a49f2AC2730ba15AB7EA832EdaC7f6BA22289f8); //USDe Pendle Market
    address rewardPool = address(0x16296859C15289731521F199F0a5f762dF6347d0); //MasterPenpie
    address usde = address(0x4c9EDD5852cd905f086C759E8383e09bff1E68B3);
    address syusde = address(0xd29a7D69cF5f06CCd777e53d6E437032804aBf89);
    address pendle = address(0x808507121B80c02388fAd14726482e061B8da827);
    PenpieStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      pendle,
      usde,
      syusde
    );
    rewardTokens = [pendle];
  }
}
