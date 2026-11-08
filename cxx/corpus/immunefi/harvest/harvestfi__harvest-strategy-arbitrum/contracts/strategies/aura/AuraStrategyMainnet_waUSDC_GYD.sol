//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./AuraStrategy.sol";

contract AuraStrategyMainnet_waUSDC_GYD is AuraStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x6e822c64c00393b2078f2a5BB75c575aB505B55c);
    address aura = address(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address gyd = address(0xCA5d8F8a8d49439357d3CF46Ca2e720702F132b8);
    address rewardPool = address(0x78118Bc631b0eb2FB6A350f12e0334535783e49F);
    AuraStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      0x6e822c64c00393b2078f2a5bb75c575ab505b55c000200000000000000000548,  // Balancer Pool id
      74,      // Aura Pool id
      gyd,     // depositToken
      true     // gyroPool
    );
    rewardTokens = [aura, bal];
  }
}
