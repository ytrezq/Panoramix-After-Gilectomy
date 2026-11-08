// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IErrors } from "../interfaces/IErrors.sol";
import { IStrataCDO } from "../interfaces/IStrataCDO.sol";
import { ICDOComponent } from "../interfaces/ICDOComponent.sol";
import { AccessControlled } from "../../governance/AccessControlled.sol";

/// @title CDOComponent
/// @notice Abstract base contract for CDO components (Tranches, Accounting, Strategy)
/// @dev Provides common functionality and access control for CDO-related contracts
abstract contract CDOComponent is ICDOComponent, IErrors, AccessControlled {

    IStrataCDO public cdo;

     /**
     * @dev See https://docs.openzeppelin.com/upgrades-plugins/writing-upgradeable#storage-gaps
     */
    uint256[49] private __gap;

    /// @notice ensure cooldownDuration is zero
    modifier onlyCDO() {
        if (msg.sender != address(cdo)) {
            revert InvalidCaller(msg.sender);
        }
        _;
    }

    function getCDOAddress() external view returns (address) {
        return address(cdo);
    }
}
