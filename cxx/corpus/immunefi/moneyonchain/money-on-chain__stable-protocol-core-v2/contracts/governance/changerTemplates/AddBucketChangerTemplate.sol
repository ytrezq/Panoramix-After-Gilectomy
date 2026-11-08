// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { IChangeContract } from "../../interfaces/IChangeContract.sol";
import { IMocSwapper } from "../../interfaces/IMocSwapper.sol";
import { MocRC20 } from "../../tokens/MocRC20.sol";
import { MocOperations, MocMultiCollateralGuard, MocQueue } from "../../multiCollateral/MocMultiCollateralGuard.sol";
import { MocHelper } from "../../utils/MocHelper.sol";
import { BucketParams } from "../../multiCollateral/MocMultiCollateralBase.sol";

/**
 * @title AddBucketChangerTemplate
 * @notice This contract is a ChangeContract intended to be used with Moc Aeropulus
 * governance system. It allows the addition of a new Bucket to a multi-collateral MOC V2 solution
 */
contract AddBucketChangerTemplate is IChangeContract, MocHelper {
    bytes32 private constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 private constant BURNER_ROLE = keccak256("BURNER_ROLE");

    error TpAmountUnequalLength();
    error TpNotInBaseBucket(address tp_);
    error IncompatibleBucket();

    // ------- Storage -------

    MocOperations public immutable bucket;
    MocMultiCollateralGuard public immutable mocMultiCollateralGuard;
    BucketParams public bucketParams;
    IMocSwapper[] public mocSwappers;

    /**
     * @notice Constructor
     * @param mocMultiCollateralGuard_ Address of the multi collateral guard for this bucket to be added
     * @param bucket_ Address of the bucket to be added
     * @param bucketParams_ params of bucket to add:
     *      acCoinbasePriceProvider bucket AC to coinbase price provider
     *      rtcThrld target coverage to reach during a micro liquidation [PREC]
     *      microLiquidationThrld threshold to trigger the micro liquidation [PREC]
     *      penaltyRate additional pct of AC sent to the target bucket during a micro liquidation [PREC]
     * @param mocSwappers_ MocSwapper contracts for the originBucketAC / targetBucketAC pool
     */
    constructor(
        MocMultiCollateralGuard mocMultiCollateralGuard_,
        MocOperations bucket_,
        BucketParams memory bucketParams_,
        IMocSwapper[] memory mocSwappers_
    ) {
        mocMultiCollateralGuard = mocMultiCollateralGuard_;
        bucket = bucket_;
        bucketParams = bucketParams_;
        mocSwappers = mocSwappers_;

        // validate bucket parameters. Reverts if something is wrong
        validateParameters(bucket, mocSwappers_);
        // validate changer conditions. Reverts if something is wrong
        validateChanger(mocMultiCollateralGuard_, bucket_);
    }

    /**
     * @notice Returns the bucket Params configurations that's going to be added
     */
    function getBucketParams() external view returns (BucketParams memory) {
        return bucketParams;
    }

    /**
     * @notice Execute the changes, adding the new bucket to the given mocMultiCollateralGuard
     * @dev Should be called by the governor, but this contract does not check that explicitly
     * because it is not its responsibility in the current architecture
     */
    function execute() external {
        // validate bucket parameters. Reverts if something is wrong
        validateParameters(bucket, mocSwappers);
        // validate changer conditions. Reverts if something is wrong
        validateChanger(mocMultiCollateralGuard, bucket);

        for (uint256 i = 0; i < bucket.getTpAmount(); i++) {
            MocRC20 tpi = MocRC20(address(bucket.tpTokens(i)));
            // Now the new bucket will be able to mint and redeem this Pegged Token
            tpi.grantRole(MINTER_ROLE, address(bucket));
            tpi.grantRole(BURNER_ROLE, address(bucket));
        }

        mocMultiCollateralGuard.addBucket(bucket, bucketParams, mocSwappers);
        // unpause the new bucket
        MocQueue(bucket.mocQueue()).unpause();
    }

    /**
     * @notice validate changer conditions. Reverts if something is wrong
     * @param mocMultiCollateralGuard_ Address of the MocMultiCollateralGuard contract
     *  peggedToken_ Pegged Token to add
     * @param bucket_ Address of the bucket to be added
     */
    function validateChanger(MocMultiCollateralGuard mocMultiCollateralGuard_, MocOperations bucket_) public view {
        // New bucket must be empty, no TC minted
        if (bucket_.nTCcb() != 0) revert IncompatibleBucket();
        // New bucket needs to share same governor
        if (mocMultiCollateralGuard_.governor() != bucket_.governor()) revert IncompatibleBucket();
        // New bucket queue needs to share same governor
        if (mocMultiCollateralGuard_.governor() != MocQueue(bucket.mocQueue()).governor()) revert IncompatibleBucket();
        // New bucket queue, must be assigned to the given multiCollateralGuard
        if (MocQueue(bucket_.mocQueue()).mocMultiCollateralGuard() != mocMultiCollateralGuard_)
            revert IncompatibleBucket();
        // New bucket queue needs to be paused
        if (!MocQueue(bucket.mocQueue()).paused()) revert IncompatibleBucket();
        // New bucket queue needs to be empty
        if (!MocQueue(bucket.mocQueue()).isEmpty()) revert IncompatibleBucket();

        MocOperations baseBucket = mocMultiCollateralGuard.buckets(0);
        // Every new Bucket TP, needs to be present on base Bucket
        if (baseBucket.getTpAmount() != bucket.getTpAmount()) revert TpAmountUnequalLength();
        for (uint256 i = 0; i < bucket.getTpAmount(); i++) {
            MocRC20 tpi = MocRC20(address(bucket.tpTokens(i)));
            (, bool exists) = baseBucket.peggedTokenIndex(address(tpi));
            if (!exists) revert TpNotInBaseBucket(address(tpi));
        }
    }

    /**
     * @notice validate bucket parameters. Reverts if something is wrong
     * @param bucket_ Address of the bucket to be added
     * @param mocSwappers_ MocSwapper contracts for the originBucketAC / targetBucketAC pool
     */
    function validateParameters(MocOperations bucket_, IMocSwapper[] memory mocSwappers_) public view {
        if (mocSwappers_.length != mocMultiCollateralGuard.getBucketAmount()) revert InvalidValue();
        if (bucket_.protThrld() <= ONE) revert InvalidValue();
        _checkLessThanOne(bucket_.feeRetainer());
        _checkLessThanOne(bucket_.tcMintFee());
        _checkLessThanOne(bucket_.tcRedeemFee());
        _checkLessThanOne(bucket_.swapTPforTPFee());
        _checkLessThanOne(bucket_.swapTPforTCFee());
        _checkLessThanOne(bucket_.swapTCforTPFee());
        _checkLessThanOne(bucket_.redeemTCandTPFee());
        _checkLessThanOne(bucket_.mintTCandTPFee());
        _checkLessThanOne(bucket_.feeTokenPct());
        _checkLessThanOne(bucket_.successFee() + bucket_.appreciationFactor());
    }
}
