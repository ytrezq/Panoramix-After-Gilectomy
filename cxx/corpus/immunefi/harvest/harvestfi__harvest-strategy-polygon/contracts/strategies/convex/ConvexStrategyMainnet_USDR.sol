//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./base/ConvexStrategy.sol";

contract ConvexStrategyMainnet_USDR is ConvexStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xa138341185a9D0429B0021A11FB717B225e13e1F); // Info -> LP Token address
    address rewardPool = address(0x3D17b2BcfcD7E0Dc4d6a0d6bA67c29FBc592B323); // Info -> Rewards contract address
    address crv = address(0x172370d5Cd63279eFa6d502DAB29171933a610AF);
    address cvx = address(0x4257EA7637c355F81616050CbB6a9b709fd72683);
    address usdc = address(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    address curveDeposit = address(0x5ab5C56B9db92Ba45a0B46a207286cD83C15C939);
    ConvexStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool, // rewardPool
      11,  // Pool id: Info -> Rewards contract address -> read -> pid
      usdc, // depositToken
      2, //depositArrayPosition. Find deposit transaction -> input params
      curveDeposit, // deposit contract: usually underlying. Find deposit transaction -> interacted contract
      4, //nTokens -> total number of deposit tokens
      true, //metaPool -> if LP token address == pool address (at curve)
      true //factoryPool
    );
    rewardTokens = [crv, cvx];
    reward2WETH[crv] = [crv, weth];
    reward2WETH[cvx] = [cvx, weth];
    WETH2deposit = [weth, usdc];
    storedPairFee[weth][usdc] = 500;
  }
}