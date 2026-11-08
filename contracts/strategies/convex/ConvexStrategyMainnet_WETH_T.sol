// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./ConvexStrategy.sol";

contract ConvexStrategyMainnet_WETH_T is ConvexStrategy {
    constructor() {}

    function initializeStrategy(
        address _storage,
        address _vault
    ) public initializer {
        address underlying = address(
            0xCb08717451aaE9EF950a2524E33B6DCaBA60147B
        ); // Info -> LP Token address
        address rewardPool = address(
            0x3E91E7c822AC8b4b7905d108c3faCF22A3ee5d2c
        ); // Info -> Rewards contract address
        address crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
        address cvx = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
        address t = address(0xCdF7028ceAB81fA0C6971208e83fa7872994beE5);
        address curveDeposit = address(
            0x752eBeb79963cf0732E9c0fec72a49FD1DEfAEAC
        ); // only needed if deposits are not via underlying
        ConvexStrategy.initializeBaseStrategy(
            _storage,
            underlying,
            _vault,
            rewardPool, // rewardPool
            67, // Pool id: Info -> Rewards contract address -> read -> pid
            t, // depositToken
            1, //depositArrayPosition. Find deposit transaction -> input params
            curveDeposit, // deposit contract: usually underlying. Find deposit transaction -> interacted contract
            2, //nTokens -> total number of deposit tokens
            false //metaPool -> if LP token address == pool address (at curve). For 2 crypto, if it's stable_swap LP then true else false.
        );
        rewardTokens = [crv, cvx];
    }
}
