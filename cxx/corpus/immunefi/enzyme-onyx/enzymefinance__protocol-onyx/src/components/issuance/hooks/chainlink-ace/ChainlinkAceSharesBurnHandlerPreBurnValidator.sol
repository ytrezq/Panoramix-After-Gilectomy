// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {ISharesBurnHandlerPreBurnHook} from "src/components/issuance/interfaces/ISharesBurnHandlerPreBurnHook.sol";

import {ChainlinkAceIssuanceValidatorBase} from "./ChainlinkAceIssuanceValidatorBase.sol";

/// @title ChainlinkAceSharesBurnHandlerPreBurnValidator Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Validates burns before they are committed by running
/// them through a Chainlink ACE `IPolicyEngine`.
contract ChainlinkAceSharesBurnHandlerPreBurnValidator is
    ChainlinkAceIssuanceValidatorBase,
    ISharesBurnHandlerPreBurnHook
{
    //==================================================================================================================
    // Required: ISharesBurnHandlerPreBurnHook
    //==================================================================================================================

    /// @inheritdoc ISharesBurnHandlerPreBurnHook
    function preBurn(address _originator, address _from, uint256 _sharesAmount)
        external
        override
        onlyHandler
        runPolicy
    {}
}
