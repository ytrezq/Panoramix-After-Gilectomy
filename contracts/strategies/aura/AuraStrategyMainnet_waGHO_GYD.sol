//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./AuraStrategy.sol";

contract AuraStrategyMainnet_waGHO_GYD is AuraStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xff38cC0cE0DE4476C5a3e78675b48420A851035B);
    address aura = address(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address gyd = address(0xCA5d8F8a8d49439357d3CF46Ca2e720702F132b8);
    address rewardPool = address(0x005DF7aC723E45Af4d7475A612a02f0565Eb3778);
    AuraStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      0xff38cc0ce0de4476c5a3e78675b48420a851035b000200000000000000000593,  // Balancer Pool id
      86,      // Aura Pool id
      gyd,     // depositToken
      true     // gyroPool
    );
    rewardTokens = [aura, bal];
  }
}
