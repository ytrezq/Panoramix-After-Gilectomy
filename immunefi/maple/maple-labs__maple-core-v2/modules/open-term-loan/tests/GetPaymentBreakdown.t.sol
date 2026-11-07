// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test } from "../modules/forge-std/src/Test.sol";

import { MapleLoanHarness } from "./utils/Harnesses.sol";
import { Utils }            from "./utils/Utils.sol";

contract GetPaymentBreakdownTests is Test, Utils {

    uint256 constant HUNDRED_PERCENT = 1e6;

    // NOTE: Moved variables here to avoid 'Stack too deep'

    uint256 interest;
    uint256 lateInterest;
    uint256 delegateServiceFee;
    uint256 platformServiceFee;

    uint256 expectedInterest;
    uint256 expectedLateInterest;
    uint256 expectedDelegateServiceFee;
    uint256 expectedPlatformServiceFee;

    MapleLoanHarness loan = new MapleLoanHarness();

    function testFuzz_getPaymentBreakdown(
        uint256 paymentInterval,
        uint256 dateFunded,
        uint256 principal,
        uint256 interestRate,
        uint256 lateFeeRate,
        uint256 lateInterestPremiumRate,
        uint256 delegateServiceFeeRate,
        uint256 platformServiceFeeRate
    ) external {
        paymentInterval         = bound(paymentInterval,         1 days,                     365 days);
        dateFunded              = bound(dateFunded,              block.timestamp - 365 days, block.timestamp);
        principal               = bound(principal,               1e6,                        1e30);
        interestRate            = bound(interestRate,            0,                          1.00e6);
        lateFeeRate             = bound(lateFeeRate,             0,                          0.10e6);
        lateInterestPremiumRate = bound(lateInterestPremiumRate, 0,                          0.50e6);
        delegateServiceFeeRate  = bound(delegateServiceFeeRate,  0,                          1.00e6);
        platformServiceFeeRate  = bound(platformServiceFeeRate,  0,                          1.00e6);

        loan.__setDateFunded(dateFunded);
        loan.__setLateFeeRate(uint64(lateFeeRate));
        loan.__setLateInterestPremiumRate(uint64(lateInterestPremiumRate));
        loan.__setPaymentInterval(paymentInterval);
        loan.__setPrincipal(principal);
        loan.__setInterestRate(uint64(interestRate));
        loan.__setDelegateServiceFeeRate(uint64(delegateServiceFeeRate));
        loan.__setPlatformServiceFeeRate(uint64(platformServiceFeeRate));

        ( , interest, lateInterest, delegateServiceFee, platformServiceFee ) = loan.getPaymentBreakdown(block.timestamp);

        uint256 paymentDueDate = dateFunded + paymentInterval;

        ( uint256 currentInterval, uint256 lateInterval ) =
            ( block.timestamp - dateFunded, block.timestamp > paymentDueDate ? block.timestamp - paymentDueDate : 0);

        expectedInterest     = (principal * interestRate * currentInterval) / (365 days * HUNDRED_PERCENT);
        expectedLateInterest = lateInterval != 0
            ?
                (
                    ((principal * lateInterestPremiumRate * lateInterval) / 365 days) + (principal * lateFeeRate)
                ) / HUNDRED_PERCENT
            : 0;

        expectedDelegateServiceFee = (principal * delegateServiceFeeRate * currentInterval) / (365 days * HUNDRED_PERCENT);
        expectedPlatformServiceFee = (principal * platformServiceFeeRate * currentInterval) / (365 days * HUNDRED_PERCENT);

        assertEq(interest, expectedInterest);

        // Off-by-one due to reworked formula above. Better this than to use the exact same formula, which defeats the test's purpose.
        assertApproxEqAbs(lateInterest, expectedLateInterest, 1);
        assertEq(delegateServiceFee, expectedDelegateServiceFee);
        assertEq(platformServiceFee, expectedPlatformServiceFee);
    }

    // Full year payment interval at 10%
    function test_getPaymentBreakdown_fixture1() external {
        uint256 paymentInterval        = 365 days;
        uint256 dateFunded             = block.timestamp;
        uint256 principal              = 1_000_000e6;
        uint256 interestRate           = 0.10e6;
        uint256 delegateServiceFeeRate = 0.01e6;
        uint256 platformServiceFeeRate = 0.025e6;

        loan.__setDateFunded(dateFunded);
        loan.__setPaymentInterval(paymentInterval);
        loan.__setPrincipal(principal);
        loan.__setInterestRate(interestRate);
        loan.__setDelegateServiceFeeRate(delegateServiceFeeRate);
        loan.__setPlatformServiceFeeRate(platformServiceFeeRate);

        // 3/4 of the payment interval
        ( , interest, lateInterest, delegateServiceFee, platformServiceFee ) = loan.getPaymentBreakdown(block.timestamp + (paymentInterval * 3 / 4));

        assertEq(interest,           75_000e6);
        assertEq(lateInterest,       0);
        assertEq(delegateServiceFee, 7_500e6);
        assertEq(platformServiceFee, 18_750e6);

        // At the payment interval
        ( , interest, lateInterest, delegateServiceFee, platformServiceFee ) = loan.getPaymentBreakdown(block.timestamp + paymentInterval);

        assertEq(interest,           100_000e6);
        assertEq(lateInterest,       0);
        assertEq(delegateServiceFee, 10_000e6);
        assertEq(platformServiceFee, 25_000e6);

        // 1/5 of the payment interval late
        ( , interest, lateInterest, delegateServiceFee, platformServiceFee ) = loan.getPaymentBreakdown(block.timestamp + (paymentInterval * 6 / 5));

        assertEq(interest,           120_000e6);
        assertEq(lateInterest,       0);          // No late interest in this fixture.
        assertEq(delegateServiceFee, 12_000e6);
        assertEq(platformServiceFee, 30_000e6);
    }

    // 30 day payment interval at 10%
    function test_getPaymentBreakdown_fixture2() external {
        uint256 paymentInterval        = 30 days;
        uint256 dateFunded             = block.timestamp;
        uint256 principal              = 1_000_000e6;
        uint256 interestRate           = 0.10e6;
        uint256 delegateServiceFeeRate = 0.01e6;
        uint256 platformServiceFeeRate = 0.025e6;

        loan.__setDateFunded(dateFunded);
        loan.__setPaymentInterval(paymentInterval);
        loan.__setPrincipal(principal);
        loan.__setInterestRate(interestRate);
        loan.__setDelegateServiceFeeRate(delegateServiceFeeRate);
        loan.__setPlatformServiceFeeRate(platformServiceFeeRate);

        // Half way into the interval
         ( , interest, lateInterest, delegateServiceFee, platformServiceFee ) = loan.getPaymentBreakdown(block.timestamp + paymentInterval / 2);

        assertEq(interest,           4_109.589041e6);
        assertEq(lateInterest,       0);
        assertEq(delegateServiceFee, 410.958904e6);
        assertEq(platformServiceFee, 1_027.397260e6);

        ( , interest, lateInterest, delegateServiceFee, platformServiceFee ) = loan.getPaymentBreakdown(block.timestamp + paymentInterval);

        assertEq(interest,           8_219.178082e6);
        assertEq(lateInterest,       0);
        assertEq(delegateServiceFee, 821.917808e6);
        assertEq(platformServiceFee, 2_054.794520e6);

        // Half way late into the next interval
        ( , interest, lateInterest, delegateServiceFee, platformServiceFee ) = loan.getPaymentBreakdown(block.timestamp + paymentInterval + paymentInterval / 2);

        assertEq(interest,           12_328.767123e6);
        assertEq(lateInterest,       0);
        assertEq(delegateServiceFee, 1_232.876712e6);
        assertEq(platformServiceFee, 3_082.191780e6);
    }

    // Full year at 10% interest, 0.1 years early at 10% interest (full year for easy validation)
    function test_getPaymentBreakdown_fixture3() external {
        uint256 paymentInterval        = 365 days;
        uint256 dateFunded             = block.timestamp - 365 days + (365 days / 10);
        uint256 principal              = 1_000_000e6;
        uint256 interestRate           = 0.10e6;
        uint256 delegateServiceFeeRate = 0.01e6;
        uint256 platformServiceFeeRate = 0.025e6;

        loan.__setDateFunded(dateFunded);
        loan.__setPaymentInterval(paymentInterval);
        loan.__setPrincipal(principal);
        loan.__setInterestRate(interestRate);
        loan.__setDelegateServiceFeeRate(delegateServiceFeeRate);
        loan.__setPlatformServiceFeeRate(platformServiceFeeRate);

        ( , interest, lateInterest, delegateServiceFee, platformServiceFee ) = loan.getPaymentBreakdown(block.timestamp);

        assertEq(interest,           90_000e6);
        assertEq(lateInterest,       0);
        assertEq(delegateServiceFee, 9_000e6);
        assertEq(platformServiceFee, 22_500e6);
    }

    // Full year at 10% interest, 0.1 years late at (10% + 5%) interest (full year for easy validation)
    function test_getPaymentBreakdown_fixture4() external {
        uint256 paymentInterval         = 365 days;
        uint256 dateFunded              = block.timestamp;
        uint256 principal               = 1_000_000e6;
        uint256 interestRate            = 0.10e6;
        uint256 lateInterestPremiumRate = 0.05e6;
        uint256 delegateServiceFeeRate  = 0.01e6;
        uint256 platformServiceFeeRate  = 0.025e6;

        loan.__setDateFunded(dateFunded);
        loan.__setLateInterestPremiumRate(lateInterestPremiumRate);
        loan.__setPaymentInterval(paymentInterval);
        loan.__setPrincipal(principal);
        loan.__setInterestRate(interestRate);
        loan.__setDelegateServiceFeeRate(delegateServiceFeeRate);
        loan.__setPlatformServiceFeeRate(platformServiceFeeRate);

        // 0.01 years
        ( , interest, lateInterest, delegateServiceFee, platformServiceFee ) = loan.getPaymentBreakdown(block.timestamp + 365 days - (365 days / 100));

        assertEq(interest,           99_000e6);
        assertEq(lateInterest,       0);
        assertEq(delegateServiceFee, 99_00e6);
        assertEq(platformServiceFee, 24_750e6);

        ( , interest, lateInterest, delegateServiceFee, platformServiceFee ) = loan.getPaymentBreakdown(block.timestamp + 365 days + (365 days / 10));

        assertEq(interest,           110_000e6);  // 1.1 year at 10% interest
        assertEq(lateInterest,       5_000e6);    // 0.1 years at (5%) interest (5_000e6)
        assertEq(delegateServiceFee, 11_000e6);
        assertEq(platformServiceFee, 27_500e6);
    }

    // Half year at 10% interest, 0.1 years late at 10% interest + 0.9% flat fee on principal
    function test_getPaymentBreakdown_fixture5() external {
        uint256 paymentInterval        = 365 days / 2;
        uint256 dateFunded             = block.timestamp - (365 days / 2) - (365 days / 10);
        uint256 principal              = 1_000_000e6;
        uint256 interestRate           = 0.10e6;
        uint256 lateFeeRate            = 0.009e6;
        uint256 delegateServiceFeeRate = 0.01e6;
        uint256 platformServiceFeeRate = 0.025e6;

        loan.__setDateFunded(dateFunded);
        loan.__setLateFeeRate(lateFeeRate);
        loan.__setPaymentInterval(paymentInterval);
        loan.__setPrincipal(principal);
        loan.__setInterestRate(interestRate);
        loan.__setDelegateServiceFeeRate(delegateServiceFeeRate);
        loan.__setPlatformServiceFeeRate(platformServiceFeeRate);

        ( , interest, lateInterest, delegateServiceFee, platformServiceFee ) = loan.getPaymentBreakdown(block.timestamp);

        assertEq(interest,           60_000e6);  // 0.6 years at 10% interest
        assertEq(lateInterest,       9_000e6);   // 0.1 years at 10% interest (10_000e6) + 0.9% of flat fee (9_000e6)
        assertEq(delegateServiceFee, 6_000e6);
        assertEq(platformServiceFee, 15_000e6);
    }

    // Half year at 10% interest, 0.1 years late at (10% + 5%) interest + 0.9% flat fee on principal
    function test_getPaymentBreakdown_fixture6() external {
        uint256 paymentInterval         = 365 days / 2;
        uint256 dateFunded              = block.timestamp - (365 days / 2) - (365 days / 10);
        uint256 principal               = 1_000_000e6;
        uint256 interestRate            = 0.10e6;
        uint256 lateFeeRate             = 0.009e6;
        uint256 lateInterestPremiumRate = 0.05e6;
        uint256 delegateServiceFeeRate  = 0.01e6;
        uint256 platformServiceFeeRate  = 0.025e6;

        loan.__setDateFunded(dateFunded);
        loan.__setLateFeeRate(lateFeeRate);
        loan.__setLateInterestPremiumRate(lateInterestPremiumRate);
        loan.__setPaymentInterval(paymentInterval);
        loan.__setPrincipal(principal);
        loan.__setInterestRate(interestRate);
        loan.__setDelegateServiceFeeRate(delegateServiceFeeRate);
        loan.__setPlatformServiceFeeRate(platformServiceFeeRate);

        ( , interest, lateInterest, delegateServiceFee, platformServiceFee ) = loan.getPaymentBreakdown(block.timestamp);

        assertEq(interest,           60_000e6);  // 0.6 years at 10% interest
        assertEq(lateInterest,       14_000e6);  // 0.1 years at (5%) interest (5_000e6) + 0.9% of flat fee (9_000e6)
        assertEq(delegateServiceFee, 6_000e6);
        assertEq(platformServiceFee, 15_000e6);
    }

    // Half year at 8% interest, 0.25 years late at (10% + 5%) interest + 0.9% flat fee on principal + 1.5%/2.5% service fee rates.
    function test_getPaymentBreakdown_fixture7() external {
        uint256 paymentInterval         = 365 days / 2;
        uint256 dateFunded              = block.timestamp - paymentInterval * 3 / 2;
        uint256 principal               = 1_000_000e6;
        uint256 interestRate            = 0.08e6;
        uint256 lateFeeRate             = 0.009e6;
        uint256 lateInterestPremiumRate = 0.05e6;
        uint256 delegateServiceFeeRate  = 0.015e6;
        uint256 platformServiceFeeRate  = 0.025e6;

        loan.__setDateFunded(dateFunded);
        loan.__setLateFeeRate(lateFeeRate);
        loan.__setLateInterestPremiumRate(lateInterestPremiumRate);
        loan.__setPaymentInterval(paymentInterval);
        loan.__setPrincipal(principal);
        loan.__setInterestRate(interestRate);
        loan.__setDelegateServiceFeeRate(delegateServiceFeeRate);
        loan.__setPlatformServiceFeeRate(platformServiceFeeRate);

        ( , interest, lateInterest, delegateServiceFee, platformServiceFee ) = loan.getPaymentBreakdown(block.timestamp);

        assertEq(interest,           60_000e6);  // 1,000,000 * 8% * 3/4
        assertEq(lateInterest,       21_500e6);  // 1,000,000 * 5% * 1/4 + 1,000,000 * 0.9%
        assertEq(delegateServiceFee, 11_250e6);  // 1,000,000 * 1.5% * 3/4
        assertEq(platformServiceFee, 18_750e6);  // 1,000,000 * 2.5% * 3/4
    }

    // Same as fixture 7, but with a future date being passed as argument.
    function test_getPaymentBreakdown_fixture8() external {
        uint256 paymentInterval         = 365 days / 2;
        uint256 dateFunded              = block.timestamp;
        uint256 principal               = 1_000_000e6;
        uint256 interestRate            = 0.08e6;
        uint256 lateFeeRate             = 0.009e6;
        uint256 lateInterestPremiumRate = 0.05e6;
        uint256 delegateServiceFeeRate  = 0.015e6;
        uint256 platformServiceFeeRate  = 0.025e6;

        loan.__setDateFunded(dateFunded);
        loan.__setLateFeeRate(lateFeeRate);
        loan.__setLateInterestPremiumRate(lateInterestPremiumRate);
        loan.__setPaymentInterval(paymentInterval);
        loan.__setPrincipal(principal);
        loan.__setInterestRate(interestRate);
        loan.__setDelegateServiceFeeRate(delegateServiceFeeRate);
        loan.__setPlatformServiceFeeRate(platformServiceFeeRate);

        ( , interest, lateInterest, delegateServiceFee, platformServiceFee ) = loan.getPaymentBreakdown(block.timestamp + paymentInterval * 3 / 2);

        assertEq(interest,           60_000e6);  // 1,000,000 * 8% * 3/4
        assertEq(lateInterest,       21_500e6);  // 1,000,000 * 5% * 1/4 + 1,000,000 * 0.9%
        assertEq(delegateServiceFee, 11_250e6);  // 1,000,000 * 1.5% * 3/4
        assertEq(platformServiceFee, 18_750e6);  // 1,000,000 * 2.5% * 3/4
    }

    // The loan has not been funded yet (`dateFunded` is zero) so all zeros are returned.
    function test_getPaymentBreakdown_fixture9() external {
        uint256 paymentInterval         = 30 days;
        uint256 dateFunded              = 0;
        uint256 principal               = 1_000_000e6;
        uint256 interestRate            = 0.08e6;
        uint256 lateFeeRate             = 0.009e6;
        uint256 lateInterestPremiumRate = 0.05e6;
        uint256 delegateServiceFeeRate  = 0.015e6;
        uint256 platformServiceFeeRate  = 0.025e6;

        loan.__setDateFunded(dateFunded);
        loan.__setLateFeeRate(lateFeeRate);
        loan.__setLateInterestPremiumRate(lateInterestPremiumRate);
        loan.__setPaymentInterval(paymentInterval);
        loan.__setPrincipal(principal);
        loan.__setInterestRate(interestRate);
        loan.__setDelegateServiceFeeRate(delegateServiceFeeRate);
        loan.__setPlatformServiceFeeRate(platformServiceFeeRate);

        ( principal, interest, lateInterest, delegateServiceFee, platformServiceFee ) = loan.getPaymentBreakdown(block.timestamp);

        assertEq(principal,          0);
        assertEq(interest,           0);
        assertEq(lateInterest,       0);
        assertEq(delegateServiceFee, 0);
        assertEq(platformServiceFee, 0);
    }

    // The loan has been funded but the given timestamp is not greater than the funding date so all zeros are returned.
    function test_getPaymentBreakdown_fixture10() external {
        uint256 paymentInterval         = 30 days;
        uint256 dateFunded              = block.timestamp;
        uint256 principal               = 1_000_000e6;
        uint256 interestRate            = 0.08e6;
        uint256 lateFeeRate             = 0.009e6;
        uint256 lateInterestPremiumRate = 0.05e6;
        uint256 delegateServiceFeeRate  = 0.015e6;
        uint256 platformServiceFeeRate  = 0.025e6;

        loan.__setDateFunded(dateFunded);
        loan.__setLateFeeRate(lateFeeRate);
        loan.__setLateInterestPremiumRate(lateInterestPremiumRate);
        loan.__setPaymentInterval(paymentInterval);
        loan.__setPrincipal(principal);
        loan.__setInterestRate(interestRate);
        loan.__setDelegateServiceFeeRate(delegateServiceFeeRate);
        loan.__setPlatformServiceFeeRate(platformServiceFeeRate);

        ( principal, interest, lateInterest, delegateServiceFee, platformServiceFee ) = loan.getPaymentBreakdown(block.timestamp - 1 seconds);

        assertEq(principal,          0);
        assertEq(interest,           0);
        assertEq(lateInterest,       0);
        assertEq(delegateServiceFee, 0);
        assertEq(platformServiceFee, 0);
    }

}
