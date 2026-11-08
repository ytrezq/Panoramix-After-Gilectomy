// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./ConvexStrategy.sol";

contract ConvexStrategyMainnet_sUSD_sUSDe is ConvexStrategy {
    constructor() {}

    function initializeStrategy(
        address _storage,
        address _vault
    ) public initializer {
        address underlying = address(
            0x4b5E827F4C0a1042272a11857a355dA1F4Ceebae
        ); // Info -> LP Token address
        address rewardPool = address(
            0x14d2DC2CeBC25f217bc9Aee5AC3A7967Ca7ceBae
        ); // Info -> Rewards contract address
        address crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
        address cvx = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
        address susde = address(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);
        ConvexStrategy.initializeBaseStrategy(
            _storage,
            underlying,
            _vault,
            rewardPool, // rewardPool
            436, // Pool id: Info -> Rewards contract address -> read -> pid
            susde, // depositToken
            1, //depositArrayPosition. Find deposit transaction -> input params
            underlying, // deposit contract: usually underlying. Find deposit transaction -> interacted contract
            2, //nTokens -> total number of deposit tokens
            true //metaPool -> if LP token address == pool address (at curve). For 2 crypto, if it's stable_swap LP then true else false.
        );
        rewardTokens = [crv, cvx];
    }
}
