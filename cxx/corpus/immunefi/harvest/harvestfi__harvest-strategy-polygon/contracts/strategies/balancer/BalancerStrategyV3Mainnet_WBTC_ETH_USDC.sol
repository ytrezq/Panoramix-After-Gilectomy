//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./BalancerStrategyV3.sol";

contract BalancerStrategyV3Mainnet_WBTC_ETH_USDC is BalancerStrategyV3 {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x03cD191F589d12b0582a99808cf19851E468E6B5);
    address bal = address(0x9a71012B13CA4d3D0Cdc72A177DF3ef03b0E76A3);
    address gauge = address(0x219b3a4a2D2351582277A87048995034ca7e9aEF);
    BalancerStrategyV3.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      gauge,
      address(0xBA12222222228d8Ba445958a75a0704d566BF2C8), //balancer vault
      0x03cd191f589d12b0582a99808cf19851e468e6b500010000000000000000000a,  // Pool id
      weth,   //depositToken
      false      //boosted
    );
    rewardTokens = [bal];
    reward2WETH[bal] = [bal, weth];
    poolIds[bal][weth] = 0x3d468ab2329f296e1b9d8476bb54dd77d8c2320f000200000000000000000426;
  }
}
