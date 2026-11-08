// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./ConvexStrategy.sol";

contract ConvexStrategyMainnet_stETH_ng is ConvexStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x21E27a5E5513D6e65C4f830167390997aA84843a); // Info -> LP Token address
    address rewardPool = address(0x6B27D7BC63F1999D14fF9bA900069ee516669ee8); // Info -> Rewards contract address
    address crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address cvx = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    ConvexStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool, // rewardPool
      177,  // Pool id: Info -> Rewards contract address -> read -> pid
      weth, // depositToken
      0, //depositArrayPosition. Find deposit transaction -> input params
      underlying, // deposit contract: usually underlying. Find deposit transaction -> interacted contract
      2, //nTokens -> total number of deposit tokens
      false //metaPool -> if LP token address == pool address (at curve)
    );
    rewardTokens = [crv, cvx];
  }
}
