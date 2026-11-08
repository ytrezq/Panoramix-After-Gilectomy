// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test } from "../modules/forge-std/src/Test.sol";

import { MapleLoanHarness }         from "./utils/Harnesses.sol";
import { MockFactory, MockGlobals } from "./utils/Mocks.sol";
import { Utils }                    from "./utils/Utils.sol";

contract ProposeNewTermsTests is Test, Utils {

    event NewTermsProposed(bytes32 refinanceCommitment_, address refinancer_, uint256 deadline_, bytes[] calls_);

    address lender     = makeAddr("lender");
    address refinancer = makeAddr("refinancer");

    MapleLoanHarness loan    = new MapleLoanHarness();
    MockFactory      factory = new MockFactory();
    MockGlobals      globals = new MockGlobals();

    function setUp() external {
        factory.__setGlobals(address(globals));

        loan.__setDateFunded(block.timestamp);
        loan.__setFactory(address(factory));
        loan.__setLender(lender);
    }

    function test_proposeNewTerms_paused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("ML:PAUSED");
        loan.proposeNewTerms(address(0), 0, new bytes[](0));
    }

    function test_proposeNewTerms_notLender() external {
        vm.expectRevert("ML:NOT_LENDER");
        loan.proposeNewTerms(address(0), 0, new bytes[](0));
    }

    function test_proposeNewTerms_notFunded() external {
        loan.__setDateFunded(0);

        vm.prank(lender);
        vm.expectRevert("ML:PNT:LOAN_INACTIVE");
        loan.proposeNewTerms(refinancer, block.timestamp + 1, new bytes[](0));
    }

    function test_proposeNewTerms_invalidRefinancer() external {
        vm.expectRevert("ML:PNT:INVALID_REFINANCER");
        vm.prank(lender);
        loan.proposeNewTerms(refinancer, block.timestamp + 1, new bytes[](0));
    }

    function test_proposeNewTerms_emptyCalls() external {
        globals.__setIsInstanceOf("OT_REFINANCER", refinancer, true);

        vm.expectRevert("ML:PNT:EMPTY_CALLS");
        vm.prank(lender);
        loan.proposeNewTerms(refinancer, block.timestamp + 1, new bytes[](0));
    }

    function test_proposeNewTerms_deadlineBoundary() external {
        globals.__setIsInstanceOf("OT_REFINANCER", refinancer, true);

        vm.expectRevert("ML:PNT:INVALID_DEADLINE");
        vm.prank(lender);
        loan.proposeNewTerms(refinancer, block.timestamp - 1, new bytes[](1));

        vm.prank(lender);
        loan.proposeNewTerms(refinancer, block.timestamp, new bytes[](1));
    }

    function test_proposeNewTerms_success() external {
        globals.__setIsInstanceOf("OT_REFINANCER", refinancer, true);

        vm.prank(lender);
        loan.proposeNewTerms(refinancer, block.timestamp + 1, new bytes[](1));

        bytes32 expectedRefinanceCommitment_ = keccak256(abi.encode(refinancer, block.timestamp + 1, new bytes[](1)));

        vm.expectEmit();
        emit NewTermsProposed(expectedRefinanceCommitment_, refinancer, block.timestamp + 1, new bytes[](1));

        vm.prank(lender);
        bytes32 refinanceCommitment_ = loan.proposeNewTerms(refinancer, block.timestamp + 1, new bytes[](1));

        assertEq(refinanceCommitment_,       expectedRefinanceCommitment_);
        assertEq(loan.refinanceCommitment(), expectedRefinanceCommitment_);
    }

}
