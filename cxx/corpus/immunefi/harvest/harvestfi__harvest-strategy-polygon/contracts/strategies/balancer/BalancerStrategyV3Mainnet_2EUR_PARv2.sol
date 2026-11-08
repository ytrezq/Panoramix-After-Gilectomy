//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./BalancerStrategyV3.sol";

contract BalancerStrategyV3Mainnet_2EUR_PARv2 is BalancerStrategyV3 {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x513CdEE00251F39DE280d9E5f771A6eaFebCc88E);
    address jeur = address(0x4e3Decbb3645551B8A19f0eA1678079FCB33fB4c);
    address bal = address(0x9a71012B13CA4d3D0Cdc72A177DF3ef03b0E76A3);
    address gauge = address(0x5c13C3b72b031b6405046C319B2D840d3C1403c7);
    BalancerStrategyV3.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      gauge,
      address(0xBA12222222228d8Ba445958a75a0704d566BF2C8), //balancer vault
      0x513cdee00251f39de280d9e5f771a6eafebcc88e000000000000000000000a6b,  // Pool id
      jeur,   //depositToken
      true      //boosted
    );
    rewardTokens = [bal];
    reward2WETH[bal] = [bal, weth];
    WETH2deposit = [weth, jeur];
    poolIds[bal][weth] = 0x3d468ab2329f296e1b9d8476bb54dd77d8c2320f000200000000000000000426;
  }
}
