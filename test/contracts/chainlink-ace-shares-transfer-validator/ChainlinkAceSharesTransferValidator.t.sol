// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";

import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {ISharesTransferValidator} from "src/interfaces/ISharesTransferValidator.sol";
import {Shares} from "src/shares/Shares.sol";

import {
    ChainlinkAceSharesTransferValidatorHarness
} from "test/harnesses/ChainlinkAceSharesTransferValidatorHarness.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

/// @notice Standalone suite (distinct init/gate/sender from the issuance validators). Asserts only the
/// project-owned wiring: the `onlyShares` caller gate and the selector/sender/arg encoding forwarded to the
/// engine. Vendored ACE behavior is verified once in `test/contracts/chainlink-ace-policy-protected-base/`.
contract ChainlinkAceSharesTransferValidatorTest is TestHelpers {
    Shares shares;
    ChainlinkAceSharesTransferValidatorHarness validator;

    address originator = makeAddr("originator");
    address from = makeAddr("from");
    address to = makeAddr("to");
    uint256 amount = 123;

    function setUp() public {
        shares = createShares();
        validator = new ChainlinkAceSharesTransferValidatorHarness(address(shares));
    }

    // Builds the exact payload the validator should forward to engine.run.
    function __expectedPayload(bytes memory _context) internal view returns (IPolicyEngine.Payload memory) {
        return IPolicyEngine.Payload({
            selector: ISharesTransferValidator.validateSharesTransfer.selector,
            sender: address(shares),
            data: abi.encode(originator, from, to, amount),
            context: _context
        });
    }

    function test_WhenTheCallerIsNotTheSharesContract() external {
        validator.init(deployPolicyEngine({_defaultAllow: true}));

        // It should revert with {ComponentHelpersMixin__OnlyShares__Unauthorized}.
        vm.expectRevert(
            ComponentHelpersMixin.ComponentHelpersMixin__OnlyShares__Unauthorized.selector, address(validator)
        );
        vm.prank(makeAddr("notShares"));
        validator.validateSharesTransfer(originator, from, to, amount);
    }

    function test_GivenThePolicyEngineRejectsTheRun() external {
        // Default-reject engine with no policy attached rejects every run, surfacing the exact payload.
        address engine = deployPolicyEngine({_defaultAllow: false});
        validator.init(engine);

        // It should revert with {PolicyRunRejected}, proving the validator forwards the correct
        // selector, sender (the Shares contract) and abi-encoded args to the engine.
        vm.expectRevert(
            abi.encodeWithSelector(
                IPolicyEngine.PolicyRunRejected.selector,
                address(0),
                "no policy allowed the action and default is reject",
                __expectedPayload(bytes(""))
            ),
            engine
        );
        vm.prank(address(shares));
        validator.validateSharesTransfer(originator, from, to, amount);
    }
}
