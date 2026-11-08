// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { MocRebalancer, MocOperations } from "./MocRebalancer.sol";
import { MocQueue } from "../queue/MocQueue.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title MocMultiCollateralGuard
 * @notice this contract serves as a reference source for all buckets to determine the overall state
 * of the multi-collateral system, allowing only operations that maintain it in a healthy state
 */
contract MocMultiCollateralGuard is MocRebalancer {
    // ------- Custom Errors -------
    error BucketEmpty();

    // ------- Storage -------

    // max amount of Operations that can be executed on a single batch,
    // gas restricted batch size to guarantee no gas limit failure
    uint256 public maxOperPerBatch;
    // switches the way that price providers trigger the queue execution using the last publication block
    // false: use the minimum, so operations enqueued before the oldest price are executed. New operations
    //  have to wait until all the prices are updated
    // true: use the maximum, so operations enqueued before the newest price are executed. New operations
    //  have to wait until only one price is updated
    bool public useMaxLastPublicationBlock;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ------- Initializer -------

    /**
     * @notice contract initializer
     * @param governor_ governor address
     * @param pauser_ pauser address
     * @param microLiquidationExecCost_ coinbase micro liquidation execution fee. Paid from the
     *  rebalanced bucket to the executor
     * @param liquidationExecCost_ coinbase liquidation execution fee. Paid from the liquidated bucket to the executor
     * @param coinbaseExecFeeRecipient_ address who receives all the coinbase execution fees
     * @param maxOperPerBatch_ max amount of Operations that can be executed on a single batch
     * @param useMaxLastPublicationBlock_ use max last publication block to trigger the queue execution
     */
    function initialize(
        address governor_,
        address pauser_,
        uint256 microLiquidationExecCost_,
        uint256 liquidationExecCost_,
        address payable coinbaseExecFeeRecipient_,
        uint256 maxOperPerBatch_,
        bool useMaxLastPublicationBlock_
    ) external initializer {
        __MocUpgradable_init(governor_, pauser_);
        __ReentrancyGuard_init();
        __MocRebalancer_init(microLiquidationExecCost_, liquidationExecCost_, coinbaseExecFeeRecipient_);
        maxOperPerBatch = maxOperPerBatch_;
        useMaxLastPublicationBlock = useMaxLastPublicationBlock_;
    }

    // ------- Internal Functions -------

    /**
     * @notice calculates the AC price ratio between `baseBucket_ and `bucketTo_`
     * @dev nf = pACtpBase / pACtpTo
     *  we use the median of all the TP prices in order to discard outliers
     * @param pACtpsTo_ array of all AC prices for each TP for target bucket [PREC]
     * @param baseBucket_ base bucket
     * @param bucketTo_ target bucket to calculate the price ratio of, in relation to the base bucket
     * @return nf normalization factor [PREC]
     */
    function _calcBucketNormalizationFactor(
        uint256[] memory pACtpsBaseBucket_,
        uint256[] memory pACtpsTo_,
        MocOperations baseBucket_,
        MocOperations bucketTo_
    ) internal view returns (uint256 nf) {
        for (uint256 i = 0; i < pACtpsTo_.length; i = unchecked_inc(i)) {
            address tpAddress = address(bucketTo_.tpTokens(i));
            (uint256 index, ) = baseBucket_.peggedTokenIndex(tpAddress);
            // [PREC] = [PREC] * [PREC] / [PREC]
            nf += _divPrec(pACtpsTo_[i], pACtpsBaseBucket_[index]);
        }
        // [PREC] = [PREC] / [N]
        nf /= pACtpsTo_.length;
        return nf;
    }

    /**
     * @notice transfer coinbase execution fee to the recipient
     * @dev reverts if coinbase transfer fails
     * @param executionFee_ amount to transfer
     */
    function _payExecutionFee(uint256 executionFee_) internal {
        // if execution fees were increased before the execution, the balance could not be enough
        // to pay the required, so, the recipient will receive everything that the contract has
        if (executionFee_ > address(this).balance) executionFee_ = address(this).balance;
        _coinbaseExecFeeTransfer(executionFee_);
    }

    /**
     * @notice gets all TP prices for each bucket
     * @param buckets_ buckets array
     * @return bucketsPACtps All tps prices [PREC]
     */
    function _getBucketsPACtps(
        MocOperations[] memory buckets_
    ) internal view returns (uint256[][] memory bucketsPACtps) {
        bucketsPACtps = new uint256[][](buckets_.length);
        for (uint256 j = 0; j < buckets_.length; j = unchecked_inc(j)) {
            bucketsPACtps[j] = buckets_[j].getPACtps();
        }
    }

    /**
     * @notice calc all bucket normalization factors
     * @param buckets_ buckets array
     * @param bucketsPACtps_ all tps prices for each bucket [PREC]
     * @return normalizationFactors array of normalization factors [PREC]
     */
    function _calcNormalizationFactors(
        MocOperations[] memory buckets_,
        uint256[][] memory bucketsPACtps_
    ) internal view returns (uint256[] memory normalizationFactors) {
        normalizationFactors = new uint256[](buckets_.length);
        normalizationFactors[0] = PRECISION;
        for (uint256 j = 1; j < buckets_.length; j = unchecked_inc(j)) {
            normalizationFactors[j] = _calcBucketNormalizationFactor(
                bucketsPACtps_[0],
                bucketsPACtps_[j],
                buckets_[0],
                buckets_[j]
            );
        }
    }

    /**
     * @notice gets all buckets combined coverage
     *  combinedCglb = (Σ cglb(i) * lckACNormalized(i)) / Σ lckACNormalized(i)
     * @param buckets_ buckets array
     * @param bucketsPACtps_ all tps prices for each bucket [PREC]
     * @param normalizationFactors_ array of normalization factors [PREC]
     * @return combinedCglb combined coverage [PREC]
     */
    function _calcCombinedCglb(
        MocOperations[] memory buckets_,
        uint256[][] memory bucketsPACtps_,
        uint256[] memory normalizationFactors_
    ) internal view returns (uint256 combinedCglb) {
        uint256 num;
        uint256 den;
        for (uint256 j = 0; j < buckets_.length; j = unchecked_inc(j)) {
            MocOperations bucket = buckets_[j];
            (uint256 bucketCglb, uint256 bucketLckAC) = bucket.calcCglbAndLckAC(bucketsPACtps_[j]);
            // empty buckets are not considered to calculate combined coverage
            if (bucketCglb != UINT256_MAX) {
                // [PREC] = [N] * [PREC]
                uint256 lckACNormalized = bucketLckAC * normalizationFactors_[j];
                // [PREC]² = [PREC] + [PREC] * [PREC]
                num += bucketCglb * lckACNormalized;
                // [PREC] = [PREC] + [PREC]
                den += lckACNormalized;
            }
        }
        // if all the buckets are empty
        if (den == 0) return UINT256_MAX;
        // [PREC] = [PREC]² / [PREC]
        combinedCglb = num / den;
        return combinedCglb;
    }

    /**
     * @notice gets all buckets target coverage adjusted by Ema
     *  combinedCtargemaCA = (Σ ctargemaCA(i) * lckACNormalized(i)) / Σ lckACNormalized(i)
     * @param buckets_ buckets array
     * @param bucketsPACtps_ all tps prices for each bucket [PREC]
     * @param normalizationFactors_ normalization factors array
     * @return combinedCtargemaCA combined ctargemaCA [PREC]
     */
    function _calcCombinedCtargemaCA(
        MocOperations[] memory buckets_,
        uint256[][] memory bucketsPACtps_,
        uint256[] memory normalizationFactors_
    ) internal view returns (uint256 combinedCtargemaCA) {
        uint256 num;
        uint256 den;
        for (uint256 j = 0; j < buckets_.length; j = unchecked_inc(j)) {
            MocOperations bucket = buckets_[j];
            uint256 bucketLckAC = bucket.calcLckAC(bucketsPACtps_[j]);
            uint256 ctargemaCA = bucket.calcCtargemaCA(bucketsPACtps_[j]);
            // [PREC] = [N] * [PREC]
            uint256 lckACNormalized = bucketLckAC * normalizationFactors_[j];
            // [PREC]² = [PREC] + [PREC] * [PREC]
            num += ctargemaCA * lckACNormalized;
            // [PREC] = [PREC] + [PREC]
            den += lckACNormalized;
        }
        // we must return a default value when all nTP are 0
        // slither-disable-next-line incorrect-equality
        if (den == 0) {
            return buckets[0].protThrld() * 2;
        }
        // [PREC] = [PREC]² / [PREC]
        combinedCtargemaCA = num / den;
        return combinedCtargemaCA;
    }

    /**
     * @notice gets the real TC available to redeem considering all buckets status
     * @dev this function only is valid when it is called by a bucket
     * @param bucket_ bucket that is intended to operate
     * @param buckets_ buckets array
     * @param bucketsPACtps_ all tps prices for each bucket [PREC]
     * @param normalizationFactors_ array of normalization factors [PREC]
     * @return realTCAvailableToRedeem real TC available to redeem [N]
     */
    function _calcRealTCAvailableToRedeem(
        MocOperations bucket_,
        MocOperations[] memory buckets_,
        uint256[][] memory bucketsPACtps_,
        uint256[] memory normalizationFactors_
    ) internal view returns (uint256 realTCAvailableToRedeem) {
        uint256 localTCAvailableToRedeem;
        int256 lckACemaAdjustedSigned;
        uint256 pTCacNormalized;
        for (uint256 j = 0; j < buckets_.length; j = unchecked_inc(j)) {
            MocOperations currBucket = buckets_[j];
            // [PREC]² = [PREC] * [PREC]
            lckACemaAdjustedSigned +=
                currBucket.calcLckACemaAdjusted(bucketsPACtps_[j]) *
                int256(normalizationFactors_[j]);
            if (currBucket == bucket_) {
                localTCAvailableToRedeem = currBucket.calcTCAvailableToRedeem(bucketsPACtps_[j]);
                if (localTCAvailableToRedeem == 0) return 0;
                // [PREC]² = [PREC] * [PREC]
                pTCacNormalized = currBucket.calcPTCac(bucketsPACtps_[j]) * normalizationFactors_[j];
            }
        }
        if (lckACemaAdjustedSigned <= 0 || pTCacNormalized == 0) return 0;
        // [N] = [PREC]² / [PREC]²
        realTCAvailableToRedeem = uint256(lckACemaAdjustedSigned) / pTCacNormalized;
        // [N]
        return Math.min(realTCAvailableToRedeem, localTCAvailableToRedeem);
    }

    /**
     * @notice gets the real TP available to mint considering all buckets status
     * @dev this function only is valid when it is called by a bucket
     * @param bucket_ bucket that is intended to operate
     * @param tp_ Pegged Token address
     * @param buckets_ buckets array
     * @param bucketsPACtps_ all tps prices for each bucket [PREC]
     * @return realTPAvailableToMint real TP available to mint [N]
     */
    function _calcRealTPAvailableToMint(
        MocOperations bucket_,
        address tp_,
        MocOperations[] memory buckets_,
        uint256[][] memory bucketsPACtps_
    ) internal view returns (uint256 realTPAvailableToMint) {
        int256 localTPAvailableToMintSigned;
        int256 realTPAvailableToMintSigned;
        for (uint256 j = 0; j < buckets_.length; j = unchecked_inc(j)) {
            MocOperations currBucket = buckets_[j];
            if (currBucket != bucket_) {
                // if TP doesn't exist in the others bucket is not taking on account
                (, bool exists) = currBucket.peggedTokenIndex(tp_);
                // [N] = [N] + [N]
                if (exists) realTPAvailableToMintSigned += currBucket.calcTPAvailableToMint(tp_, bucketsPACtps_[j]);
            } else {
                localTPAvailableToMintSigned = currBucket.calcTPAvailableToMint(tp_, bucketsPACtps_[j]);
                // [N] = [N] + [N]
                realTPAvailableToMintSigned += localTPAvailableToMintSigned;
            }
        }
        if (realTPAvailableToMintSigned <= 0 || localTPAvailableToMintSigned <= 0) return 0;
        // [N]
        return Math.min(uint256(realTPAvailableToMintSigned), uint256(localTPAvailableToMintSigned));
    }

    /**
     * @notice get the min or max last TP price publication block among all the buckets
     * @param buckets_ buckets array
     * @param useMaxLastPublicationBlock_ use the max last publication block to trigger the queue execution
     * @return lastPublicationBlock the min or max last block where there was a price publication
     */
    function _getLastPublicationBlock(
        MocOperations[] memory buckets_,
        bool useMaxLastPublicationBlock_
    ) internal view returns (uint256 lastPublicationBlock) {
        lastPublicationBlock = buckets_[0].getLastPublicationBlock(useMaxLastPublicationBlock_);
        for (uint256 j = 1; j < buckets_.length; j = unchecked_inc(j)) {
            uint256 bucketLastPublicationBlock = buckets_[j].getLastPublicationBlock(useMaxLastPublicationBlock_);
            lastPublicationBlock = useMaxLastPublicationBlock_
                ? Math.max(lastPublicationBlock, bucketLastPublicationBlock)
                : Math.min(lastPublicationBlock, bucketLastPublicationBlock);
        }
    }

    // ------- External Functions -------

    /**
     * @notice get combined coverage and combined ctargemaCA
     * @param bucket_ bucket that is intended to operate
     * @return combinedCglb combined coverage [PREC]
     * @return combinedCtargemaCA combined ctargemaCA [PREC]
     * @return bucketPACtps all tps prices for the given bucket [PREC]
     */
    function getCombinedValues(
        MocOperations bucket_
    ) external returns (uint256 combinedCglb, uint256 combinedCtargemaCA, uint256[] memory bucketPACtps) {
        MocOperations[] memory bucketsArray = buckets;
        uint256[][] memory bucketsPACtps = _getBucketsPACtps(bucketsArray);
        uint256[] memory normalizationFactors = _calcNormalizationFactors(bucketsArray, bucketsPACtps);
        _updatesCtargemaCA(bucketsArray);
        return (
            _calcCombinedCglb(bucketsArray, bucketsPACtps, normalizationFactors),
            _calcCombinedCtargemaCA(bucketsArray, bucketsPACtps, normalizationFactors),
            bucketsPACtps[bucketIndex[bucket_].index]
        );
    }

    /**
     * @notice get combined values and TC available to redeem
     * @param bucket_ bucket that is intended to operate
     * @return combinedCglb combined coverage [PREC]
     * @return combinedCtargemaCA combined ctargemaCA [PREC]
     * @return realTCAvailableToRedeem real TC available to redeem [N]
     * @return bucketPACtps all tps prices for the given bucket [PREC]
     */
    function getCombinedAndTC(
        MocOperations bucket_
    )
        external
        returns (
            uint256 combinedCglb,
            uint256 combinedCtargemaCA,
            uint256 realTCAvailableToRedeem,
            uint256[] memory bucketPACtps
        )
    {
        MocOperations[] memory bucketsArray = buckets;
        uint256[][] memory bucketsPACtps = _getBucketsPACtps(bucketsArray);
        uint256[] memory normalizationFactors = _calcNormalizationFactors(bucketsArray, bucketsPACtps);
        _updatesCtargemaCA(bucketsArray);
        return (
            _calcCombinedCglb(bucketsArray, bucketsPACtps, normalizationFactors),
            _calcCombinedCtargemaCA(bucketsArray, bucketsPACtps, normalizationFactors),
            _calcRealTCAvailableToRedeem(bucket_, bucketsArray, bucketsPACtps, normalizationFactors),
            bucketsPACtps[bucketIndex[bucket_].index]
        );
    }

    /**
     * @notice get combined values and TP available to mint
     * @param bucket_ bucket that is intended to operate
     * @param tp_ Pegged Token that is intended to operate
     * @return combinedCglb combined coverage [PREC]
     * @return combinedCtargemaCA combined ctargemaCA [PREC]
     * @return realTPAvailableToMint real TP available to mint [N]
     * @return bucketPACtps all tps prices for the given bucket [PREC]
     */
    function getCombinedAndTP(
        MocOperations bucket_,
        address tp_
    )
        external
        returns (
            uint256 combinedCglb,
            uint256 combinedCtargemaCA,
            uint256 realTPAvailableToMint,
            uint256[] memory bucketPACtps
        )
    {
        MocOperations[] memory bucketsArray = buckets;
        uint256[][] memory bucketsPACtps = _getBucketsPACtps(bucketsArray);
        uint256[] memory normalizationFactors = _calcNormalizationFactors(bucketsArray, bucketsPACtps);
        _updatesCtargemaCA(bucketsArray);
        return (
            _calcCombinedCglb(bucketsArray, bucketsPACtps, normalizationFactors),
            _calcCombinedCtargemaCA(bucketsArray, bucketsPACtps, normalizationFactors),
            _calcRealTPAvailableToMint(bucket_, tp_, bucketsArray, bucketsPACtps),
            bucketsPACtps[bucketIndex[bucket_].index]
        );
    }

    /**
     * @notice get combined values, TC available to redeem and TP available to mint
     * @param bucket_ bucket that is intended to operate
     * @param tp_ Pegged Token that is intended to operate
     * @return combinedCglb combined coverage [PREC]
     * @return combinedCtargemaCA combined ctargemaCA [PREC]
     * @return realTCAvailableToRedeem real TC available to redeem [N]
     * @return realTPAvailableToMint real TP available to mint [N]
     * @return bucketPACtps all tps prices for the given bucket [PREC]
     */
    function getCombinedAndTCAndTP(
        MocOperations bucket_,
        address tp_
    )
        external
        returns (
            uint256 combinedCglb,
            uint256 combinedCtargemaCA,
            uint256 realTCAvailableToRedeem,
            uint256 realTPAvailableToMint,
            uint256[] memory bucketPACtps
        )
    {
        MocOperations[] memory bucketsArray = buckets;
        uint256[][] memory bucketsPACtps = _getBucketsPACtps(bucketsArray);
        uint256[] memory normalizationFactors = _calcNormalizationFactors(bucketsArray, bucketsPACtps);
        _updatesCtargemaCA(bucketsArray);
        return (
            _calcCombinedCglb(bucketsArray, bucketsPACtps, normalizationFactors),
            _calcCombinedCtargemaCA(bucketsArray, bucketsPACtps, normalizationFactors),
            _calcRealTCAvailableToRedeem(bucket_, bucketsArray, bucketsPACtps, normalizationFactors),
            _calcRealTPAvailableToMint(bucket_, tp_, bucketsArray, bucketsPACtps),
            bucketsPACtps[bucketIndex[bucket_].index]
        );
    }

    /**
     * @notice return current amount of buckets
     */
    function getBucketAmount() external view returns (uint256) {
        return buckets.length;
    }

    /**
     * @notice gets all TP prices for each bucket
     * @return bucketsPACtps All tps prices [PREC]
     */
    function getBucketsPACtps() external view returns (uint256[][] memory bucketsPACtps) {
        return _getBucketsPACtps(buckets);
    }

    /**
     * @notice gets all bucket normalization factors
     * @return normalizationFactors array of normalization factors [PREC]
     */
    function getNormalizationFactors() external view returns (uint256[] memory normalizationFactors) {
        MocOperations[] memory bucketsArray = buckets;
        return _calcNormalizationFactors(bucketsArray, _getBucketsPACtps(bucketsArray));
    }

    /**
     * @notice calc all bucket normalization factors
     * @param bucketsPACtps_ all tps prices for each bucket [PREC]
     * @return normalizationFactors array of normalization factors [PREC]
     */
    function calcNormalizationFactorsWithPrices(
        uint256[][] calldata bucketsPACtps_
    ) external view returns (uint256[] memory normalizationFactors) {
        return _calcNormalizationFactors(buckets, bucketsPACtps_);
    }

    /**
     * @notice gets all buckets combined coverage
     *  combinedCglb = (Σ cglb(i) * lckACNormalized(i)) / Σ lckACNormalized(i)
     * @return combinedCglb combined coverage [PREC]
     */
    function getCombinedCglb() external view returns (uint256 combinedCglb) {
        MocOperations[] memory bucketsArray = buckets;
        uint256[][] memory bucketsPACtps = _getBucketsPACtps(bucketsArray);
        return _calcCombinedCglb(bucketsArray, bucketsPACtps, _calcNormalizationFactors(bucketsArray, bucketsPACtps));
    }

    /**
     * @notice gets all buckets combined coverage
     *  combinedCglb = (Σ cglb(i) * lckACNormalized(i)) / Σ lckACNormalized(i)
     * @param bucketsPACtps_ all tps prices for each bucket [PREC]
     * @return combinedCglb combined coverage [PREC]
     */
    function calcCombinedCglbWithPrices(
        uint256[][] calldata bucketsPACtps_
    ) external view returns (uint256 combinedCglb) {
        MocOperations[] memory bucketsArray = buckets;
        return _calcCombinedCglb(bucketsArray, bucketsPACtps_, _calcNormalizationFactors(bucketsArray, bucketsPACtps_));
    }

    /**
     * @notice gets all buckets target coverage adjusted by Ema
     *  combinedCtargemaCA = (Σ ctargemaCA(i) * lckACNormalized(i)) / Σ lckACNormalized(i)
     * @return combinedCtargemaCA combined ctargemaCA [PREC]
     */

    function getCombinedCtargemaCA() public view returns (uint256 combinedCtargemaCA) {
        MocOperations[] memory bucketsArray = buckets;
        uint256[][] memory bucketsPACtps = _getBucketsPACtps(bucketsArray);
        return
            _calcCombinedCtargemaCA(
                bucketsArray,
                bucketsPACtps,
                _calcNormalizationFactors(bucketsArray, bucketsPACtps)
            );
    }

    /**
     * @notice gets all buckets target coverage adjusted by Ema
     *  combinedCtargemaCA = (Σ ctargemaCA(i) * lckACNormalized(i)) / Σ lckACNormalized(i)
     * @param bucketsPACtps_ all tps prices for each bucket [PREC]
     * @return combinedCtargemaCA combined ctargemaCA [PREC]
     */
    function calcCombinedCtargemaCAWithPrices(
        uint256[][] calldata bucketsPACtps_
    ) external view returns (uint256 combinedCtargemaCA) {
        MocOperations[] memory bucketsArray = buckets;
        return
            _calcCombinedCtargemaCA(
                bucketsArray,
                bucketsPACtps_,
                _calcNormalizationFactors(bucketsArray, bucketsPACtps_)
            );
    }

    /**
     * @notice gets the real TC available to redeem considering all buckets status
     * @dev this function only is valid when it is called by a bucket
     * @param bucket_ bucket that is intended to operate
     * @return realTCAvailableToRedeem real TC available to redeem [N]
     */
    function getRealTCAvailableToRedeem(MocOperations bucket_) external view returns (uint256 realTCAvailableToRedeem) {
        MocOperations[] memory bucketsArray = buckets;
        uint256[][] memory bucketsPACtps = _getBucketsPACtps(bucketsArray);
        return
            _calcRealTCAvailableToRedeem(
                bucket_,
                bucketsArray,
                bucketsPACtps,
                _calcNormalizationFactors(bucketsArray, bucketsPACtps)
            );
    }

    /**
     * @notice gets the real TC available to redeem considering all buckets status
     * @dev this function only is valid when it is called by a bucket
     * @param bucket_ bucket that is intended to operate
     * @param bucketsPACtps_ all tps prices for each bucket [PREC]
     * @return realTCAvailableToRedeem real TC available to redeem [N]
     */
    function calcRealTCAvailableToRedeemWithPrices(
        MocOperations bucket_,
        uint256[][] calldata bucketsPACtps_
    ) external view returns (uint256 realTCAvailableToRedeem) {
        MocOperations[] memory bucketsArray = buckets;
        return
            _calcRealTCAvailableToRedeem(
                bucket_,
                bucketsArray,
                bucketsPACtps_,
                _calcNormalizationFactors(bucketsArray, bucketsPACtps_)
            );
    }

    /**
     * @notice gets the real TP available to mint considering all buckets status
     * @dev this function only is valid when it is called by a bucket
     * @param bucket_ bucket that is intended to operate
     * @param tp_ Pegged Token address
     * @return realTPAvailableToMint real TP available to mint [N]
     */
    function getRealTPAvailableToMint(
        MocOperations bucket_,
        address tp_
    ) external view returns (uint256 realTPAvailableToMint) {
        MocOperations[] memory bucketsArray = buckets;
        return _calcRealTPAvailableToMint(bucket_, tp_, bucketsArray, _getBucketsPACtps(bucketsArray));
    }

    /**
     * @notice gets the real TP available to mint considering all buckets status
     * @dev this function only is valid when it is called by a bucket
     * @param bucket_ bucket that is intended to operate
     * @param tp_ Pegged Token address
     * @param bucketsPACtps_ all tps prices for each bucket [PREC]
     * @return realTPAvailableToMint real TP available to mint [N]
     */
    function calcRealTPAvailableToMintWithPrices(
        MocOperations bucket_,
        address tp_,
        uint256[][] calldata bucketsPACtps_
    ) external view returns (uint256 realTPAvailableToMint) {
        return _calcRealTPAvailableToMint(bucket_, tp_, buckets, bucketsPACtps_);
    }

    /**
     * @notice get the min or max last TP price publication block among all the buckets
     * @param useMaxLastPublicationBlock_ use the max last publication block to trigger the queue execution
     * @return lastPublicationBlock the min or max last block where there was a price publication.
     */
    function getLastPublicationBlock(
        bool useMaxLastPublicationBlock_
    ) external view returns (uint256 lastPublicationBlock) {
        return _getLastPublicationBlock(buckets, useMaxLastPublicationBlock_);
    }

    /**
     * @notice Processes Operations on every bucket's queue
     * @dev does not revert on Operation failure, throws events according to
     * the Oper type and result
     */
    function execute() external notPaused nonReentrant {
        MocOperations[] memory bucketsArray = buckets;
        uint256 bucketsCounter;
        uint256 totalExecutionFee;
        uint256 remainingOperToExecute = maxOperPerBatch;
        uint256 blocksSinceLastPublication = block.number -
            _getLastPublicationBlock(bucketsArray, useMaxLastPublicationBlock);

        while (bucketsCounter < bucketsArray.length && remainingOperToExecute > 0) {
            // use block.number as bucket index seed not to start always with the same bucket
            uint256 iBucket = (block.number + bucketsCounter) % bucketsArray.length;
            (uint256 executionFee, uint256 operExecuted) = MocQueue(bucketsArray[iBucket].mocQueue()).execute(
                msg.sender,
                remainingOperToExecute,
                blocksSinceLastPublication
            );
            unchecked {
                totalExecutionFee += executionFee;
                remainingOperToExecute -= operExecuted;
                bucketsCounter += 1;
            }
        }
        _payExecutionFee(totalExecutionFee);
    }

    /**
     * @notice Processes Operations on a liquidated bucket
     * @dev does not revert on Operation failure, throws events according to
     * the Oper type and result
     */
    function executeLiquidatedBucket(MocOperations liquidatedBucket_) external notPaused nonReentrant {
        if (!bucketIndex[liquidatedBucket_].liquidated) revert BucketNotLiquidated();
        if (MocQueue(liquidatedBucket_.mocQueue()).isEmpty()) revert BucketEmpty();

        (uint256 totalExecutionFee, ) = MocQueue(liquidatedBucket_.mocQueue()).execute(
            msg.sender,
            maxOperPerBatch,
            0 /*blocksSinceLastPublication; allow to execute everything*/
        );

        _payExecutionFee(totalExecutionFee);
    }

    /**
     * @notice true if some queue has at least one Operation ready to be executed
     */
    function readyToExecute() external view returns (bool) {
        MocOperations[] memory bucketsArray = buckets;
        uint256 blocksSinceLastPublication = block.number -
            _getLastPublicationBlock(bucketsArray, useMaxLastPublicationBlock);
        for (uint256 j = 0; j < bucketsArray.length; j = unchecked_inc(j)) {
            if (MocQueue(bucketsArray[j].mocQueue()).readyToExecute(blocksSinceLastPublication)) return true;
        }
        return false;
    }

    /**
     * @notice checks if some bucket requires micro liquidation
     * @param bucketsPACtps_ all tps prices for each bucket [PREC]
     * @return true if some bucket requires micro liquidation
     */
    function readyToMicroLiquidate(uint256[][] calldata bucketsPACtps_) external view returns (bool) {
        MocOperations[] memory bucketsArray = buckets;
        for (uint256 j = 0; j < bucketsArray.length; j = unchecked_inc(j)) {
            if (isMicroLiquidationAvailableWithPrices(bucketsArray[j], bucketsPACtps_[j])) return true;
        }
        return false;
    }

    /**
     * @notice checks if some bucket requires liquidation
     * @param bucketsPACtps_ all tps prices for each bucket [PREC]
     * @return true if some bucket requires liquidation
     */
    function readyToLiquidate(uint256[][] calldata bucketsPACtps_) external view returns (bool) {
        MocOperations[] memory bucketsArray = buckets;
        for (uint256 j = 0; j < bucketsArray.length; j = unchecked_inc(j)) {
            if (isLiquidationAvailableWithPrices(bucketsArray[j], bucketsPACtps_[j])) return true;
        }
        return false;
    }

    // ------- Only Authorized Functions -------

    /**
     * @notice sets maximum amount of operations per execution batch
     * @param maxOperPerBatch_ maximum amount of operations allowed on a batch to avoid going over
     * the block gas limit
     */
    function setMaxOperPerBatch(uint256 maxOperPerBatch_) external onlyAuthorizedChanger {
        maxOperPerBatch = maxOperPerBatch_;
    }

    /**
     * @notice switches the way that price providers trigger the queue execution using the last publication block
     * false: use the minimum, so operations enqueued before the oldest price are executed. New operations
     *  have to wait until all the prices are updated
     * true: use the maximum, so operations enqueued before the newest price are executed. New operations
     *  have to wait until only one price is updated
     * @param useMaxLastPublicationBlock_ new way to trigger the queue execution using the last publication block
     */
    function setUseMaxLastPublicationBlock(bool useMaxLastPublicationBlock_) external onlyAuthorizedChanger {
        useMaxLastPublicationBlock = useMaxLastPublicationBlock_;
    }

    /**
     * @notice sets the address of the coinbase execution fee recipient
     * @param coinbaseExecFeeRecipient_ address of the coinbase execution fee recipient
     */
    function setCoinbaseExecFeeRecipient(address payable coinbaseExecFeeRecipient_) external onlyAuthorizedChanger {
        coinbaseExecFeeRecipient = coinbaseExecFeeRecipient_;
    }

    // @notice used to receive executions fee payment
    receive() external payable {}

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */

    // Purposely left unused to save some state space to allow for future upgrades
    // slither-disable-next-line unused-state
    uint256[50] private __gap;
}
