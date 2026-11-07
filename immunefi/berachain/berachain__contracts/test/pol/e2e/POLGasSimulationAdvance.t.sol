// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./POLGasSim.t.sol";

contract POLGasSimulationAdvance is POLGasSimulationSimple {
    function setUp() public virtual override {
        super.setUp();

        // Create reward vaults with consensus asset
        RewardVault[] memory vaults = createVaults(3);

        // configure reward allocation with three consensus assets
        uint96[] memory weights = new uint96[](3);
        weights[0] = 2500;
        weights[1] = 2500;
        weights[2] = 5000;

        configureWeights(vaults, weights);

        // whitelist and add validator incentives
        addIncentives(vaults, 2);
    }
}
