//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./BalancerStrategyV3.sol";

contract BalancerStrategyV3Mainnet_frxETH_amWETH is BalancerStrategyV3 {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xD00f9Ca46ce0E4A63067c4657986f0167b0De1E5);
    address bbaWETH = address(0x43894DE14462B421372bCFe445fA51b1b4A0Ff3D);
    address bal = address(0x9a71012B13CA4d3D0Cdc72A177DF3ef03b0E76A3);
    address gauge = address(0x83Ed440E7122FE3EFA28d3BC9d9eFca1952Ccb4b);
    BalancerStrategyV3.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      gauge,
      address(0xBA12222222228d8Ba445958a75a0704d566BF2C8), //balancer vault
      0xd00f9ca46ce0e4a63067c4657986f0167b0de1e5000000000000000000000b42,  // Pool id
      bbaWETH,   //depositToken
      true      //boosted
    );
    rewardTokens = [bal];
    reward2WETH[bal] = [bal, weth];
    WETH2deposit = [weth, bbaWETH];
    poolIds[bal][weth] = 0x3d468ab2329f296e1b9d8476bb54dd77d8c2320f000200000000000000000426;
    poolIds[weth][bbaWETH] = 0x43894de14462b421372bcfe445fa51b1b4a0ff3d000000000000000000000b36;
  }
}
