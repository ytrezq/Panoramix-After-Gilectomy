// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

/// @title IERC7540LikeDepositQueuePreRequestDepositHook Interface
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Hook called by ERC7540LikeDepositQueue before creating a deposit request
interface IERC7540LikeDepositQueuePreRequestDepositHook {
    /// @param _originator The user requesting the deposit
    /// @param _controller The user who owns the request
    /// @param _owner The user whose assets are used for the deposit
    /// @param _assetAmount Gross asset amount to deposit
    function preRequestDeposit(address _originator, address _controller, address _owner, uint256 _assetAmount) external;
}
