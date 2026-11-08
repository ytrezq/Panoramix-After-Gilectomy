//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./BalancerStrategyV3.sol";

contract BalancerStrategyV3Mainnet_MaticX_amMatic is BalancerStrategyV3 {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xE78b25c06dB117fdF8F98583CDaaa6c92B79E917);
    address maticX = address(0xfa68FB4628DFF1028CFEc22b4162FCcd0d45efb6);
    address wmatic = address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    address bal = address(0x9a71012B13CA4d3D0Cdc72A177DF3ef03b0E76A3);
    address sd = address(0x1d734A02eF1e1f5886e66b0673b71Af5B53ffA94);
    address usdc = address(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    address gauge = address(0x956074628A64a316086f7125074a8A52d3306321);
    BalancerStrategyV3.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      gauge,
      address(0xBA12222222228d8Ba445958a75a0704d566BF2C8), //balancer vault
      0xe78b25c06db117fdf8f98583cdaaa6c92b79e917000000000000000000000b2b,  // Pool id
      maticX,   //depositToken
      true      //boosted
    );
    rewardTokens = [bal, sd];
    reward2WETH[bal] = [bal, weth];
    reward2WETH[sd] = [sd, usdc, weth];
    WETH2deposit = [weth, wmatic, maticX];
    poolIds[bal][weth] = 0x3d468ab2329f296e1b9d8476bb54dd77d8c2320f000200000000000000000426;
  }
}
