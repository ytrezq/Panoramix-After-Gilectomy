// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test } from "../modules/forge-std/src/Test.sol";

import { MapleLoanHarness }         from "./utils/Harnesses.sol";
import { MockFactory, MockGlobals } from "./utils/Mocks.sol";

contract AcceptLenderTests is Test {

    event LenderAccepted(address indexed newLender_);

    address account = makeAddr("account");

    MapleLoanHarness loan    = new MapleLoanHarness();
    MockFactory      factory = new MockFactory();
    MockGlobals      globals = new MockGlobals();

    function setUp() external {
        factory.__setGlobals(address(globals));

        loan.__setFactory(address(factory));
    }

    function test_acceptLender_paused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("ML:PAUSED");
        loan.acceptLender();
    }

    function test_acceptLender_notPendingLender() external {
        loan.__setPendingLender(account);

        vm.expectRevert("ML:AL:NOT_PENDING_LENDER");
        loan.acceptLender();
    }

    function test_acceptLender_success() external {
        loan.__setPendingLender(account);

        vm.expectEmit();
        emit LenderAccepted(account);

        vm.prank(account);
        loan.acceptLender();

        assertEq(loan.lender(),        account);
        assertEq(loan.pendingLender(), address(0));
    }

}
