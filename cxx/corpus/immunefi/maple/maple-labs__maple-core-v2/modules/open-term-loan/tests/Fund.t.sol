// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test } from "../modules/forge-std/src/Test.sol";

import { MapleLoanHarness }                    from "./utils/Harnesses.sol";
import { MockERC20, MockFactory, MockGlobals } from "./utils/Mocks.sol";
import { Utils }                               from "./utils/Utils.sol";

contract FundTests is Test, Utils {

    event Funded(uint256 amount, uint40 paymentDueDate, uint40 defaultDate);

    address lender = makeAddr("lender");

    MapleLoanHarness loan    = new MapleLoanHarness();
    MockFactory      factory = new MockFactory();
    MockGlobals      globals = new MockGlobals();

    function setUp() external {
        factory.__setGlobals(address(globals));

        loan.__setFactory(address(factory));
        loan.__setLender(lender);
        loan.__setLoanTermsAccepted(true);
    }

    function test_fund_paused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("ML:PAUSED");
        loan.fund();
    }

    function test_fund_notLender() external {
        vm.expectRevert("ML:NOT_LENDER");
        loan.fund();
    }

    function test_fund_termsNotAccepted() external {
        loan.__setLoanTermsAccepted(false);

        vm.prank(lender);
        vm.expectRevert("ML:F:TERMS_NOT_ACCEPTED");
        loan.fund();
    }

    function test_fund_loanActive() external {
        loan.__setDateFunded(block.timestamp);

        vm.prank(lender);
        vm.expectRevert("ML:F:LOAN_ACTIVE");
        loan.fund();
    }

    function test_fund_loanClosed() external {
        vm.prank(lender);
        vm.expectRevert("ML:F:LOAN_CLOSED");
        loan.fund();
    }

    function test_fund_revertingTransfer() external {
        address asset     = address(new MockERC20("Asset", "A", 6));
        uint256 principal = 100_0000e6;

        loan.__setFundsAsset(asset);
        loan.__setPrincipal(principal);

        deal(asset, lender, principal);

        // Call without approval should cause revert of transfer.
        vm.prank(lender);
        vm.expectRevert("ML:F:TRANSFER_FROM_FAILED");
        loan.fund();
    }

    function testFuzz_fund_success() external {
        address asset           = address(new MockERC20("Asset", "A", 6));
        address borrower        = makeAddr("borrower");
        uint256 extra           = 50_000_000e6;
        uint256 gracePeriod     = 5 days;
        uint256 paymentInterval = 30 days;
        uint256 principal       = 100_000_000e6;

        loan.__setBorrower(borrower);
        loan.__setFundsAsset(asset);
        loan.__setPrincipal(principal);
        loan.__setPaymentInterval(paymentInterval);
        loan.__setGracePeriod(gracePeriod);

        deal(asset, lender, principal + extra);

        vm.prank(lender);
        MockERC20(asset).approve(address(loan), type(uint256).max);

        uint256 expectedPaymentDueDate = block.timestamp + paymentInterval;
        uint256 expectedDefaultDate    = expectedPaymentDueDate + gracePeriod;

        assertEq(MockERC20(asset).balanceOf(borrower),      0);
        assertEq(MockERC20(asset).balanceOf(lender),        principal + extra);
        assertEq(MockERC20(asset).balanceOf(address(loan)), 0);

        vm.expectEmit();
        emit Funded(principal, uint40(expectedPaymentDueDate), uint40(expectedDefaultDate));

        vm.prank(lender);
        ( uint256 fundsLent, uint40 paymentDueDate, uint40 defaultDate ) = loan.fund();

        assertEq(fundsLent,      principal);
        assertEq(paymentDueDate, uint40(expectedPaymentDueDate));
        assertEq(defaultDate,    uint40(expectedDefaultDate));

        assertEq(loan.dateFunded(), block.timestamp);

        assertEq(MockERC20(asset).balanceOf(borrower),      principal);
        assertEq(MockERC20(asset).balanceOf(lender),        extra);
        assertEq(MockERC20(asset).balanceOf(address(loan)), 0);
    }

}
