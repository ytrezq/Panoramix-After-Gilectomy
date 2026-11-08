// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {ChainlinkAcePolicyProtectedBase} from "src/infra/chainlink-ace/ChainlinkAcePolicyProtectedBase.sol";
import {StorageHelpersLib} from "src/utils/StorageHelpersLib.sol";

/// @title ChainlinkAceIssuanceValidatorBase Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Shared base for issuance validators that run issuance actions through a Chainlink ACE
/// `IPolicyEngine`. Concrete validators add only their specific (pre/post) issuance entrypoint.
abstract contract ChainlinkAceIssuanceValidatorBase is ChainlinkAcePolicyProtectedBase {
    //==================================================================================================================
    // Storage
    //==================================================================================================================

    bytes32 private constant CHAINLINK_ACE_ISSUANCE_VALIDATOR_BASE_STORAGE_LOCATION =
        0x29d4b031d4049a16372bf7795c19a1a4c51c85d6c6ce9b1a798e768fd6e85300;
    string private constant CHAINLINK_ACE_ISSUANCE_VALIDATOR_BASE_STORAGE_LOCATION_ID =
        "ChainlinkAceIssuanceValidatorBase";

    /// @custom:storage-location erc7201:enzyme.ChainlinkAceIssuanceValidatorBase
    /// @param handler The single issuance handler bound to this validator
    struct ChainlinkAceIssuanceValidatorBaseStorage {
        address handler;
    }

    function __getChainlinkAceIssuanceValidatorBaseStorage()
        private
        pure
        returns (ChainlinkAceIssuanceValidatorBaseStorage storage $)
    {
        bytes32 location = CHAINLINK_ACE_ISSUANCE_VALIDATOR_BASE_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }

    //==================================================================================================================
    // Errors
    //==================================================================================================================

    error ChainlinkAceIssuanceValidatorBase__Init__EmptyHandler();
    error ChainlinkAceIssuanceValidatorBase__OnlyHandler();

    //==================================================================================================================
    // Modifiers
    //==================================================================================================================

    modifier onlyHandler() {
        require(msg.sender == getHandler(), ChainlinkAceIssuanceValidatorBase__OnlyHandler());
        _;
    }

    //==================================================================================================================
    // Constructor
    //==================================================================================================================

    constructor() {
        StorageHelpersLib.verifyErc7201LocationForId({
            _location: CHAINLINK_ACE_ISSUANCE_VALIDATOR_BASE_STORAGE_LOCATION,
            _id: CHAINLINK_ACE_ISSUANCE_VALIDATOR_BASE_STORAGE_LOCATION_ID
        });
    }

    //==================================================================================================================
    // Init
    //==================================================================================================================

    /// @notice Initializer
    /// @param _handler The issuance handler permitted to call the validation entrypoint
    /// @param _policyEngine The policy engine to attach (required non-zero; admin-replaceable)
    function init(address _handler, address _policyEngine) external initializer {
        require(_handler != address(0), ChainlinkAceIssuanceValidatorBase__Init__EmptyHandler());
        __getChainlinkAceIssuanceValidatorBaseStorage().handler = _handler;
        __PolicyProtectedBase_init(_policyEngine);
    }

    //==================================================================================================================
    // State getters
    //==================================================================================================================

    /// @notice Returns the issuance handler bound to this validator
    function getHandler() public view returns (address) {
        return __getChainlinkAceIssuanceValidatorBaseStorage().handler;
    }
}
