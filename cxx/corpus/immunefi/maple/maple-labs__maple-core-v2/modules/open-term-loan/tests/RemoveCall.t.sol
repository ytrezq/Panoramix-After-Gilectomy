// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test } from "../modules/forge-std/src/Test.sol";

import { MapleLoanHarness }         from "./utils/Harnesses.sol";
import { MockFactory, MockGlobals } from "./utils/Mocks.sol";
import { Utils }                    from "./utils/Utils.sol";

contract RemoveCallTests is Test, Utils {

    event CallRemoved(uint40 paymentDueDate, uint40 defaultDate);

    address lender = makeAddr("lender");

    MapleLoanHarness loan    = new MapleLoanHarness();
    MockFactory      factory = new MockFactory();
    MockGlobals      globals = new MockGlobals();

    function setUp() external {
        factory.__setGlobals(address(globals));

        loan.__setFactory(address(factory));
        loan.__setLender(lender);
    }

    function test_removeCall_paused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("ML:PAUSED");
        loan.removeCall();
    }

    function test_removeCall_notLender() external {
        vm.expectRevert("ML:NOT_LENDER");
        loan.removeCall();
    }

    function test_removeCall_notCalled() external {
        vm.expectRevert("ML:RC:NOT_CALLED");
        vm.prank(lender);
        loan.removeCall();
    }

    function testFuzz_removeCall_success(
        uint256 gracePeriod,
        uint256 noticePeriod,
        uint256 paymentInterval,
        uint256 dateFunded,
        uint256 dateImpaired,
        uint256 datePaid
    ) external {
        uint256 dateCalled = block.timestamp - 1 days;

        gracePeriod     = bound(gracePeriod,     0, 365 days);
        noticePeriod    = bound(noticePeriod,    0, 365 days);
        paymentInterval = bound(paymentInterval, 0, 365 days);

        dateFunded = dateCalled - bound(dateFunded, 1 days, 365 days);  // `dateFunded` is 1 to 365 days ago.

        // `datePaid` is between `dateFunded` and `dateCalled`, if at all, since it only possible that `dateCalled > `datePaid`.
        datePaid = boundWithEqualChanceOfZero(datePaid, dateFunded, dateCalled);

        // `dateImpaired` is between `datePaid` and `dateCalled`, if at all, since it only possible that `dateImpaired > `datePaid`.
        dateImpaired = boundWithEqualChanceOfZero(dateImpaired, datePaid, dateCalled);

        loan.__setCalledPrincipal(1);
        loan.__setGracePeriod(gracePeriod);
        loan.__setDateCalled(dateCalled);
        loan.__setDateFunded(dateFunded);
        loan.__setDateImpaired(dateImpaired);
        loan.__setDatePaid(datePaid);
        loan.__setNoticePeriod(noticePeriod);
        loan.__setPaymentInterval(paymentInterval);

        uint256 impairedDate = loan.__getImpairedDueDate(dateImpaired);
        uint256 normalDate   = loan.__getNormalDueDate(dateFunded, datePaid, paymentInterval);

        uint256 expectedPaymentDueDate = minIgnoreZero(impairedDate, normalDate);

        // Reuse dates as default dates to avoid STACK_TOO_DEEP.
        impairedDate = loan.__getImpairedDefaultDate(impairedDate, gracePeriod);
        normalDate   = loan.__getNormalDefaultDate(normalDate, gracePeriod);

        uint256 expectedDefaultDate = minIgnoreZero(impairedDate, normalDate);

        vm.expectEmit();
        emit CallRemoved(uint40(expectedPaymentDueDate), uint40(expectedDefaultDate));

        vm.prank(lender);
        ( uint40 paymentDueDate, uint40 defaultDate ) = loan.removeCall();

        assertEq(loan.calledPrincipal(), 0);
        assertEq(loan.dateCalled(),      0);
        assertEq(defaultDate,            uint40(expectedDefaultDate));
        assertEq(paymentDueDate,         uint40(expectedPaymentDueDate));
    }

}
