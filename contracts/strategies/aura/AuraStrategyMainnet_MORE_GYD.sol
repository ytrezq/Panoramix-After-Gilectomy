//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./AuraStrategy.sol";

contract AuraStrategyMainnet_MORE_GYD is AuraStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x4284c68f567903537E2d9Ff726fdF8591E431DDC);
    address aura = address(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address usdc = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    address gyd = address(0xCA5d8F8a8d49439357d3CF46Ca2e720702F132b8);
    address rewardPool = address(0x159e8E79b63f345461613c97c58B21509287f647);
    AuraStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      0x4284c68f567903537e2d9ff726fdf8591e431ddc0002000000000000000005b5,  // Balancer Pool id
      90,      // Aura Pool id
      gyd,     // depositToken
      true     // gyroPool
    );
    rewardTokens = [aura, bal, usdc];
  }
}
