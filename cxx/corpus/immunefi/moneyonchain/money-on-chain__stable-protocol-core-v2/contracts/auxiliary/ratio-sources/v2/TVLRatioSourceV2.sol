// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { TVLRatioSource } from "../TVLRatioSource.sol";
import { IMocV2 } from "../../../interfaces/IMocV2.sol";

/**
 * @title TVLRatioSourceV2
 * @notice Ratio source for the MocV2 TVL MocTokenAllocator
 * @dev This contract is used to define the split ratio calculating the total value locked (TVL) in the system.
 *  The recipients are 2:
 *  1. The TC yeld recipient. The percentage if related to the amount of TC in the system.
 *  2. The TP yeld recipient. The percentage if related to the amount of TP in the system.
 */
contract TVLRatioSourceV2 is TVLRatioSource {
    /**
     * @notice constructor
     * @param governor_ address of the governor contract
     * @param mocV2_ address of the MocV2 contract
     * @param tcYeldRecipient_ address of the TC yeld recipient
     * @param tpYeldRecipient_ address of the TP yeld recipient
     */
    constructor(address governor_, address mocV2_, address tcYeldRecipient_, address tpYeldRecipient_) {
        _initialize(governor_, mocV2_, tcYeldRecipient_, tpYeldRecipient_);
    }

    /**
     * @notice get total value locked (TVL) in the system
     * @param mocSource_ Moc contract
     * @return tvl total value locked in the system AC [PREC]
     */
    function _getTVL(address mocSource_, uint256[] memory /*extraData_*/) internal view override returns (uint256 tvl) {
        return IMocV2(mocSource_).getTotalACavailable() * PRECISION;
    }

    /**
     * @notice get the locked AC in the system
     * @param mocSource_ Moc contract
     * @return lckAC locked AC in the system [PREC]
     */
    function _getLckAC(
        address mocSource_,
        uint256[] memory /*extraData_*/
    ) internal view override returns (uint256 lckAC) {
        return IMocV2(mocSource_).getLckAC() * PRECISION;
    }

    /**
     * @notice get global coverage
     * @param mocSource_ Moc contract
     * @return coverage current global coverage [PREC]
     */
    function _getCoverage(address mocSource_) internal view override returns (uint256 coverage) {
        return IMocV2(mocSource_).getCglb();
    }

    /**
     * @notice get target coverage adjusted by EMA
     * @param mocSource_ Moc contract
     * @return targetCoverageAdj target coverage adjusted by EMA [PREC]
     */
    function _getTargetCoverageAdj(address mocSource_) internal view override returns (uint256 targetCoverageAdj) {
        return IMocV2(mocSource_).calcCtargemaCA();
    }

    /**
     * @notice get the extra data used to calculate
     * @return extraData_ array of extra data
     */
    function _getExtraData(address /*mocSource_*/) internal pure override returns (uint256[] memory extraData_) {
        return new uint256[](0);
    }
}
