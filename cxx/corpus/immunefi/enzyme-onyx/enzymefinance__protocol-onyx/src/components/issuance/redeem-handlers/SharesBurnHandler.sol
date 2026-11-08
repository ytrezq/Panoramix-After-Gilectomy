// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {ISharesBurnHandlerPreBurnHook} from "src/components/issuance/interfaces/ISharesBurnHandlerPreBurnHook.sol";
import {Shares} from "src/shares/Shares.sol";
import {StorageHelpersLib} from "src/utils/StorageHelpersLib.sol";

/// @title SharesBurnHandler Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice A redeem handler that directly burns shares from specified holders
contract SharesBurnHandler is ComponentHelpersMixin {
    //==================================================================================================================
    // Types
    //==================================================================================================================

    /// @param from The holder whose shares are burned
    /// @param sharesAmount The amount of shares to burn
    struct BurnInput {
        address from;
        uint256 sharesAmount;
    }

    //==================================================================================================================
    // Storage
    //==================================================================================================================

    bytes32 private constant SHARES_BURN_HANDLER_STORAGE_LOCATION =
        0xf51cb156e3821e2b603ec3864b8c7c6b953c94b0c0a30d69fdb0c8d26edb6a00;
    string private constant SHARES_BURN_HANDLER_STORAGE_LOCATION_ID = "SharesBurnHandler";

    /// @custom:storage-location erc7201:enzyme.SharesBurnHandler
    /// @param preBurnHook A hook called with burns before they are committed (`address(0)` disables it)
    struct SharesBurnHandlerStorage {
        address preBurnHook;
    }

    function __getSharesBurnHandlerStorage() private pure returns (SharesBurnHandlerStorage storage $) {
        bytes32 location = SHARES_BURN_HANDLER_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }

    //==================================================================================================================
    // Events
    //==================================================================================================================

    event PreBurnHookSet(address hook);

    event SharesBurned(address caller, address from, uint256 sharesAmount);

    //==================================================================================================================
    // Errors
    //==================================================================================================================

    error SharesBurnHandler__Burn__ZeroShares();

    //==================================================================================================================
    // Constructor
    //==================================================================================================================

    constructor() {
        StorageHelpersLib.verifyErc7201LocationForId({
            _location: SHARES_BURN_HANDLER_STORAGE_LOCATION, _id: SHARES_BURN_HANDLER_STORAGE_LOCATION_ID
        });
    }

    //==================================================================================================================
    // Config (access: admin or owner)
    //==================================================================================================================

    /// @notice Sets the pre-burn hook (`address(0)` disables the pre-burn hook)
    function setPreBurnHook(address _preBurnHook) external onlyAdminOrOwner {
        __getSharesBurnHandlerStorage().preBurnHook = _preBurnHook;

        emit PreBurnHookSet(_preBurnHook);
    }

    //==================================================================================================================
    // Burns (access: admin or owner)
    //==================================================================================================================

    /// @notice Burns shares from the specified holders
    /// @param _inputs The burns to execute
    function burn(BurnInput[] calldata _inputs) external onlyAdminOrOwner {
        Shares shares = Shares(__getShares());

        for (uint256 i; i < _inputs.length; i++) {
            BurnInput memory input = _inputs[i];

            require(input.sharesAmount > 0, SharesBurnHandler__Burn__ZeroShares());

            __runPreBurnHook({_originator: msg.sender, _from: input.from, _sharesAmount: input.sharesAmount});

            shares.burnFor({_from: input.from, _sharesAmount: input.sharesAmount});

            emit SharesBurned({caller: msg.sender, from: input.from, sharesAmount: input.sharesAmount});
        }
    }

    //==================================================================================================================
    // Validation
    //==================================================================================================================

    /// @dev Runs the burn through the attached pre-burn hook, if any. No-op when unset.
    function __runPreBurnHook(address _originator, address _from, uint256 _sharesAmount) internal {
        address hook = getPreBurnHook();

        if (hook == address(0)) {
            return;
        }

        ISharesBurnHandlerPreBurnHook(hook).preBurn({
            _originator: _originator, _from: _from, _sharesAmount: _sharesAmount
        });
    }

    //==================================================================================================================
    // State getters
    //==================================================================================================================

    /// @notice Returns the hook called with burns before they are committed
    function getPreBurnHook() public view returns (address) {
        return __getSharesBurnHandlerStorage().preBurnHook;
    }
}
