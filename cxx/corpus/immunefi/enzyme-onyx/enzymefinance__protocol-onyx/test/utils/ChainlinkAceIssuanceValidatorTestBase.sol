// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";

import {
    ChainlinkAceIssuanceValidatorBase
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceIssuanceValidatorBase.sol";
import {Shares} from "src/shares/Shares.sol";

import {TestHelpers} from "test/utils/TestHelpers.sol";

/// @notice Shared test base for the ACE issuance validators. Holds the project-owned wiring assertions
/// (caller gate + per-validator selector/arg encoding forwarded to the policy engine), written once and
/// executed against each concrete validator's entrypoint. Vendored ACE behavior (skip-when-no-engine,
/// allow-path, attach/event, `runPolicy` mechanics) is verified once in
/// `test/contracts/chainlink-ace-policy-protected-base/` and `test/contracts/chainlink-ace-issuance-validator-base/`.
/// @dev Abstract: Forge never runs it standalone. Each concrete suite implements the three virtual hooks.
abstract contract ChainlinkAceIssuanceValidatorTestBase is TestHelpers {
    Shares shares;

    address handler = makeAddr("handler");

    function setUp() public {
        shares = createShares();
    }

    //==================================================================================================================
    // Virtual hooks (per-validator)
    //==================================================================================================================

    /// @dev Constructs the specific validator harness bound to `shares_` (uninitialized).
    function __deployValidator(address shares_) internal virtual returns (address validator_);

    /// @dev Invokes the validator's issuance entrypoint with this suite's canonical test args.
    function __callEntrypoint(address validator_) internal virtual;

    /// @dev The exact payload the validator should forward to `engine.run`: selector + abi-encoded args.
    function __expectedPayload(bytes memory context_) internal view virtual returns (IPolicyEngine.Payload memory);

    //==================================================================================================================
    // Helpers
    //==================================================================================================================

    function __deployInitializedValidator(bool defaultAllow_) internal returns (address validator_, address engine_) {
        engine_ = deployPolicyEngine(defaultAllow_);
        validator_ = __deployValidator(address(shares));
        ChainlinkAceIssuanceValidatorBase(validator_).init({_handler: handler, _policyEngine: engine_});
    }

    //==================================================================================================================
    // Shared assertions
    //
    // The two leaves live in every concrete suite's tree; the assertion logic is written once here and each
    // concrete file calls it through a bulloak-named wrapper so `bulloak check` resolves both leaves per file.
    //==================================================================================================================

    function __assertRevertsWhenCallerNotHandler() internal {
        (address validator,) = __deployInitializedValidator({defaultAllow_: true});

        // It should revert with {ChainlinkAceIssuanceValidatorBase__OnlyHandler}.
        vm.expectRevert(
            ChainlinkAceIssuanceValidatorBase.ChainlinkAceIssuanceValidatorBase__OnlyHandler.selector, validator
        );
        vm.prank(makeAddr("notHandler"));
        __callEntrypoint(validator);
    }

    function __assertRevertsWhenPolicyRejects() internal {
        // Default-reject engine with no policy attached rejects every run, surfacing the exact payload.
        (address validator, address engine) = __deployInitializedValidator({defaultAllow_: false});

        // It should revert with {PolicyRunRejected}, proving the validator forwards the correct
        // selector, sender and abi-encoded args to the engine.
        vm.expectRevert(
            abi.encodeWithSelector(
                IPolicyEngine.PolicyRunRejected.selector,
                address(0),
                "no policy allowed the action and default is reject",
                __expectedPayload(bytes(""))
            ),
            engine
        );
        vm.prank(handler);
        __callEntrypoint(validator);
    }
}
