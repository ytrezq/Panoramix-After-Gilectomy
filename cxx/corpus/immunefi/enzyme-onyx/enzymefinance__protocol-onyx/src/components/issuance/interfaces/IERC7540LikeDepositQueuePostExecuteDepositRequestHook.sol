// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

/// @title IERC7540LikeDepositQueuePostExecuteDepositRequestHook Interface
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Hook called by ERC7540LikeDepositQueue after executing a deposit request
interface IERC7540LikeDepositQueuePostExecuteDepositRequestHook {
    /// @param _originator An admin or the owner of the Shares contract executing the deposit requests
    /// @param _controller The user who owns the request
    /// @param _owner The user whose assets were used for the request
    /// @param _sharesAmount Net shares minted (gross shares minus entrance fee shares)
    /// @param _assetAmount Gross asset amount deposited
    function postExecuteDepositRequest(
        address _originator,
        address _controller,
        address _owner,
        uint256 _sharesAmount,
        uint256 _assetAmount
    ) external;
}
