// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {NotImplementedException} from "@gearbox-protocol/core-v3/contracts/interfaces/IExceptions.sol";
import {AccountMigratorAdapter} from "./AccountMigratorAdapter.sol";
import {MigrationParams} from "../types/AccountMigrationTypes.sol";

contract AccountMigratorAdapterV30 is AccountMigratorAdapter {
    /// @dev Legacy adapter type for compatibility with 3.0 contracts
    uint8 public constant _gearboxAdapterType = 0;

    /// @dev Legacy adapter version for compatibility with 3.0 contracts
    uint16 public constant _gearboxAdapterVersion = 3_00;

    constructor(address _creditManager, address _targetContract)
        AccountMigratorAdapter(_creditManager, _targetContract)
    {}

    function contractType() external pure returns (bytes32) {
        revert NotImplementedException();
    }

    function version() external pure returns (uint256) {
        revert NotImplementedException();
    }

    /// @notice Migrates collaterals to a new credit account, using the migrator bot as a target contract.
    function migrate(MigrationParams memory params)
        external
        whenUnlocked
        creditFacadeOnly
        returns (uint256 tokensToEnable, uint256 tokensToDisable)
    {
        _migrate(params);
        return (0, type(uint256).max);
    }
}
