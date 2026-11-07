// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.22;

import { CapAutomator } from "../../src/CapAutomator.sol";

contract CapAutomatorHarness is CapAutomator {

    constructor(
        address poolAddressesProvider,
        address admin,
        address updater
    ) CapAutomator(poolAddressesProvider, admin, updater) {}

    function _calculateNewCapExternal(
        CapConfig memory capConfig,
        uint256          currentState,
        uint256          currentCap
    ) public view returns (uint256) {
        return super._calculateNewCap(capConfig, currentState, currentCap);
    }

}
