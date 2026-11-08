// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {
    IERC7540LikeDepositQueuePreRequestDepositHook
} from "src/components/issuance/interfaces/IERC7540LikeDepositQueuePreRequestDepositHook.sol";

import {ChainlinkAceIssuanceValidatorBase} from "./ChainlinkAceIssuanceValidatorBase.sol";

/// @title ChainlinkAceERC7540LikeDepositQueuePreRequestDepositValidator Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Validates deposit requests before they are committed by running
/// them through a Chainlink ACE `IPolicyEngine`.
contract ChainlinkAceERC7540LikeDepositQueuePreRequestDepositValidator is
    ChainlinkAceIssuanceValidatorBase,
    IERC7540LikeDepositQueuePreRequestDepositHook
{
    //==================================================================================================================
    // Required: IERC7540LikeDepositQueuePreRequestDepositHook
    //==================================================================================================================

    /// @inheritdoc IERC7540LikeDepositQueuePreRequestDepositHook
    function preRequestDeposit(address _originator, address _controller, address _owner, uint256 _assetAmount)
        external
        override
        onlyHandler
        runPolicy
    {}
}
