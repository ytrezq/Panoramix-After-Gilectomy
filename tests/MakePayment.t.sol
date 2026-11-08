// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test } from "../modules/forge-std/src/Test.sol";

import { MapleLoanHarness } from "./utils/Harnesses.sol";
import { Utils }            from "./utils/Utils.sol";

import {
    MockERC20,
    MockFactory,
    MockGlobals,
    MockLender
} from "./utils/Mocks.sol";

contract MakePaymentFailureTests is Test, Utils {

    MapleLoanHarness loan    = new MapleLoanHarness();
    MockFactory      factory = new MockFactory();
    MockGlobals      globals = new MockGlobals();

    function setUp() external {
        factory.__setGlobals(address(globals));

        loan.__setFactory(address(factory));
    }

    function test_makePayment_paused() external {
        globals.__setFunctionPaused(true);
        vm.expectRevert("ML:PAUSED");
        loan.makePayment(0);
    }

    function test_makePayment_notFunded() external {
        vm.expectRevert("ML:MP:LOAN_INACTIVE");
        loan.makePayment(2);
    }

    function test_makePayment_returningTooMuch() external {
        loan.__setDateFunded(1);
        loan.__setPrincipal(1);
        vm.expectRevert("ML:MP:RETURNING_TOO_MUCH");
        loan.makePayment(2);
    }

    function test_makePayment_insufficientForCalled() external {
        loan.__setCalledPrincipal(1);
        loan.__setDateFunded(1);
        loan.__setPrincipal(1);

        vm.expectRevert("ML:MP:INSUFFICIENT_FOR_CALL");
        loan.makePayment(0);
    }

    function test_makePayment_insufficientForTotalTransferFromCaller() external {
        address account   = makeAddr("account");
        address asset     = address(new MockERC20("Asset", "A", 6));
        uint256 principal = 100_000e6;

        loan.__setDateFunded(1);
        loan.__setFundsAsset(asset);
        loan.__setPrincipal(principal);

        deal(asset, account, principal - 1);

        vm.prank(account);
        MockERC20(asset).approve(address(loan), type(uint256).max);

        vm.expectRevert("ML:MP:TRANSFER_FROM_FAILED");
        vm.startPrank(account);
        loan.makePayment(principal);
    }

}

