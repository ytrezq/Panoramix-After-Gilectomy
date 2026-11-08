// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import "contracts/utils/Constants.sol";
import "contracts/utils/Errors.sol";
import { BaseActor, IParallelizer, AggregatorV3Interface, IERC20, IERC20Metadata } from "./BaseActor.t.sol";
import { MockChainlinkOracle } from "tests/mock/MockChainlinkOracle.sol";
import "../../utils/FunctionUtils.sol";

contract Governance is BaseActor, FunctionUtils {
  uint64 public collateralRatio;
  uint64 public collateralRatioSplit;

  uint256 public totalSurplusProcessed;
  uint256 public successfulSurplusCalls;
  uint256 public undercollateralizedReverts;
  uint256 public totalIncomeReleased;
  uint256 public releaseCallCount;
  bool public lastReleaseProportional = true;
  bool public surplusCausedUndercollateralization;

  constructor(
    IParallelizer parallelizer,
    IParallelizer transmuterSplit,
    address[] memory collaterals,
    AggregatorV3Interface[] memory oracles
  )
    BaseActor(1, "Trader", parallelizer, transmuterSplit, collaterals, oracles)
  { }

  // Random oracle change of at most 1%
  // Only this function can decrease the collateral ratio, so when triggered update
  // the collat ratio
  function updateOracle(uint256 collatNumber, int256 change) public useActor(0) countCall("oracle") {
    collatNumber = bound(collatNumber, 0, 2);
    change = bound(change, int256((99 * BASE_18) / 100), int256((101 * BASE_18) / 100)); // +/- 1%

    (, int256 answer,,,) = _oracles[collatNumber].latestRoundData();
    answer = (answer * change) / int256(BASE_18);
    MockChainlinkOracle(address(_oracles[collatNumber])).setLatestAnswer(answer);
    (collateralRatio,) = _parallelizer.getCollateralRatio();
    (collateralRatioSplit,) = _parallelizerSplit.getCollateralRatio();
    // if collateral ratio is max -can only happen if stablecoin supply is null -
    // then it can only decrease, so set it to 0
    if (collateralRatio == type(uint64).max) collateralRatio = 0;
    if (collateralRatioSplit == type(uint64).max) collateralRatioSplit = 0;
  }

  function updateRedemptionFees(
    uint64[10] memory xFee,
    int64[10] memory yFee
  )
    public
    useActor(0)
    countCall("feeRedeem")
  {
    (uint64[] memory xFeeRedeem, int64[] memory yFeeRedeem) =
      _generateCurves(xFee, yFee, true, false, 0, int256(BASE_9));
    _parallelizer.setRedemptionCurveParams(xFeeRedeem, yFeeRedeem);
    _parallelizerSplit.setRedemptionCurveParams(xFeeRedeem, yFeeRedeem);
  }

  function updateBurnFees(
    uint256 collatNumber,
    uint64[10] memory xFee,
    int64[10] memory yFee
  )
    public
    useActor(0)
    countCall("feeBurn")
  {
    collatNumber = bound(collatNumber, 0, 2);

    int256 minBurnFee = int256(BASE_9);
    for (uint256 i; i < _collaterals.length; i++) {
      (, int64[] memory yFeeMint) = _parallelizer.getCollateralMintFees(_collaterals[i]);
      if (yFeeMint[0] < minBurnFee) minBurnFee = yFeeMint[0];
    }
    (uint64[] memory xFeeBurn, int64[] memory yFeeBurn) =
      _generateCurves(xFee, yFee, false, false, (minBurnFee > 0) ? int256(0) : -minBurnFee, int256(MAX_BURN_FEE) - 1);
    _parallelizer.setFees(_collaterals[collatNumber], xFeeBurn, yFeeBurn, false);
    _parallelizerSplit.setFees(_collaterals[collatNumber], xFeeBurn, yFeeBurn, false);
  }

  function updateMintFees(
    uint256 collatNumber,
    uint64[10] memory xFee,
    int64[10] memory yFee
  )
    public
    useActor(0)
    countCall("feeMint")
  {
    collatNumber = bound(collatNumber, 0, 2);
    int256 minMintFee = int256(BASE_9);
    for (uint256 i; i < _collaterals.length; i++) {
      (, int64[] memory yFeeBurn) = _parallelizer.getCollateralBurnFees(_collaterals[i]);
      if (yFeeBurn[0] < minMintFee) minMintFee = yFeeBurn[0];
    }
    (uint64[] memory xFeeMint, int64[] memory yFeeMint) =
      _generateCurves(xFee, yFee, true, true, (minMintFee > 0) ? int256(0) : -minMintFee, int256(BASE_12) - 1);
    _parallelizer.setFees(_collaterals[collatNumber], xFeeMint, yFeeMint, true);
    _parallelizerSplit.setFees(_collaterals[collatNumber], xFeeMint, yFeeMint, true);
  }

  function processSurplus(uint256 collatNumber) public useActor(0) countCall("processSurplus") {
    collatNumber = bound(collatNumber, 0, _collaterals.length - 1);
    try _parallelizer.processSurplus(_collaterals[collatNumber], 0) returns (uint256, uint256, uint256 issuedAmount) {
      totalSurplusProcessed += issuedAmount;
      successfulSurplusCalls++;
      // CR must be >= BASE_9 immediately after successful processSurplus
      (uint64 cr,) = _parallelizer.getCollateralRatio();
      if (cr < uint64(BASE_9)) {
        surplusCausedUndercollateralization = true;
      }
    } catch (bytes memory reason) {
      if (reason.length >= 4 && bytes4(reason) == Undercollateralized.selector) {
        undercollateralizedReverts++;
      }
    }
  }

  function release() public useActor(0) countCall("release") {
    uint256 income = tokenP.balanceOf(address(_parallelizer));
    if (income == 0) return;

    try _parallelizer.release() returns (address[] memory payees, uint256[] memory amounts) {
      releaseCallCount++;
      uint256 totalShares = _parallelizer.getTotalShares();
      uint256 totalDistributed;
      bool proportional = true;

      for (uint256 i; i < payees.length; i++) {
        totalDistributed += amounts[i];
        uint256 expectedAmount = (income * _parallelizer.getShares(payees[i])) / totalShares;
        if (amounts[i] > expectedAmount + 1 || amounts[i] + 1 < expectedAmount) {
          proportional = false;
        }
      }
      totalIncomeReleased += totalDistributed;
      lastReleaseProportional = proportional;
    } catch { }
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    UTILS                                                      
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function updateCollateralRatio(uint64 newCollateralRatio) public {
    collateralRatioSplit = newCollateralRatio;
  }

  function updateSplitCollateralRatio(uint64 newCollateralRatio) public {
    collateralRatioSplit = newCollateralRatio;
  }
}
