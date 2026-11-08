//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./AuraStrategy.sol";

contract AuraStrategyMainnet_wstETH_GYD is AuraStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x6ce1D1e46548ef657f8D7Ebddfc4BEaDB04F72f3);
    address aura = address(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address wsteth = address(0x5979D7b546E38E414F7E9822514be443A4800529);
    address rewardPool = address(0x9af228E16Ed7C9a39A44844860c8c72A4c4a1fDa);
    AuraStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      0x6ce1d1e46548ef657f8d7ebddfc4beadb04f72f30002000000000000000005a1,  // Balancer Pool id
      89,      // Aura Pool id
      wsteth,     // depositToken
      true     // gyroPool
    );
    rewardTokens = [aura, bal];
  }
}
