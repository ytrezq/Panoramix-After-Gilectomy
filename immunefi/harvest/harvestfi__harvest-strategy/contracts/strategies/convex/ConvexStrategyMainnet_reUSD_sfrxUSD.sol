// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./ConvexStrategy.sol";

contract ConvexStrategyMainnet_reUSD_sfrxUSD is ConvexStrategy {
    constructor() {}

    function initializeStrategy(
        address _storage,
        address _vault
    ) public initializer {
        address underlying = address(
            0xed785Af60bEd688baa8990cD5c4166221599A441
        ); // Info -> LP Token address
        address rewardPool = address(
            0x18574c2047A2D4786567A2C31B4f25Ae291ed6bF
        ); // Info -> Rewards contract address
        address crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
        address cvx = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
        address sfrxusd = address(0xcf62F905562626CfcDD2261162a51fd02Fc9c5b6);
        ConvexStrategy.initializeBaseStrategy(
            _storage,
            underlying,
            _vault,
            rewardPool, // rewardPool
            439, // Pool id: Info -> Rewards contract address -> read -> pid
            sfrxusd, // depositToken
            1, //depositArrayPosition. Find deposit transaction -> input params
            underlying, // deposit contract: usually underlying. Find deposit transaction -> interacted contract
            2, //nTokens -> total number of deposit tokens
            true //metaPool -> if LP token address == pool address (at curve). For 2 crypto, if it's stable_swap LP then true else false.
        );
        rewardTokens = [crv, cvx];
    }
}
