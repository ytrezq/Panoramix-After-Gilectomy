// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./ConvexStrategy.sol";

contract ConvexStrategyMainnet_reUSD_scrvUSD is ConvexStrategy {
    constructor() {}

    function initializeStrategy(
        address _storage,
        address _vault
    ) public initializer {
        address underlying = address(
            0xc522A6606BBA746d7960404F22a3DB936B6F4F50
        ); // Info -> LP Token address
        address rewardPool = address(
            0x7Fafc1876970dBD9F6568586EFa7d0FAc0FE8EA8
        ); // Info -> Rewards contract address
        address crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
        address cvx = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
        address scrvusd = address(0x0655977FEb2f289A4aB78af67BAB0d17aAb84367);
        ConvexStrategy.initializeBaseStrategy(
            _storage,
            underlying,
            _vault,
            rewardPool, // rewardPool
            440, // Pool id: Info -> Rewards contract address -> read -> pid
            scrvusd, // depositToken
            1, //depositArrayPosition. Find deposit transaction -> input params
            underlying, // deposit contract: usually underlying. Find deposit transaction -> interacted contract
            2, //nTokens -> total number of deposit tokens
            true //metaPool -> if LP token address == pool address (at curve). For 2 crypto, if it's stable_swap LP then true else false.
        );
        rewardTokens = [crv, cvx];
    }
}
