// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test } from "../../modules/forge-std/src/Test.sol";

import { ILoanManagerStructs } from "./Interfaces.sol";

import { LoanManagerHarness } from "./Harnesses.sol";

contract TestBase is Test {

    function assertImpairment(address loanManager, address loan, uint256 impairedDate, bool impairedByGovernor) internal {
        ILoanManagerStructs.Impairment memory impairment = ILoanManagerStructs(loanManager).impairmentFor(loan);

        assertEq(impairment.impairedDate,       impairedDate,       "impairedDate");
        assertEq(impairment.impairedByGovernor, impairedByGovernor, "impairedByGovernor");
    }

    function assertGlobalState(
        address loanManager,
        uint256 domainStart,
        uint256 accountedInterest,
        uint256 accruedInterest,
        uint256 assetsUnderManagement,
        uint256 principalOut,
        uint256 unrealizedLosses,
        uint256 issuanceRate
    ) internal {
        LoanManagerHarness loanManager_ = LoanManagerHarness(loanManager);

        assertEq(loanManager_.domainStart(),           uint40(domainStart),        "domainStart");
        assertEq(loanManager_.accountedInterest(),     uint112(accountedInterest), "accountedInterest");
        assertEq(loanManager_.accruedInterest(),       accruedInterest,            "accruedInterest");
        assertEq(loanManager_.assetsUnderManagement(), assetsUnderManagement,      "assetsUnderManagement");
        assertEq(loanManager_.principalOut(),          uint128(principalOut),      "principalOut");
        assertEq(loanManager_.unrealizedLosses(),      uint128(unrealizedLosses),  "unrealizedLosses");
        assertEq(loanManager_.issuanceRate(),          uint168(issuanceRate),      "issuanceRate");
    }

    function assertPaymentState(
        address loanManager,
        address loan,
        uint256 platformManagementFeeRate,
        uint256 delegateManagementFeeRate,
        uint256 startDate,
        uint256 issuanceRate
    ) internal {
        ILoanManagerStructs.Payment memory payment = ILoanManagerStructs(loanManager).paymentFor(loan);

        assertEq(payment.platformManagementFeeRate, platformManagementFeeRate, "platformManagementFeeRate");
        assertEq(payment.delegateManagementFeeRate, delegateManagementFeeRate, "delegateManagementFeeRate");
        assertEq(payment.startDate,                 startDate,                 "startDate");
        assertEq(payment.issuanceRate,              issuanceRate,              "issuanceRate");
    }

    function assertPaymentState(
        address loanManager,
        address loan,
        uint256 startDate,
        uint256 issuanceRate
    ) internal {
        ILoanManagerStructs.Payment memory payment = ILoanManagerStructs(loanManager).paymentFor(loan);

        assertEq(payment.startDate,    startDate,    "startDate");
        assertEq(payment.issuanceRate, issuanceRate, "issuanceRate");
    }

}
