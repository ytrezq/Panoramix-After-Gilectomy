// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { LoanManager } from "../../contracts/LoanManager.sol";

contract LoanManagerHarness is LoanManager {

    function __distributeClaimedFunds(
        address loan_,
        int256  principal_,
        uint256 interest_,
        uint256 delegateServiceFee_,
        uint256 platformServiceFee_
    ) external {
        _distributeClaimedFunds(loan_, principal_, interest_, delegateServiceFee_, platformServiceFee_);
    }

    function __distributeLiquidationFunds(
        address loan_,
        uint256 principal_,
        uint256 interest_,
        uint256 platformServiceFee_,
        uint256 recoveredFunds_
    )
        external returns (uint256 remainingLosses_, uint256 unrecoveredPlatformFees_) {
        return _distributeLiquidationFunds(loan_, principal_, interest_, platformServiceFee_, recoveredFunds_);
    }

    function __setAccountedInterest(uint256 accountedInterest_) external {
        accountedInterest = uint112(accountedInterest_);
    }

    function __setDomainStart(uint256 domainStart_) external {
        domainStart = uint40(domainStart_);
    }

    function __setFactory(address factory_) external {
        _setFactory(factory_);
    }

    function __setFundsAsset(address asset_) external {
        fundsAsset = asset_;
    }

    function __setImpairmentFor(address loan_, uint256 impairedDate_, bool impairedByGovernor_) external {
        impairmentFor[loan_] = Impairment(uint40(impairedDate_), impairedByGovernor_);
    }

    function __setIssuanceRate(uint256 issuanceRate_) external {
        issuanceRate = issuanceRate_;
    }

    function __setLocked(uint256 locked_) external {
        _locked = locked_;
    }

    function __setPaymentFor(
        address loan_,
        uint256 platformManagementFeeRate_,
        uint256 delegateManagementFeeRate_,
        uint256 startDate_,
        uint256 issuanceRate_
    ) external {
        paymentFor[loan_] = Payment(
            uint24(platformManagementFeeRate_),
            uint24(delegateManagementFeeRate_),
            uint40(startDate_),
            uint168(issuanceRate_)
        );
    }

    function __setPoolManager(address poolManager_) external {
        poolManager = poolManager_;
    }

    function __setPrincipalOut(uint256 principalOut_) external {
        principalOut = uint128(principalOut_);
    }

    function __setUnrealizedLosses(uint256 unrealizedLosses_) external {
        unrealizedLosses = uint128(unrealizedLosses_);
    }

    function __updatePrincipalOut(int256 principal_) external {
        _updatePrincipalOut(principal_);
    }

    function __updateUnrealizedLosses(int256 lossesAdjustments_) external {
        _updateUnrealizedLosses(lossesAdjustments_);
    }

    function __updateInterestAccounting(int256 interestAdjustment_, int256 issuanceRate_) external {
        _updateInterestAccounting(interestAdjustment_, issuanceRate_);
    }

}
