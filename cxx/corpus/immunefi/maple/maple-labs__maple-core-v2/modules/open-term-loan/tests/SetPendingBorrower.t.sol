// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test } from "../modules/forge-std/src/Test.sol";

import { MapleLoanHarness }         from "./utils/Harnesses.sol";
import { MockFactory, MockGlobals } from "./utils/Mocks.sol";

contract SetPendingBorrowerTests is Test {

    event PendingBorrowerSet(address indexed pendingBorrower_);

    address borrowerActions = makeAddr("borrowerActions");
    address currentBorrower = makeAddr("currentBorrower");
    address newBorrower     = makeAddr("newBorrower");

    MapleLoanHarness loan    = new MapleLoanHarness();
    MockFactory      factory = new MockFactory();
    MockGlobals      globals = new MockGlobals();

    function setUp() external {
        factory.__setGlobals(address(globals));

        loan.__setBorrower(currentBorrower);
        loan.__setFactory(address(factory));
    }

    function test_setPendingBorrower_paused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("ML:PAUSED");
        loan.setPendingBorrower(newBorrower);
    }

    function test_setPendingBorrower_notBorrower() external {
        vm.expectRevert("ML:NOT_BORROWER");
        loan.setPendingBorrower(newBorrower);
    }

    function test_setPendingBorrower_invalidBorrower() external {
        vm.prank(currentBorrower);
        vm.expectRevert("ML:SPB:INVALID_BORROWER");
        loan.setPendingBorrower(newBorrower);
    }

    function test_setPendingBorrower_success_asCurrentBorrower() external {
        globals.__setIsBorrower(newBorrower, true);

        vm.expectEmit();
        emit PendingBorrowerSet(newBorrower);

        vm.prank(currentBorrower);
        loan.setPendingBorrower(newBorrower);

        assertEq(loan.pendingBorrower(), newBorrower);
    }

    function test_setPendingBorrower_success_asBorrowerActions() external {
        globals.__setIsBorrower(newBorrower, true);
        globals.__setIsInstanceOf("BORROWER_ACTIONS", borrowerActions, true);   

        vm.expectEmit();
        emit PendingBorrowerSet(newBorrower);

        vm.prank(borrowerActions);
        loan.setPendingBorrower(newBorrower);

        assertEq(loan.pendingBorrower(), newBorrower);
    }

}
