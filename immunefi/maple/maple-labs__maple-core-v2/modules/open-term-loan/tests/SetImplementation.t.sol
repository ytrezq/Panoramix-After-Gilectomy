// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test } from "../modules/forge-std/src/Test.sol";

import { MapleLoanHarness }                             from "./utils/Harnesses.sol";
import { MockFactory, MockGlobals, MockImplementation } from "./utils/Mocks.sol";

contract SetImplementationTests is Test {

    MockFactory      factory = new MockFactory();
    MockGlobals      globals = new MockGlobals();
    MapleLoanHarness loan    = new MapleLoanHarness();

    function setUp() external {
        factory.__setGlobals(address(globals));
        
        loan.__setFactory(address(factory));
    }

    function test_setImplementation_paused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("ML:PAUSED");
        loan.setImplementation(address(0));
    }

    function test_setImplementation_notFactory() external {
        vm.expectRevert("ML:SI:NOT_FACTORY");
        loan.setImplementation(address(0));
    }

    function test_setImplementation_success() external {
        address implementation = address(new MockImplementation());

        vm.prank(address(factory));
        loan.setImplementation(implementation);

        assertEq(loan.implementation(), implementation);
    }

}
