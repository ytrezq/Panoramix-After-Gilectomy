// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

/// @title IERC7540LikeRedeemQueuePostExecuteRedeemRequestHook Interface
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Hook called by ERC7540LikeRedeemQueue after executing a redeem request
interface IERC7540LikeRedeemQueuePostExecuteRedeemRequestHook {
    /// @param _originator An admin or the owner of the Shares contract executing the redeem requests
    /// @param _controller The user who owns the request
    /// @param _owner The user whose shares were used for the request
    /// @param _sharesAmount Gross shares burned (before exit fee)
    /// @param _assetAmount Net asset amount withdrawn (after exit fee)
    function postExecuteRedeemRequest(
        address _originator,
        address _controller,
        address _owner,
        uint256 _sharesAmount,
        uint256 _assetAmount
    ) external;
}
