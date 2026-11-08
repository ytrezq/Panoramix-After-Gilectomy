//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./AuraStrategy.sol";

contract AuraStrategyMainnet_APW_ETH is AuraStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x093254005743b7Af89e24F645730Ba2dD8441333);
    address aura = address(0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF);
    address bal = address(0xba100000625a3754423978a60c9317c58a424e3D);
    address rewardPool = address(0x3Db0d3b807CdF9d22c4691503a78582cb96D0653);
    AuraStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      0x093254005743b7af89e24f645730ba2dd84413330002000000000000000006a4,  // Balancer Pool id
      225,      // Aura Pool id
      weth   //depositToken
    );
    rewardTokens = [aura, bal];
  }
}
