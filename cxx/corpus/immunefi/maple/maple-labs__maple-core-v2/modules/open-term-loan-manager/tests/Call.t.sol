// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { LoanManagerHarness } from "./utils/Harnesses.sol";

import { MockFactory, MockGlobals, MockLoan, MockPoolManager } from "./utils/Mocks.sol";

import { TestBase } from "./utils/TestBase.sol";

contract CallPrincipalTestBase is TestBase {

    address poolDelegate = makeAddr("poolDelegate");

    LoanManagerHarness loanManager = new LoanManagerHarness();
    MockFactory        factory     = new MockFactory();
    MockGlobals        globals     = new MockGlobals();
    MockLoan           loan        = new MockLoan();
    MockPoolManager    poolManager = new MockPoolManager();

    function setUp() public virtual {
        factory.__setMapleGlobals(address(globals));

        poolManager.__setPoolDelegate(address(poolDelegate));

        loanManager.__setFactory(address(factory));
        loanManager.__setPoolManager(address(poolManager));
    }

}

contract CallPrincipalTests is CallPrincipalTestBase {

    function test_callPrincipal_paused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("LM:PAUSED");
        loanManager.callPrincipal(address(loan), 1_000_000e6);
    }

    function test_callPrincipal_notPoolDelegate() external {
        vm.expectRevert("LM:NOT_PD");
        loanManager.callPrincipal(address(loan), 1_000_000e6);
    }

    function test_callPrincipal_notLoan() external {
        vm.prank(poolDelegate);
        vm.expectRevert("LM:NOT_LOAN");
        loanManager.callPrincipal(address(0), 1_000_000e6);
    }

    function test_callPrincipal_success() external {
        loanManager.__setPaymentFor(address(loan), 0, 0, block.timestamp, 0);

        loan.__expectCall();
        loan.callPrincipal(1_000_000e6);

        vm.prank(poolDelegate);
        loanManager.callPrincipal(address(loan), 1_000_000e6);
    }

}

contract RemoveCallTests is CallPrincipalTestBase {

    function test_removeCall_paused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("LM:PAUSED");
        loanManager.removeCall(address(loan));
    }

    function test_removeCall_notPoolDelegate() external {
        vm.expectRevert("LM:NOT_PD");
        loanManager.removeCall(address(loan));
    }

    function test_removeCall_notLoan() external {
        vm.prank(poolDelegate);
        vm.expectRevert("LM:NOT_LOAN");
        loanManager.removeCall(address(0));
    }

    function test_removeCall_success() external {
        loanManager.__setPaymentFor(address(loan), 0, 0, block.timestamp, 0);

        loan.__expectCall();
        loan.removeCall();

        vm.prank(poolDelegate);
        loanManager.removeCall(address(loan));
    }

}
