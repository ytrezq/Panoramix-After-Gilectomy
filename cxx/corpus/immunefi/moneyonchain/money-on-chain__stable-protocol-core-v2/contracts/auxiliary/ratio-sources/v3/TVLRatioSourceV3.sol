// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { TVLRatioSource } from "../TVLRatioSource.sol";
import { MocMultiCollateralGuard } from "../../../multiCollateral/MocMultiCollateralGuard.sol";

/**
 * @title TVLRatioSourceV3
 * @notice Ratio source for the MocV3 TVL MocTokenAllocator
 * @dev This contract is used to define the split ratio calculating the total value locked (TVL) in the system.
 *  The recipients are 2:
 *  1. The TC yeld recipient. The percentage if related to the amount of TC in the system.
 *  2. The TP yeld recipient. The percentage if related to the amount of TP in the system.
 */
contract TVLRatioSourceV3 is TVLRatioSource {
    /**
     * @notice constructor
     * @param governor_ address of the governor contract
     * @param mocMultiCollateralGuard_ address of the MocMultiCollateralGuard contract
     * @param tcYeldRecipient_ address of the TC yeld recipient
     * @param tpYeldRecipient_ address of the TP yeld recipient
     */
    constructor(
        address governor_,
        address mocMultiCollateralGuard_,
        address tcYeldRecipient_,
        address tpYeldRecipient_
    ) {
        _initialize(governor_, mocMultiCollateralGuard_, tcYeldRecipient_, tpYeldRecipient_);
    }

    /**
     * @notice get total value locked (TVL) in the system, normalized to bucket(0) AC
     * @param mocSource_ Moc contract
     * @param normalizationFactors_ array of normalization factors for each bucket [PREC]
     * @return tvl total value locked in the system AC, normalized to bucket(0) AC [PREC]
     */
    function _getTVL(
        address mocSource_,
        uint256[] memory normalizationFactors_
    ) internal view override returns (uint256 tvl) {
        MocMultiCollateralGuard mocMC = MocMultiCollateralGuard(payable(mocSource_));
        for (uint256 i = 0; i < normalizationFactors_.length; i = unchecked_inc(i)) {
            uint256 bucketAC = mocMC.buckets(i).getTotalACavailable();
            // [PREC] = [N] * [PREC]
            tvl += bucketAC * normalizationFactors_[i];
        }
    }

    /**
     * @notice get the locked AC in the system, normalized to bucket(0) AC
     * @param mocSource_ Moc contract
     * @param normalizationFactors_ array of normalization factors for each bucket [PREC]
     * @return lckAC locked AC in the system, normalized to bucket(0) AC [PREC]
     */
    function _getLckAC(
        address mocSource_,
        uint256[] memory normalizationFactors_
    ) internal view override returns (uint256 lckAC) {
        MocMultiCollateralGuard mocMC = MocMultiCollateralGuard(payable(mocSource_));
        for (uint256 i = 0; i < normalizationFactors_.length; i = unchecked_inc(i)) {
            uint256 bucketLckAC = mocMC.buckets(i).getLckAC();
            // [PREC] = [N] * [PREC]
            lckAC += bucketLckAC * normalizationFactors_[i];
        }
    }

    /**
     * @notice get global coverage
     * @param mocSource_ Moc contract
     * @return coverage current global coverage [PREC]
     */
    function _getCoverage(address mocSource_) internal view override returns (uint256 coverage) {
        return MocMultiCollateralGuard(payable(mocSource_)).getCombinedCglb();
    }

    /**
     * @notice get target coverage adjusted by EMA
     * @param mocSource_ Moc contract
     * @return targetCoverageAdj target coverage adjusted by EMA [PREC]
     */
    function _getTargetCoverageAdj(address mocSource_) internal view override returns (uint256 targetCoverageAdj) {
        return MocMultiCollateralGuard(payable(mocSource_)).getCombinedCtargemaCA();
    }

    /**
     * @notice get the extra data used to calculate
     * @param mocSource_ Moc contract
     * @return normalizationFactors array of normalization factors for each bucket [PREC]
     */
    function _getExtraData(address mocSource_) internal view override returns (uint256[] memory normalizationFactors) {
        return MocMultiCollateralGuard(payable(mocSource_)).getNormalizationFactors();
    }
}
