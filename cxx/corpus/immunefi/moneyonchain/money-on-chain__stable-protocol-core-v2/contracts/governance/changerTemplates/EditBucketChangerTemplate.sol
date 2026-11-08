// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { IChangeContract } from "../../interfaces/IChangeContract.sol";
import { MocOperations, MocMultiCollateralGuard } from "../../multiCollateral/MocMultiCollateralGuard.sol";
import { BucketParams } from "../../multiCollateral/MocMultiCollateralBase.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title EditBucketChangerTemplate
 * @notice This contract is a ChangeContract intended to be used with Moc Aeropulus
 * governance system. It allows the addition of a new Bucket to a multi-collateral MOC V2 solution
 *
 * @dev IMPORTANT: This template provides a basic framework for bucket params editions,
 * but it's not intended to be use out of the box. Depending on the combination of params
 * you need to edit, you'll need to generate new methods, disable others and adjust the
 * `PARAMS_CHANGED` config. In this example, only the microLiquidationThrld is used as showcase.
 * Also please notice that params values, are not verify on the target contract, so it's desirable
 * that the changer itself do it. See `AddBucketChangerTemplate.sol` for reference.
 */

contract EditBucketChangerTemplate is IChangeContract, Ownable {
    error InvalidParamSetCount();
    error BucketDoesNotExist();

    // ------- Storage -------

    MocMultiCollateralGuard public immutable mocMultiCollateralGuard;
    MocOperations public immutable bucketToEdit;
    BucketParams internal bucketParams;
    uint256 public paramSet;
    uint256 private constant PARAMS_CHANGED = 1;

    /**
     * @notice Constructor
     * @param mocMultiCollateralGuard_ Address of the multi collateral guard
     * @param bucketToEdit_ Address of the bucket to edit, needs to belong to `mocMultiCollateralGuard_`
     */
    constructor(MocMultiCollateralGuard mocMultiCollateralGuard_, MocOperations bucketToEdit_) {
        mocMultiCollateralGuard = mocMultiCollateralGuard_;
        bucketToEdit = bucketToEdit_;

        (, bool exists, ) = mocMultiCollateralGuard_.bucketIndex(bucketToEdit_);
        if (!exists) revert BucketDoesNotExist();
    }

    /**
     * @notice set micro liquidation threshold
     * @param microLiquidationThrld_  new bucket micro liquidation Thrld
     */
    function setMicroLiquidationThrld(uint256 microLiquidationThrld_) external onlyOwner {
        if (paramSet != 0) revert InvalidParamSetCount();
        // Increase param set to allow execution
        paramSet++;

        // Only edits the microLiquidationThrld, all the other values are taken from the contracts itself
        bucketParams = BucketParams({
            acCoinbasePriceProvider: mocMultiCollateralGuard.acCoinbasePriceProvider(bucketToEdit),
            rebalanceExecFeeRecipient: mocMultiCollateralGuard.rebalanceExecFeeRecipient(bucketToEdit),
            rtcThrld: mocMultiCollateralGuard.rtcThrld(bucketToEdit),
            microLiquidationThrld: microLiquidationThrld_, // param edited
            penaltyRate: mocMultiCollateralGuard.penaltyRate(bucketToEdit)
        });
    }

    /**
     * @notice Returns the bucket Params configurations that's going to be edited
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
        if (paramSet != PARAMS_CHANGED) revert InvalidParamSetCount();
        mocMultiCollateralGuard.editBucket(bucketToEdit, bucketParams);
        // Blocks re-execution
        paramSet++;
    }
}
