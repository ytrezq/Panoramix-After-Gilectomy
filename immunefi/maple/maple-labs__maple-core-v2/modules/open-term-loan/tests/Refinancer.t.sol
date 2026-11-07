// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test } from "../modules/forge-std/src/Test.sol";

import { MapleRefinancer } from "../contracts/MapleRefinancer.sol";

import { MapleLoanHarness } from "./utils/Harnesses.sol";

// TODO: Consider just attaching the refinancer to the harness via a `__refinance` on the harness.

// Expose refinancer via delegatecall in the context of the loans storage
contract MapleLoanWithRefinance is MapleLoanHarness {

    function refinance(address refinancer, bytes[]calldata calls) external {
        for (uint256 i; i < calls.length;) {
            ( bool success, ) = refinancer.delegatecall(calls[i]);
            require(success, "ML:R:FAILED");
            unchecked { ++i; }
        }
    }

}

// Tests to ensure the refinancer updates the correct storage slots on the loan.
contract RefinancerTests is Test {

    // Loan Boundaries
    uint256 internal constant MAX_RATE         = 1e18;          // 100%
    uint256 internal constant MAX_TIME         = 2 * 365 days;  // Assumed reasonable upper limit for payment intervals and grace periods
    uint256 internal constant MAX_TOKEN_AMOUNT = 1e12 * 10e18;  // 1 trillion units of a token with 18 decimals
    uint256 internal constant MIN_TOKEN_AMOUNT = 10e6;          // Needed so payments don't round down to zero

    address refinancer = address(new MapleRefinancer());

    MapleLoanWithRefinance loan = new MapleLoanWithRefinance();

    function setupLoan(
        uint256 principal,
        uint256 delegateServiceFeeRate,
        uint256 gracePeriod,
        uint256 interestRate,
        uint256 lateFeeRate,
        uint256 lateInterestPremiumRate,
        uint256 noticePeriod,
        uint256 paymentInterval
    ) internal {
        loan.__setPrincipal(principal);
        loan.__setDelegateServiceFeeRate(delegateServiceFeeRate);
        loan.__setGracePeriod(gracePeriod);
        loan.__setInterestRate(interestRate);
        loan.__setLateFeeRate(lateFeeRate);
        loan.__setLateInterestPremiumRate(lateInterestPremiumRate);
        loan.__setNoticePeriod(noticePeriod);
        loan.__setPaymentInterval(paymentInterval);

        assertEq(loan.principal(),               principal);
        assertEq(loan.delegateServiceFeeRate(),  delegateServiceFeeRate);
        assertEq(loan.gracePeriod(),             gracePeriod);
        assertEq(loan.interestRate(),            interestRate);
        assertEq(loan.lateFeeRate(),             lateFeeRate);
        assertEq(loan.lateInterestPremiumRate(), lateInterestPremiumRate);
        assertEq(loan.noticePeriod(),            noticePeriod);
        assertEq(loan.paymentInterval(),         paymentInterval);
    }

    function test_refinancer_decreasePrincipal(
        uint256 principal,
        uint256 delegateServiceFeeRate,
        uint256 gracePeriod,
        uint256 interestRate,
        uint256 lateFeeRate,
        uint256 lateInterestPremiumRate,
        uint256 noticePeriod,
        uint256 paymentInterval,
        uint256 newPrincipalDecrease
    ) external {
        principal               = bound(principal,               MIN_TOKEN_AMOUNT, MAX_TOKEN_AMOUNT);
        delegateServiceFeeRate  = bound(delegateServiceFeeRate,  0,                MAX_RATE);
        gracePeriod             = bound(gracePeriod,             0,                MAX_TIME);
        interestRate            = bound(interestRate,            0,                MAX_RATE);
        lateFeeRate             = bound(lateFeeRate,             0,                MAX_RATE);
        lateInterestPremiumRate = bound(lateInterestPremiumRate, 0,                MAX_RATE);
        noticePeriod            = bound(noticePeriod,            0,                MAX_TIME);
        paymentInterval         = bound(paymentInterval,         1,                MAX_TIME);

        newPrincipalDecrease = bound(newPrincipalDecrease, 0, principal);

        setupLoan(
            principal,
            delegateServiceFeeRate,
            gracePeriod,
            interestRate,
            lateFeeRate,
            lateInterestPremiumRate,
            noticePeriod,
            paymentInterval
        );

        bytes[] memory calls = new bytes[](1);

        calls[0] = abi.encodeWithSignature("decreasePrincipal(uint256)", newPrincipalDecrease);

        loan.refinance(refinancer, calls);

        assertEq(loan.principal(),               principal - newPrincipalDecrease);
        assertEq(loan.delegateServiceFeeRate(),  delegateServiceFeeRate);
        assertEq(loan.gracePeriod(),             gracePeriod);
        assertEq(loan.interestRate(),            interestRate);
        assertEq(loan.lateFeeRate(),             lateFeeRate);
        assertEq(loan.lateInterestPremiumRate(), lateInterestPremiumRate);
        assertEq(loan.noticePeriod(),            noticePeriod);
        assertEq(loan.paymentInterval(),         paymentInterval);
    }

    function test_refinancer_increasePrincipal(
        uint256 principal,
        uint256 delegateServiceFeeRate,
        uint256 gracePeriod,
        uint256 interestRate,
        uint256 lateFeeRate,
        uint256 lateInterestPremiumRate,
        uint256 noticePeriod,
        uint256 paymentInterval,
        uint256 newPrincipalIncrease
    ) external {
        principal               = bound(principal,               MIN_TOKEN_AMOUNT, MAX_TOKEN_AMOUNT);
        delegateServiceFeeRate  = bound(delegateServiceFeeRate,  0,                MAX_RATE);
        gracePeriod             = bound(gracePeriod,             0,                MAX_TIME);
        interestRate            = bound(interestRate,            0,                MAX_RATE);
        lateFeeRate             = bound(lateFeeRate,             0,                MAX_RATE);
        lateInterestPremiumRate = bound(lateInterestPremiumRate, 0,                MAX_RATE);
        noticePeriod            = bound(noticePeriod,            0,                MAX_TIME);
        paymentInterval         = bound(paymentInterval,         1,                MAX_TIME);

        newPrincipalIncrease = bound(principal, 0, MAX_TOKEN_AMOUNT);

        setupLoan(
            principal,
            delegateServiceFeeRate,
            gracePeriod,
            interestRate,
            lateFeeRate,
            lateInterestPremiumRate,
            noticePeriod,
            paymentInterval
        );

        bytes[] memory calls = new bytes[](1);

        calls[0] = abi.encodeWithSignature("increasePrincipal(uint256)", newPrincipalIncrease);

        loan.refinance(refinancer, calls);

        assertEq(loan.principal(),               principal + newPrincipalIncrease);
        assertEq(loan.delegateServiceFeeRate(),  delegateServiceFeeRate);
        assertEq(loan.gracePeriod(),             gracePeriod);
        assertEq(loan.interestRate(),            interestRate);
        assertEq(loan.lateFeeRate(),             lateFeeRate);
        assertEq(loan.lateInterestPremiumRate(), lateInterestPremiumRate);
        assertEq(loan.noticePeriod(),            noticePeriod);
        assertEq(loan.paymentInterval(),         paymentInterval);
    }

    function test_refinancer_setDelegateServiceFeeRate(
        uint256 principal,
        uint256 delegateServiceFeeRate,
        uint256 gracePeriod,
        uint256 interestRate,
        uint256 lateFeeRate,
        uint256 lateInterestPremiumRate,
        uint256 noticePeriod,
        uint256 paymentInterval,
        uint256 newDelegateServiceFeeRate
    ) external {
        principal               = bound(principal,               MIN_TOKEN_AMOUNT, MAX_TOKEN_AMOUNT);
        delegateServiceFeeRate  = bound(delegateServiceFeeRate,  0,                MAX_RATE);
        gracePeriod             = bound(gracePeriod,             0,                MAX_TIME);
        interestRate            = bound(interestRate,            0,                MAX_RATE);
        lateFeeRate             = bound(lateFeeRate,             0,                MAX_RATE);
        lateInterestPremiumRate = bound(lateInterestPremiumRate, 0,                MAX_RATE);
        noticePeriod            = bound(noticePeriod,            0,                MAX_TIME);
        paymentInterval         = bound(paymentInterval,         1,                MAX_TIME);

        newDelegateServiceFeeRate = bound(newDelegateServiceFeeRate, 0, MAX_TIME);

        setupLoan(
            principal,
            delegateServiceFeeRate,
            gracePeriod,
            interestRate,
            lateFeeRate,
            lateInterestPremiumRate,
            noticePeriod,
            paymentInterval
        );

        bytes[] memory calls = new bytes[](1);

        calls[0] = abi.encodeWithSignature("setGracePeriod(uint32)", newDelegateServiceFeeRate);

        loan.refinance(refinancer, calls);

        assertEq(loan.principal(),               principal);
        assertEq(loan.gracePeriod(),             newDelegateServiceFeeRate);
        assertEq(loan.interestRate(),            interestRate);
        assertEq(loan.lateFeeRate(),             lateFeeRate);
        assertEq(loan.lateInterestPremiumRate(), lateInterestPremiumRate);
        assertEq(loan.noticePeriod(),            noticePeriod);
        assertEq(loan.paymentInterval(),         paymentInterval);
    }

    function test_refinancer_setGracePeriod(
        uint256 principal,
        uint256 delegateServiceFeeRate,
        uint256 gracePeriod,
        uint256 interestRate,
        uint256 lateFeeRate,
        uint256 lateInterestPremiumRate,
        uint256 noticePeriod,
        uint256 paymentInterval,
        uint256 newGracePeriod
    ) external {
        principal               = bound(principal,               MIN_TOKEN_AMOUNT, MAX_TOKEN_AMOUNT);
        delegateServiceFeeRate  = bound(delegateServiceFeeRate,  0,                MAX_RATE);
        gracePeriod             = bound(gracePeriod,             0,                MAX_TIME);
        interestRate            = bound(interestRate,            0,                MAX_RATE);
        lateFeeRate             = bound(lateFeeRate,             0,                MAX_RATE);
        lateInterestPremiumRate = bound(lateInterestPremiumRate, 0,                MAX_RATE);
        noticePeriod            = bound(noticePeriod,            0,                MAX_TIME);
        paymentInterval         = bound(paymentInterval,         1,                MAX_TIME);

        newGracePeriod = bound(newGracePeriod, 0, MAX_TIME);

        setupLoan(
            principal,
            delegateServiceFeeRate,
            gracePeriod,
            interestRate,
            lateFeeRate,
            lateInterestPremiumRate,
            noticePeriod,
            paymentInterval
        );

        bytes[] memory calls = new bytes[](1);

        calls[0] = abi.encodeWithSignature("setGracePeriod(uint32)", newGracePeriod);

        loan.refinance(refinancer, calls);

        assertEq(loan.principal(),               principal);
        assertEq(loan.gracePeriod(),             newGracePeriod);
        assertEq(loan.interestRate(),            interestRate);
        assertEq(loan.lateFeeRate(),             lateFeeRate);
        assertEq(loan.lateInterestPremiumRate(), lateInterestPremiumRate);
        assertEq(loan.noticePeriod(),            noticePeriod);
        assertEq(loan.paymentInterval(),         paymentInterval);
    }

    function test_refinancer_setInterestRate(
        uint256 principal,
        uint256 delegateServiceFeeRate,
        uint256 gracePeriod,
        uint256 interestRate,
        uint256 lateFeeRate,
        uint256 lateInterestPremiumRate,
        uint256 noticePeriod,
        uint256 paymentInterval,
        uint256 newInterestRate
    ) external {
        principal               = bound(principal,               MIN_TOKEN_AMOUNT, MAX_TOKEN_AMOUNT);
        delegateServiceFeeRate  = bound(delegateServiceFeeRate,  0,                MAX_RATE);
        gracePeriod             = bound(gracePeriod,             0,                MAX_TIME);
        interestRate            = bound(interestRate,            0,                MAX_RATE);
        lateFeeRate             = bound(lateFeeRate,             0,                MAX_RATE);
        lateInterestPremiumRate = bound(lateInterestPremiumRate, 0,                MAX_RATE);
        noticePeriod            = bound(noticePeriod,            0,                MAX_TIME);
        paymentInterval         = bound(paymentInterval,         1,                MAX_TIME);

        newInterestRate = bound(newInterestRate, 0, MAX_RATE);

        setupLoan(
            principal,
            delegateServiceFeeRate,
            gracePeriod,
            interestRate,
            lateFeeRate,
            lateInterestPremiumRate,
            noticePeriod,
            paymentInterval
        );

        bytes[] memory calls = new bytes[](1);

        calls[0] = abi.encodeWithSignature("setInterestRate(uint64)", newInterestRate);

        loan.refinance(refinancer, calls);

        assertEq(loan.principal(),               principal);
        assertEq(loan.delegateServiceFeeRate(),  delegateServiceFeeRate);
        assertEq(loan.gracePeriod(),             gracePeriod);
        assertEq(loan.interestRate(),            newInterestRate);
        assertEq(loan.lateFeeRate(),             lateFeeRate);
        assertEq(loan.lateInterestPremiumRate(), lateInterestPremiumRate);
        assertEq(loan.noticePeriod(),            noticePeriod);
        assertEq(loan.paymentInterval(),         paymentInterval);
    }

    function test_refinancer_setLateFeeRate(
        uint256 principal,
        uint256 delegateServiceFeeRate,
        uint256 gracePeriod,
        uint256 interestRate,
        uint256 lateFeeRate,
        uint256 lateInterestPremiumRate,
        uint256 noticePeriod,
        uint256 paymentInterval,
        uint256 newLateFeeRate
    ) external {
        principal               = bound(principal,               MIN_TOKEN_AMOUNT, MAX_TOKEN_AMOUNT);
        delegateServiceFeeRate  = bound(delegateServiceFeeRate,  0,                MAX_RATE);
        gracePeriod             = bound(gracePeriod,             0,                MAX_TIME);
        interestRate            = bound(interestRate,            0,                MAX_RATE);
        lateFeeRate             = bound(lateFeeRate,             0,                MAX_RATE);
        lateInterestPremiumRate = bound(lateInterestPremiumRate, 0,                MAX_RATE);
        noticePeriod            = bound(noticePeriod,            0,                MAX_TIME);
        paymentInterval         = bound(paymentInterval,         1,                MAX_TIME);

        newLateFeeRate = bound(newLateFeeRate, 0, MAX_RATE);

        setupLoan(
            principal,
            delegateServiceFeeRate,
            gracePeriod,
            interestRate,
            lateFeeRate,
            lateInterestPremiumRate,
            noticePeriod,
            paymentInterval
        );

        bytes[] memory calls = new bytes[](1);

        calls[0] = abi.encodeWithSignature("setLateFeeRate(uint64)", newLateFeeRate);

        loan.refinance(refinancer, calls);

        assertEq(loan.principal(),               principal);
        assertEq(loan.delegateServiceFeeRate(),  delegateServiceFeeRate);
        assertEq(loan.gracePeriod(),             gracePeriod);
        assertEq(loan.interestRate(),            interestRate);
        assertEq(loan.lateFeeRate(),             newLateFeeRate);
        assertEq(loan.lateInterestPremiumRate(), lateInterestPremiumRate);
        assertEq(loan.noticePeriod(),            noticePeriod);
        assertEq(loan.paymentInterval(),         paymentInterval);
    }

    function test_refinancer_setLateInterestPremiumRate(
        uint256 principal,
        uint256 delegateServiceFeeRate,
        uint256 gracePeriod,
        uint256 interestRate,
        uint256 lateFeeRate,
        uint256 lateInterestPremiumRate,
        uint256 noticePeriod,
        uint256 paymentInterval,
        uint256 newLateInterestPremiumRate
    ) external {
        principal               = bound(principal,               MIN_TOKEN_AMOUNT, MAX_TOKEN_AMOUNT);
        delegateServiceFeeRate  = bound(delegateServiceFeeRate,  0,                MAX_RATE);
        gracePeriod             = bound(gracePeriod,             0,                MAX_TIME);
        interestRate            = bound(interestRate,            0,                MAX_RATE);
        lateFeeRate             = bound(lateFeeRate,             0,                MAX_RATE);
        lateInterestPremiumRate = bound(lateInterestPremiumRate, 0,                MAX_RATE);
        noticePeriod            = bound(noticePeriod,            0,                MAX_TIME);
        paymentInterval         = bound(paymentInterval,         1,                MAX_TIME);

        newLateInterestPremiumRate = bound(newLateInterestPremiumRate, 0, MAX_RATE);

        setupLoan(
            principal,
            delegateServiceFeeRate,
            gracePeriod,
            interestRate,
            lateFeeRate,
            lateInterestPremiumRate,
            noticePeriod,
            paymentInterval
        );

        bytes[] memory calls = new bytes[](1);

        calls[0] = abi.encodeWithSignature("setLateInterestPremiumRate(uint64)", newLateInterestPremiumRate);

        loan.refinance(refinancer, calls);

        assertEq(loan.principal(),               principal);
        assertEq(loan.delegateServiceFeeRate(),  delegateServiceFeeRate);
        assertEq(loan.gracePeriod(),             gracePeriod);
        assertEq(loan.interestRate(),            interestRate);
        assertEq(loan.lateFeeRate(),             lateFeeRate);
        assertEq(loan.lateInterestPremiumRate(), newLateInterestPremiumRate);
        assertEq(loan.noticePeriod(),            noticePeriod);
        assertEq(loan.paymentInterval(),         paymentInterval);
    }

    function test_refinancer_setNoticePeriod(
        uint256 principal,
        uint256 delegateServiceFeeRate,
        uint256 gracePeriod,
        uint256 interestRate,
        uint256 lateFeeRate,
        uint256 lateInterestPremiumRate,
        uint256 noticePeriod,
        uint256 paymentInterval,
        uint256 newNoticePeriod
    ) external {
        principal               = bound(principal,               MIN_TOKEN_AMOUNT, MAX_TOKEN_AMOUNT);
        delegateServiceFeeRate  = bound(delegateServiceFeeRate,  0,                MAX_RATE);
        gracePeriod             = bound(gracePeriod,             0,                MAX_TIME);
        interestRate            = bound(interestRate,            0,                MAX_RATE);
        lateFeeRate             = bound(lateFeeRate,             0,                MAX_RATE);
        lateInterestPremiumRate = bound(lateInterestPremiumRate, 0,                MAX_RATE);
        noticePeriod            = bound(noticePeriod,            0,                MAX_TIME);
        paymentInterval         = bound(paymentInterval,         1,                MAX_TIME);

        newNoticePeriod = bound(newNoticePeriod, 0, MAX_TIME);

        setupLoan(
            principal,
            delegateServiceFeeRate,
            gracePeriod,
            interestRate,
            lateFeeRate,
            lateInterestPremiumRate,
            noticePeriod,
            paymentInterval
        );

        bytes[] memory calls = new bytes[](1);

        calls[0] = abi.encodeWithSignature("setNoticePeriod(uint32)", newNoticePeriod);

        loan.refinance(refinancer, calls);

        assertEq(loan.principal(),               principal);
        assertEq(loan.delegateServiceFeeRate(),  delegateServiceFeeRate);
        assertEq(loan.gracePeriod(),             gracePeriod);
        assertEq(loan.interestRate(),            interestRate);
        assertEq(loan.lateFeeRate(),             lateFeeRate);
        assertEq(loan.lateInterestPremiumRate(), lateInterestPremiumRate);
        assertEq(loan.noticePeriod(),            newNoticePeriod);
        assertEq(loan.paymentInterval(),         paymentInterval);
    }

    function test_refinancer_setPaymentInterval(
        uint256 principal,
        uint256 delegateServiceFeeRate,
        uint256 gracePeriod,
        uint256 interestRate,
        uint256 lateFeeRate,
        uint256 lateInterestPremiumRate,
        uint256 noticePeriod,
        uint256 paymentInterval,
        uint256 newPaymentInterval
    ) external {
        principal               = bound(principal,               MIN_TOKEN_AMOUNT, MAX_TOKEN_AMOUNT);
        delegateServiceFeeRate  = bound(delegateServiceFeeRate,  0,                MAX_RATE);
        gracePeriod             = bound(gracePeriod,             0,                MAX_TIME);
        interestRate            = bound(interestRate,            0,                MAX_RATE);
        lateFeeRate             = bound(lateFeeRate,             0,                MAX_RATE);
        lateInterestPremiumRate = bound(lateInterestPremiumRate, 0,                MAX_RATE);
        noticePeriod            = bound(noticePeriod,            0,                MAX_TIME);
        paymentInterval         = bound(paymentInterval,         1,                MAX_TIME);

        newPaymentInterval = bound(newPaymentInterval, 1, MAX_TIME);

        setupLoan(
            principal,
            delegateServiceFeeRate,
            gracePeriod,
            interestRate,
            lateFeeRate,
            lateInterestPremiumRate,
            noticePeriod,
            paymentInterval
        );

        bytes[] memory calls = new bytes[](1);

        calls[0] = abi.encodeWithSignature("setPaymentInterval(uint32)", newPaymentInterval);

        loan.refinance(refinancer, calls);

        assertEq(loan.principal(),               principal);
        assertEq(loan.delegateServiceFeeRate(),  delegateServiceFeeRate);
        assertEq(loan.gracePeriod(),             gracePeriod);
        assertEq(loan.interestRate(),            interestRate);
        assertEq(loan.lateFeeRate(),             lateFeeRate);
        assertEq(loan.lateInterestPremiumRate(), lateInterestPremiumRate);
        assertEq(loan.noticePeriod(),            noticePeriod);
        assertEq(loan.paymentInterval(),         newPaymentInterval);
    }

    function test_refinancer_multipleCalls_refinance(
        uint256 principal,
        uint256 delegateServiceFeeRate,
        uint256 gracePeriod,
        uint256 interestRate,
        uint256 lateFeeRate,
        uint256 lateInterestPremiumRate,
        uint256 noticePeriod,
        uint256 paymentInterval
    ) external {
        principal               = bound(principal,               MIN_TOKEN_AMOUNT, MAX_TOKEN_AMOUNT);
        delegateServiceFeeRate  = bound(delegateServiceFeeRate,  0,                MAX_RATE);
        gracePeriod             = bound(gracePeriod,             0,                MAX_TIME);
        interestRate            = bound(interestRate,            0,                MAX_RATE);
        lateFeeRate             = bound(lateFeeRate,             0,                MAX_RATE);
        lateInterestPremiumRate = bound(lateInterestPremiumRate, 0,                MAX_RATE);
        noticePeriod            = bound(noticePeriod,            0,                MAX_TIME);
        paymentInterval         = bound(paymentInterval,         1,                MAX_TIME);

        setupLoan(
            principal,
            delegateServiceFeeRate,
            gracePeriod,
            interestRate,
            lateFeeRate,
            lateInterestPremiumRate,
            noticePeriod,
            paymentInterval
        );

        bytes[] memory calls = new bytes[](9);

        // Note: Change just out of range of min/max values to ensure refinance is setting the values correctly.
        calls[0] = abi.encodeWithSignature("decreasePrincipal(uint256)",         MIN_TOKEN_AMOUNT - 1);
        calls[1] = abi.encodeWithSignature("increasePrincipal(uint256)",         MAX_TOKEN_AMOUNT + 1);
        calls[2] = abi.encodeWithSignature("setDelegateServiceFeeRate(uint64)",  MAX_TIME + 1);
        calls[3] = abi.encodeWithSignature("setGracePeriod(uint32)",             MAX_TIME + 1);
        calls[4] = abi.encodeWithSignature("setInterestRate(uint64)",            MAX_RATE + 1);
        calls[5] = abi.encodeWithSignature("setLateFeeRate(uint64)",             MAX_RATE + 1);
        calls[6] = abi.encodeWithSignature("setLateInterestPremiumRate(uint64)", MAX_RATE + 1);
        calls[7] = abi.encodeWithSignature("setNoticePeriod(uint32)",            MAX_TIME + 1);
        calls[8] = abi.encodeWithSignature("setPaymentInterval(uint32)",         MAX_TIME + 1);

        loan.refinance(refinancer, calls);

        uint256 newPrincipal = principal - (MIN_TOKEN_AMOUNT - 1) + (MAX_TOKEN_AMOUNT + 1);

        assertEq(loan.principal(),               newPrincipal);
        assertEq(loan.delegateServiceFeeRate(),  MAX_TIME + 1);
        assertEq(loan.gracePeriod(),             MAX_TIME + 1);
        assertEq(loan.interestRate(),            MAX_RATE + 1);
        assertEq(loan.lateFeeRate(),             MAX_RATE + 1);
        assertEq(loan.lateInterestPremiumRate(), MAX_RATE + 1);
        assertEq(loan.noticePeriod(),            MAX_TIME + 1);
        assertEq(loan.paymentInterval(),         MAX_TIME + 1);
    }

}
