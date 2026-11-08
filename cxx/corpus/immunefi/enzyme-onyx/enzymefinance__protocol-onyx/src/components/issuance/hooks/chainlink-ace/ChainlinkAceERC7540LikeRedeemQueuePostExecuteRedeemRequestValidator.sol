// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {
    IERC7540LikeRedeemQueuePostExecuteRedeemRequestHook
} from "src/components/issuance/interfaces/IERC7540LikeRedeemQueuePostExecuteRedeemRequestHook.sol";

import {ChainlinkAceIssuanceValidatorBase} from "./ChainlinkAceIssuanceValidatorBase.sol";

/// @title ChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestValidator Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Validates redeem executions after they settle by running
/// them through a Chainlink ACE `IPolicyEngine`.
contract ChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestValidator is
    ChainlinkAceIssuanceValidatorBase,
    IERC7540LikeRedeemQueuePostExecuteRedeemRequestHook
{
    //==================================================================================================================
    // Required: IERC7540LikeRedeemQueuePostExecuteRedeemRequestHook
    //==================================================================================================================

    /// @inheritdoc IERC7540LikeRedeemQueuePostExecuteRedeemRequestHook
    function postExecuteRedeemRequest(
        address _originator,
        address _controller,
        address _owner,
        uint256 _sharesAmount,
        uint256 _assetAmount
    ) external override onlyHandler runPolicy {}
}
