// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MockRegistry} from "./MockRegistry.sol";

contract MockRegistryV2 is MockRegistry {
    address immutable previousImpl;

    constructor(address _previousImpl) {
        previousImpl = _previousImpl;
    }

    function canUpgradeFrom(address previousImplementation) external view override returns (bool) {
        return previousImplementation == previousImpl;
    }

    function getRegistryVersion() public pure override returns (uint256) {
        return 2;
    }
}