contract MakePaymentSuccessTests is Test, Utils {

    event PaymentMade(
        address indexed lender,
        uint256 principalPaid,
        uint256 interestPaid,
        uint256 lateInterestPaid,
        uint256 delegateServiceFee,
        uint256 platformServiceFee,
        uint40  paymentDueDate,
        uint40  defaultDate
    );

    event PrincipalReturned(uint256 principalReturned, uint256 principalRemaining);

    uint256 constant delegateServiceFeeRate  = 0.01e18;
    uint256 constant gracePeriod             = 1 days;
    uint256 constant interestRate            = 0.10e18;
    uint256 constant lateFeeRate             = 0.01e18;
    uint256 constant lateInterestPremiumRate = 0.05e18;
    uint256 constant noticePeriod            = 2 days;
    uint256 constant platformServiceFeeRate  = 0.02e18;
    uint256 constant principal               = 100_000e6;

    address account = makeAddr("account");

    uint256 datePaid = block.timestamp;  // Always paying now

    MapleLoanHarness loan    = new MapleLoanHarness();
    MockERC20        asset   = new MockERC20("Asset", "A", 6);
    MockGlobals      globals = new MockGlobals();
    MockLender       lender  = new MockLender();

    function setUp() external {
        MockFactory factory = new MockFactory();

        factory.__setGlobals(address(globals));

        loan.__setFactory(address(factory));
        loan.__setFundsAsset(address(asset));
        loan.__setGracePeriod(gracePeriod);
        loan.__setInterestRate(interestRate);
        loan.__setLateFeeRate(lateFeeRate);
        loan.__setLateInterestPremiumRate(lateInterestPremiumRate);
        loan.__setLender(address(lender));
        loan.__setNoticePeriod(noticePeriod);
        loan.__setPlatformServiceFeeRate(platformServiceFeeRate);
        loan.__setPrincipal(principal);

        vm.prank(account);
        asset.approve(address(loan), type(uint256).max);
    }

    function testFuzz_makePayment(
        uint256 paymentInterval,
        uint256 dateFunded,
        uint256 calledPrincipal,
        uint256 principalToReturn
    )
        external
    {
        // Need calledPrincipal to be 0, [0, principal], or principal each 33% of the time.
        calledPrincipal = calledPrincipal % (3 * principal);
        calledPrincipal = calledPrincipal < principal ? 0 : calledPrincipal > principal ? principal : calledPrincipal;

        loan.__setCalledPrincipal(calledPrincipal);

        // `principalToReturn` be at least `calledPrincipal`, but it `calledPrincipal == principal`, then it can only be `principal`.
        principalToReturn = calledPrincipal == principal
            ? principal
            : bound(principalToReturn, calledPrincipal, principal);

        // Just set these to check that they are cleared after the payment. They have no impact on the payment itself.
        loan.__setDateCalled(datePaid);
        loan.__setDateImpaired(datePaid);

        paymentInterval = bound(paymentInterval, 1 days, 30 days);

        loan.__setPaymentInterval(paymentInterval);

        // The date funded will be between `datePaid - 1 days` (early payment) and `datePaid - 2 * paymentInterval` (very lat payment).
        dateFunded = datePaid - bound(dateFunded, 1 days, 2 * paymentInterval);

        loan.__setDateFunded(dateFunded);

        (
            , // UNUSED
            uint256 expectedInterest,
            uint256 expectedLateInterest,
            uint256 expectedDelegateServiceFee,
            uint256 expectedPlatformServiceFee
        ) = loan.getPaymentBreakdown(block.timestamp);

        // `expectedPaymentDueDate` and `expectedDefaultDate` will be 0 if all principal is returned.
        uint256 expectedPaymentDueDate = principalToReturn == principal ? 0 : datePaid + paymentInterval;
        uint256 expectedDefaultDate    = expectedPaymentDueDate == 0 ? 0 : expectedPaymentDueDate + gracePeriod;

        uint256 totalPayment =
            principalToReturn +
            expectedInterest +
            expectedLateInterest +
            expectedDelegateServiceFee +
            expectedPlatformServiceFee;

        deal(address(asset), account, totalPayment);

        // Asset balances of relevant addresses before the payment is made.
        assertEq(asset.balanceOf(account),         totalPayment);
        assertEq(asset.balanceOf(address(lender)), 0);
        assertEq(asset.balanceOf(address(loan)),   0);

        // Set up the mock lender to expect it's `claim` to be called with these specific values.
        lender.__expectCall();
        lender.claim(
            int256(principalToReturn),
            expectedInterest + expectedLateInterest,
            expectedDelegateServiceFee,
            expectedPlatformServiceFee,
            uint40(expectedPaymentDueDate)
        );

        // If there is principal returned, expect the relevant event.
        if (principalToReturn != 0) {
            vm.expectEmit();
            emit PrincipalReturned(principalToReturn, principal - principalToReturn);
        }

        vm.expectEmit();
        emit PaymentMade(
            address(lender),
            principalToReturn,
            expectedInterest,
            expectedLateInterest,
            expectedDelegateServiceFee,
            expectedPlatformServiceFee,
            uint40(expectedPaymentDueDate),
            uint40(expectedDefaultDate)
        );

        vm.prank(account);
        (
            uint256 interest,
            uint256 lateInterest,
            uint256 delegateServiceFee,
            uint256 platformServiceFee
        ) = loan.makePayment(principalToReturn);

        // Asset returns of function.
        assertEq(interest,           expectedInterest);
        assertEq(lateInterest,       expectedLateInterest);
        assertEq(delegateServiceFee, expectedDelegateServiceFee);
        assertEq(platformServiceFee, expectedPlatformServiceFee);

        // Asset balances of relevant addresses after the payment is made.
        assertEq(asset.balanceOf(account),         0);
        assertEq(asset.balanceOf(address(lender)), totalPayment);
        assertEq(asset.balanceOf(address(loan)),   0);

        // Asset values that will be deleted regardless the condition of the loan or parameters of the payment.
        assertEq(loan.dateCalled(),      0);
        assertEq(loan.dateImpaired(),    0);
        assertEq(loan.calledPrincipal(), 0);

        if (principalToReturn == principal) {
            // If the principal was returned entirely, the loan is closed, and the following variables would have been deleted.
            assertEq(loan.gracePeriod(),             0);
            assertEq(loan.noticePeriod(),            0);
            assertEq(loan.paymentInterval(),         0);
            assertEq(loan.datePaid(),                0);
            assertEq(loan.dateFunded(),              0);
            assertEq(loan.principal(),               0);
            assertEq(loan.interestRate(),            0);
            assertEq(loan.lateFeeRate(),             0);
            assertEq(loan.lateInterestPremiumRate(), 0);
            assertEq(loan.paymentDueDate(),          0);
        } else {
            // For every other payment, the `datePaid` and `paymentDueDate` would be updated.
            assertEq(loan.datePaid(),       uint40(datePaid));
            assertEq(loan.paymentDueDate(), uint40(expectedPaymentDueDate));
        }
    }

}
