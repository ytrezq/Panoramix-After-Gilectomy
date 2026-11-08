// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test } from "../modules/forge-std/src/Test.sol";

import { MapleLoanHarness }                    from "./utils/Harnesses.sol";
import { MockERC20, MockFactory, MockGlobals } from "./utils/Mocks.sol";
import { Utils }                               from "./utils/Utils.sol";

contract CallPrincipalTests is Test, Utils {

    event PrincipalCalled(uint256 principalToReturn, uint40 paymentDueDate, uint40 defaultDate);

    uint256 constant principal = 100_000e6;

    address lender = makeAddr("lender");

    MapleLoanHarness loan    = new MapleLoanHarness();
    MockFactory      factory = new MockFactory();
    MockGlobals      globals = new MockGlobals();

    function setUp() external {
        factory.__setGlobals(address(globals));

        loan.__setFactory(address(factory));
        loan.__setLender(lender);
        loan.__setPrincipal(principal);
    }

    function test_callPrincipal_paused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("ML:PAUSED");
        loan.callPrincipal(1);
    }

    function test_callPrincipal_notLender() external {
        vm.expectRevert("ML:NOT_LENDER");
        loan.callPrincipal(1);
    }

    function test_callPrincipal_loanNotFunded() external {
        vm.expectRevert("ML:C:LOAN_INACTIVE");
        vm.prank(lender);
        loan.callPrincipal(1);
    }

    function test_callPrincipal_insufficientPrincipalToReturn() external {
        loan.__setDateFunded(block.timestamp);

        vm.expectRevert("ML:C:INVALID_AMOUNT");
        vm.prank(lender);
        loan.callPrincipal(0);
    }

    function test_callPrincipal_principalToReturnBoundary() external {
        loan.__setDateFunded(block.timestamp);

        vm.expectRevert("ML:C:INVALID_AMOUNT");
        vm.prank(lender);
        loan.callPrincipal(principal + 1);

        vm.prank(lender);
        loan.callPrincipal(principal);
    }

    function testFuzz_callPrincipal_success(
        uint256 gracePeriod,
        uint256 noticePeriod,
        uint256 paymentInterval,
        uint256 dateFunded,
        uint256 dateImpaired,
        uint256 datePaid
    ) external {
        uint256 dateCalled = block.timestamp;  // Calling now.

        gracePeriod     = bound(gracePeriod,     0, 365 days);
        noticePeriod    = bound(noticePeriod,    0, 365 days);
        paymentInterval = bound(paymentInterval, 0, 365 days);

        dateFunded = dateCalled - bound(dateFunded, 1 days, 365 days);  // `dateFunded` is 1 to 365 days ago.

        // `datePaid` is between `dateFunded` and `dateCalled`, if at all, since it only possible that `dateCalled > `datePaid`.
        datePaid = boundWithEqualChanceOfZero(datePaid, dateFunded, dateCalled);

        // `dateImpaired` is between `datePaid` and `dateCalled`, if at all, since it only possible that `dateImpaired > `datePaid`.
        dateImpaired = boundWithEqualChanceOfZero(dateImpaired, datePaid, dateCalled);

        loan.__setGracePeriod(gracePeriod);
        loan.__setDateFunded(dateFunded);
        loan.__setDateImpaired(dateImpaired);
        loan.__setDatePaid(datePaid);
        loan.__setNoticePeriod(noticePeriod);
        loan.__setPaymentInterval(paymentInterval);
        loan.__setPrincipal(2);

        uint256 callDate     = loan.__getCallDueDate(dateCalled, noticePeriod);
        uint256 impairedDate = loan.__getImpairedDueDate(dateImpaired);
        uint256 normalDate   = loan.__getNormalDueDate(dateFunded, datePaid, paymentInterval);

        uint256 expectedPaymentDueDate = minIgnoreZero(callDate, impairedDate, normalDate);

        // Reuse dates as default dates to avoid STACK_TOO_DEEP.
        callDate     = loan.__getCallDefaultDate(callDate);
        impairedDate = loan.__getImpairedDefaultDate(impairedDate, gracePeriod);
        normalDate   = loan.__getNormalDefaultDate(normalDate, gracePeriod);

        uint256 expectedDefaultDate = minIgnoreZero(callDate, impairedDate, normalDate);

        vm.expectEmit();
        emit PrincipalCalled(1, uint40(expectedPaymentDueDate), uint40(expectedDefaultDate));

        vm.prank(lender);
        ( uint40 paymentDueDate, uint40 defaultDate ) = loan.callPrincipal(1);

        assertEq(loan.calledPrincipal(), 1);
        assertEq(loan.dateCalled(),      uint40(dateCalled));
        assertEq(defaultDate,            uint40(expectedDefaultDate));
        assertEq(paymentDueDate,         uint40(expectedPaymentDueDate));
    }

}
