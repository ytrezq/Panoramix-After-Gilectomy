// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {ISharesMintHandlerPreMintHook} from "src/components/issuance/interfaces/ISharesMintHandlerPreMintHook.sol";

import {ChainlinkAceIssuanceValidatorBase} from "./ChainlinkAceIssuanceValidatorBase.sol";

/// @title ChainlinkAceSharesMintHandlerPreMintValidator Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Validates mints before they are committed by running
/// them through a Chainlink ACE `IPolicyEngine`.
contract ChainlinkAceSharesMintHandlerPreMintValidator is
    ChainlinkAceIssuanceValidatorBase,
    ISharesMintHandlerPreMintHook
{
    //==================================================================================================================
    // Required: ISharesMintHandlerPreMintHook
    //==================================================================================================================

    /// @inheritdoc ISharesMintHandlerPreMintHook
    function preMint(address _originator, address _to, uint256 _sharesAmount) external override onlyHandler runPolicy {}
}
