// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test } from "../modules/forge-std/src/Test.sol";

import { MapleLoanHarness } from "./utils/Harnesses.sol";
import { Utils }            from "./utils/Utils.sol";

import {
    MockERC20,
    MockRevertingERC20,
    MockFactory,
    MockGlobals
} from "./utils/Mocks.sol";

contract RepossessTests is Test, Utils {

    event Repossessed(uint256 fundsRepossessed, address indexed destination);

    address account = makeAddr("account");
    address lender  = makeAddr("lender");

    MapleLoanHarness loan    = new MapleLoanHarness();
    MockFactory      factory = new MockFactory();
    MockGlobals      globals = new MockGlobals();

    function setUp() external {
        factory.__setGlobals(address(globals));

        loan.__setFactory(address(factory));
        loan.__setLender(lender);
    }

    function test_repossess_paused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("ML:PAUSED");
        loan.repossess(account);
    }

    function test_repossess_notLender() external {
        vm.expectRevert("ML:NOT_LENDER");
        loan.repossess(account);
    }

    function test_repossess_notInDefault() external {
        loan.__setDateFunded(block.timestamp);

        vm.prank(lender);
        vm.expectRevert("ML:R:NOT_IN_DEFAULT");
        loan.repossess(account);
    }

    function test_repossess_revertingToken() external {
        address asset = address(new MockRevertingERC20("Asset", "A", 6));

        loan.__setDateFunded(block.timestamp - 1);  // Results in loan being immediately in default since `paymentInterval` is 0.
        loan.__setFundsAsset(asset);

        deal(asset, address(loan), 1);

        vm.prank(lender);
        vm.expectRevert("ML:R:TRANSFER_FAILED");
        loan.repossess(account);
    }

    function setAllState(address asset, address borrower, address pendingBorrower, address pendingLender) internal {
        loan.__setGracePeriod(1);
        loan.__setNoticePeriod(1);
        loan.__setPaymentInterval(1);

        loan.__setDateCalled(1);
        loan.__setDatePaid(1);
        loan.__setDateFunded(1);
        loan.__setDateImpaired(1);

        loan.__setCalledPrincipal(1);
        loan.__setPrincipal(1);

        loan.__setInterestRate(1);
        loan.__setLateFeeRate(1);
        loan.__setLateInterestPremiumRate(1);

        loan.__setBorrower(borrower);
        loan.__setFundsAsset(asset);
        loan.__setPendingBorrower(pendingBorrower);
        loan.__setPendingLender(pendingLender);
    }

    function assertCloseLoanState(address asset, address borrower, address pendingBorrower, address pendingLender) internal {
        assertEq(loan.gracePeriod(),     0);
        assertEq(loan.noticePeriod(),    0);
        assertEq(loan.paymentInterval(), 0);

        assertEq(loan.dateCalled(),   0);
        assertEq(loan.datePaid(),     0);
        assertEq(loan.dateFunded(),   0);
        assertEq(loan.dateImpaired(), 0);

        assertEq(loan.calledPrincipal(),     0);
        assertEq(loan.principal(),           0);

        assertEq(loan.interestRate(),            0);
        assertEq(loan.lateFeeRate(),             0);
        assertEq(loan.lateInterestPremiumRate(), 0);

        assertEq(loan.borrower(),        borrower);
        assertEq(loan.fundsAsset(),      asset);
        assertEq(loan.lender(),          lender);
        assertEq(loan.pendingBorrower(), pendingBorrower);
        assertEq(loan.pendingLender(),   pendingLender);
    }

    function test_repossess_success() external {
        uint256 funds = 100_000e6;

        address asset           = address(new MockERC20("Asset", "A", 6));
        address borrower        = makeAddr("borrower");
        address pendingBorrower = makeAddr("pendingBorrower");
        address pendingLender   = makeAddr("pendingLender");

        setAllState(asset, borrower, pendingBorrower, pendingLender);

        deal(asset, address(loan), funds);

        assertEq(MockERC20(asset).balanceOf(account),       0);
        assertEq(MockERC20(asset).balanceOf(address(loan)), funds);

        vm.expectEmit();
        emit Repossessed(funds, account);
        vm.prank(lender);
        ( uint256 fundsRepossessed ) = loan.repossess(account);

        assertEq(MockERC20(asset).balanceOf(account),       funds);
        assertEq(MockERC20(asset).balanceOf(address(loan)), 0);

        assertEq(fundsRepossessed, funds);

        assertCloseLoanState(asset, borrower, pendingBorrower, pendingLender);
    }

    function test_repossess_success_noTransfer() external {
        address asset           = address(new MockERC20("Asset", "A", 6));
        address borrower        = makeAddr("borrower");
        address pendingBorrower = makeAddr("pendingBorrower");
        address pendingLender   = makeAddr("pendingLender");

        setAllState(asset, borrower, pendingBorrower, pendingLender);

        vm.expectEmit();
        emit Repossessed(0, account);
        vm.prank(lender);
        ( uint256 fundsRepossessed ) = loan.repossess(account);

        assertEq(fundsRepossessed, 0);

        assertCloseLoanState(asset, borrower, pendingBorrower, pendingLender);
    }

}
