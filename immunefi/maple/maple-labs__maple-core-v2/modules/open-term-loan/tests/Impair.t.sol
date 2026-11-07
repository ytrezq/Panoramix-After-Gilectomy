// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test } from "../modules/forge-std/src/Test.sol";

import { MapleLoanHarness }                    from "./utils/Harnesses.sol";
import { MockERC20, MockFactory, MockGlobals } from "./utils/Mocks.sol";
import { Utils }                               from "./utils/Utils.sol";

contract ImpairTests is Test, Utils {

    event Impaired(uint40 paymentDueDate, uint40 defaultDate);

    address lender = makeAddr("lender");

    MapleLoanHarness loan    = new MapleLoanHarness();
    MockFactory      factory = new MockFactory();
    MockGlobals      globals = new MockGlobals();

    function setUp() external {
        factory.__setGlobals(address(globals));

        loan.__setFactory(address(factory));
        loan.__setLender(lender);
    }

    function test_impair_paused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("ML:PAUSED");
        loan.impair();
    }

    function test_impair_notLender() external {
        vm.expectRevert("ML:NOT_LENDER");
        loan.impair();
    }

    function test_impair_loanNotFunded() external {
        vm.expectRevert("ML:I:LOAN_INACTIVE");
        vm.prank(lender);
        loan.impair();
    }

    function testFuzz_impair_success(
        uint256 gracePeriod,
        uint256 noticePeriod,
        uint256 paymentInterval,
        uint256 dateCalled,
        uint256 dateFunded,
        uint256 datePaid
    ) external {
        uint256 dateImpaired = block.timestamp;  // Impairing now.

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
        loan.__setDatePaid(datePaid);
        loan.__setNoticePeriod(noticePeriod);
        loan.__setPaymentInterval(paymentInterval);

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
        emit Impaired(uint40(expectedPaymentDueDate), uint40(expectedDefaultDate));

        vm.prank(lender);
        ( uint40 paymentDueDate, uint40 defaultDate ) = loan.impair();

        assertEq(loan.dateImpaired(), uint40(dateImpaired));
        assertEq(paymentDueDate,      uint40(expectedPaymentDueDate));
        assertEq(defaultDate,         uint40(expectedDefaultDate));
    }

}
