// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
// Use LegacyUpgrades for OpenZeppelin Contracts v4
import { Upgrades, Options } from "openzeppelin-foundry-upgrades/LegacyUpgrades.sol";

/// @title Storage Layout Compatibility Tests
/// @notice Tests that verify storage layout compatibility between contract versions
/// @dev Uses OpenZeppelin Foundry Upgrades library for validation
contract StorageLayoutTests is Test {
    /// @notice Test MocRif storage layout compatibility between v1.0.6 and v1.1.0
    /// @dev Validates that the upgrade from MocCARC20 v1.0.6 to MocRif v1.1.0 is safe
    function test_MocRifStorageLayoutCompatibility_v106_to_v110() public {
        Options memory opts;

        // Reference contract is the old v1.0.6 implementation
        opts.referenceContract = "MocRifStable.sol:MocRifStable";

        // Allow delegatecall (used for MocCoreExpansion) and missing-initializer
        opts.unsafeAllow = "delegatecall,missing-initializer";

        // Allow renames (some variables were renamed between versions)
        opts.unsafeAllowRenames = true;

        // Validate the upgrade from v1.0.6 to v1.1.0
        // This will check for storage layout collisions
        Upgrades.validateUpgrade("MocRif.sol:MocRif", opts);
    }

    /// @notice Test USDRIF (StableTokenV2) storage layout compatibility
    /// @dev Validates that the upgrade from StableTokenV2_Legacy to StableTokenV2 is safe
    function test_USDRIFStorageLayoutCompatibility() public {
        Options memory opts;

        // Reference contract is the legacy implementation
        opts.referenceContract = "StableTokenV2.sol:StableTokenV2_Legacy";

        // Allow missing-initializer
        opts.unsafeAllow = "missing-initializer";

        // Validate the upgrade
        Upgrades.validateUpgrade("StableTokenV2.sol:StableTokenV2", opts);
    }
}
