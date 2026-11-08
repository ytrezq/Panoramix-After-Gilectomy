//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./AuraStrategy.sol";

contract AuraStrategyMainnet_waUSDC_GHO is AuraStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x46472CBA35E6800012aA9fcC7939Ff07478C473E);
    address aura = address(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address gho = address(0x7dfF72693f6A4149b17e7C6314655f6A9F7c8B33);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    address rewardPool = address(0xe48D1173EE577c1daE45C9CD2D29BD3DfaF02BD6);
    AuraStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      0x46472cba35e6800012aa9fcc7939ff07478c473e00020000000000000000056c,  // Balancer Pool id
      69,      // Aura Pool id
      gho,     // depositToken
      true     // gyroPool
    );
    rewardTokens = [aura, bal, gho, arb];
  }
}
