// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test } from "../modules/forge-std/src/Test.sol";

import { MapleLoanHarness }         from "./utils/Harnesses.sol";
import { MockFactory, MockGlobals } from "./utils/Mocks.sol";

contract AcceptBorrowerTests is Test {

    event BorrowerAccepted(address indexed newBorrower_);

    address account = makeAddr("account");

    MapleLoanHarness loan    = new MapleLoanHarness();
    MockFactory      factory = new MockFactory();
    MockGlobals      globals = new MockGlobals();

    function setUp() external {
        factory.__setGlobals(address(globals));

        loan.__setFactory(address(factory));
    }

    function test_acceptBorrower_paused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("ML:PAUSED");
        loan.acceptBorrower();
    }

    function test_acceptBorrower_notPendingBorrower() external {
        loan.__setPendingBorrower(account);

        vm.expectRevert("ML:AB:NOT_PENDING_BORROWER");
        loan.acceptBorrower();
    }

    function test_acceptBorrower_success() external {
        loan.__setPendingBorrower(account);

        vm.expectEmit();
        emit BorrowerAccepted(account);

        vm.prank(account);
        loan.acceptBorrower();

        assertEq(loan.borrower(),        account);
        assertEq(loan.pendingBorrower(), address(0));
    }

}
