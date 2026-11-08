// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test } from "../modules/forge-std/src/Test.sol";

import { MapleLoanHarness } from "./utils/Harnesses.sol";
import { Utils }            from "./utils/Utils.sol";

contract DueDatesTests is Test, Utils {

    MapleLoanHarness loan = new MapleLoanHarness();

    function getConstrictedParameters(
        uint256 noticePeriod,
        uint256 paymentInterval,
        uint256 dateFunded,
        uint256 dateCalled,
        uint256 dateImpaired,
        uint256 datePaid
    )
        internal view
        returns (
            uint256 constrictedNoticePeriod,
            uint256 constrictedPaymentInterval,
            uint256 constrictedDateFunded,
            uint256 constrictedDateCalled,
            uint256 constrictedDateImpaired,
            uint256 constrictedDatePaid
        )
    {
        // Constrict and set relevant periods to reasonable values.
        noticePeriod    = bound(noticePeriod,    0, 365 days);
        paymentInterval = bound(paymentInterval, 0, 365 days);

        dateFunded = bound(dateFunded, block.timestamp - 365 days, block.timestamp);  // Any time in last 365 days.

        // Constrict and set dates to any time between `dateFunded` and 365 days later, if at all.
        // NOTE: Only possible that `dateCalled > `datePaid` and `dateImpaired > `datePaid`.
        datePaid     = boundWithEqualChanceOfZero(datePaid,     dateFunded, dateFunded + 365 days);
        dateCalled   = boundWithEqualChanceOfZero(dateCalled,   datePaid,   dateFunded + 365 days);
        dateImpaired = boundWithEqualChanceOfZero(dateImpaired, datePaid,   dateFunded + 365 days);

        // Doing these sets here makes the above read better.
        constrictedNoticePeriod    = noticePeriod;
        constrictedPaymentInterval = paymentInterval;
        constrictedDateFunded      = dateFunded;
        constrictedDateCalled      = dateCalled;
        constrictedDateImpaired    = dateImpaired;
        constrictedDatePaid        = datePaid;
    }

    function testFuzz_dueDates(
        uint256 noticePeriod,
        uint256 paymentInterval,
        uint256 dateFunded,
        uint256 dateCalled,
        uint256 dateImpaired,
        uint256 datePaid
    ) external {
        (
            noticePeriod,
            paymentInterval,
            dateFunded,
            dateCalled,
            dateImpaired,
            datePaid
        ) = getConstrictedParameters(noticePeriod, paymentInterval, dateFunded, dateCalled, dateImpaired, datePaid);

        loan.__setDateFunded(dateFunded);
        loan.__setDateCalled(dateCalled);
        loan.__setDateImpaired(dateImpaired);
        loan.__setDatePaid(datePaid);
        loan.__setGracePeriod(365 days);             // Set this to ensure gracePeriod is not taken into account in the contract.
        loan.__setNoticePeriod(noticePeriod);
        loan.__setPaymentInterval(paymentInterval);

        ( uint256 callDueDate, uint256 impairedDueDate, uint256 normalDueDate ) = loan.__dueDates();

        uint256 dateFundedOrPaid = maxIgnoreZero(dateFunded, datePaid);

        assertEq(callDueDate,     callDueDate == 0      ? 0 : dateCalled + noticePeriod);
        assertEq(impairedDueDate, impairedDueDate == 0  ? 0 : dateImpaired);
        assertEq(normalDueDate,   dateFundedOrPaid == 0 ? 0 : dateFundedOrPaid + paymentInterval);

        assertEq(loan.paymentDueDate(), minIgnoreZero(callDueDate, impairedDueDate, normalDueDate));  // TODO: loan.__minDate
    }

    // TODO: test_dueDates_dateFunded

    // TODO: test_dueDates_dateFundedAndDatePaid

    // TODO: test_dueDates_dateFundedAndDateCalled

    // TODO: test_dueDates_dateFundedAndDateImpaired

    // TODO: test_dueDates_dateFundedAndDateCalledThenDateImpaired

    // TODO: test_dueDates_dateFundedAndDateImpairedThenDateCalled

}
