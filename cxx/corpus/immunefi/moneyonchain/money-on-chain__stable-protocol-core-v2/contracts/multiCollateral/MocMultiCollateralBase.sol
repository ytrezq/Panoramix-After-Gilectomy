// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { MocUpgradable } from "../governance/MocUpgradable.sol";
import { MocOperations } from "../core/MocOperations.sol";
import { IMocSwapper } from "../interfaces/IMocSwapper.sol";
import { IPriceProvider } from "../interfaces/IPriceProvider.sol";
/* solhint-disable-next-line max-line-length */
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

// ------- External Structs -------

struct BucketParams {
    // bucket AC to coinbase price provider. Not used for coinbase bucket
    IPriceProvider acCoinbasePriceProvider;
    // bucket rebalance execution fee recipient. Not used for coinbase bucket
    address rebalanceExecFeeRecipient;
    // target coverage to reach during a micro liquidation [PREC]
    uint256 rtcThrld;
    // threshold to trigger the micro liquidation [PREC]
    uint256 microLiquidationThrld;
    // additional pct of AC sent to the target bucket during a micro liquidation [PREC]
    uint256 penaltyRate;
}

/**
 * @title MocMultiCollateralBase
 *
 */
abstract contract MocMultiCollateralBase is MocUpgradable, ReentrancyGuardUpgradeable {
    // ------- Custom Errors -------
    error BucketAlreadyExists();
    error BucketDoesNotExist();
    error InvalidParams();
    // ------- Events -------
    event BucketChange(
        uint256 bucketIndex_,
        address indexed bucket_,
        BucketParams bucketParams_,
        IMocSwapper[] mocSwappers
    );

    // ------- Structs -------
    struct BucketIndex {
        // bucket index
        uint240 index;
        // true if bucket exists
        bool exists;
        // true if bucket is liquidated, queue can be executed to empty all the the operations and return locked funds
        bool liquidated;
    }

    // ------- Storage -------
    // bucket index 0 is considered the base bucket and used to calculate the normalization factor
    MocOperations[] public buckets;
    // bucket indexes
    mapping(MocOperations => BucketIndex) public bucketIndex;

    // ------- Internal Functions -------
    /**
     * @notice set rebalance params. Used when a bucket is added or edited
     * @param bucket_ address of the mocOperations implementation to interact with
     * @param params_ params of bucket to add or edit:
     *      acCoinbasePriceProvider bucket AC to coinbase price provider. Not used for coinbase bucket
     *      rebalanceExecFeeRecipient bucket rebalance execution fee recipient. Not used for coinbase bucket
     *      rtcThrld target coverage to reach during a micro liquidation [PREC]
     *      microLiquidationThrld threshold to trigger the micro liquidation [PREC]
     *      penaltyRate additional pct of AC sent to the target bucket during a micro liquidation [PREC]
     * @param mocSwappers_ MocSwapper contracts for the originBucketAC / targetBucketAC pool
     */
    function _setRebalanceParams(
        MocOperations bucket_,
        BucketParams calldata params_,
        IMocSwapper[] memory mocSwappers_
    ) internal virtual;

    /**
     * @notice If time, updates the EMA for all the Pegged Token prices for all the buckets.
     * @param buckets_ buckets array
     */
    function _updatesCtargemaCA(MocOperations[] memory buckets_) internal {
        for (uint256 j = 0; j < buckets_.length; j = unchecked_inc(j)) {
            buckets_[j].updateEmas();
        }
    }

    // ------- Only Authorized Functions -------

    /**
     * @notice adds a new bucket
     * @param bucket_ address of the mocOperations implementation to interact with
     * @param params_ params of bucket to add:
     *      acCoinbasePriceProvider bucket AC to coinbase price provider
     *      rtcThrld target coverage to reach during a micro liquidation [PREC]
     *      microLiquidationThrld threshold to trigger the micro liquidation [PREC]
     *      penaltyRate additional pct of AC sent to the target bucket during a micro liquidation [PREC]
     * @param mocSwappers_ MocSwapper contracts for the originBucketAC / targetBucketAC pool
     *
     * @dev buckets should be added using the corresponding changer template, which
     *      should guarantee bucket is not already part of the solution and all its
     *      TPs exists on base bucket (normalization precondition)
     */
    function addBucket(
        MocOperations bucket_,
        BucketParams calldata params_,
        IMocSwapper[] calldata mocSwappers_
    ) external onlyAuthorizedChanger {
        if (bucketIndex[bucket_].exists || bucketIndex[bucket_].liquidated) revert BucketAlreadyExists();
        uint256 bucketsAmount = buckets.length;
        if (mocSwappers_.length != bucketsAmount) revert InvalidParams();

        uint240 newBucketIndex = uint240(bucketsAmount);
        bucketIndex[bucket_] = BucketIndex({ index: newBucketIndex, exists: true, liquidated: false });

        _setRebalanceParams(bucket_, params_, mocSwappers_);

        buckets.push(bucket_);

        emit BucketChange(newBucketIndex, address(bucket_), params_, mocSwappers_);
    }

    /**
     * @notice modifies a bucket
     * @param bucket_ address of the mocOperations implementation to interact with
     * @param params_ params of bucket to edit:
     *      acCoinbasePriceProvider bucket AC to coinbase price provider. Not used for coinbase bucket
     *      rebalanceExecFeeRecipient bucket rebalance execution fee recipient. Not used for coinbase bucket
     *      rtcThrld target coverage to reach during a micro liquidation [PREC]
     *      microLiquidationThrld threshold to trigger the micro liquidation [PREC]
     *      penaltyRate additional pct of AC sent to the target bucket during a micro liquidation [PREC]
     */
    function editBucket(MocOperations bucket_, BucketParams calldata params_) external onlyAuthorizedChanger {
        BucketIndex memory iBucket = bucketIndex[bucket_];
        if (!iBucket.exists) revert BucketDoesNotExist();

        IMocSwapper[] memory mocSwappers; // empty array, MocSwappers are edited using an specific setter
        _setRebalanceParams(bucket_, params_, mocSwappers);

        emit BucketChange(iBucket.index, address(bucket_), params_, mocSwappers);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */

    // Purposely left unused to save some state space to allow for future upgrades
    // slither-disable-next-line unused-state
    uint256[50] private __gap;
}
