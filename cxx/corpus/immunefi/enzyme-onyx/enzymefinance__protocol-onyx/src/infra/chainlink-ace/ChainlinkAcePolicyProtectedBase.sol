// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {PolicyProtectedBaseUpgradeable} from "@chainlink/policy-management/core/PolicyProtectedBaseUpgradeable.sol";

import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";

/// @title ChainlinkAcePolicyProtectedBase Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Base for integrating Onyx contracts with a Chainlink ACE policy engine.
/// @dev This integration does not use per-user context: policy inputs are decoded from calldata by extractors.
/// The inherited `setContext`/`getContext`/`clearContext` remain callable (vendored `IPolicyProtected` surface)
/// but have no effect on policy runs here, since hooks are invoked by protocol contracts (handler or Shares),
/// whose stored context is always empty.
abstract contract ChainlinkAcePolicyProtectedBase is PolicyProtectedBaseUpgradeable, ComponentHelpersMixin {
    //==================================================================================================================
    // Constructor
    //==================================================================================================================

    constructor() {
        _disableInitializers();
    }

    //==================================================================================================================
    // Errors
    //==================================================================================================================

    error ChainlinkAcePolicyProtectedBase__AuthorizeAttachPolicyEngine__Unauthorized();

    //==================================================================================================================
    // Policy engine
    //==================================================================================================================

    function _authorizeAttachPolicyEngine(address) internal view override {
        require(
            __isAdminOrOwner(msg.sender), ChainlinkAcePolicyProtectedBase__AuthorizeAttachPolicyEngine__Unauthorized()
        );
    }
}
