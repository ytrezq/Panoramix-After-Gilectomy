// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./ConvexStrategy.sol";

contract ConvexStrategyMainnet_CVX_ETH is ConvexStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x3A283D9c08E8b55966afb64C515f5143cf907611); // Info -> LP Token address
    address rewardPool = address(0xb1Fb0BA0676A1fFA83882c7F4805408bA232C1fA); // Info -> Rewards contract address
    address crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address cvx = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    address curveDeposit = address(0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4); // only needed if deposits are not via underlying
    ConvexStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool, // rewardPool
      64,  // Pool id: Info -> Rewards contract address -> read -> pid
      cvx, // depositToken
      1, //depositArrayPosition. Find deposit transaction -> input params
      curveDeposit, // deposit contract: usually underlying. Find deposit transaction -> interacted contract
      2, //nTokens -> total number of deposit tokens
      false //metaPool -> if LP token address == pool address (at curve)
    );

    _setRewardToken(cvx);
    rewardTokens = [crv, cvx];
  }
}
