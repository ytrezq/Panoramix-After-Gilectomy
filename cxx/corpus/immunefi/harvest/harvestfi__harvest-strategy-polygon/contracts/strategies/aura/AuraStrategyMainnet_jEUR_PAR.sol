//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./AuraStrategy.sol";

contract AuraStrategyMainnet_jEUR_PAR is AuraStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x513CdEE00251F39DE280d9E5f771A6eaFebCc88E);
    address aura = address(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
    address bal = address(0x9a71012B13CA4d3D0Cdc72A177DF3ef03b0E76A3);
    address rewardPool = address(0x333122d446A950a951942a6C065b6ebBEE72EA98);
    AuraStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      0x513cdee00251f39de280d9e5f771a6eafebcc88e000000000000000000000a6b,  // Balancer Pool id
      6,      // Aura Pool id
      underlying   //depositToken
    );
    rewardTokens = [aura, bal];
  }
}
