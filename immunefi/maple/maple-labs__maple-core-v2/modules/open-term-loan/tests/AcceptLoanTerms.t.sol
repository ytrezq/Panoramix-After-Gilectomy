// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test } from "../modules/forge-std/src/Test.sol";

import { MapleLoanHarness }         from "./utils/Harnesses.sol";
import { MockFactory, MockGlobals } from "./utils/Mocks.sol";

contract AcceptLoanTermsTests is Test {

    event LoanTermsAccepted();

    address account         = makeAddr("account");
    address borrowerActions = makeAddr("borrowerActions");

    MapleLoanHarness loan    = new MapleLoanHarness();
    MockFactory      factory = new MockFactory();
    MockGlobals      globals = new MockGlobals();

    function setUp() external {
        factory.__setGlobals(address(globals));

        loan.__setFactory(address(factory));
        loan.__setBorrower(account);
    }

    function test_acceptLoanTerms_paused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("ML:PAUSED");
        loan.acceptLoanTerms();
    }

    function test_acceptLoanTerms_notBorrower() external {
        vm.expectRevert("ML:NOT_BORROWER");
        loan.acceptLoanTerms();
    }

    function test_acceptLoanTerms_alreadyAccepted() external {
        loan.__setLoanTermsAccepted(true);

        vm.prank(account);
        vm.expectRevert("ML:ALT:ALREADY_ACCEPTED");
        loan.acceptLoanTerms();
    }

    function test_acceptLoanTerms_success_asBorrower() external {
        assertTrue(!loan.loanTermsAccepted());

        vm.expectEmit();
        emit LoanTermsAccepted();

        vm.prank(account);
        loan.acceptLoanTerms();

        assertTrue(loan.loanTermsAccepted());
    }

    function test_acceptLoanTerms_success_asBorrowerActions() external {
        assertTrue(!loan.loanTermsAccepted());

        globals.__setIsInstanceOf("BORROWER_ACTIONS", borrowerActions, true);

        vm.expectEmit();
        emit LoanTermsAccepted();

        vm.prank(borrowerActions);
        loan.acceptLoanTerms();

        assertTrue(loan.loanTermsAccepted());
    }

}
