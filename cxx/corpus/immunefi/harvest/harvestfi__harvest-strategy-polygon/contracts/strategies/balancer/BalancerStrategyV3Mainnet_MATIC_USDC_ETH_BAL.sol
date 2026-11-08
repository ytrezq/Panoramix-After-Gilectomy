//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./BalancerStrategyV3.sol";

contract BalancerStrategyV3Mainnet_MATIC_USDC_ETH_BAL is BalancerStrategyV3 {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x0297e37f1873D2DAb4487Aa67cD56B58E2F27875);
    address bal = address(0x9a71012B13CA4d3D0Cdc72A177DF3ef03b0E76A3);
    address gauge = address(0x0aea1abC694a3608C8aC5F131d8310f95039111A);
    BalancerStrategyV3.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      gauge,
      address(0xBA12222222228d8Ba445958a75a0704d566BF2C8), //balancer vault
      0x0297e37f1873d2dab4487aa67cd56b58e2f27875000100000000000000000002,  // Pool id
      weth,   //depositToken
      false      //boosted
    );
    rewardTokens = [bal];
    reward2WETH[bal] = [bal, weth];
    poolIds[bal][weth] = 0x3d468ab2329f296e1b9d8476bb54dd77d8c2320f000200000000000000000426;
  }
}
