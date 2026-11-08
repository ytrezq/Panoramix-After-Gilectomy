// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test } from "../modules/forge-std/src/Test.sol";

import { MapleLoanHarness }         from "./utils/Harnesses.sol";
import { MockFactory, MockGlobals } from "./utils/Mocks.sol";
import { Utils }                    from "./utils/Utils.sol";

contract RemoveImpairmentTests is Test, Utils {

    event ImpairmentRemoved(uint40 paymentDueDate, uint40 defaultDate);

    address lender = makeAddr("lender");

    MapleLoanHarness loan    = new MapleLoanHarness();
    MockFactory      factory = new MockFactory();
    MockGlobals      globals = new MockGlobals();

    function setUp() external {
        factory.__setGlobals(address(globals));

        loan.__setFactory(address(factory));
        loan.__setLender(lender);
    }

    function test_removeImpairment_paused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("ML:PAUSED");
        loan.removeImpairment();
    }

    function test_removeImpairment_notLender() external {
        vm.expectRevert("ML:NOT_LENDER");
        loan.removeImpairment();
    }

    function test_removeImpairment_notImpaired() external {
        vm.expectRevert("ML:RI:NOT_IMPAIRED");
        vm.prank(lender);
        loan.removeImpairment();
    }

    function testFuzz_removeImpairment_success(
        uint256 gracePeriod,
        uint256 noticePeriod,
        uint256 paymentInterval,
        uint256 dateCalled,
        uint256 dateFunded,
        uint256 datePaid
    ) external {
        uint256 dateImpaired = block.timestamp - 1 days;

        gracePeriod     = bound(gracePeriod,     0, 365 days);
        noticePeriod    = bound(noticePeriod,    0, 365 days);
        paymentInterval = bound(paymentInterval, 0, 365 days);

        dateFunded = dateImpaired - bound(dateFunded, 1 days, 365 days);  // `dateFunded` is 1 to 365 days before impairment.

        // `datePaid` is between `dateFunded` and `dateImpaired`, if at all, since it only possible that `dateImpaired > `datePaid`.
        datePaid = boundWithEqualChanceOfZero(datePaid, dateFunded, dateImpaired);

        // `dateCalled` is between `datePaid` and `dateImpaired`, if at all, since it only possible that `dateCalled > `datePaid`.
        dateCalled = boundWithEqualChanceOfZero(dateCalled, datePaid, dateImpaired);

        loan.__setGracePeriod(gracePeriod);
        loan.__setDateCalled(dateCalled);
        loan.__setDateFunded(dateFunded);
        loan.__setDateImpaired(dateImpaired);
        loan.__setDatePaid(datePaid);
        loan.__setNoticePeriod(noticePeriod);
        loan.__setPaymentInterval(paymentInterval);

        uint256 callDate   = loan.__getCallDueDate(dateCalled, noticePeriod);
        uint256 normalDate = loan.__getNormalDueDate(dateFunded, datePaid, paymentInterval);

        uint256 expectedPaymentDueDate = minIgnoreZero(callDate, normalDate);

        // Reuse dates as default dates to avoid STACK_TOO_DEEP.
        callDate   = loan.__getCallDefaultDate(callDate);
        normalDate = loan.__getNormalDefaultDate(normalDate, gracePeriod);

        uint256 expectedDefaultDate = minIgnoreZero(callDate, normalDate);

        vm.expectEmit();
        emit ImpairmentRemoved(uint40(expectedPaymentDueDate), uint40(expectedDefaultDate));

        vm.prank(lender);
        ( uint40 paymentDueDate, uint40 defaultDate ) = loan.removeImpairment();

        assertEq(loan.dateImpaired(), 0);
        assertEq(paymentDueDate,      uint40(expectedPaymentDueDate));
        assertEq(defaultDate,         uint40(expectedDefaultDate));
    }

}
