// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { TokenRatioSource } from "../TokenRatioSource.sol";
import { MocMultiCollateralGuard } from "../../../multiCollateral/MocMultiCollateralGuard.sol";
import { MocOperations } from "../../../core/MocOperations.sol";

/**
 * @title TCRatioSourceV3
 * @notice Ratio source for the MocV3 TC MocTokenAllocator
 * @dev This contract is used to define the split ratio calculating the amount of AC supplied by each Collateral Token.
 *  The recipients are N addresses, one for each TC
 */
contract TCRatioSourceV3 is TokenRatioSource {
    /**
     * @notice constructor
     * @dev index of TC address in the array should be the same as the index of the recipient addresses
     * @param governor_ address of the governor contract
     * @param mocMultiCollateralGuard_ address of the MocMultiCollateralGuard contract
     * @param tcAddresses_ addresses of the TC
     * @param yeldRecipients_ addresses who receive the split
     */
    constructor(
        address governor_,
        address mocMultiCollateralGuard_,
        address[] memory tcAddresses_,
        address[] memory yeldRecipients_
    ) {
        _initialize(governor_, mocMultiCollateralGuard_, tcAddresses_, yeldRecipients_);
    }

    /**
     * @notice get the amount of TCs (buckets)
     * @return length
     */
    function _getTokenLength(address mocSource_) internal view override returns (uint256 length) {
        return MocMultiCollateralGuard(payable(mocSource_)).getBucketAmount();
    }

    /**
     * @notice get the recipient when there is only one TC
     * @return yeldRecipient address who receives all the funds when there is only one TC
     */
    function _getUniqueRecipient(address mocSource_) internal view override returns (address yeldRecipient) {
        return yeldRecipients[address(MocMultiCollateralGuard(payable(mocSource_)).buckets(0).tcToken())];
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
     * @notice get the AC available to mint in the system, normalized to bucket(0) AC
     * @param mocSource_ Moc contract
     * @param tokenLength_ amount of TC
     * @param normalizationFactors_ array of normalization factors for each bucket [PREC]
     * @return totalACAvailable total AC available to mint in the system, normalized to bucket(0) AC [PREC]
     * @return acAvailableByTC array of AC available to mint by TC, normalized to bucket(0) AC [PREC]
     * @return tcAddresses array of TC addresses
     */
    function _getShares(
        address mocSource_,
        uint256 tokenLength_,
        uint256[] memory normalizationFactors_
    )
        internal
        view
        override
        returns (uint256 totalACAvailable, uint256[] memory acAvailableByTC, address[] memory tcAddresses)
    {
        acAvailableByTC = new uint256[](tokenLength_);
        tcAddresses = new address[](tokenLength_);
        MocMultiCollateralGuard mocMC = MocMultiCollateralGuard(payable(mocSource_));
        for (uint256 i = 0; i < tokenLength_; i = unchecked_inc(i)) {
            MocOperations bucket = mocMC.buckets(i);
            tcAddresses[i] = address(bucket.tcToken());
            uint256 bucketTotalACAvailable = bucket.getTotalACavailable();
            uint256 bucketLckAC = bucket.getLckAC();
            if (bucketTotalACAvailable > bucketLckAC) {
                // [PREC] = ([N] - [N]) * [PREC] * [PREC] / [PREC]
                acAvailableByTC[i] = _divPrec(
                    (bucketTotalACAvailable - bucketLckAC) * normalizationFactors_[i],
                    bucket.getCtargemaCA()
                );
                // [PREC] = [PREC] + [PREC]
                totalACAvailable += acAvailableByTC[i];
            } else {
                // the bucket has no AC available to mint
                acAvailableByTC[i] = 0;
            }
        }
    }
}
