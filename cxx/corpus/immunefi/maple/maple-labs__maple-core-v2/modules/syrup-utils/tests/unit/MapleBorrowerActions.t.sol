// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { console2 as console, Test, Vm } from "../../modules/forge-std/src/Test.sol";

import { NonTransparentProxy } from "../../modules/non-transparent-proxy/contracts/NonTransparentProxy.sol";

import { MapleBorrowerActions } from "../../contracts/MapleBorrowerActions.sol";

import { MockLoan } from "../utils/Mocks.sol";

contract MapleBorrowerActionsTests is Test {

    address admin    = makeAddr("admin");
    address borrower = makeAddr("borrower");

    address borrowerActions;
    address borrowerActionsImpl;

    MockLoan loan;

    function setUp() public {
        borrowerActionsImpl = address(new MapleBorrowerActions());
        borrowerActions     = address(new NonTransparentProxy(admin, borrowerActionsImpl));
        loan                = new MockLoan();

        loan.__setBorrower(borrower);
    }

    function test_acceptLoanTerms_notBorrower() public {
        vm.expectRevert("MBA:NOT_BORROWER");
        MapleBorrowerActions(borrowerActions).acceptLoanTerms(address(loan));
    }

    function test_acceptLoanTerms() public {
        vm.prank(borrower);
        MapleBorrowerActions(borrowerActions).acceptLoanTerms(address(loan));
    }

}
