// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./ConvexStrategy.sol";

contract ConvexStrategyMainnet_ALCX_FRAXBP is ConvexStrategy {
    constructor() {}

    function initializeStrategy(
        address _storage,
        address _vault
    ) public initializer {
        address underlying = address(
            0xf985005a3793DbA4cCe241B3C19ddcd3Fe069ff4
        ); // Info -> LP Token address
        address rewardPool = address(
            0xC10fD95fd3B56535668426B2c8681AD1E15Be608
        ); // Info -> Rewards contract address
        address crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
        address cvx = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
        address alcx = address(0xdBdb4d16EdA451D0503b854CF79D55697F90c8DF);
        address curveDeposit = address(
            0x4149d1038575CE235E03E03B39487a80FD709D31
        ); // only needed if deposits are not via underlying

        ConvexStrategy.initializeBaseStrategy(
            _storage,
            underlying,
            _vault,
            rewardPool, // rewardPool
            120, // Pool id: Info -> Rewards contract address -> read -> pid
            alcx, // depositToken
            0, //depositArrayPosition. Find deposit transaction -> input params
            curveDeposit, // deposit contract: usually underlying. Find deposit transaction -> interacted contract
            2, //nTokens -> total number of deposit tokens
            false //metaPool -> if LP token address == pool address (at curve)
        );
        rewardTokens = [crv, cvx];
    }
}
