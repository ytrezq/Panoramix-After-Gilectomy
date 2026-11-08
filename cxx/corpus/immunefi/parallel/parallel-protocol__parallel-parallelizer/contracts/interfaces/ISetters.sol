// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import "../parallelizer/Storage.sol";

/// @title ISettersGovernor
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @dev This interface is an authorized fork of Angle's `ISettersGovernor` interface
/// https://github.com/AngleProtocol/angle-transmuter/blob/main/contracts/interfaces/ISetters.sol
interface ISettersGovernor {
  /// @notice Recovers `amount` of `token` from the Parallelizer contract
  function recoverERC20(address collateral, IERC20 token, address to, uint256 amount) external;

  /// @notice Sets a new access manager address
  function setAccessManager(address _newAccessManager) external;

  /// @notice Sets (or unsets) a collateral manager  `collateral`
  /// @dev If `checkExternalManagerBalance` is true, the function will check that the current manager no longer has
  /// assets before setting the new manager
  function setCollateralManager(
    address collateral,
    bool checkExternalManagerBalance,
    ManagerStorage memory managerData
  )
    external;

  /// @notice Sets the allowance of the contract on `token` for `spender` to `amount`
  function changeAllowance(IERC20 token, address spender, uint256 amount) external;

  /// @notice Changes the trusted status for `sender` when for selling rewards or updating the normalizer
  function toggleTrusted(address sender, TrustedType t) external;

  /// @notice Changes whether a `collateral` can only be handled during burns and redemptions by whitelisted
  /// addresses
  /// and sets the data used to read into the whitelist
  function setWhitelistStatus(address collateral, uint8 whitelistStatus, bytes memory whitelistData) external;

  /// @notice Add `collateral` as a supported collateral in the system
  function addCollateral(address collateral) external;

  /// @notice Adjusts the amount of stablecoins issued from `collateral` by `amount`
  function adjustStablecoins(address collateral, uint128 amount, bool increase) external;

  /// @notice Revokes `collateral` from the system
  /// @dev If `checkExternalManagerBalance` is true, the function will check that the current manager no longer has
  /// assets before revoking the collateral
  function revokeCollateral(address collateral, bool checkExternalManagerBalance) external;

  /// @notice Sets the `oracleConfig` used to read the value of `collateral` for the mint, burn and redemption
  /// operations
  function setOracle(address collateral, bytes memory oracleConfig) external;

  /// @notice Update oracle data for a given `collateral`
  function updateOracle(address collateral) external;

  /// @notice Updates the payees and their shares
  /// @param _payees The new payee addresses
  /// @param _shares The new shares for each payee
  /// @param _skipRelease If true, skips the automatic income release before updating
  function updatePayees(address[] memory _payees, uint256[] memory _shares, bool _skipRelease) external;

  /// @notice Updates the slippage tolerance for a `collateral`
  /// @dev Maximum slippage tolerance is 1e9 (100%)
  /// @dev The slippage tolerance is used to compute the minimum expected amount of stablecoins to be received when
  /// calling the `processSurplus` function
  function updateSlippageTolerance(address collateral, uint256 slippageTolerance) external;

  /// @notice Updates the surplus buffer ratio
  /// @dev The surplus buffer ratio is the minimum collateral ratio required after surplus processing
  /// @param _surplusBufferRatio The new surplus buffer ratio in BASE_9
  function updateSurplusBufferRatio(uint64 _surplusBufferRatio) external;

  /// @notice Sets the aggregator or DEX the `RewardHandler` forwards its swap payload to
  /// @dev The payload is executed with a raw call, so any router can be configured. It is chain
  /// specific and must be set on every deployment before rewards can be sold
  function setSwapRouter(address swapRouter) external;
}

/// @title ISettersGovernor
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
interface ISettersGuardian {
  /// @notice Pauses `action` for `collateral` (or pauses redemption protocol-wide when
  /// `action == Redeem`). Reverts if the action is already paused.
  function pause(address collateral, ActionType action) external;

  /// @notice Unpauses `action` for `collateral` (or unpauses redemption protocol-wide when
  /// `action == Redeem`). Reverts if the action is not paused.
  function unpause(address collateral, ActionType action) external;

  /// @notice Sets the mint or burn fees for `collateral`
  function setFees(address collateral, uint64[] memory xFee, int64[] memory yFee, bool mint) external;

  /// @notice Sets the parameters for the redemption curve
  function setRedemptionCurveParams(uint64[] memory xFee, int64[] memory yFee) external;

  /// @notice Changes the whitelist status for a collateral with `whitelistType` for an address `who`
  function toggleWhitelist(WhitelistType whitelistType, address who) external;

  /// @notice Sets the stablecoin cap that can be issued from a `collateral`
  function setStablecoinCap(address collateral, uint256 stablecoinCap) external;
}
