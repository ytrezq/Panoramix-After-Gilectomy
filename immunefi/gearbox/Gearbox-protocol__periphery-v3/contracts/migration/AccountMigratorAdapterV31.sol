// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {AccountMigratorAdapter} from "./AccountMigratorAdapter.sol";

import {MigrationParams} from "../types/AccountMigrationTypes.sol";

contract AccountMigratorAdapterV31 is AccountMigratorAdapter {
    bytes32 public constant override contractType = "ADAPTER::ACCOUNT_MIGRATOR";
    uint256 public constant override version = 3_10;

    constructor(address _creditManager, address _targetContract)
        AccountMigratorAdapter(_creditManager, _targetContract)
    {}

    /// @notice Migrates collaterals to a new credit account, using the migrator bot as a target contract.
    function migrate(MigrationParams memory params) external whenUnlocked creditFacadeOnly returns (bool) {
        _migrate(params);
        return false;
    }
}
