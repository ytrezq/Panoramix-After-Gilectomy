// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {ChainlinkAcePolicyProtectedBase} from "src/infra/chainlink-ace/ChainlinkAcePolicyProtectedBase.sol";
import {ISharesTransferValidator} from "src/interfaces/ISharesTransferValidator.sol";

/// @title ChainlinkAceSharesTransferValidator Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Validates shares transfers by running them through a Chainlink ACE
contract ChainlinkAceSharesTransferValidator is ChainlinkAcePolicyProtectedBase, ISharesTransferValidator {
    //==================================================================================================================
    // Init
    //==================================================================================================================

    /// @notice Initializer
    /// @param _policyEngine The policy engine to attach (required non-zero; admin-replaceable)
    function init(address _policyEngine) external initializer {
        __PolicyProtectedBase_init(_policyEngine);
    }

    //==================================================================================================================
    // Required: ISharesTransferValidator
    //==================================================================================================================

    /// @inheritdoc ISharesTransferValidator
    function validateSharesTransfer(address _originator, address _from, address _to, uint256 _amount)
        external
        override
        onlyShares
        runPolicy
    {}
}
