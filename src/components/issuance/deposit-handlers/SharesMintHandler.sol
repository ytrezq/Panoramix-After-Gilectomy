// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {ISharesMintHandlerPreMintHook} from "src/components/issuance/interfaces/ISharesMintHandlerPreMintHook.sol";
import {Shares} from "src/shares/Shares.sol";
import {StorageHelpersLib} from "src/utils/StorageHelpersLib.sol";

/// @title SharesMintHandler Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice A deposit handler that directly mints shares to specified recipients,
/// e.g., to mirror subscriptions settled off-chain
contract SharesMintHandler is ComponentHelpersMixin {
    //==================================================================================================================
    // Types
    //==================================================================================================================

    /// @param to The recipient of the minted shares
    /// @param sharesAmount The amount of shares to mint
    struct MintInput {
        address to;
        uint256 sharesAmount;
    }

    //==================================================================================================================
    // Storage
    //==================================================================================================================

    bytes32 private constant SHARES_MINT_HANDLER_STORAGE_LOCATION =
        0xb496ba006d943dfce809c7df17ac90f8632f2bd159f3be9d66d42d0163652a00;
    string private constant SHARES_MINT_HANDLER_STORAGE_LOCATION_ID = "SharesMintHandler";

    /// @custom:storage-location erc7201:enzyme.SharesMintHandler
    /// @param preMintHook A hook called with mints before they are committed (`address(0)` disables it)
    struct SharesMintHandlerStorage {
        address preMintHook;
    }

    function __getSharesMintHandlerStorage() private pure returns (SharesMintHandlerStorage storage $) {
        bytes32 location = SHARES_MINT_HANDLER_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }

    //==================================================================================================================
    // Events
    //==================================================================================================================

    event PreMintHookSet(address hook);

    event SharesMinted(address caller, address to, uint256 sharesAmount);

    //==================================================================================================================
    // Errors
    //==================================================================================================================

    error SharesMintHandler__Mint__ZeroShares();

    //==================================================================================================================
    // Constructor
    //==================================================================================================================

    constructor() {
        StorageHelpersLib.verifyErc7201LocationForId({
            _location: SHARES_MINT_HANDLER_STORAGE_LOCATION, _id: SHARES_MINT_HANDLER_STORAGE_LOCATION_ID
        });
    }

    //==================================================================================================================
    // Config (access: admin or owner)
    //==================================================================================================================

    /// @notice Sets the pre-mint hook (`address(0)` disables the pre-mint hook)
    function setPreMintHook(address _preMintHook) external onlyAdminOrOwner {
        __getSharesMintHandlerStorage().preMintHook = _preMintHook;

        emit PreMintHookSet(_preMintHook);
    }

    //==================================================================================================================
    // Mints (access: admin or owner)
    //==================================================================================================================

    /// @notice Mints shares to the specified recipients
    /// @param _inputs The mints to execute
    function mint(MintInput[] calldata _inputs) external onlyAdminOrOwner {
        Shares shares = Shares(__getShares());

        for (uint256 i; i < _inputs.length; i++) {
            MintInput memory input = _inputs[i];

            require(input.sharesAmount > 0, SharesMintHandler__Mint__ZeroShares());

            __runPreMintHook({_originator: msg.sender, _to: input.to, _sharesAmount: input.sharesAmount});

            shares.mintFor({_to: input.to, _sharesAmount: input.sharesAmount});

            emit SharesMinted({caller: msg.sender, to: input.to, sharesAmount: input.sharesAmount});
        }
    }

    //==================================================================================================================
    // Validation
    //==================================================================================================================

    /// @dev Runs the mint through the attached pre-mint hook, if any. No-op when unset.
    function __runPreMintHook(address _originator, address _to, uint256 _sharesAmount) internal {
        address hook = getPreMintHook();

        if (hook == address(0)) {
            return;
        }

        ISharesMintHandlerPreMintHook(hook).preMint({_originator: _originator, _to: _to, _sharesAmount: _sharesAmount});
    }

    //==================================================================================================================
    // State getters
    //==================================================================================================================

    /// @notice Returns the hook called with mints before they are committed
    function getPreMintHook() public view returns (address) {
        return __getSharesMintHandlerStorage().preMintHook;
    }
}
