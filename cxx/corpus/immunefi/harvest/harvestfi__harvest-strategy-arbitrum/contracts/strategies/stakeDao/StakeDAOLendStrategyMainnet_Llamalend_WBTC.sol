// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./StakeDAOLendStrategy.sol";

contract StakeDAOLendStrategyMainnet_Llamalend_WBTC is StakeDAOLendStrategy {
    constructor() {}

    function initializeStrategy(address _storage, address _vault) public initializer {
        address underlying = address(0x498Bf2B1e120FeD3ad3D42EA2165E9b73f99C1e5);
        address lendingVault = address(0xe07f1151887b8FDC6800f737252f6b91b46b5865);
        address rewardPool = address(0x1544E663DD326a6d853a0cc4ceEf0860eb82B287);
        address crv = address(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);

        StakeDAOLendStrategy.initializeBaseStrategy(
            _storage,
            underlying,
            _vault,
            lendingVault,
            rewardPool,
            crv
        );
        rewardTokens = [crv];
    }
}
