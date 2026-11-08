// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./StakeDAOLendStrategy.sol";

contract StakeDAOLendStrategyMainnet_Llamalend_WETH is StakeDAOLendStrategy {
    constructor() {}

    function initializeStrategy(address _storage, address _vault) public initializer {
        address underlying = address(0x498Bf2B1e120FeD3ad3D42EA2165E9b73f99C1e5);
        address lendingVault = address(0xd3cA9BEc3e681b0f578FD87f20eBCf2B7e0bb739);
        address rewardPool = address(0x2abaD3D0c104fE1C9A412431D070e73108B4eFF8);
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
