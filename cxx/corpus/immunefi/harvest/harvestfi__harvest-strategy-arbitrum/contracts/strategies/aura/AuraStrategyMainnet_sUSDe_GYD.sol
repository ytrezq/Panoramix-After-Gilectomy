//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./AuraStrategy.sol";

contract AuraStrategyMainnet_sUSDe_GYD is AuraStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xdeEaF8B0A8Cf26217261b813e085418C7dD8F1eE);
    address aura = address(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address gyd = address(0xCA5d8F8a8d49439357d3CF46Ca2e720702F132b8);
    address rewardPool = address(0x2d7cFe43BcDf10137924a20445B763Fb40E5871c);
    AuraStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      0xdeeaf8b0a8cf26217261b813e085418c7dd8f1ee00020000000000000000058f,  // Balancer Pool id
      82,      // Aura Pool id
      gyd,     // depositToken
      true     // gyroPool
    );
    rewardTokens = [aura, bal];
  }
}
