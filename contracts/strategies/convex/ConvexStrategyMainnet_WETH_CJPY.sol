// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./ConvexStrategy.sol";

contract ConvexStrategyMainnet_WETH_CJPY is ConvexStrategy {
    constructor() {}

    function initializeStrategy(
        address _storage,
        address _vault
    ) public initializer {
        address underlying = address(
            0x592878b920101946Fb5915aB97961bC546f211CC
        ); // Info -> LP Token address
        address rewardPool = address(
            0xfae6645b8FaF13FC3CE6B9d61829e1fF57Ffc038
        ); // Info -> Rewards contract address
        address crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
        address cvx = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
        address cjpy = address(0x1cfa5641c01406aB8AC350dEd7d735ec41298372);
        ConvexStrategy.initializeBaseStrategy(
            _storage,
            underlying,
            _vault,
            rewardPool, // rewardPool
            324, // Pool id: Info -> Rewards contract address -> read -> pid
            cjpy, // depositToken
            1, //depositArrayPosition. Find deposit transaction -> input params
            underlying, // deposit contract: usually underlying. Find deposit transaction -> interacted contract
            2, //nTokens -> total number of deposit tokens
            false //metaPool -> if LP token address == pool address (at curve). For 2 crypto, if it's stable_swap LP then true else false.
        );
        rewardTokens = [crv, cvx];
    }
}
