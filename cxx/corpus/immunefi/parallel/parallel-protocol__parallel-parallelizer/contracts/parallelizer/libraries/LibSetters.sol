// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { LibSurplus } from "./LibSurplus.sol";
import { LibManager } from "./LibManager.sol";
import { LibOracle } from "./LibOracle.sol";
import { LibStorage as s } from "./LibStorage.sol";
import { LibDiamond } from "./LibDiamond.sol";
import { LibWhitelist } from "./LibWhitelist.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import "../Storage.sol";

/// @title LibSetters
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @dev This library is an authorized fork of Angle's `LibSetters` library
/// https://github.com/AngleProtocol/angle-transmuter/blob/main/contracts/transmuter/libraries/LibSetters.sol
library LibSetters {
  using SafeCast for uint256;

  event CollateralAdded(address indexed collateral);
  event CollateralManagerSet(address indexed collateral, ManagerStorage managerData);
  event CollateralRevoked(address indexed collateral);
  event CollateralWhitelistStatusUpdated(address indexed collateral, bytes whitelistData, uint8 whitelistStatus);
  event FeesSet(address indexed collateral, uint64[] xFee, int64[] yFee, bool mint);
  event OracleSet(address indexed collateral, bytes oracleConfig);
  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
  event PauseToggled(address indexed collateral, uint256 pausedType, bool isPaused);
  event RedemptionCurveParamsSet(uint64[] xFee, int64[] yFee);
  event ReservesAdjusted(address indexed collateral, uint256 amount, bool increase);
  event StablecoinCapSet(address indexed collateral, uint256 stablecoinCap);
  event TrustedToggled(address indexed sender, bool isTrusted, TrustedType trustedType);
  event WhitelistStatusToggled(WhitelistType whitelistType, address indexed who, uint256 whitelistStatus);
  event PayeeAdded(address indexed payee, uint256 shares);
  event SlippageToleranceUpdated(address indexed collateral, uint256 slippageTolerance);
  event SurplusBufferRatioUpdated(uint64 surplusBufferRatio);
  event SwapRouterUpdated(address indexed swapRouter);

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ONLY GOVERNOR ACTIONS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  /// @notice Internal version of `setAccessManager`
  function setAccessManager(IAccessManager _newAccessManager) internal {
    if (address(_newAccessManager).code.length == 0) revert InvalidAccessManager();
    DiamondStorage storage ds = s.diamondStorage();
    address previousAccessManager = address(ds.accessManager);
    ds.accessManager = _newAccessManager;
    emit OwnershipTransferred(previousAccessManager, address(_newAccessManager));
  }

  /// @notice Internal version of `setCollateralManager`
  function setCollateralManager(
    address collateral,
    bool checkExternalManagerBalance,
    ManagerStorage memory managerData
  )
    internal
  {
    Collateral storage collatInfo = s.transmuterStorage().collaterals[collateral];
    if (collatInfo.decimals == 0) revert NotCollateral();
    uint8 isManaged = collatInfo.isManaged;
    if (isManaged > 0 && checkExternalManagerBalance) {
      (, uint256 totalValue) = LibManager.totalAssets(collatInfo.managerData.config);
      if (totalValue > 0) revert ManagerHasAssets();
    }
    if (managerData.config.length != 0) {
      // The first subCollateral given should be the actual collateral asset
      if (address(managerData.subCollaterals[0]) != collateral) revert InvalidParams();
      // Sanity check on the manager data that is passed
      LibManager.parseManagerConfig(managerData.config);
      collatInfo.isManaged = 1;
    } else {
      collatInfo.isManaged = 0;
    }
    collatInfo.managerData = managerData;
    emit CollateralManagerSet(collateral, managerData);
  }

  /// @notice Internal version of `toggleTrusted`
  function toggleTrusted(address sender, TrustedType t) internal {
    ParallelizerStorage storage ts = s.transmuterStorage();
    uint256 trustedStatus;
    if (t == TrustedType.Updater) {
      trustedStatus = 1 - ts.isTrusted[sender];
      ts.isTrusted[sender] = trustedStatus;
    } else {
      trustedStatus = 1 - ts.isSellerTrusted[sender];
      ts.isSellerTrusted[sender] = trustedStatus;
    }
    emit TrustedToggled(sender, trustedStatus == 1, t);
  }

  /// @notice Internal version of `addCollateral`
  function addCollateral(address collateral) internal {
    ParallelizerStorage storage ts = s.transmuterStorage();
    Collateral storage collatInfo = ts.collaterals[collateral];
    if (collatInfo.decimals != 0) revert AlreadyAdded();
    collatInfo.decimals = uint8(IERC20Metadata(collateral).decimals());
    ts.collateralList.push(collateral);
    emit CollateralAdded(collateral);
  }

  /// @notice Internal version of `adjustStablecoins`
  function adjustStablecoins(address collateral, uint128 amount, bool increase) internal {
    ParallelizerStorage storage ts = s.transmuterStorage();
    Collateral storage collatInfo = ts.collaterals[collateral];
    if (collatInfo.decimals == 0) revert NotCollateral();
    uint128 normalizedAmount = ((amount * BASE_27) / ts.normalizer).toUint128();
    if (increase) {
      collatInfo.normalizedStables = collatInfo.normalizedStables + uint216(normalizedAmount);
      ts.normalizedStables = ts.normalizedStables + normalizedAmount;
      if (uint256(collatInfo.normalizedStables) * uint256(ts.normalizer) / BASE_27 > collatInfo.stablecoinCap) {
        revert AboveCap();
      }
    } else {
      collatInfo.normalizedStables = collatInfo.normalizedStables - uint216(normalizedAmount);
      ts.normalizedStables = ts.normalizedStables - normalizedAmount;
    }
    emit ReservesAdjusted(collateral, amount, increase);
  }

  /// @notice Internal version of `revokeCollateral`
  function revokeCollateral(address collateral, bool checkExternalManagerBalance) internal {
    ParallelizerStorage storage ts = s.transmuterStorage();
    Collateral storage collatInfo = ts.collaterals[collateral];
    if (collatInfo.decimals == 0) revert NotCollateral();
    if (collatInfo.normalizedStables > 0) revert CollateralBacked();
    uint8 isManaged = collatInfo.isManaged;
    if (isManaged > 0 && checkExternalManagerBalance) {
      (, uint256 totalValue) = LibManager.totalAssets(collatInfo.managerData.config);
      if (totalValue > 0) revert ManagerHasAssets();
    }
    delete ts.collaterals[collateral];
    address[] memory collateralListMem = ts.collateralList;
    uint256 length = collateralListMem.length;
    for (uint256 i; i < length - 1; ++i) {
      if (collateralListMem[i] == collateral) {
        ts.collateralList[i] = collateralListMem[length - 1];
        break;
      }
    }
    ts.collateralList.pop();
    emit CollateralRevoked(collateral);
  }

  /// @notice Internal version of `setOracle`
  function setOracle(address collateral, bytes memory oracleConfig) internal {
    Collateral storage collatInfo = s.transmuterStorage().collaterals[collateral];
    if (collatInfo.decimals == 0) revert NotCollateral();
    (,,,, bytes memory hyperparameters) =
      abi.decode(oracleConfig, (OracleReadType, OracleReadType, bytes, bytes, bytes));
    (uint128 userDeviation, uint128 burnRatioDeviation) = abi.decode(hyperparameters, (uint128, uint128));
    if (userDeviation > burnRatioDeviation) revert InvalidParams();
    // Checks oracle validity
    LibOracle.readMint(oracleConfig);
    collatInfo.oracleConfig = oracleConfig;
    emit OracleSet(collateral, oracleConfig);
  }

  /// @notice Internal version of `setWhitelistStatus`
  function setWhitelistStatus(address collateral, uint8 whitelistStatus, bytes memory whitelistData) internal {
    if (whitelistStatus > 1) revert InvalidWhitelistStatus();
    Collateral storage collatInfo = s.transmuterStorage().collaterals[collateral];
    if (collatInfo.decimals == 0) revert NotCollateral();
    if (whitelistStatus == 1) {
      // Sanity check
      LibWhitelist.checkWhitelist(whitelistData, address(this));
      collatInfo.whitelistData = whitelistData;
    } else {
      // If whitelist is revoked, clear the whitelist data
      collatInfo.whitelistData = "";
    }
    collatInfo.onlyWhitelisted = whitelistStatus;
    emit CollateralWhitelistStatusUpdated(collateral, collatInfo.whitelistData, whitelistStatus);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ONLY GUARDIAN ACTIONS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  /// @notice Internal version of `pause` — sets the action's live flag to `0`
  /// @dev Reverts with `AlreadyPaused` if the action is already paused so a no-op governance
  /// call cannot pass silently
  function pause(address collateral, ActionType action) internal {
    _setPauseState(collateral, action, 0);
  }

  /// @notice Internal version of `unpause` — sets the action's live flag to `1`
  /// @dev Reverts with `NotPaused` if the action is already unpaused so a no-op governance
  /// call cannot pass silently
  function unpause(address collateral, ActionType action) internal {
    _setPauseState(collateral, action, 1);
  }

  /// @dev Shared accessor for `pause` and `unpause`. `targetIsLive` is `0` to pause and `1`
  /// to unpause. Reverts on no-op transitions.
  function _setPauseState(address collateral, ActionType action, uint8 targetIsLive) private {
    if (action == ActionType.Mint || action == ActionType.Burn) {
      Collateral storage collatInfo = s.transmuterStorage().collaterals[collateral];
      if (collatInfo.decimals == 0) revert NotCollateral();
      uint8 currentIsLive = action == ActionType.Mint ? collatInfo.isMintLive : collatInfo.isBurnLive;
      if (currentIsLive == targetIsLive) {
        if (targetIsLive == 0) revert AlreadyPaused();
        revert NotPaused();
      }
      if (action == ActionType.Mint) {
        collatInfo.isMintLive = targetIsLive;
      } else {
        collatInfo.isBurnLive = targetIsLive;
      }
    } else {
      ParallelizerStorage storage ts = s.transmuterStorage();
      if (ts.isRedemptionLive == targetIsLive) {
        if (targetIsLive == 0) revert AlreadyPaused();
        revert NotPaused();
      }
      ts.isRedemptionLive = targetIsLive;
    }
    emit PauseToggled(collateral, uint256(action), targetIsLive == 0);
  }

  /// @notice Internal version of `setFees`
  function setFees(address collateral, uint64[] memory xFee, int64[] memory yFee, bool mint) internal {
    ParallelizerStorage storage ts = s.transmuterStorage();
    Collateral storage collatInfo = ts.collaterals[collateral];
    if (collatInfo.decimals == 0) revert NotCollateral();
    checkFees(xFee, yFee, mint ? ActionType.Mint : ActionType.Burn);
    if (mint) {
      collatInfo.xFeeMint = xFee;
      collatInfo.yFeeMint = yFee;
    } else {
      collatInfo.xFeeBurn = xFee;
      collatInfo.yFeeBurn = yFee;
    }
    emit FeesSet(collateral, xFee, yFee, mint);
  }

  /// @notice Internal version of `setRedemptionCurveParams`
  function setRedemptionCurveParams(uint64[] memory xFee, int64[] memory yFee) internal {
    ParallelizerStorage storage ts = s.transmuterStorage();
    LibSetters.checkFees(xFee, yFee, ActionType.Redeem);
    ts.xRedemptionCurve = xFee;
    ts.yRedemptionCurve = yFee;
    emit RedemptionCurveParamsSet(xFee, yFee);
  }

  /// @notice Internal version of `toggleWhitelist`
  function toggleWhitelist(WhitelistType whitelistType, address who) internal {
    ParallelizerStorage storage ts = s.transmuterStorage();
    uint256 whitelistStatus = 1 - ts.isWhitelistedForType[whitelistType][who];
    ts.isWhitelistedForType[whitelistType][who] = whitelistStatus;
    emit WhitelistStatusToggled(whitelistType, who, whitelistStatus);
  }

  /// @notice Sets the stablecoin cap that can be issued from a collateral
  function setStablecoinCap(address collateral, uint256 stablecoinCap) internal {
    Collateral storage collatInfo = s.transmuterStorage().collaterals[collateral];
    if (collatInfo.decimals == 0) revert NotCollateral();
    collatInfo.stablecoinCap = stablecoinCap;
    emit StablecoinCapSet(collateral, stablecoinCap);
  }

  /// @notice Internal version of `updatePayees`
  function updatePayees(address[] memory _payees, uint256[] memory _shares, bool _skipRelease) internal {
    if (_payees.length == 0 || _payees.length > MAX_PAYEES) revert InvalidLengths();
    if (_payees.length != _shares.length) revert ArrayLengthMismatch();
    /// @dev Distribute the fees before updating the fee receivers.
    ParallelizerStorage storage ts = s.transmuterStorage();
    if (!_skipRelease) {
      uint256 income = ts.tokenP.balanceOf(address(this));
      if (income > 0 && ts.payees.length > 0) {
        LibSurplus.release(income, ts.payees);
      }
    }

    // Zero out stale shares for old payees
    uint256 i = 0;
    for (; i < ts.payees.length; ++i) {
      ts.shares[ts.payees[i]] = 0;
    }
    delete ts.payees;
    uint256 _totalShares = 0;
    i = 0;
    for (; i < _payees.length; ++i) {
      for (uint256 j = 0; j < i; ++j) {
        if (_payees[j] == _payees[i]) revert AlreadyAdded();
      }
      _totalShares += _addPayee(_payees[i], _shares[i]);
    }
    ts.totalShares = _totalShares;
  }

  /// @notice Internal version of `updateSlippageTolerance`
  function updateSlippageTolerance(address collateral, uint256 slippageTolerance) internal {
    if (slippageTolerance > BASE_9) revert InvalidRate();
    ParallelizerStorage storage ts = s.transmuterStorage();
    ts.slippageTolerance[collateral] = slippageTolerance;
    emit SlippageToleranceUpdated(collateral, slippageTolerance);
  }

  /// @notice Internal version of `setSwapRouter`
  function setSwapRouter(address swapRouter) internal {
    if (swapRouter == address(0)) revert ZeroAddress();
    s.transmuterStorage().swapRouter = swapRouter;
    emit SwapRouterUpdated(swapRouter);
  }

  /// @notice Internal version of `updateSurplusBufferRatio`
  function updateSurplusBufferRatio(uint64 _surplusBufferRatio) internal {
    if (_surplusBufferRatio < uint64(BASE_9)) revert InvalidParam();
    ParallelizerStorage storage ts = s.transmuterStorage();
    ts.surplusBufferRatio = _surplusBufferRatio;
    emit SurplusBufferRatioUpdated(_surplusBufferRatio);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    HELPERS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  /// @notice Checks the fee values given for the `mint`, `burn`, and `redeem` functions
  function checkFees(uint64[] memory xFee, int64[] memory yFee, ActionType action) internal view {
    uint256 n = xFee.length;
    if (n != yFee.length || n == 0) revert InvalidParams();
    if (
      // Mint inflexion points should be in [0,BASE_9[
      // We have: amountPostFee * (BASE_9 + yFeeMint) = amountPreFee * BASE_9
      // Hence we consider BASE_12 as the max value (100% fees) for yFeeMint
      // Burn inflexion points should be in [0,BASE_9] but fees should be constant in
      // the first segment [BASE_9, x_{n-1}[
      // Redemption inflexion points should be in [0,BASE_9]
      (action == ActionType.Mint && (xFee[n - 1] >= BASE_9 || xFee[0] != 0 || yFee[n - 1] > int256(BASE_12)))
        || (action == ActionType.Burn
          && (xFee[0] != BASE_9 || yFee[n - 1] > int256(BASE_9) || (n > 1 && (yFee[0] != yFee[1]))))
        || (action == ActionType.Redeem && (xFee[n - 1] > BASE_9 || yFee[n - 1] < 0 || yFee[n - 1] > int256(BASE_9)))
    ) {
      revert InvalidParams();
    }

    for (uint256 i; i < n - 1; ++i) {
      if (
        // xFee strictly increasing and yFee increasing for mints
        // xFee strictly decreasing and yFee increasing for burns
        // xFee strictly increasing and yFee should be in [0,BASE_9] for redemptions
        (action == ActionType.Mint && (xFee[i] >= xFee[i + 1] || (yFee[i + 1] < yFee[i])))
          || (action == ActionType.Burn && (xFee[i] <= xFee[i + 1] || (yFee[i + 1] < yFee[i])))
          || (action == ActionType.Redeem && (xFee[i] >= xFee[i + 1] || yFee[i] < 0 || yFee[i] > int256(BASE_9)))
      ) revert InvalidParams();
    }

    // If a mint or burn fee is negative, we need to check that accounts atomically minting
    // (from any collateral) and then burning cannot get more than their initial value
    if (yFee[0] < 0) {
      if (!LibDiamond.isGovernor(msg.sender)) revert NotGovernor(); // Only governor can set negative fees
      ParallelizerStorage storage ts = s.transmuterStorage();
      address[] memory collateralListMem = ts.collateralList;
      uint256 length = collateralListMem.length;
      if (action == ActionType.Mint) {
        // This can be mathematically expressed by `(1-min_c(burnFee_c))<=(1+mintFee[0])`
        for (uint256 i; i < length; ++i) {
          int64[] memory burnFees = ts.collaterals[collateralListMem[i]].yFeeBurn;
          if (burnFees[0] + yFee[0] < 0) revert InvalidNegativeFees();
        }
      }
      if (action == ActionType.Burn) {
        // This can be mathematically expressed by `(1-burnFee[0])<=(1+min_c(mintFee_c))`
        for (uint256 i; i < length; ++i) {
          int64[] memory mintFees = ts.collaterals[collateralListMem[i]].yFeeMint;
          if (yFee[0] + mintFees[0] < 0) revert InvalidNegativeFees();
        }
      }
    }
  }

  /// @notice Add a new fee receiver.
  /// @param _payee The address of the fee receiver.
  /// @param _shares The number of shares assigned to the fee receiver.
  function _addPayee(address _payee, uint256 _shares) internal returns (uint256) {
    if (_shares == 0) revert ZeroAmount();
    // The Parallelizer holds the income being distributed, so a share allocated to itself is handed
    // back to `release` as fresh income on the next call. `address(0)` stays valid: `LibSurplus`
    // treats it as the sentinel for burning that share.
    if (_payee == address(this)) revert InvalidPayee();
    ParallelizerStorage storage ts = s.transmuterStorage();

    ts.payees.push(_payee);
    ts.shares[_payee] = _shares;
    emit PayeeAdded(_payee, _shares);
    return _shares;
  }
}
