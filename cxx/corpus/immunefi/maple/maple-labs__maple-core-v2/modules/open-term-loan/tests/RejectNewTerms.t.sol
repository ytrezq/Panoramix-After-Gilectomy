// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test } from "../modules/forge-std/src/Test.sol";

import { MapleLoanHarness }         from "./utils/Harnesses.sol";
import { MockFactory, MockGlobals } from "./utils/Mocks.sol";
import { Utils }                    from "./utils/Utils.sol";

contract RejectNewTermsTests is Test, Utils {

    address borrowerActions = makeAddr("borrowerActions");
    address borrower        = makeAddr("borrower");
    address lender          = makeAddr("lender");
    address refinancer      = makeAddr("refinancer");

    bytes[] calls = _encodeCall(abi.encodeWithSignature("setPaymentInterval(uint32)", 2_000_000));

    MapleLoanHarness loan    = new MapleLoanHarness();
    MockFactory      factory = new MockFactory();
    MockGlobals      globals = new MockGlobals();

    function setUp() external {
        factory.__setGlobals(address(globals));

        loan.__setBorrower(borrower);
        loan.__setFactory(address(factory));
        loan.__setLender(lender);
        loan.__setRefinanceCommitment(keccak256(abi.encode(address(refinancer), block.timestamp, calls)));
    }

    function test_rejectNewTerms_paused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("ML:PAUSED");
        loan.rejectNewTerms(refinancer, block.timestamp, new bytes[](0));
    }

    function test_rejectNewTerms_notBorrowerNorLender() external {
        vm.expectRevert("ML:RNT:NO_AUTH");
        loan.rejectNewTerms(refinancer, block.timestamp, new bytes[](0));
    }

    function test_rejectNewTerms_mismatchedCommitment() external {
        vm.expectRevert("ML:RNT:COMMITMENT_MISMATCH");
        vm.prank(borrower);
        loan.rejectNewTerms(refinancer, block.timestamp, new bytes[](0));
    }

    function test_rejectNewTerms_success_asBorrower() external {
        vm.prank(borrower);
        loan.rejectNewTerms(refinancer, block.timestamp, calls);

        assertEq(loan.refinanceCommitment(), bytes32(0));
    }

    function test_rejectNewTerms_success_asBorrowerActions() external {
        globals.__setIsInstanceOf("BORROWER_ACTIONS", borrowerActions, true);

        vm.prank(borrowerActions);
        loan.rejectNewTerms(refinancer, block.timestamp, calls);

        assertEq(loan.refinanceCommitment(), bytes32(0));
    }

    function test_rejectNewTerms_success_asLender() external {
        vm.prank(lender);
        loan.rejectNewTerms(refinancer, block.timestamp, calls);

        assertEq(loan.refinanceCommitment(), bytes32(0));
    }

    function _encodeCall(bytes memory call) internal pure returns (bytes[] memory calls) {
        calls = new bytes[](1);
        calls[0] = call;
    }

}
