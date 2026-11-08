// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessManaged } from "../utils/AccessManaged.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IParallelizer } from "contracts/interfaces/IParallelizer.sol";
import { ITokenP } from "contracts/interfaces/ITokenP.sol";
import "contracts/interfaces/IRebalancer.sol";

import "../utils/Errors.sol";

struct YieldBearingParams {
  // Address of the asset used to mint the yield bearing asset
  address asset;
  // Target exposure to the collateral yield bearing asset used
  uint64 targetExposure;
  // Maximum exposure within the Parallelizer to the deposit asset
  uint64 maxExposure;
  // Minimum exposure within the Parallelizer to the deposit asset
  uint64 minExposure;
  // Whether limit exposures should be overriden or read onchain through the Parallelizer
  // This value should be 1 to override exposures or 2 if these shouldn't be overriden
  uint64 overrideExposures;
  // Maximum slippage when dealing with the Parallelizer, bounded below 1e9 so uint64 leaves the
  // struct packed in two slots
  uint64 maxSlippage;
}

/// @title BaseRebalancer
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @dev Abstract contract for a rebalancer that aims at rebalancing a Parallelizer
/// @dev This contract is an authorized fork of Angle's BaseHarvester contract, substantially modified:
/// https://github.com/AngleProtocol/angle-transmuter/blob/main/contracts/helpers/BaseHarvester.sol
abstract contract BaseRebalancer is IRebalancer, AccessManaged {
  using SafeERC20 for IERC20;

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       MODIFIERS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  /**
   * @notice Checks whether the `msg.sender` is trusted to update
   * target exposure and do others non critical operations
   */
  modifier onlyTrusted() {
    if (!isTrusted[msg.sender]) revert NotTrusted();
    _;
  }

  /**
   * @notice Checks whether the `msg.sender` is trusted or guardian to update
   * target exposure and do others non critical operations
   */
  modifier onlyTrustedOrRestricted() {
    if (!isTrusted[msg.sender] && !_checkCanCall(_msgSender(), _msgData())) {
      revert NotTrustedOrGuardian();
    }
    _;
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       VARIABLES
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  /// @notice Reference to the `parallelizer` implementation this contract aims at rebalancing
  IParallelizer public immutable parallelizer;
  /// @notice TokenP handled by the `parallelizer` of interest
  ITokenP public immutable tokenP;
  /// @notice Data associated to a yield bearing asset
  mapping(address => YieldBearingParams) public yieldBearingData;
  /// @notice trusted addresses that can update target exposure and do others non critical operations
  mapping(address => bool) public isTrusted;

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    EVENTS                                                      
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  event Recovered(address token, uint256 amount, address to);
  event TrustedToggled(address trusted, bool status);
  event AllowanceReset(address indexed token, address indexed spender);

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       CONSTRUCTOR
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  constructor(
    address initialAuthority,
    ITokenP definitiveTokenP,
    IParallelizer definitiveParallelizer
  )
    AccessManaged(initialAuthority)
  {
    tokenP = definitiveTokenP;
    parallelizer = definitiveParallelizer;
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        GUARDIAN FUNCTIONS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  /**
   * @notice Set the yieldBearingAsset data
   * @param yieldBearingAsset address of the yieldBearingAsset
   * @param asset address of the asset
   * @param targetExposure target exposure to the yieldBearingAsset asset used
   * @param minExposure minimum exposure within the Parallelizer to the asset
   * @param maxExposure maximum exposure within the Parallelizer to the asset
   * @param overrideExposures whether limit exposures should be overriden or read onchain through the Parallelizer
   */
  function setYieldBearingAssetData(
    address yieldBearingAsset,
    address asset,
    uint64 targetExposure,
    uint64 minExposure,
    uint64 maxExposure,
    uint64 overrideExposures,
    uint64 maxSlippage
  )
    external
    restricted
  {
    _setYieldBearingAssetData(
      yieldBearingAsset, asset, targetExposure, minExposure, maxExposure, overrideExposures, maxSlippage
    );
  }

  /**
   * @notice Set the limit exposures to the asset linked to the yield bearing asset
   * @param yieldBearingAsset address of the yield bearing asset
   */
  function updateLimitExposuresYieldAsset(address yieldBearingAsset) public virtual {
    YieldBearingParams storage yieldBearingInfo = yieldBearingData[yieldBearingAsset];
    if (yieldBearingInfo.overrideExposures == 2) {
      _updateLimitExposuresYieldAsset(yieldBearingInfo.asset, yieldBearingInfo);
    }
  }

  /**
   * @notice Set the max allowed slippage
   * @param newMaxSlippage new max allowed slippage
   */
  function setMaxSlippage(address yieldBearingAsset, uint64 newMaxSlippage) external restricted {
    _setMaxSlippage(yieldBearingAsset, newMaxSlippage);
  }

  /**
   * @notice Toggle the trusted status of an address
   * @param trusted address to toggle the trusted status
   */
  function toggleTrusted(address trusted) external restricted {
    emit TrustedToggled(trusted, isTrusted[trusted]);
    isTrusted[trusted] = !isTrusted[trusted];
  }

  /**
   * @notice Recover ERC20 tokens
   * @param tokenAddress address of the token to recover
   * @param amountToRecover amount to recover
   * @param to address to send the recovered tokens
   */
  function recoverERC20(address tokenAddress, uint256 amountToRecover, address to) external restricted {
    emit Recovered(tokenAddress, amountToRecover, to);
    IERC20(tokenAddress).safeTransfer(to, amountToRecover);
  }

  /**
   * @notice Set an allowance this contract granted back to zero
   * @param token address of the token
   * @param spender address losing the allowance
   * @dev Rebalancing grants unlimited allowances that are never reduced. Rotating a yield bearing
   * asset's configuration revokes the approvals it created, but this covers a spender that became
   * untrusted for any other reason.
   */
  function resetAllowance(address token, address spender) external restricted {
    IERC20(token).forceApprove(spender, 0);
    emit AllowanceReset(token, spender);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        TRUSTED FUNCTIONS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  /**
   * @notice Set the target exposure of a yield bearing asset
   * @param yieldBearingAsset address of the yield bearing asset
   * @param targetExposure target exposure to the yield bearing asset used
   */
  function setTargetExposure(address yieldBearingAsset, uint64 targetExposure) external onlyTrustedOrRestricted {
    yieldBearingData[yieldBearingAsset].targetExposure = targetExposure;
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  /**
   * @notice Compute the amount needed to rebalance the Parallelizer
   * @param yieldBearingAsset address of the yield bearing asset
   * @return increase whether the exposure should be increased
   * @return amount amount to be rebalanced
   */
  function computeRebalanceAmount(address yieldBearingAsset) external view returns (uint8 increase, uint256 amount) {
    return _computeRebalanceAmount(yieldBearingAsset, yieldBearingData[yieldBearingAsset]);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        INTERNAL FUNCTIONS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function _computeRebalanceAmount(
    address yieldBearingAsset,
    YieldBearingParams memory yieldBearingInfo
  )
    internal
    view
    returns (uint8 increase, uint256 amount)
  {
    (uint256 stablecoinsFromYieldBearingAsset, uint256 stablecoinsIssued) =
      parallelizer.getIssuedByCollateral(yieldBearingAsset);
    (uint256 stablecoinsFromAsset,) = parallelizer.getIssuedByCollateral(yieldBearingInfo.asset);
    uint256 targetExposureScaled = yieldBearingInfo.targetExposure * stablecoinsIssued;
    if (stablecoinsFromYieldBearingAsset * 1e9 > targetExposureScaled) {
      // Need to decrease exposure to yield bearing asset
      amount = stablecoinsFromYieldBearingAsset - targetExposureScaled / 1e9;
      uint256 maxValueScaled = yieldBearingInfo.maxExposure * stablecoinsIssued;
      // These checks assume that there are no transaction fees on the stablecoin->collateral conversion and so
      // it's still possible that exposure goes above the max exposure in some rare cases
      if (stablecoinsFromAsset * 1e9 > maxValueScaled) {
        amount = 0;
      } else if ((stablecoinsFromAsset + amount) * 1e9 > maxValueScaled) {
        amount = maxValueScaled / 1e9 - stablecoinsFromAsset;
      }
    } else {
      // In this case, exposure after the operation might remain slightly below the targetExposure as less
      // collateral may be obtained by burning stablecoins for the yield asset and unwrapping it
      increase = 1;
      amount = targetExposureScaled / 1e9 - stablecoinsFromYieldBearingAsset;
      uint256 minValueScaled = yieldBearingInfo.minExposure * stablecoinsIssued;
      if (stablecoinsFromAsset * 1e9 < minValueScaled) {
        amount = 0;
      } else if (stablecoinsFromAsset * 1e9 < minValueScaled + amount * 1e9) {
        amount = stablecoinsFromAsset - minValueScaled / 1e9;
      }
    }
  }

  function _setYieldBearingAssetData(
    address yieldBearingAsset,
    address asset,
    uint64 targetExposure,
    uint64 minExposure,
    uint64 maxExposure,
    uint64 overrideExposures,
    uint64 maxSlippage
  )
    internal
    virtual
  {
    YieldBearingParams storage yieldBearingInfo = yieldBearingData[yieldBearingAsset];
    address previousAsset = yieldBearingInfo.asset;
    // Allowances are granted without expiry, so the outgoing asset would keep the yield bearing
    // vault authorised over any of it later held here
    if (previousAsset != address(0) && previousAsset != asset) {
      IERC20(previousAsset).forceApprove(yieldBearingAsset, 0);
      emit AllowanceReset(previousAsset, yieldBearingAsset);
      _revokeAssetAllowances(yieldBearingAsset, previousAsset);
    }
    yieldBearingInfo.asset = asset;
    if (targetExposure >= 1e9) revert InvalidParam();
    if (maxSlippage >= 1e9) revert InvalidParam();
    yieldBearingInfo.targetExposure = targetExposure;
    yieldBearingInfo.overrideExposures = overrideExposures;
    yieldBearingInfo.maxSlippage = maxSlippage;
    if (overrideExposures == 1) {
      if (maxExposure >= 1e9 || minExposure >= maxExposure) revert InvalidParam();
      yieldBearingInfo.maxExposure = maxExposure;
      yieldBearingInfo.minExposure = minExposure;
    } else {
      yieldBearingInfo.overrideExposures = 2;
      _updateLimitExposuresYieldAsset(asset, yieldBearingInfo);
    }
  }

  /// @notice Lets a rebalancer revoke the allowances it granted over an asset being rotated out
  function _revokeAssetAllowances(address yieldBearingAsset, address previousAsset) internal virtual { }

  function _updateLimitExposuresYieldAsset(
    address asset,
    YieldBearingParams storage yieldBearingInfo
  )
    internal
    virtual
  {
    uint64[] memory xFeeMint;
    (xFeeMint,) = parallelizer.getCollateralMintFees(asset);
    uint256 length = xFeeMint.length;
    if (length <= 1) yieldBearingInfo.maxExposure = 1e9;
    else yieldBearingInfo.maxExposure = xFeeMint[length - 2];

    uint64[] memory xFeeBurn;
    (xFeeBurn,) = parallelizer.getCollateralBurnFees(asset);
    length = xFeeBurn.length;
    if (length <= 1) yieldBearingInfo.minExposure = 0;
    else yieldBearingInfo.minExposure = xFeeBurn[length - 2];
  }

  function _setMaxSlippage(address yieldBearingAsset, uint64 newMaxSlippage) internal virtual {
    if (newMaxSlippage >= 1e9) revert InvalidParam();
    yieldBearingData[yieldBearingAsset].maxSlippage = newMaxSlippage;
  }

  function _scaleAmountBasedOnDecimals(
    uint256 decimalsTokenIn,
    uint256 decimalsTokenOut,
    uint256 amountIn,
    bool assetIn
  )
    internal
    pure
    returns (uint256)
  {
    if (decimalsTokenIn > decimalsTokenOut) {
      if (assetIn) {
        amountIn /= 10 ** (decimalsTokenIn - decimalsTokenOut);
      } else {
        amountIn *= 10 ** (decimalsTokenIn - decimalsTokenOut);
      }
    } else if (decimalsTokenIn < decimalsTokenOut) {
      if (assetIn) {
        amountIn *= 10 ** (decimalsTokenOut - decimalsTokenIn);
      } else {
        amountIn /= 10 ** (decimalsTokenOut - decimalsTokenIn);
      }
    }
    return amountIn;
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    HELPER                                                      
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function _adjustAllowance(address token, address sender, uint256 amountIn) internal {
    uint256 allowance = IERC20(token).allowance(address(this), sender);
    if (allowance < amountIn) IERC20(token).safeIncreaseAllowance(sender, type(uint256).max - allowance);
  }
}
