// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {Multisig} from "./Multisig.sol";

import {IPermissionCondition} from "@aragon/osx-commons-contracts/src/permission/condition/IPermissionCondition.sol";
import {PermissionCondition} from "@aragon/osx-commons-contracts/src/permission/condition/PermissionCondition.sol";

/// @title ListedCheckCondition
/// @author Aragon X - 2024
/// @notice A condition contract that checks if an address is listed as a member in the associated Multisig contract.
/// @custom:security-contact sirt@aragon.org
contract ListedCheckCondition is PermissionCondition {
    /// @notice The immutable address of the Multisig plugin used for fetching plugin settings.
    Multisig private immutable MULTISIG;

    /// @notice Initializes the condition with the address of the Multisig plugin.
    /// @param _multisig The address of the Multisig plugin that stores listing and other configuration settings.
    constructor(address _multisig) {
        MULTISIG = Multisig(_multisig);
    }

    /// @inheritdoc IPermissionCondition
    function isGranted(
        address _where,
        address _who,
        bytes32 _permissionId,
        bytes calldata _data
    ) public view override returns (bool) {
        (_where, _data, _permissionId);

        (bool onlyListed, ) = MULTISIG.multisigSettings();

        if (onlyListed && !MULTISIG.isListed(_who)) {
            return false;
        }

        return true;
    }
}
