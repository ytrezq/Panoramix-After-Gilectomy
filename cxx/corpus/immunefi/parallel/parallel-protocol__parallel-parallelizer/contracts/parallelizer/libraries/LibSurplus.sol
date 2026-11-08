// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { LibManager } from "../libraries/LibManager.sol";
import { LibOracle } from "../libraries/LibOracle.sol";
import { LibGetters } from "../libraries/LibGetters.sol";
import { LibHelpers } from "../libraries/LibHelpers.sol";
import { LibStorage as s } from "../libraries/LibStorage.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import "../Storage.sol";

/// @title LibSurplus
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
library LibSurplus {
  using SafeERC20 for IERC20;
  using Math for uint256;

  event IncomeReleased(uint256 income, uint256 releasedAt);
  event IncomeReleasedToPayee(uint256 income, address payee, uint256 releasedAt);

  /// @notice Internal version of `release`
  function release(
    uint256 _incomeToRelease,
    address[] memory _payees
  )
    internal
    returns (address[] memory payees, uint256[] memory amounts)
  {
    ParallelizerStorage storage ts = s.transmuterStorage();
    ts.lastReleasedAt = block.timestamp;
    uint256 i;
    amounts = new uint256[](_payees.length);
    for (; i < _payees.length; ++i) {
      address payee = _payees[i];
      amounts[i] = _release(_incomeToRelease, payee, ts);
    }

    emit IncomeReleased(_incomeToRelease, ts.lastReleasedAt);
    return (_payees, amounts);
  }

  /// @notice Internal function to release a percentage of income to a specific payee.
  /// @dev uses totalShares to calculate correct share.
  /// @param _totalIncomeReceived Total income for all payees, will be split according to shares.
  /// @param _payee The address of the payee to whom to distribute the fees.
  /// @param _ts The contract storage.
  /// @return income The amount transfer to the payee.
  function _release(
    uint256 _totalIncomeReceived,
    address _payee,
    ParallelizerStorage storage _ts
  )
    internal
    returns (uint256 income)
  {
    income = _totalIncomeReceived.mulDiv(_ts.shares[_payee], _ts.totalShares);
    if (_payee == address(0)) {
      _ts.tokenP.burnSelf(income, address(this));
    } else {
      IERC20(address(_ts.tokenP)).safeTransfer(_payee, income);
    }
    emit IncomeReleasedToPayee(income, _payee, _ts.lastReleasedAt);
  }

  /// @notice Computes the surplus of a collateral.
  /// @param collateral The collateral address to compute the surplus of.
  /// @return collateralSurplus The collateral surplus amount.
  /// @return stableSurplus The surplus in stable amount.
  function _computeCollateralSurplus(address collateral)
    internal
    view
    returns (uint256 collateralSurplus, uint256 stableSurplus)
  {
    ParallelizerStorage storage ts = s.transmuterStorage();
    if (ts.surplusBufferRatio == 0) revert SurplusBufferRatioNotSet();
    Collateral storage collatInfo = ts.collaterals[collateral];
    uint256 collateralBalance = _getCollateralBalance(collateral);
    uint256 redemptionValue = LibOracle.readRedemption(collatInfo.oracleConfig);
    uint256 mintValue = LibOracle.readMint(collatInfo.oracleConfig);
    // Use the lower oracle value to conservatively size the surplus, preventing over-extraction
    // that would cause the post-swap CR check (which uses readRedemption) to revert
    uint256 totalCollateralValue = LibHelpers.convertDecimalTo(
      Math.min(redemptionValue, mintValue) * collateralBalance, 18 + collatInfo.decimals, 18, Math.Rounding.Floor
    );
    uint256 stablesBacked = (uint256(collatInfo.normalizedStables) * ts.normalizer) / BASE_27;
    // Compute the max stables that can be backed while maintaining the buffer ratio
    uint256 maxBackable = (totalCollateralValue * BASE_9) / ts.surplusBufferRatio;
    if (maxBackable <= stablesBacked) revert ZeroSurplusAmount();
    stableSurplus = maxBackable - stablesBacked;
    // Cap per-collateral surplus by global extractable surplus
    stableSurplus = Math.min(stableSurplus, _calculateGlobalExtractableSurplus(ts.surplusBufferRatio));
    if (stableSurplus == 0) revert ZeroSurplusAmount();
    collateralSurplus =
      LibHelpers.convertDecimalTo((stableSurplus * BASE_18) / mintValue, 18, collatInfo.decimals, Math.Rounding.Floor);
  }

  /// @notice Computes the global extractable surplus above the surplus buffer ratio.
  /// @param surplusBufferRatio The surplus buffer ratio.
  /// @return globalStableSurplus The maximum stables that can be minted globally while maintaining the buffer ratio.
  function _calculateGlobalExtractableSurplus(uint64 surplusBufferRatio)
    internal
    view
    returns (uint256 globalStableSurplus)
  {
    (uint64 collatRatio, uint256 stablecoinsIssued,,,) = LibGetters.getCollateralRatio();
    if (collatRatio <= surplusBufferRatio) revert ZeroSurplusAmount();
    globalStableSurplus = stablecoinsIssued * (uint256(collatRatio) - surplusBufferRatio) / surplusBufferRatio;
  }

  /// @notice Gets the balance of a collateral.
  /// @dev If the collateral is managed, the balance is the total assets of the managed collateral.
  /// @param collateral The collateral address to get the balance of.
  /// @return balance The balance of the collateral.
  function _getCollateralBalance(address collateral) internal view returns (uint256 balance) {
    Collateral storage collatInfo = s.transmuterStorage().collaterals[collateral];
    if (collatInfo.isManaged > 0) {
      (, balance) = LibManager.totalAssets(collatInfo.managerData.config);
    } else {
      balance = IERC20(collateral).balanceOf(address(this));
    }
  }

  /// @notice Computes the minimum expected amount of stablecoins to receive for a given surplus.
  /// @param stableSurplus The surplus in stable amount.
  /// @param slippageTolerance The slippage tolerance.
  /// @return minExpectedAmount The minimum expected amount of stablecoins to receive.
  function _minExpectedAmount(
    uint256 stableSurplus,
    uint256 slippageTolerance
  )
    internal
    pure
    returns (uint256 minExpectedAmount)
  {
    return (stableSurplus * (BASE_9 - slippageTolerance)) / BASE_9;
  }
}
