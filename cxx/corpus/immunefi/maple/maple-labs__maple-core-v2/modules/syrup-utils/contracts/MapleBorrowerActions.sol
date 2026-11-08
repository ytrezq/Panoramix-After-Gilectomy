// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import { NonTransparentProxied } from "../modules/non-transparent-proxy/contracts/NonTransparentProxied.sol";

import { ILoanLike }             from "./interfaces/Interfaces.sol";
import { IMapleBorrowerActions } from "./interfaces/IMapleBorrowerActions.sol";

contract MapleBorrowerActions is IMapleBorrowerActions, NonTransparentProxied {

    modifier onlyBorrower(address loan_) {
        require(msg.sender == ILoanLike(loan_).borrower(), "MBA:NOT_BORROWER");
        _;
    }

    function acceptLoanTerms(address loan_) external override onlyBorrower(loan_) {
        ILoanLike(loan_).acceptLoanTerms();
    }

}
