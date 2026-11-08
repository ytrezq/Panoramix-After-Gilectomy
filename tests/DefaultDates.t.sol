// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test } from "../modules/forge-std/src/Test.sol";

import { MapleLoanHarness } from "./utils/Harnesses.sol";
import { Utils }            from "./utils/Utils.sol";

contract DefaultDatesTests is Test, Utils {

    MapleLoanHarness loan = new MapleLoanHarness();

    function getConstrictedParameters(
        uint256 gracePeriod,
        uint256 noticePeriod,
        uint256 paymentInterval,
        uint256 dateFunded,
        uint256 dateCalled,
        uint256 dateImpaired,
        uint256 datePaid
    )
        internal view
        returns (
            uint256 constrictedGracePeriod,
            uint256 constrictedNoticePeriod,
            uint256 constrictedPaymentInterval,
            uint256 constrictedDateFunded,
            uint256 constrictedDateCalled,
            uint256 constrictedDateImpaired,
            uint256 constrictedDatePaid
        )
    {
        // Constrict and set relevant periods to reasonable values.
        gracePeriod     = bound(gracePeriod,     0, 365 days);
        noticePeriod    = bound(noticePeriod,    0, 365 days);
        paymentInterval = bound(paymentInterval, 0, 365 days);

        dateFunded = bound(dateFunded, block.timestamp - 365 days, block.timestamp);  // Any time in last 365 days.

        // Constrict and set dates to any time between `dateFunded` and 365 days later, if at all.
        // NOTE: Only possible that `dateCalled > `datePaid` and `dateImpaired > `datePaid`.
        datePaid     = boundWithEqualChanceOfZero(datePaid,     dateFunded, dateFunded + 365 days);
        dateCalled   = boundWithEqualChanceOfZero(dateCalled,   datePaid,   dateFunded + 365 days);
        dateImpaired = boundWithEqualChanceOfZero(dateImpaired, datePaid,   dateFunded + 365 days);

        // Doing these sets here makes the above read better.
        constrictedGracePeriod     = gracePeriod;
        constrictedNoticePeriod    = noticePeriod;
        constrictedPaymentInterval = paymentInterval;
        constrictedDateFunded      = dateFunded;
        constrictedDateCalled      = dateCalled;
        constrictedDateImpaired    = dateImpaired;
        constrictedDatePaid        = datePaid;
    }

    function testFuzz_defaultDates(
        uint256 gracePeriod,
        uint256 noticePeriod,
        uint256 paymentInterval,
        uint256 dateFunded,
        uint256 dateCalled,
        uint256 dateImpaired,
        uint256 datePaid
    ) external {
        (
            gracePeriod,
            noticePeriod,
            paymentInterval,
            dateFunded,
            dateCalled,
            dateImpaired,
            datePaid
        ) = getConstrictedParameters(gracePeriod, noticePeriod, paymentInterval, dateFunded, dateCalled, dateImpaired, datePaid);

        loan.__setDateFunded(dateFunded);
        loan.__setDateCalled(dateCalled);
        loan.__setDateImpaired(dateImpaired);
        loan.__setDatePaid(datePaid);
        loan.__setGracePeriod(gracePeriod);
        loan.__setNoticePeriod(noticePeriod);
        loan.__setPaymentInterval(paymentInterval);

        ( uint256 callDefaultDate, uint256 impairedDefaultDate, uint256 normalDefaultDate ) = loan.__defaultDates();

        uint256 dateFundedOrPaid = maxIgnoreZero(dateFunded, datePaid);

        assertEq(callDefaultDate,     callDefaultDate == 0     ? 0 : dateCalled + noticePeriod);
        assertEq(impairedDefaultDate, impairedDefaultDate == 0 ? 0 : dateImpaired + gracePeriod);
        assertEq(normalDefaultDate,   dateFundedOrPaid == 0    ? 0 : dateFundedOrPaid + paymentInterval + gracePeriod);

        assertEq(loan.defaultDate(), minIgnoreZero(callDefaultDate, impairedDefaultDate, normalDefaultDate));  // TODO: loan.__minDate
    }

    // TODO: test_defaultDates_dateFunded

    // TODO: test_defaultDates_dateFundedAndDatePaid

    // TODO: test_defaultDates_dateFundedAndDateCalled

    // TODO: test_defaultDates_dateFundedAndDateImpaired

    // TODO: test_defaultDates_dateFundedAndDateCalledThenDateImpaired

    // TODO: test_defaultDates_dateFundedAndDateImpairedThenDateCalled

}
