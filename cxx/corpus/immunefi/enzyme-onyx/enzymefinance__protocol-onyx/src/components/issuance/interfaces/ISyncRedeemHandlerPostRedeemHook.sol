// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

/// @title ISyncRedeemHandlerPostRedeemHook Interface
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Hook called by SyncRedeemHandler after a synchronous redemption
interface ISyncRedeemHandlerPostRedeemHook {
    /// @param _originator The user who redeemed
    /// @param _sharesAmount Gross shares burned (including exit-fee shares)
    /// @param _assetAmount Assets paid to the redeemer (after the exit fee)
    function postRedeem(address _originator, uint256 _sharesAmount, uint256 _assetAmount) external;
}
