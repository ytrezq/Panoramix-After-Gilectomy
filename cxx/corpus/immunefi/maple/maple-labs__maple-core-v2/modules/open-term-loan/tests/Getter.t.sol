// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test } from "../modules/forge-std/src/Test.sol";

import { MapleLoanHarness }         from "./utils/Harnesses.sol";
import { MockFactory, MockGlobals } from "./utils/Mocks.sol";

contract GetterTests is Test {

    address lender = makeAddr("lender");

    MockFactory      factoryMock = new MockFactory();
    MapleLoanHarness loan        = new MapleLoanHarness();
    MockGlobals      globals     = new MockGlobals();

    function setUp() external {
        factoryMock.__setGlobals(address(globals));

        loan.__setFactory(address(factoryMock));
        loan.__setLender(lender);
        loan.__setPrincipal(100_000e6);
    }

    function test_factory_getter() external {
        assertEq(loan.factory(), address(factoryMock));
    }

    function test_globals_getter() external {
        assertEq(loan.globals(), address(globals));
    }

    function test_isCalled_getter() external {
        assertEq(loan.isCalled(), false);

        loan.__setDateCalled(block.timestamp);

        assertEq(loan.isCalled(), true);
    }

    function test_isImpaied_getter() external {
        assertEq(loan.isImpaired(), false);

        loan.__setDateImpaired(block.timestamp);

        assertEq(loan.isImpaired(), true);
    }

}
