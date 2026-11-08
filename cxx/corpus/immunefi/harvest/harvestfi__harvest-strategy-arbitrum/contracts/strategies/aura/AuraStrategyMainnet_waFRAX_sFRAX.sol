//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./AuraStrategy.sol";

contract AuraStrategyMainnet_waFRAX_sFRAX is AuraStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x36C2f879f446c3b6533f9703745C0504f3a84885);
    address aura = address(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address sFrax = address(0xe3b3FE7bcA19cA77Ad877A5Bebab186bEcfAD906);
    address rewardPool = address(0xE6940b5FF5C0b4A09576667c7F71953a200e666A);
    AuraStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      0x36c2f879f446c3b6533f9703745c0504f3a84885000200000000000000000591,  // Balancer Pool id
      81,      // Aura Pool id
      sFrax,     // depositToken
      true     // gyroPool
    );
    rewardTokens = [aura, bal];
  }
}
