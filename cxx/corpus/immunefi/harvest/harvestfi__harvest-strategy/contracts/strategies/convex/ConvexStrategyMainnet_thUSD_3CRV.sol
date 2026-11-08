// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./ConvexStrategy.sol";

contract ConvexStrategyMainnet_thUSD_3CRV is ConvexStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x91553BAD9Fbc8bD69Ff5d5678Cbf7D514d00De0b); // Info -> LP Token address
    address rewardPool = address(0x7E44379FF8e35D9d0f81EE232e038Ca4a0968196); // Info -> Rewards contract address
    address crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address cvx = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    address usdc = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address curveDeposit = address(0xA79828DF1850E8a3A3064576f380D90aECDD3359); // only needed if deposits are not via underlying
    ConvexStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool, // rewardPool
      356,  // Pool id: Info -> Rewards contract address -> read -> pid
      usdc, // depositToken
      2, //depositArrayPosition. Find deposit transaction -> input params
      curveDeposit, // deposit contract: usually underlying. Find deposit transaction -> interacted contract
      4, //nTokens -> total number of deposit tokens
      true //metaPool -> if LP token address == pool address (at curve)
    );
    rewardTokens = [crv, cvx];
  }
}
