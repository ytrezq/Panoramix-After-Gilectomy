//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./AuraStrategy.sol";

contract AuraStrategyMainnet_waUSDT_GYD is AuraStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x7272163A931DaC5BBe1CB5feFaF959BB65F7346F);
    address aura = address(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address gyd = address(0xCA5d8F8a8d49439357d3CF46Ca2e720702F132b8);
    address rewardPool = address(0x66EeE72121E64Cd5fb67B306087511ca20B1956E);
    AuraStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      0x7272163a931dac5bbe1cb5fefaf959bb65f7346f000200000000000000000549,  // Balancer Pool id
      71,      // Aura Pool id
      gyd,     // depositToken
      true     // gyroPool
    );
    rewardTokens = [aura, bal];
  }
}
