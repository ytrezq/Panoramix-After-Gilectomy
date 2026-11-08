// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {
    IERC7540LikeRedeemQueuePreRequestRedeemHook
} from "src/components/issuance/interfaces/IERC7540LikeRedeemQueuePreRequestRedeemHook.sol";

import {ChainlinkAceIssuanceValidatorBase} from "./ChainlinkAceIssuanceValidatorBase.sol";

/// @title ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemValidator Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Validates redeem requests before they are committed by running
/// them through a Chainlink ACE `IPolicyEngine`.
contract ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemValidator is
    ChainlinkAceIssuanceValidatorBase,
    IERC7540LikeRedeemQueuePreRequestRedeemHook
{
    //==================================================================================================================
    // Required: IERC7540LikeRedeemQueuePreRequestRedeemHook
    //==================================================================================================================

    /// @inheritdoc IERC7540LikeRedeemQueuePreRequestRedeemHook
    function preRequestRedeem(address _originator, address _controller, address _owner, uint256 _sharesAmount)
        external
        override
        onlyHandler
        runPolicy
    {}
}
