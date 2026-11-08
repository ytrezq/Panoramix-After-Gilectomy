// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {
    ISyncDepositHandlerPostDepositHook
} from "src/components/issuance/interfaces/ISyncDepositHandlerPostDepositHook.sol";

import {ChainlinkAceIssuanceValidatorBase} from "./ChainlinkAceIssuanceValidatorBase.sol";

/// @title ChainlinkAceSyncDepositHandlerPostDepositValidator Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Validates deposit executions after they settle by running
/// them through a Chainlink ACE `IPolicyEngine`.
contract ChainlinkAceSyncDepositHandlerPostDepositValidator is
    ChainlinkAceIssuanceValidatorBase,
    ISyncDepositHandlerPostDepositHook
{
    //==================================================================================================================
    // Required: ISyncDepositHandlerPostDepositHook
    //==================================================================================================================

    /// @inheritdoc ISyncDepositHandlerPostDepositHook
    function postDeposit(address _originator, uint256 _sharesAmount, uint256 _assetAmount)
        external
        override
        onlyHandler
        runPolicy
    {}
}
