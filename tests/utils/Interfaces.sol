// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { LoanManagerStorage } from "../../contracts/LoanManagerStorage.sol";

interface ILoanManagerStructs {

    struct Impairment {
        uint40 impairedDate;
        bool   impairedByGovernor;
    }

    struct Payment {
        uint24  platformManagementFeeRate;
        uint24  delegateManagementFeeRate;
        uint40  startDate;
        uint168 issuanceRate;
    }

    function impairmentFor(address loan_) external view returns (Impairment memory impairment_);

    function paymentFor(address loan_) external view returns (Payment memory payment_);

}
