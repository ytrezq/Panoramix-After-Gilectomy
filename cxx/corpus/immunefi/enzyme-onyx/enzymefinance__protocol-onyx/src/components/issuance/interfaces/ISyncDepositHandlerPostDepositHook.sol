// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

/// @title ISyncDepositHandlerPostDepositHook Interface
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Hook called by SyncDepositHandler after a synchronous deposit
interface ISyncDepositHandlerPostDepositHook {
    /// @param _originator The user who deposited
    /// @param _sharesAmount Net shares minted (gross shares minus entrance fee shares)
    /// @param _assetAmount Gross asset amount deposited
    function postDeposit(address _originator, uint256 _sharesAmount, uint256 _assetAmount) external;
}
