// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title Global Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice A contract for global values
/// @dev OpenZeppelin ERC1967Proxy-compatible implementation
contract Global is UUPSUpgradeable, Ownable2StepUpgradeable {
    //==================================================================================================================
    // Initialize
    //==================================================================================================================

    function init(address _owner) external initializer {
        __Ownable_init({initialOwner: _owner});
    }

    //==================================================================================================================
    // UUPSUpgradeable
    //==================================================================================================================

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
