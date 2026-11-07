// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";
import {IPolicyProtected} from "@chainlink/policy-management/interfaces/IPolicyProtected.sol";

import {
    ChainlinkAceIssuanceValidatorBase
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceIssuanceValidatorBase.sol";
import {Shares} from "src/shares/Shares.sol";

import {ChainlinkAceIssuanceValidatorBaseHarness} from "test/harnesses/ChainlinkAceIssuanceValidatorBaseHarness.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

/// @notice Verifies the project-owned logic that `ChainlinkAceIssuanceValidatorBase` adds on top of the
/// vendored ACE base: handler storage/validation on init, engine attachment wiring, and `getHandler`.
/// Runs once against a minimal harness; the concrete validator suites cover only their per-entrypoint wiring.
contract ChainlinkAceIssuanceValidatorBaseTest is TestHelpers {
    Shares shares;

    address handler = makeAddr("handler");

    function setUp() public {
        shares = createShares();
    }

    function __deployUninitializedValidator() internal returns (ChainlinkAceIssuanceValidatorBaseHarness validator_) {
        validator_ = new ChainlinkAceIssuanceValidatorBaseHarness(address(shares));
    }

    modifier whenInitializing() {
        _;
    }

    //==================================================================================================================
    // init
    //==================================================================================================================

    function test_WhenTheHandlerIsTheZeroAddress() external whenInitializing {
        ChainlinkAceIssuanceValidatorBaseHarness validator = __deployUninitializedValidator();
        address engine = makeAddr("engine");

        // It should revert with {ChainlinkAceIssuanceValidatorBase__Init__EmptyHandler}.
        vm.expectRevert(
            ChainlinkAceIssuanceValidatorBase.ChainlinkAceIssuanceValidatorBase__Init__EmptyHandler.selector,
            address(validator)
        );
        validator.init({_handler: address(0), _policyEngine: engine});
    }

    function test_WhenThePolicyEngineIsTheZeroAddress() external whenInitializing {
        ChainlinkAceIssuanceValidatorBaseHarness validator = __deployUninitializedValidator();

        // It should revert.
        vm.expectRevert(bytes("Policy engine is zero address"), address(validator));
        validator.init({_handler: handler, _policyEngine: address(0)});
    }

    function test_WhenBothTheHandlerAndThePolicyEngineAreNon_zeroAddresses() external whenInitializing {
        ChainlinkAceIssuanceValidatorBaseHarness validator = __deployUninitializedValidator();
        address engine = deployPolicyEngine({_defaultAllow: true});

        // It should attach the validator to the policy engine.
        vm.expectCall(engine, abi.encodeCall(IPolicyEngine.attach, ()));

        vm.expectEmit(address(validator));
        emit IPolicyProtected.PolicyEngineAttached(engine);

        validator.init({_handler: handler, _policyEngine: engine});

        // It should store the handler.
        assertEq(validator.getHandler(), handler, "handler not stored");

        // It should store the policy engine as the attached engine.
        assertEq(validator.getPolicyEngine(), engine, "engine not stored");
    }

    //==================================================================================================================
    // getHandler
    //==================================================================================================================

    function test_WhenGettingTheHandler() external {
        ChainlinkAceIssuanceValidatorBaseHarness validator = __deployUninitializedValidator();
        validator.init({_handler: handler, _policyEngine: deployPolicyEngine({_defaultAllow: true})});

        // It should return the stored handler.
        assertEq(validator.getHandler(), handler, "handler mismatch");
    }
}
