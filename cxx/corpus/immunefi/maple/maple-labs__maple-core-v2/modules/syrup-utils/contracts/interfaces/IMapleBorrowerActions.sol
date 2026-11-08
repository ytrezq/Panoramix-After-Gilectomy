// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IMapleBorrowerActions {

    /**
     * @dev   Accepts the terms of a loan. Only the borrower of the loan can accept the terms.
     * @param loan_ The address of the loan to accept terms for.
     */
    function acceptLoanTerms(address loan_) external;

}
