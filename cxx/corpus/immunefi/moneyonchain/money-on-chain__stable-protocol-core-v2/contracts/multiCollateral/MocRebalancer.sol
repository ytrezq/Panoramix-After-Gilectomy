// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { MocMultiCollateralBase, BucketParams, MocOperations, IMocSwapper } from "./MocMultiCollateralBase.sol";
import { IPriceProvider } from "../interfaces/IPriceProvider.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MocRebalancer
 * @notice It provides the methods to articulate the rebalance of AC and TP between buckets
 * It is used for:
 *  - micro liquidations: when a bucket coverage goes below the micro liquidation threshold and
 *   a certain amount of TP must be rebalanced to another bucket, the one with the best score
 *  - liquidation: when a bucket coverage goes below the liquidation threshold and
 *   all its TPs must be rebalanced to another bucket
 *  Both process can be limited by a max amount of AC allowed to swap and the target bucket capacity to
 *  receive the tokens. If there is one of those limits, it should be executed continuously in successive txs until the
 *  necessary amount of TPs were rebalanced.
 *  In a liquidation case, that could mean, remove all the buckets TPs and be full liquidated. After that
 *  the bucket will be removed from the MultiCollateral system
 *
 */
abstract contract MocRebalancer is MocMultiCollateralBase {
    address private constant COINBASE = address(0);
    // ------- Custom Errors -------
    error MissingProviderPrice(address priceProviderAddress_);
    error MicroLiquidationNotAvailable();
    error LiquidationNotAvailable();
    error NoTargetBucketAvailableToRebalance();
    error BucketNotLiquidated();
    error CoinbaseRebalanceTransferFailed();

    // ------- Events -------
    event MicroLiquidationExecuted(
        address executor_,
        address indexed originBucket,
        address indexed targetBucket_,
        address indexed targetTP_,
        uint256 qACtoSwap_,
        uint256 qACOut_,
        uint256 qTPtoRebalance_,
        uint256 qACExecFee_
    );
    event PartialLiquidationExecuted(
        address executor_,
        address indexed originBucket,
        address indexed targetBucket_,
        address indexed targetTP_,
        uint256 qACtoSwap_,
        uint256 qACOut_,
        uint256 qTPtoRebalance_,
        uint256 qACExecFee_
    );
    event BucketLiquidated(address indexed originBucket);
    event CoinbaseExecFeePaymentFailed(uint256 executionFee_);

    // ------- Storage Rebalance -------
    // bucket AC to coinbase price provider. Not used for coinbase bucket
    mapping(MocOperations bucket => IPriceProvider acCoinbasePriceProvider) public acCoinbasePriceProvider;
    // bucket rebalance execution fee recipient. Not used for coinbase bucket
    mapping(MocOperations bucket => address rebalanceExecFeeRecipient) public rebalanceExecFeeRecipient;
    // MocSwapper contracts for the originBucketAC / targetBucketAC pool
    mapping(MocOperations originBucket => mapping(MocOperations targetBucket => IMocSwapper mocSwapper))
        public mocSwappers;

    // ------- Storage MicroLiquidation -------
    // coinbase micro liquidation execution fee. Paid from the rebalanced bucket to the executor
    uint256 public microLiquidationExecCost;
    // target coverage to reach during a micro liquidation [PREC]
    mapping(MocOperations bucket => uint256 rtcThrld) public rtcThrld;
    // threshold to trigger the micro liquidation [PREC]
    mapping(MocOperations bucket => uint256 microLiquidationThrld) public microLiquidationThrld;
    // additional pct of AC sent to the target bucket during a micro liquidation [PREC]
    mapping(MocOperations bucket => uint256 penaltyRate) public penaltyRate;

    // ------- Storage Liquidation -------
    // coinbase liquidation execution fee. Paid from the liquidated bucket to the executor
    uint256 public liquidationExecCost;

    // ------- Storage Execution Fees -------
    // address who receives all the coinbase execution fees(queue and coinbase bucket rebalancing executions)
    address payable public coinbaseExecFeeRecipient;

    // ------- Initializer -------
    /**
     * @notice contract initializer
     * @param microLiquidationExecCost_ coinbase micro liquidation execution fee. Paid from the
     *  rebalanced bucket to the executor
     * @param liquidationExecCost_ coinbase liquidation execution fee. Paid from the liquidated bucket to the executor
     * @param coinbaseExecFeeRecipient_ address who receives all the coinbase execution fees
     */
    function __MocRebalancer_init(
        uint256 microLiquidationExecCost_,
        uint256 liquidationExecCost_,
        address payable coinbaseExecFeeRecipient_
    ) internal onlyInitializing {
        microLiquidationExecCost = microLiquidationExecCost_;
        liquidationExecCost = liquidationExecCost_;
        coinbaseExecFeeRecipient = coinbaseExecFeeRecipient_;
    }

    // ------- Internal Functions -------
    /**
     * @inheritdoc MocMultiCollateralBase
     */
    function _setRebalanceParams(
        MocOperations bucket_,
        BucketParams calldata params_,
        IMocSwapper[] memory mocSwappers_
    ) internal override {
        // bucket AC to coinbase price provider
        acCoinbasePriceProvider[bucket_] = IPriceProvider(params_.acCoinbasePriceProvider);
        rebalanceExecFeeRecipient[bucket_] = params_.rebalanceExecFeeRecipient;
        // target coverage to reach during a micro liquidation [PREC]
        rtcThrld[bucket_] = params_.rtcThrld;
        // threshold to trigger the micro liquidation [PREC]
        microLiquidationThrld[bucket_] = params_.microLiquidationThrld;
        // additional pct of AC sent to the target bucket during a micro liquidation [PREC]
        penaltyRate[bucket_] = params_.penaltyRate;
        // fill the map with the MocSwapper contracts for each bucket
        for (uint256 j = 0; j < mocSwappers_.length; j = unchecked_inc(j)) {
            mocSwappers[buckets[j]][bucket_] = mocSwappers_[j];
            mocSwappers[bucket_][buckets[j]] = mocSwappers_[j];
        }
    }

    /**
     * @notice transfers the execution fee to the coinbaseExecFeeRecipient
     * @dev emit CoinbaseExecFeePaymentFailed if the transfer fails
     * @param executionFee_ amount of execution fee to transfer
     */
    function _coinbaseExecFeeTransfer(uint256 executionFee_) internal {
        if (executionFee_ > 0) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = coinbaseExecFeeRecipient.call{ value: executionFee_ }("");
            // transfer failures are expected to be exceptional. In such cases, an event is emitted
            // and the funds remain in the contract, to be recovered later through governance.
            if (!success) emit CoinbaseExecFeePaymentFailed(executionFee_);
        }
    }

    /**
     * @notice calculates target bucket to receive micro liquidation given a `originBucket_` and the buckets array
     * @param originBucket_ origin bucket to rebalance
     * @param buckets_ buckets array
     * @return targetBucket target bucket to receive micro liquidation
     * @return targetBucketCglb target bucket coverage [PREC]
     */
    function _calcTargetBucketToRebalanceOnMicroLiquidation(
        MocOperations originBucket_,
        MocOperations[] memory buckets_
    ) internal view returns (MocOperations targetBucket, uint256 targetBucketCglb) {
        uint256 maxScore;
        for (uint256 j = 0; j < buckets_.length; j = unchecked_inc(j)) {
            MocOperations currBucket = buckets_[j];
            if (currBucket != originBucket_) {
                uint256 bucketCglb = currBucket.getCglb();
                // empty buckets are not eligible to receive micro liquidations, so they are filtered out
                if (bucketCglb > rtcThrld[currBucket] && bucketCglb < UINT256_MAX) {
                    // [PREC] = [PREC] * [N] / [PREC]
                    uint256 bucketScore = (bucketCglb * currBucket.getTotalACavailable()) / currBucket.getCtargemaCA();
                    if (bucketScore > maxScore) {
                        maxScore = bucketScore;
                        targetBucket = currBucket;
                        targetBucketCglb = bucketCglb;
                    }
                }
            }
        }
    }

    /**
     * @notice calculates target bucket to receive liquidation given a `originBucket_` and the buckets array
     * @param originBucket_ origin bucket to rebalance
     * @param buckets_ buckets array
     * @return targetBucket target bucket to receive liquidation
     * @return targetBucketCglb target bucket coverage [PREC]
     * @return thrld threshold to limit the amount of TP available to mint on target bucket
     */
    function _calcTargetBucketToRebalanceOnLiquidation(
        MocOperations originBucket_,
        MocOperations[] memory buckets_
    ) internal view returns (MocOperations targetBucket, uint256 targetBucketCglb, uint256 thrld) {
        // Temporary arrays to store by matching Cglb criteria [rtcThrld, liqThrld, 0] respectively
        uint256[] memory maxScore = new uint256[](3);
        MocOperations[] memory targets = new MocOperations[](3);
        uint256[] memory targetBucketCglbs = new uint256[](3);
        uint256[] memory thrlds = new uint256[](3);

        for (uint256 j = 0; j < buckets_.length; j = unchecked_inc(j)) {
            MocOperations currBucket = buckets_[j];
            if (currBucket != originBucket_) {
                uint256 liqThrld = currBucket.liqThrld();
                uint256 bucketCglb = currBucket.getCglb();
                // empty buckets are not eligible to receive liquidations, so they are filtered out
                if (bucketCglb < UINT256_MAX) {
                    // [PREC] = [PREC] * [N] / [PREC]
                    uint256 bucketScore = (bucketCglb * currBucket.getTotalACavailable()) / currBucket.getCtargemaCA();
                    if (bucketScore > maxScore[2]) {
                        maxScore[2] = bucketScore;
                        targets[2] = currBucket;
                        targetBucketCglbs[2] = bucketCglb;
                        thrlds[2] = 0;
                    }
                    if (bucketCglb > liqThrld) {
                        if (bucketScore > maxScore[1]) {
                            maxScore[1] = bucketScore;
                            targets[1] = currBucket;
                            targetBucketCglbs[1] = bucketCglb;
                            thrlds[1] = liqThrld;
                        }
                        uint256 bucketRTCThrld = rtcThrld[currBucket];
                        if (bucketCglb > bucketRTCThrld && bucketScore > maxScore[0]) {
                            maxScore[0] = bucketScore;
                            targets[0] = currBucket;
                            targetBucketCglbs[0] = bucketCglb;
                            thrlds[0] = bucketRTCThrld;
                        }
                    }
                }
            }
        }
        // If there is any over the rtcThrld, we return that one
        if (address(targets[0]) != address(0)) return (targets[0], targetBucketCglbs[0], thrlds[0]);
        // Else, if there is any over the liqThrld
        if (address(targets[1]) != address(0)) return (targets[1], targetBucketCglbs[1], thrlds[1]);
        // Else, we return the best ranked
        return (targets[2], targetBucketCglbs[2], thrlds[2]);
    }

    /**
     * @notice calculates target bucket to receive micro liquidation given a `originBucket_` and the buckets array
     * @param originBucket_ origin bucket to rebalance
     * @return targetBucket target bucket to receive micro liquidation
     * @return targetBucketCglb target bucket coverage [PREC]
     */
    function _getTargetBucketToRebalanceOnMicroLiquidation(
        MocOperations originBucket_
    ) internal returns (MocOperations targetBucket, uint256 targetBucketCglb) {
        MocOperations[] memory bucketsArray = buckets;
        _updatesCtargemaCA(bucketsArray);
        return _calcTargetBucketToRebalanceOnMicroLiquidation(originBucket_, bucketsArray);
    }

    /**
     * @notice calculates target bucket to receive liquidation given a `originBucket_` and the buckets array
     * @param originBucket_ origin bucket to rebalance
     * @return targetBucket target bucket to receive liquidation
     * @return targetBucketCglb target bucket coverage [PREC]
     * @return thrld threshold to limit the amount of TP available to mint on target bucket
     */
    function _getTargetBucketToRebalanceOnLiquidation(
        MocOperations originBucket_
    ) internal returns (MocOperations targetBucket, uint256 targetBucketCglb, uint256 thrld) {
        MocOperations[] memory bucketsArray = buckets;
        _updatesCtargemaCA(bucketsArray);
        return _calcTargetBucketToRebalanceOnLiquidation(originBucket_, bucketsArray);
    }

    /**
     * @notice gets target TP to rebalance given a `originBucket_`
     * @param originBucket_ origin bucket to rebalance
     * @return targetTP target TP to rebalance
     */
    function _getTPMostLockedAC(MocOperations originBucket_) internal view returns (address) {
        uint256 tpAmount = originBucket_.getTpAmount();
        if (tpAmount == 1) return address(originBucket_.tpTokens(0));

        uint256 maxLckAC;
        uint256 iTPMaxLckAC;
        for (uint256 i = 0; i < tpAmount; i = unchecked_inc(i)) {
            uint256 lckAC = originBucket_.getLckACByTP(i);
            if (lckAC > maxLckAC) {
                maxLckAC = lckAC;
                iTPMaxLckAC = i;
            }
        }
        return address(originBucket_.tpTokens(iTPMaxLckAC));
    }

    /**
     * @notice calculates TP available to mint for a `targetBucket_` and a `targetTP_`
     * @param targetBucket_ target bucket to rebalance
     * @param targetBucketCglb_ target bucket coverage [PREC]
     * @param targetBucketPACtp_ pACtp of the target TP for the target bucket
     * @param thrld_ threshold to limit the amount of TP available to mint on target bucket
     * @return tpAvailable amount of TP available on target bucket
     *
     */
    function _calcTPAvailableTargetBucket(
        MocOperations targetBucket_,
        uint256 targetBucketCglb_,
        uint256 targetBucketPACtp_,
        uint256 thrld_
    ) internal view returns (uint256) {
        if (thrld_ <= ONE) return UINT256_MAX;
        // [PREC²] = ([PREC] - [PREC]) * [N]) * [PREC]
        uint256 num = (targetBucketCglb_ - thrld_) * targetBucket_.getTotalACavailable() * targetBucketPACtp_;
        // [PREC²] = [PREC] * ([PREC] - [PREC])
        uint256 den = targetBucketCglb_ * (thrld_ - ONE);
        // [N] = [PREC²] / [PREC²]
        return num / den;
    }

    /**
     * @notice fetch AC coinbase price
     * @param originBucket_ origin bucket to rebalance
     * @return AC coinbase price
     */
    function _peekACCoinbasePrice(MocOperations originBucket_) internal view returns (uint256) {
        (bytes32 acCoinbasePrice, bool has) = acCoinbasePriceProvider[originBucket_].peek();
        if (!has) revert MissingProviderPrice(address(acCoinbasePriceProvider[originBucket_]));
        return uint256(acCoinbasePrice);
    }

    /**
     * @notice calculates qAC and qTP to rebalance
     * @param originBucket_ origin bucket to rebalance
     * @param targetBucket_ target bucket to rebalance
     * @param targetTP_ target TP to rebalance
     * @param targetBucketCglb_ target bucket coverage [PREC]
     * @param targetBucketThrld_ threshold to limit the amount of TP available to mint on target bucket
     * @param isMicroLiquidation_ true if it is a micro liquidation
     * @param baseGasPrice_ base gas price you want the execFee calculation to use
     * @return mocSwapper swapper contract to use
     * @return tokenIn token to send
     * @return tokenOut token to receive
     * @return qACToSwap amount of AC from origin bucket to swap
     * @return qTPToRebalance amount of TP to rebalance
     * @return qACmin minimum amount of AC to receive on the swap
     * @return qACExecFee amount of AC for execution fee
     */
    function _calcACAndTPtoRebalance(
        MocOperations originBucket_,
        MocOperations targetBucket_,
        address targetTP_,
        uint256 targetBucketCglb_,
        uint256 targetBucketThrld_,
        bool isMicroLiquidation_,
        uint256 baseGasPrice_
    )
        internal
        view
        returns (
            IMocSwapper mocSwapper,
            address tokenIn,
            address tokenOut,
            uint256 qACToSwap,
            uint256 qTPToRebalance,
            uint256 qACmin,
            uint256 qACExecFee
        )
    {
        mocSwapper = mocSwappers[originBucket_][targetBucket_];
        tokenIn = originBucket_.acToken();
        tokenOut = targetBucket_.acToken();
        uint256 maxACtoSwap = mocSwapper.getSafeMaxAmountToSwap(tokenIn, tokenOut);
        uint256 acCoinbasePrice = tokenIn != COINBASE ? _peekACCoinbasePrice(originBucket_) : ONE;
        uint256 pACtp = originBucket_.getPACtp(targetTP_);
        uint256 targetBucketPACtp = targetBucket_.getPACtp(targetTP_);
        uint256 totalACavailable = originBucket_.getTotalACavailable();
        uint256 lckAC = originBucket_.getLckAC();

        // Calculate the max amount of TP to rebalance
        qTPToRebalance = Math.min(
            originBucket_.getNTP(targetTP_),
            _calcTPAvailableTargetBucket(targetBucket_, targetBucketCglb_, targetBucketPACtp, targetBucketThrld_)
        );

        if (isMicroLiquidation_) {
            uint256 originBucketThrld = rtcThrld[originBucket_];
            // [N] = [N] * [PREC] / [PREC]
            qACExecFee = _divPrec(microLiquidationExecCost * baseGasPrice_, acCoinbasePrice);
            // [PREC] = [PREC] + [PREC]
            uint256 onePlusPR = ONE + penaltyRate[originBucket_];
            // calculates the amount of AC to reach the target RTC coverage
            // [N] = [PREC] * [N] + [N] * [PREC] - [N] * [PREC] / [PREC] - [PREC]
            uint256 qACOnTP = (originBucketThrld * lckAC + qACExecFee * PRECISION - totalACavailable * PRECISION) /
                (originBucketThrld - onePlusPR);

            // [N] = [N] * [PREC] / [PREC]
            uint256 maxACAvailableOnTP = _divPrec(qTPToRebalance, pACtp);
            // if there is a TP limit on the origin or target bucket we use that amount of AC instead
            if (qACOnTP > maxACAvailableOnTP) {
                qACOnTP = maxACAvailableOnTP;
            } else {
                // [N] = [N] * [PREC] / [PREC]
                qTPToRebalance = _mulPrec(qACOnTP, pACtp);
            }

            // [N] = [N] * [PREC] / [PREC]
            qACToSwap = _mulPrec(qACOnTP, onePlusPR);
            if (qACToSwap > maxACtoSwap) {
                qACToSwap = maxACtoSwap;
                // [N] = [N] * [PREC] / [PREC]
                qTPToRebalance = (qACToSwap * pACtp) / onePlusPR;
            }
            // we send AC increased by the penalty rate, so that is the slippage allowed in the swap
            // [N] = [N] * [PREC] / [PREC]
            qACmin = _divPrec(qTPToRebalance, targetBucketPACtp);
        } else {
            // [N] = [N] * [PREC] / [PREC]
            qACExecFee = _divPrec(liquidationExecCost * baseGasPrice_, acCoinbasePrice);
            // prevent underflow in extreme cases where the exec fee is higher than the total AC available in the bucket
            if (qACExecFee >= totalACavailable) qACExecFee = 0;
            // calculates TP liquidation price
            // [PREC] = [PREC] * [N] / ([N] - [N])
            uint256 tpLiqPrice = (pACtp * lckAC) / (totalACavailable - qACExecFee);
            // [N] = [N] * [PREC] / [PREC]
            qACToSwap = _divPrec(qTPToRebalance, tpLiqPrice);

            // if there is a AC limit on the max amount allowed to swap parameter we use it instead
            if (qACToSwap > maxACtoSwap) {
                qACToSwap = maxACtoSwap;
                // [N] = [N] * [PREC] / [PREC]
                qTPToRebalance = _mulPrec(qACToSwap, tpLiqPrice);
            }
            // if we are removing all the AC from the bucket, ensure do not revert by underflow due rounding errors
            if (qACToSwap + qACExecFee > totalACavailable) {
                // if qACExecFee is 0 or very low, it may not be enough to absorb rounding error
                if (totalACavailable > qACToSwap) {
                    // the difference is absorbed on the qACExecFee
                    qACExecFee = totalACavailable - qACToSwap;
                } else {
                    qACToSwap = totalACavailable;
                    qACExecFee = 0;
                }
            }
            // in a liquidation scenario where coverage < 1, the qAC sent will be less than the TP-equivalent value.
            // as a result, the target bucket must absorb the loss. We use the normalization factor  to determine the
            // equivalence between both ACs and apply the penalty rate percentage as slippage in the swap.
            // [N] = [N] * [PREC] * ([PREC] - [PREC]) / [PREC²]
            qACmin = (qACToSwap * pACtp * (ONE - penaltyRate[targetBucket_])) / (targetBucketPACtp * PRECISION);
        }
        return (mocSwapper, tokenIn, tokenOut, qACToSwap, qTPToRebalance, qACmin, qACExecFee);
    }

    /**
     * @notice moves AC and TP from `originBucket_` to `targetBucket_'
     * @param originBucket_ origin bucket to rebalance
     * @param targetBucket_ target bucket to rebalance
     * @param tokenIn_ token to send
     * @param tokenOut_ token to receive
     * @param mocSwapper_ swapper contract to use
     * @param targetTP_ target TP to rebalance
     * @param qACtoSwap_ amount of AC from origin bucket to swap
     * @param qTPtoRebalance_ amount of TP to rebalance
     * @param qACmin_ minimum amount of AC to receive on the swap
     * @param qACExecFee_ amount of AC for execution fee
     * @return qACOut amount of AC sent to target bucket
     */
    function _rebalanceBuckets(
        MocOperations originBucket_,
        MocOperations targetBucket_,
        address tokenIn_,
        address tokenOut_,
        IMocSwapper mocSwapper_,
        address targetTP_,
        uint256 qACtoSwap_,
        uint256 qTPtoRebalance_,
        uint256 qACmin_,
        uint256 qACExecFee_
    ) internal returns (uint256 qACOut) {
        // subtract TP and AC from the origin bucket. AC is sent to this address
        originBucket_.rebalance(targetTP_, qTPtoRebalance_, qACtoSwap_ + qACExecFee_);

        if (tokenIn_ == COINBASE) {
            qACOut = mocSwapper_.swapCoinbase{ value: qACtoSwap_ }(tokenOut_, qACmin_, address(targetBucket_));
            _coinbaseExecFeeTransfer(qACExecFee_);
        } else {
            SafeERC20.forceApprove(IERC20(tokenIn_), address(mocSwapper_), qACtoSwap_);
            qACOut = mocSwapper_.swapRC20(tokenIn_, tokenOut_, qACtoSwap_, qACmin_, address(targetBucket_));
            SafeERC20.safeTransfer(IERC20(tokenIn_), rebalanceExecFeeRecipient[originBucket_], qACExecFee_);
        }

        // add TP to the target bucket
        targetBucket_.acceptRebalance(targetTP_, qTPtoRebalance_);
        // take account the injected collateral
        targetBucket_.refreshACBalance();
    }

    /**
     * @notice set liquidated and remove bucket form the multi collateral protocol
     * @param bucket_ bucket to remove and liquidate
     */
    function _liquidateAndRemoveBucket(MocOperations bucket_) internal {
        bucket_.setLiquidated();
        BucketIndex storage iBucketLiquidated = bucketIndex[bucket_];
        emit BucketLiquidated(address(bucket_));

        // the last bucket cannot be removed from the buckets array because view function will fail
        // and executeLiquidatedBucket will be useless. If this situation arises, it is recommended to deploy
        // an entirely new protocol to get back in the game.
        if (buckets.length == 1) {
            iBucketLiquidated.exists = false;
            iBucketLiquidated.liquidated = true;
            return;
        }

        MocOperations bucketToMove = buckets[buckets.length - 1];

        // move last bucket to the new index on the array
        buckets[iBucketLiquidated.index] = bucketToMove;
        // set new array index
        bucketIndex[bucketToMove].index = iBucketLiquidated.index;
        // reset bucket removed index
        iBucketLiquidated.index = 0;
        iBucketLiquidated.exists = false;
        iBucketLiquidated.liquidated = true;

        // remove last item from the array
        buckets.pop();
    }

    // ------- External Functions -------

    /**
     * @notice verifies if bucket micro liquidation is available,
     *  checking if bucket coverage > liquidation && bucket coverage <= micro liquidation
     * @param originBucket_ origin bucket to verify
     * @return true if micro liquidation threshold is reached, false otherwise
     */
    function isMicroLiquidationAvailable(MocOperations originBucket_) public view returns (bool) {
        return isMicroLiquidationAvailableWithPrices(originBucket_, originBucket_.getPACtps());
    }

    /**
     * @notice verifies if bucket micro liquidation is available,
     *  checking if bucket coverage > liquidation && bucket coverage <= micro liquidation
     * @param originBucket_ origin bucket to verify
     * @param pACtps_ all tps prices for the given bucket [PREC]
     * @return true if micro liquidation threshold is reached, false otherwise
     */
    function isMicroLiquidationAvailableWithPrices(
        MocOperations originBucket_,
        uint256[] memory pACtps_
    ) public view returns (bool) {
        uint256 cglb = originBucket_.calcCglb(pACtps_);
        return (cglb > originBucket_.liqThrld() && cglb <= microLiquidationThrld[originBucket_]);
    }

    /**
     * @notice verifies if liquidation threshold has been reached and liq is enabled on `originBucket_`
     * @param originBucket_ origin bucket to verify
     * @return true if liquidation threshold is reached, false otherwise
     */
    function isLiquidationAvailable(MocOperations originBucket_) public view returns (bool) {
        return isLiquidationAvailableWithPrices(originBucket_, originBucket_.getPACtps());
    }

    /**
     * @notice verifies if liquidation threshold has been reached and liq is enabled on `originBucket_`
     * @param originBucket_ origin bucket to verify
     * @param pACtps_ all tps prices for the given bucket [PREC]
     * @return true if liquidation threshold is reached, false otherwise
     */
    function isLiquidationAvailableWithPrices(
        MocOperations originBucket_,
        uint256[] memory pACtps_
    ) public view returns (bool) {
        bool liqEnable = originBucket_.liqEnabled() && !originBucket_.liquidated();
        if (liqEnable) {
            return originBucket_.calcCglb(pACtps_) <= originBucket_.liqThrld();
        }
        return false;
    }

    /**
     * @notice gets qAC and qTP to rebalance on a micro liquidation
     * @param originBucket_ origin bucket to rebalance
     * @param baseGasPrice_ base gas price you want the execFee calculation to use, zero for network basefee
     * @return targetBucket target bucket to rebalance
     * @return targetTP target TP to rebalance
     * @return qACToSwap amount of AC from origin bucket to swap
     * @return qTPToRebalance amount of TP to rebalance
     * @return qACExecFee amount of AC for execution fee
     */
    function getACAndTPtoRebalanceOnMicroLiquidation(
        MocOperations originBucket_,
        uint256 baseGasPrice_
    )
        external
        view
        returns (
            MocOperations targetBucket,
            address targetTP,
            uint256 qACToSwap,
            uint256 qTPToRebalance,
            uint256 qACExecFee
        )
    {
        if (!isMicroLiquidationAvailable(originBucket_)) return (MocOperations(address(0)), address(0), 0, 0, 0);
        uint256 targetBucketCglb;
        (targetBucket, targetBucketCglb) = _calcTargetBucketToRebalanceOnMicroLiquidation(originBucket_, buckets);
        if (address(targetBucket) == address(0)) return (MocOperations(address(0)), address(0), 0, 0, 0);
        targetTP = _getTPMostLockedAC(originBucket_);

        (, , , qACToSwap, qTPToRebalance /*qACmin*/, , qACExecFee) = _calcACAndTPtoRebalance(
            originBucket_,
            targetBucket,
            targetTP,
            targetBucketCglb,
            rtcThrld[targetBucket],
            true /*isMicroLiquidation == true*/,
            baseGasPrice_ == 0 ? block.basefee : baseGasPrice_
        );
        return (targetBucket, targetTP, qACToSwap, qTPToRebalance, qACExecFee);
    }

    /**
     * @notice gets qAC and qTP to rebalance on a liquidation
     * @param originBucket_ origin bucket to liquidate
     * @param baseGasPrice_ base gas price you want the execFee calculation to use, zero for network basefee
     * @return targetBucket target bucket to receive liquidation
     * @return targetTP target TP to rebalance
     * @return qACToSwap amount of AC from origin bucket to swap
     * @return qTPToRebalance amount of TP to rebalance
     * @return qACExecFee amount of AC for execution fee
     */
    function getACAndTPtoRebalanceOnLiquidation(
        MocOperations originBucket_,
        uint256 baseGasPrice_
    )
        external
        view
        returns (
            MocOperations targetBucket,
            address targetTP,
            uint256 qACToSwap,
            uint256 qTPToRebalance,
            uint256 qACExecFee
        )
    {
        if (!isLiquidationAvailable(originBucket_)) return (MocOperations(address(0)), address(0), 0, 0, 0);
        uint256 targetBucketCglb;
        uint256 thrld;
        (targetBucket, targetBucketCglb, thrld) = _calcTargetBucketToRebalanceOnLiquidation(originBucket_, buckets);
        if (address(targetBucket) == address(0)) return (MocOperations(address(0)), address(0), 0, 0, 0);
        targetTP = _getTPMostLockedAC(originBucket_);

        (, , , qACToSwap, qTPToRebalance /*qACmin*/, , qACExecFee) = _calcACAndTPtoRebalance(
            originBucket_,
            targetBucket,
            targetTP,
            targetBucketCglb,
            thrld,
            false /*isMicroLiquidation == false*/,
            baseGasPrice_ == 0 ? block.basefee : baseGasPrice_
        );
        return (targetBucket, targetTP, qACToSwap, qTPToRebalance, qACExecFee);
    }

    /**
     * @notice execute micro liquidation on `originBucket_`
     * @param originBucket_ origin bucket to rebalance
     */
    // slither-disable-next-line reentrancy-no-eth
    function execMicroLiquidation(MocOperations originBucket_) external notPaused nonReentrant {
        BucketIndex storage iBucket = bucketIndex[originBucket_];
        if (!iBucket.exists) revert BucketDoesNotExist();
        // Before evaluating micro liquidation, we need to make sure injected collateral is accounted
        originBucket_.refreshACBalance();
        if (!isMicroLiquidationAvailable(originBucket_)) revert MicroLiquidationNotAvailable();

        (MocOperations targetBucket, uint256 targetBucketCglb) = _getTargetBucketToRebalanceOnMicroLiquidation(
            originBucket_
        );
        if (address(targetBucket) == address(0)) revert NoTargetBucketAvailableToRebalance();

        address targetTP = _getTPMostLockedAC(originBucket_);
        (
            IMocSwapper mocSwapper,
            address tokenIn,
            address tokenOut,
            uint256 qACToSwap,
            uint256 qTPToRebalance,
            uint256 qACmin,
            uint256 qACExecFee
        ) = _calcACAndTPtoRebalance(
                originBucket_,
                targetBucket,
                targetTP,
                targetBucketCglb,
                rtcThrld[targetBucket],
                true /*isMicroLiquidation == true*/,
                block.basefee
            );

        uint256 qACOut = _rebalanceBuckets(
            originBucket_,
            targetBucket,
            tokenIn,
            tokenOut,
            mocSwapper,
            targetTP,
            qACToSwap,
            qTPToRebalance,
            qACmin,
            qACExecFee
        );

        emit MicroLiquidationExecuted(
            msg.sender,
            address(originBucket_),
            address(targetBucket),
            address(targetTP),
            qACToSwap,
            qACOut,
            qTPToRebalance,
            qACExecFee
        );
    }

    /**
     * @notice execute liquidation if threshold has been reached and liq is enabled on `originBucket_`
     * @param originBucket_ origin bucket to evaluate liquidation
     */
    // slither-disable-next-line reentrancy-no-eth
    function execLiquidation(MocOperations originBucket_) external notPaused nonReentrant {
        BucketIndex storage iBucket = bucketIndex[originBucket_];
        if (!iBucket.exists) revert BucketDoesNotExist();
        // Before evaluating liquidation, we need to make sure injected collateral is accounted
        originBucket_.refreshACBalance();
        if (!isLiquidationAvailable(originBucket_)) revert LiquidationNotAvailable();

        // if it is the only bucket available execute the single liquidation
        if (buckets.length == 1) {
            originBucket_.liquidate();
            _liquidateAndRemoveBucket(originBucket_);
        } else {
            (
                MocOperations targetBucket,
                uint256 targetBucketCglb,
                uint256 thrld
            ) = _getTargetBucketToRebalanceOnLiquidation(originBucket_);
            address targetTP = _getTPMostLockedAC(originBucket_);
            (
                IMocSwapper mocSwapper,
                address tokenIn,
                address tokenOut,
                uint256 qACToSwap,
                uint256 qTPToRebalance,
                uint256 qACmin,
                uint256 qACExecFee
            ) = _calcACAndTPtoRebalance(
                    originBucket_,
                    targetBucket,
                    targetTP,
                    targetBucketCglb,
                    thrld,
                    false /*isMicroLiquidation == false*/,
                    block.basefee
                );
            uint256 qACOut = _rebalanceBuckets(
                originBucket_,
                targetBucket,
                tokenIn,
                tokenOut,
                mocSwapper,
                targetTP,
                qACToSwap,
                qTPToRebalance,
                qACmin,
                qACExecFee
            );
            emit PartialLiquidationExecuted(
                msg.sender,
                address(originBucket_),
                address(targetBucket),
                address(targetTP),
                qACToSwap,
                qACOut,
                qTPToRebalance,
                qACExecFee
            );

            // if bucket is empty set liquidated and remove it from the protocol
            if (originBucket_.getLckAC() == 0) {
                _liquidateAndRemoveBucket(originBucket_);
            }
        }
    }

    // ------- Only Authorized Functions -------

    /**
     * @notice sets micro liquidation execution cost
     * @param microLiquidationExecCost_ coinbase micro liquidation execution fee. Paid from the
     *  rebalanced bucket to the executor
     */
    function setMicroLiquidationExecCost(uint256 microLiquidationExecCost_) external onlyAuthorizedChanger {
        microLiquidationExecCost = microLiquidationExecCost_;
    }

    /**
     * @notice sets liquidation execution cost
     * @param liquidationExecCost_ coinbase liquidation execution fee. Paid from the liquidated bucket to the executor
     */
    function setLiquidationExecCost(uint256 liquidationExecCost_) external onlyAuthorizedChanger {
        liquidationExecCost = liquidationExecCost_;
    }

    /**
     * @notice sets mocSwapper for a given pair of buckets
     * @param bucketA_ bucket to set the new mocSwapper
     * @param bucketB_ bucket to set the new mocSwapper
     * @param mocSwapper_ mocSwapper contract to swap the bucketA_ / bucketB_ pool
     */
    function setMocSwapper(
        MocOperations bucketA_,
        MocOperations bucketB_,
        IMocSwapper mocSwapper_
    ) external onlyAuthorizedChanger {
        mocSwappers[bucketA_][bucketB_] = mocSwapper_;
        mocSwappers[bucketB_][bucketA_] = mocSwapper_;
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
