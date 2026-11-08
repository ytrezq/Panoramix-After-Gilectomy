//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./BalancerStrategyV3.sol";

contract BalancerStrategyV3Mainnet_wstETH_amWETH is BalancerStrategyV3 {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x4a77eF015ddcd972fd9BA2C7D5D658689D090f1A);
    address bbaWETH = address(0x43894DE14462B421372bCFe445fA51b1b4A0Ff3D);
    address bal = address(0x9a71012B13CA4d3D0Cdc72A177DF3ef03b0E76A3);
    address usdc = address(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    address gauge = address(0xB95397A17ACbb5824535ebE69Cd9DCF8fA7aFC50);
    BalancerStrategyV3.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      gauge,
      address(0xBA12222222228d8Ba445958a75a0704d566BF2C8), //balancer vault
      0x4a77ef015ddcd972fd9ba2c7d5d658689d090f1a000000000000000000000b38,  // Pool id
      bbaWETH,   //depositToken
      true      //boosted
    );
    rewardTokens = [bal, usdc];
    reward2WETH[bal] = [bal, weth];
    reward2WETH[usdc] = [usdc, weth];
    WETH2deposit = [weth, bbaWETH];
    poolIds[bal][weth] = 0x3d468ab2329f296e1b9d8476bb54dd77d8c2320f000200000000000000000426;
    poolIds[weth][bbaWETH] = 0x43894de14462b421372bcfe445fa51b1b4a0ff3d000000000000000000000b36;
  }
}
