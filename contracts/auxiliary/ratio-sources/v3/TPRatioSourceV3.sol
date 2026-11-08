// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { TokenRatioSource } from "../TokenRatioSource.sol";
import { MocMultiCollateralGuard } from "../../../multiCollateral/MocMultiCollateralGuard.sol";
import { MocOperations } from "../../../core/MocOperations.sol";

/**
 * @title TPRatioSourceV3
 * @notice Ratio source for the MocV3 TP MocTokenAllocator
 * @dev This contract is used to define the split ratio calculating the amount of AC locked by each Pegged Token.
 *  The recipients are N addresses, one for each TP
 */
contract TPRatioSourceV3 is TokenRatioSource {
    /**
     * @notice constructor
     * @dev index of TP address in the array should be the same as the index of the recipient addresses
     * @param governor_ address of the governor contract
     * @param mocMultiCollateralGuard_ address of the MocMultiCollateralGuard contract
     * @param tpAddresses_ addresses of the TP
     * @param yeldRecipients_ addresses who receive the split
     */
    constructor(
        address governor_,
        address mocMultiCollateralGuard_,
        address[] memory tpAddresses_,
        address[] memory yeldRecipients_
    ) {
        _initialize(governor_, mocMultiCollateralGuard_, tpAddresses_, yeldRecipients_);
    }

    /**
     * @notice get the amount of TPs
     * @return length
     */
    function _getTokenLength(address mocSource_) internal view override returns (uint256 length) {
        return MocMultiCollateralGuard(payable(mocSource_)).buckets(0).getTpAmount();
    }

    /**
     * @notice get the recipient when there is only one TP
     * @return yeldRecipient address who receives all the funds when there is only one TP
     */
    function _getUniqueRecipient(address mocSource_) internal view override returns (address yeldRecipient) {
        return yeldRecipients[address(MocMultiCollateralGuard(payable(mocSource_)).buckets(0).tpTokens(0))];
    }

    /**
     * @notice get the extra data used to calculate
     * @param mocSource_ Moc contract
     * @return normalizationFactors array of normalization factors for each bucket [PREC]
     */
    function _getExtraData(address mocSource_) internal view override returns (uint256[] memory normalizationFactors) {
        return MocMultiCollateralGuard(payable(mocSource_)).getNormalizationFactors();
    }

    /**
     * @notice get the locked AC in the system, normalized to bucket(0) AC
     * @param mocSource_ Moc contract
     * @param tokenLength_ amount of TP
     * @param normalizationFactors_ array of normalization factors for each bucket [PREC]
     * @return totalLckAC total locked AC in the system, normalized to bucket(0) AC [PREC]
     * @return lckACByTP array of locked AC by TP, normalized to bucket(0) AC [PREC]
     * @return tpAddresses array of TP addresses
     */
    function _getShares(
        address mocSource_,
        uint256 tokenLength_,
        uint256[] memory normalizationFactors_
    ) internal view override returns (uint256 totalLckAC, uint256[] memory lckACByTP, address[] memory tpAddresses) {
        lckACByTP = new uint256[](tokenLength_);
        tpAddresses = new address[](tokenLength_);
        MocMultiCollateralGuard mocMC = MocMultiCollateralGuard(payable(mocSource_));
        MocOperations baseBucket = mocMC.buckets(0);
        for (uint256 i = 0; i < tokenLength_; i = unchecked_inc(i)) {
            tpAddresses[i] = address(baseBucket.tpTokens(i));
            for (uint256 j = 0; j < normalizationFactors_.length; j = unchecked_inc(j)) {
                MocOperations bucket = mocMC.buckets(j);
                // TPs could have different index in each bucket, we search it by the address
                (uint256 index, ) = bucket.peggedTokenIndex(tpAddresses[i]);
                // [PREC] = [N] * [PREC]
                lckACByTP[i] += bucket.getLckACByTP(index) * normalizationFactors_[j];
            }
            // [PREC] = [PREC] + [PREC]
            totalLckAC += lckACByTP[i];
        }
    }
}
