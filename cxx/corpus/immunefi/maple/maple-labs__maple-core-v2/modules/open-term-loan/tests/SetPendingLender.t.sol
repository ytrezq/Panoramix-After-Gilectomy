// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test } from "../modules/forge-std/src/Test.sol";

import { MapleLoanHarness }         from "./utils/Harnesses.sol";
import { MockFactory, MockGlobals } from "./utils/Mocks.sol";

contract SetPendingLenderTests is Test {

    event PendingLenderSet(address indexed pendingLender_);

    address currentLender = makeAddr("currentLender");
    address newLender     = makeAddr("newLender");

    MapleLoanHarness loan    = new MapleLoanHarness();
    MockFactory      factory = new MockFactory();
    MockGlobals      globals = new MockGlobals();

    function setUp() external {
        factory.__setGlobals(address(globals));

        loan.__setFactory(address(factory));
    }

    function test_setPendingLender_paused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("ML:PAUSED");
        loan.setPendingLender(newLender);
    }

    function test_setPendingLender_notLender() external {
        vm.expectRevert("ML:NOT_LENDER");
        loan.setPendingLender(newLender);
    }

    function test_setPendingLender_success() external {
        loan.__setLender(currentLender);

        vm.expectEmit();
        emit PendingLenderSet(newLender);

        vm.prank(currentLender);
        loan.setPendingLender(newLender);

        assertEq(loan.pendingLender(), newLender);
    }

}
