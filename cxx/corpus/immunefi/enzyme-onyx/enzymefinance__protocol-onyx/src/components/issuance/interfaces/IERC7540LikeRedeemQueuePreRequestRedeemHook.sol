// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

/// @title IERC7540LikeRedeemQueuePreRequestRedeemHook Interface
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Hook called by ERC7540LikeRedeemQueue before creating a redeem request
interface IERC7540LikeRedeemQueuePreRequestRedeemHook {
    /// @param _originator The user requesting the redemption
    /// @param _controller The user who owns the request
    /// @param _owner The user whose shares are redeemed
    /// @param _sharesAmount Gross shares amount to redeem
    function preRequestRedeem(address _originator, address _controller, address _owner, uint256 _sharesAmount) external;
}
