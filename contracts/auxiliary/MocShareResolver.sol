// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { MocHelper } from "../utils/MocHelper.sol";
import { MocMultiCollateralGuard } from "../multiCollateral/MocMultiCollateralGuard.sol";
import { MocOperations } from "../core/MocOperations.sol";
import { IPriceProvider } from "../interfaces/IPriceProvider.sol";

contract MocShareResolver is MocHelper {
    // ------- Custom Errors -------
    error InvalidToken();

    // ------- Storage -------

    // MocMultiCollateralGuard contract
    MocMultiCollateralGuard public mocMultiCollateralGuard;

    /**
     * @notice constructor
     * @param mocMultiCollateralGuard_ address of the MocMultiCollateralGuard contract
     */
    constructor(address payable mocMultiCollateralGuard_) {
        mocMultiCollateralGuard = MocMultiCollateralGuard(mocMultiCollateralGuard_);
    }

    /**
     * @notice gets the TP prices of all buckets
     * @dev This function does not revert if some price is not valid
     * @return pACtps TP prices of all buckets
     * @return buckets Addresses of all buckets
     */
    function getPACtps() public view returns (uint256[][] memory pACtps, MocOperations[] memory buckets) {
        MocMultiCollateralGuard mocMC = mocMultiCollateralGuard;
        uint256 bucketsLength = mocMC.getBucketAmount();
        pACtps = new uint256[][](bucketsLength);
        buckets = new MocOperations[](bucketsLength);
        for (uint256 i = 0; i < bucketsLength; i = unchecked_inc(i)) {
            buckets[i] = mocMC.buckets(i);
            uint256 tpsLength = buckets[i].getTpAmount();
            pACtps[i] = new uint256[](tpsLength);
            for (uint256 j = 0; j < tpsLength; j = unchecked_inc(j)) {
                (, IPriceProvider priceProvider) = buckets[i].pegContainer(j);
                (bytes32 price, ) = priceProvider.peek();
                pACtps[i][j] = uint256(price);
            }
        }
    }

    /**
     * @notice gets the proportional share of `amount_` relative to the AC of `tokenAddress_`.
     * @param tokenAddress_ The address of the token whose AC is used for share calculation.
     * @param amount_ The amount of tokens to evaluate against the total AC normalized to bucket(0).
     * @return The share of the amount relative to the total AC normalized to bucket(0) [PREC].
     */
    function getTokenShare(address tokenAddress_, uint256 amount_) external view returns (uint256) {
        (uint256[][] memory pACtps, MocOperations[] memory buckets) = getPACtps();
        // if there is only one bucket we do not need to normalize anything
        if (buckets.length == 1) {
            if (tokenAddress_ != address(buckets[0].tcToken())) revert InvalidToken();
            // [PREC] = [PREC] * [PREC] / [PREC]
            return _divPrec(amount_, buckets[0].nTCcb());
        }
        MocMultiCollateralGuard mocMC = mocMultiCollateralGuard;
        uint256[] memory normalizationFactors = mocMC.calcNormalizationFactorsWithPrices(pACtps);
        address vetoToken;
        uint256 amountNormalized;
        uint256 totalACAvailable;
        for (uint256 i = 0; i < buckets.length; i = unchecked_inc(i)) {
            address tcToken = address(buckets[i].tcToken());
            uint256 bucketTotalACAvailable = buckets[i].nACcb();
            uint256 bucketLckAC = buckets[i].calcLckAC(pACtps[i]);
            uint256 acAvailableByTC;
            if (bucketTotalACAvailable > bucketLckAC) {
                // [PREC] = ([N] - [N]) * [PREC]
                acAvailableByTC = (bucketTotalACAvailable - bucketLckAC) * normalizationFactors[i];
                // [PREC] = [PREC] + [PREC]
                totalACAvailable += acAvailableByTC;
            } else {
                // the bucket has no AC available to mint
                acAvailableByTC = 0;
            }
            if (tokenAddress_ == tcToken) {
                vetoToken = tcToken;
                // [PREC] = [N] * [PREC] / [N]
                amountNormalized = (amount_ * acAvailableByTC) / buckets[i].nTCcb();
            }
        }

        if (vetoToken == address(0)) revert InvalidToken();
        // [PREC] = [PREC] * [PREC] / [PREC]
        return _divPrec(amountNormalized, totalACAvailable);
    }
}
