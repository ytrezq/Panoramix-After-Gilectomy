// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {
    ChainlinkAceSharesTransferValidator
} from "src/components/shares-transfer-validators/ChainlinkAceSharesTransferValidator.sol";
import {ChainlinkAcePolicyProtectedBase} from "src/infra/chainlink-ace/ChainlinkAcePolicyProtectedBase.sol";
import {Shares} from "src/shares/Shares.sol";

import {ChainlinkAcePolicyProtectedBaseHarness} from "test/harnesses/ChainlinkAcePolicyProtectedBaseHarness.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

contract ChainlinkAcePolicyProtectedBaseTest is TestHelpers {
    Shares shares;
    ChainlinkAcePolicyProtectedBaseHarness harness;

    address admin = makeAddr("admin");
    address stranger = makeAddr("stranger");
    address policyEngine;

    function setUp() public {
        shares = createShares();

        vm.prank(shares.owner());
        shares.addAdmin(admin);

        harness = new ChainlinkAcePolicyProtectedBaseHarness(address(shares));

        policyEngine = deployPolicyEngine({_defaultAllow: true, _uniqueId: bytes32("engine")});
    }

    //==================================================================================================================
    // init
    //==================================================================================================================

    function test_RevertGiven_TheContractIsTheImplementation() external {
        // It should revert with {InvalidInitialization}.
        // Initializers are disabled in the base constructor, so an implementation cannot be initialized directly.
        ChainlinkAceSharesTransferValidator implementation = new ChainlinkAceSharesTransferValidator();

        vm.expectRevert({revertData: Initializable.InvalidInitialization.selector, reverter: address(implementation)});
        implementation.init(address(0));
    }

    modifier whenCallingAttachPolicyEngine() {
        _;
    }

    //==================================================================================================================
    // attachPolicyEngine
    //==================================================================================================================

    function test_WhenTheCallerIsNotAnAdminOrTheOwner() external whenCallingAttachPolicyEngine {
        // It should revert with {ChainlinkAcePolicyProtectedBase__AuthorizeAttachPolicyEngine__Unauthorized}.
        vm.expectRevert(
            ChainlinkAcePolicyProtectedBase.ChainlinkAcePolicyProtectedBase__AuthorizeAttachPolicyEngine__Unauthorized
                .selector,
            address(harness)
        );

        vm.prank(stranger);
        harness.attachPolicyEngine(policyEngine);
    }

    function test_WhenTheCallerIsAnAdmin() external whenCallingAttachPolicyEngine {
        // It should not revert (authorized).
        vm.prank(admin);
        harness.attachPolicyEngine(policyEngine);
    }

    function test_WhenTheCallerIsTheOwner() external whenCallingAttachPolicyEngine {
        // It should not revert (authorized).
        vm.prank(shares.owner());
        harness.attachPolicyEngine(policyEngine);
    }
}
