// SPDX-License-Identifier: BUSL-1.1
/*
      ▄▄█████████▄
   ╓██▀└ ,╓▄▄▄, '▀██▄
  ██▀ ▄██▀▀╙╙▀▀██▄ └██µ           ,,       ,,      ,     ,,,            ,,,
 ██ ,██¬ ▄████▄  ▀█▄ ╙█▄      ▄███▀▀███▄   ███▄    ██  ███▀▀▀███▄    ▄███▀▀███,
██  ██ ╒█▀'   ╙█▌ ╙█▌ ██     ▐██      ███  █████,  ██  ██▌    └██▌  ██▌     └██▌
██ ▐█▌ ██      ╟█  █▌ ╟█     ██▌      ▐██  ██ └███ ██  ██▌     ╟██ j██       ╟██
╟█  ██ ╙██    ▄█▀ ▐█▌ ██     ╙██      ██▌  ██   ╙████  ██▌    ▄██▀  ██▌     ,██▀
 ██ "██, ╙▀▀███████████⌐      ╙████████▀   ██     ╙██  ███████▀▀     ╙███████▀`
  ██▄ ╙▀██▄▄▄▄▄,,,                ¬─                                    '─¬
   ╙▀██▄ '╙╙╙▀▀▀▀▀▀▀▀
      ╙▀▀██████R⌐
 */
pragma solidity 0.8.33;

import {IOndoFees} from "contracts/xManager/interfaces/IOndoFees.sol";
import {
  AccessControlEnumerable
} from "contracts/external/openzeppelin/contracts/access/AccessControlEnumerable.sol";

/**
 * @title  OndoFees
 * @author Ondo Finance
 * @notice This contract handles fee configurations for multiple RWA tokens.
 *         It can be used for subscriptions or redemptions on the Ondo platform.
 *         Fee configurations can be set at varying levels of granularity.
 *         The logic that determines which fee configuration will be used follows this order of
 *         precedence:
 *         1. User specific fee configuration for specific stablecoins used in the transaction
 *         2. User specific fee configuration
 *         3. Default fee configuration for specific stablecoins used in the transaction
 *         4. Default fee configuration
 *
 *         If the default fee configuration is not set, the contract will revert. User specific
 *         fee configurations have the ability to set a maximum volume allowed with or without
 *         fees over a certain period of time. This is useful for users who have a certain
 *         volume of transactions per month that are exempt from fees, or, conversely,
 *         for users who are fee exempt until they reach a certain volume.
 *         Roles:
 *            - FEE_MANAGER_ROLE
 *            - CLIENT_ROLE
 */
contract OndoFees is IOndoFees, AccessControlEnumerable {
  /// Role to set fee configurations
  bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

  /// Role to interact with the contract via the `getAndUpdateFee` function
  bytes32 public constant CLIENT_ROLE = keccak256("CLIENT_ROLE");

  /// The precision for calculating basis points fees (1e4 = 100%)
  uint256 public constant FEE_PRECISION = 10_000;

  /**
   * @notice The fee configuration for a subscription
   * @param  active  Whether the fee config is active
   * @param  flatFee The flat fee charged in USD with 18 decimals
   * @param  bpsFee  The basis points fee charged in `FEE_PRECISION` decimals
   *                 (1 basis point = 0.01% = 1)
   */
  struct FeeConfig {
    bool active;
    uint256 flatFee;
    uint256 bpsFee;
  }

  /**
   * @notice The user fee configuration
   * @param  feeConfig     The fee configuration for the user
   * @param  userFeeMode   The user fee mode
   * @param  limitVolume   The volume limit for the user in a window, in USD with 18 decimals
   * @param  currentVolume The current volume for the user, in USD with 18 decimals
   * @param  lastReset     The timestamp of the last time the currentVolume was reset
   * @param  volumeWindow  The window for the volume limit in seconds
   */
  struct UserFeeConfig {
    FeeConfig feeConfig;
    UserFeeMode userFeeMode;
    uint256 limitVolume;
    uint256 currentVolume;
    uint256 lastReset;
    uint256 volumeWindow;
  }

  enum UserFeeMode {
    /// NO_FEE_UNTIL_LIMIT Fees are waived for the user UNTIL the limit
    NO_FEE_UNTIL_LIMIT,
    /// NO_FEE_AFTER_LIMIT Fees are waived for the user AFTER the limit
    NO_FEE_AFTER_LIMIT
  }

  /// Default fee configurations for RWAs
  mapping(address /* rwaToken */ => FeeConfig) public defaultFee;

  /// Optional override for default fees for (RWA, stablecoin) combinations
  mapping(address /* rwaToken */ => mapping(address /* stablecoin */ => FeeConfig)) public
    defaultFeeOverride;

  /// Optional override for user fees for (RWA, user) combinations
  mapping(address /* rwaToken */ => mapping(bytes32 /* userID */ => UserFeeConfig)) public userFee;

  /// Optional override for user fees for (RWA, user, stablecoin) combinations
  mapping(
    address /* rwaToken */
      => mapping(address /* stablecoin */ => mapping(bytes32 /* userId */ => UserFeeConfig))
  ) public userFeeOverride;

  /**
   * @notice Emitted when the default fee configuration is updated
   * @param  rwaToken The RWA token address the fee config is for
   * @param  active   Whether the fee config is active
   * @param  flatFee  The flat fee charged in USD with 18 decimals
   * @param  bpsFee   The basis points fee charged in `FEE_PRECISION` decimals
   *                  (1 basis point = 0.01% = 1)
   */
  event DefaultFeeConfigUpdated(address rwaToken, bool active, uint256 flatFee, uint256 bpsFee);

  /**
   * @notice Emitted when the default fee configuration override is updated
   * @param  rwaToken   The RWA token address the fee config is for
   * @param  stablecoin The stablecoin address the fee config is for
   * @param  active     Whether the fee config is active
   * @param  flatFee    The flat fee charged in USD with 18 decimals
   * @param  bpsFee     The basis points fee charged in `FEE_PRECISION` decimals
   *                    (1 basis point = 0.01% = 1)
   */
  event DefaultFeeConfigOverrideUpdated(
    address rwaToken, address stablecoin, bool active, uint256 flatFee, uint256 bpsFee
  );

  /**
   * @notice Emitted when the user fee configuration is updated
   * @param  rwaToken      The RWA token address associated with the fee config
   * @param  userID        The user ID associated with the fee config
   * @param  active        Whether the fee config is active
   * @param  flatFee       The flat fee charged in USD with 18 decimals
   * @param  bpsFee        The basis points fee charged in `FEE_PRECISION` decimals
   *                       (1 basis point = 0.01% = 1)
   * @param  userFeeMode   The user fee mode, either NO_FEE_UNTIL_LIMIT or NO_FEE_AFTER_LIMIT
   * @param  limitVolume   The volume limit for the user in a window, in USD with 18 decimals
   * @param  currentVolume The current volume for the user, in USD with 18 decimals
   * @param  lastReset     The timestamp of the last time the currentVolume was reset
   * @param  volumeWindow  The window for the volume limit in seconds
   */
  event UserFeeConfigUpdated(
    address rwaToken,
    bytes32 userID,
    bool active,
    uint256 flatFee,
    uint256 bpsFee,
    UserFeeMode userFeeMode,
    uint256 limitVolume,
    uint256 currentVolume,
    uint256 lastReset,
    uint256 volumeWindow
  );

  /**
   * @notice Emitted when the user fee configuration override is updated
   * @param  rwaToken      The RWA token address the fee config is for
   * @param  stablecoin    The stablecoin address the fee config is for
   * @param  userID        The user ID the fee config is for
   * @param  active        Whether the fee config is active
   * @param  flatFee       The flat fee charged in USD with 18 decimals
   * @param  bpsFee        The basis points fee charged in `FEE_PRECISION` decimals
   *                       (1 basis point = 0.01% = 1)
   * @param  userFeeMode   The user fee mode, either NO_FEE_UNTIL_LIMIT or NO_FEE_AFTER_LIMIT
   * @param  limitVolume   The volume limit for the user in a window, in USD with 18 decimals
   * @param  currentVolume The current volume for the user, in USD with 18 decimals
   * @param  lastReset     The timestamp of the last time the `currentVolume` was reset
   * @param  volumeWindow  The window for the volume limit in seconds
   */
  event UserFeeConfigOverrideUpdated(
    address rwaToken,
    address stablecoin,
    bytes32 userID,
    bool active,
    uint256 flatFee,
    uint256 bpsFee,
    UserFeeMode userFeeMode,
    uint256 limitVolume,
    uint256 currentVolume,
    uint256 lastReset,
    uint256 volumeWindow
  );

  /// Error thrown when attempting to get a fee when no fee is set
  error FeeNotSet();

  /// Error thrown when an invalid address of 0x0 is passed to the contract
  error InvalidAddress();

  /// Error thrown when an invalid user ID of 0x0 is passed to the contract
  error InvalidUserID();

  /// Error thrown when attempting to set bps fees to over 100%
  error InvalidBpsFee();

  /// Error thrown when attempting to set a timestamp in the future
  error InvalidTimestamp();

  /// @param guardian The address that will be granted the default admin role
  constructor(address guardian) {
    _grantRole(DEFAULT_ADMIN_ROLE, guardian);
  }

  /**
   * @notice Calculates the fee and potentially updates the user fee config if applicable
   * @param  rwaToken   The RWA token address the user is interacting with
   * @param  stablecoin The stablecoin the user is interacting with
   * @param  userID     The user ID
   * @param  usdValue   The USD value of the action, in 18 decimals
   * @return usdFee     The subscription fee in USD, in 18 decimals
   */
  function getAndUpdateFee(address rwaToken, address stablecoin, bytes32 userID, uint256 usdValue)
    external
    override
    onlyRole(CLIENT_ROLE)
    returns (uint256 usdFee)
  {
    // Pull the users fee config, which may be empty
    UserFeeConfig storage userFeeConfig = _getUserFeeConfig(rwaToken, stablecoin, userID);

    // Determine the fee config to use
    FeeConfig memory feeConfig;
    if (userFeeConfig.feeConfig.active) {
      // If the user has an active fee config, use it
      feeConfig = userFeeConfig.feeConfig;
      usdValue = _getEffectiveUSDValueAndUpdateUserFeeConfig(userFeeConfig, usdValue);
    } else if (defaultFeeOverride[rwaToken][stablecoin].active) {
      // If there is a default fee override for the stablecoin, use it
      feeConfig = defaultFeeOverride[rwaToken][stablecoin];
    } else if (defaultFee[rwaToken].active) {
      // If there is a default fee for the `rwaToken`, use it
      feeConfig = defaultFee[rwaToken];
    } else {
      // If no fee config is active, revert
      revert FeeNotSet();
    }

    usdFee = usdValue > 0 ? feeConfig.flatFee : 0;
    if (feeConfig.bpsFee > 0) {
      usdFee += _calculateBPSFee(feeConfig.bpsFee, usdValue);
    }
  }

  /**
   * @notice Gets the effective USD value and updates the user fee config
   * @param  userFeeConfig      The user fee config to update
   * @param  usdValue           The USD value of the transaction in 18 decimals
   * @return effectiveUSDValue  The effective USD value the user will be charged fees on,
   *                            in 18 decimals
   * @dev    This function factors in the current usdValue of the transaction to determine the
   *         effective USD value that the user will be charged fees on. The user may be
   *         charged fees on the entire value, a portion of the value, or none of the value.
   *         If the user has exceeded their volume window, the volume will be reset
   */
  function _getEffectiveUSDValueAndUpdateUserFeeConfig(
    UserFeeConfig storage userFeeConfig,
    uint256 usdValue
  ) internal returns (uint256 effectiveUSDValue) {
    if (block.timestamp - userFeeConfig.lastReset > userFeeConfig.volumeWindow) {
      // If the current volume window has expired, reset the volume and update the last reset time.
      userFeeConfig.currentVolume = 0;
      userFeeConfig.lastReset = block.timestamp;
    }

    effectiveUSDValue = 0;
    if (userFeeConfig.userFeeMode == UserFeeMode.NO_FEE_UNTIL_LIMIT) {
      // The user is charged fees on the volume exceeding the max volume
      if (userFeeConfig.currentVolume >= userFeeConfig.limitVolume) {
        // Volume window already exceeded, charge fees on full amount
        effectiveUSDValue = usdValue;
      } else if (userFeeConfig.currentVolume + usdValue > userFeeConfig.limitVolume) {
        // Incoming volume will exceed the max volume, charge fees on excess
        effectiveUSDValue = userFeeConfig.currentVolume + usdValue - userFeeConfig.limitVolume;
      }
    } else if (userFeeConfig.userFeeMode == UserFeeMode.NO_FEE_AFTER_LIMIT) {
      // The user is charged fees on the volume up until the max volume
      if (userFeeConfig.currentVolume < userFeeConfig.limitVolume) {
        // Incoming volume will exceed max volume, charge fees up until max volume
        if (userFeeConfig.currentVolume + usdValue > userFeeConfig.limitVolume) {
          effectiveUSDValue = userFeeConfig.limitVolume - userFeeConfig.currentVolume;
        } else {
          // Volume doesn't exceed the max volume, charge fees on full amount
          effectiveUSDValue = usdValue;
        }
      }
    }
    userFeeConfig.currentVolume += usdValue;
  }

  /**
   * @notice Calculates a fee based on USD value and basis points
   * @param  bps      The fee rate, in basis points
   * @param  usdValue The USD value to calculate the fee on
   * @return uint256  The fee in USD
   */
  function _calculateBPSFee(uint256 bps, uint256 usdValue) internal pure returns (uint256) {
    return (usdValue * bps) / FEE_PRECISION;
  }

  /**
   * @notice Gets the active fee config for a given (RWA Token, stablecoin, user) combination
   * @param  rwaToken            The RWA token address the user is interacting with
   * @param  stablecoin          The stablecoin the user is interacting with
   * @param  userID              The user ID
   * @return activeFeeConfig     The active fee config, empty if the user has a config
   * @return activeUserFeeConfig The active user fee config, empty if there is no user config
   * @dev    Returns at most one non-empty config
   */
  function getActiveFeeConfig(address rwaToken, address stablecoin, bytes32 userID)
    external
    view
    returns (FeeConfig memory activeFeeConfig, UserFeeConfig memory activeUserFeeConfig)
  {
    // Pull user specific fee config, which may or may not be active
    UserFeeConfig memory userFeeConfig = _getUserFeeConfig(rwaToken, stablecoin, userID);

    if (userFeeConfig.feeConfig.active) {
      // Active user fee configs take precedence over all others
      return (FeeConfig({active: false, flatFee: 0, bpsFee: 0}), userFeeConfig);
    } else if (defaultFeeOverride[rwaToken][stablecoin].active) {
      // Default fee (RWA Token, stablecoin) combinations take precedence next
      return (
        defaultFeeOverride[rwaToken][stablecoin],
        UserFeeConfig({
          feeConfig: FeeConfig({active: false, flatFee: 0, bpsFee: 0}),
          userFeeMode: UserFeeMode.NO_FEE_UNTIL_LIMIT,
          limitVolume: 0,
          currentVolume: 0,
          lastReset: 0,
          volumeWindow: 0
        })
      );
    } else {
      // Default fees for a RWA Token take last precedence
      // If the default fee is not set, this will return an empty fee config
      return (
        defaultFee[rwaToken],
        UserFeeConfig({
          feeConfig: FeeConfig({active: false, flatFee: 0, bpsFee: 0}),
          userFeeMode: UserFeeMode.NO_FEE_UNTIL_LIMIT,
          limitVolume: 0,
          currentVolume: 0,
          lastReset: 0,
          volumeWindow: 0
        })
      );
    }
  }

  /**
   * @notice Pull's the user fee config
   * @param  rwaToken   The RWA token address the user is interacting with
   * @param  stablecoin The stablecoin the user is interacting with
   * @param  userID     The user ID
   * @return            The user fee config
   * @dev    Will return inactive user fee struct if user fee config is not set
   */
  function _getUserFeeConfig(address rwaToken, address stablecoin, bytes32 userID)
    internal
    view
    returns (UserFeeConfig storage)
  {
    if (userFeeOverride[rwaToken][stablecoin][userID].feeConfig.active) {
      // If the user has a fee config override for the stablecoin, use this.
      return userFeeOverride[rwaToken][stablecoin][userID];
    } else {
      return userFee[rwaToken][userID];
    }
  }

  /**
   * @notice Admin helper to reset the user fee config volume window
   * @param rwaToken         The RWA token address the user is interacting with
   * @param stablecoin       The stablecoin the user is interacting with
   * @param userID           The user ID
   * @param newVolume        The new volume for the user fee configuration
   * @param newLastResetTime The new reset timestamp. If 0, the current block timestamp will be
   *                         used.
   */
  function setUserFeeConfigWindow(
    address rwaToken,
    address stablecoin,
    bytes32 userID,
    uint256 newVolume,
    uint256 newLastResetTime
  ) external onlyRole(FEE_MANAGER_ROLE) {
    if (rwaToken == address(0)) {
      revert InvalidAddress();
    }
    if (userID == 0) revert InvalidUserID();
    if (newLastResetTime > block.timestamp) revert InvalidTimestamp();

    UserFeeConfig storage userFeeConfig = stablecoin == address(0)
      ? userFee[rwaToken][userID]
      : userFeeOverride[rwaToken][stablecoin][userID];
    if (!userFeeConfig.feeConfig.active) revert FeeNotSet();

    // If reset time is 0, set it to the current block timestamp
    if (newLastResetTime == 0) newLastResetTime = block.timestamp;

    userFeeConfig.currentVolume = newVolume;
    userFeeConfig.lastReset = newLastResetTime;
  }

  /**
   * @notice Sets the default fee configuration for a specific RWA token
   * @param  rwaToken The RWA token address to associate fee config with
   */
  function setDefaultFee(address rwaToken, FeeConfig memory feeConfig)
    external
    onlyRole(FEE_MANAGER_ROLE)
  {
    if (rwaToken == address(0)) revert InvalidAddress();
    if (feeConfig.bpsFee > FEE_PRECISION) revert InvalidBpsFee();
    defaultFee[rwaToken] = feeConfig;

    emit DefaultFeeConfigUpdated(rwaToken, feeConfig.active, feeConfig.flatFee, feeConfig.bpsFee);
  }

  /**
   * @notice Sets the default fee configuration (RWA token, stablecoin) combination
   * @param  rwaToken   The RWA token address to associate fee config with
   * @param  stablecoin The stablecoin to associate fee config with
   * @param  feeConfig  The default fee config
   */
  function setDefaultFeeOverride(address rwaToken, address stablecoin, FeeConfig memory feeConfig)
    external
    onlyRole(FEE_MANAGER_ROLE)
  {
    if (rwaToken == address(0) || stablecoin == address(0)) {
      revert InvalidAddress();
    }
    if (feeConfig.bpsFee > FEE_PRECISION) revert InvalidBpsFee();
    defaultFeeOverride[rwaToken][stablecoin] = feeConfig;

    emit DefaultFeeConfigOverrideUpdated(
      rwaToken, stablecoin, feeConfig.active, feeConfig.flatFee, feeConfig.bpsFee
    );
  }

  /**
   * @notice Sets the user fee configuration for a (RWA Token, user) combination
   * @param  rwaToken      The RWA token address to associate the user fee config with
   * @param  userID        The user ID to associate user fee config with
   * @param  userFeeConfig The user fee config active for the (RWA token, user) combination
   */
  function setUserFee(address rwaToken, bytes32 userID, UserFeeConfig memory userFeeConfig)
    external
    onlyRole(FEE_MANAGER_ROLE)
  {
    if (rwaToken == address(0)) {
      revert InvalidAddress();
    }
    if (userID == 0) revert InvalidUserID();
    if (userFeeConfig.feeConfig.bpsFee > FEE_PRECISION) revert InvalidBpsFee();

    userFee[rwaToken][userID] = userFeeConfig;

    emit UserFeeConfigUpdated(
      rwaToken,
      userID,
      userFeeConfig.feeConfig.active,
      userFeeConfig.feeConfig.flatFee,
      userFeeConfig.feeConfig.bpsFee,
      userFeeConfig.userFeeMode,
      userFeeConfig.limitVolume,
      userFeeConfig.currentVolume,
      userFeeConfig.lastReset,
      userFeeConfig.volumeWindow
    );
  }

  /**
   * @notice Sets the user fee configuration for (RWA token, stablecoin, and
   *         user) combination
   * @param  rwaToken      The RWA token address to associate user fee config with with
   * @param  stablecoin    The stablecoin address to associate user fee config with
   * @param  userID        The user ID to associate user fee config override with
   * @param  userFeeConfig The user fee config active for the (RWA token, stablecoin, user) combination
   */
  function setUserFeeOverride(
    address rwaToken,
    address stablecoin,
    bytes32 userID,
    UserFeeConfig memory userFeeConfig
  ) external onlyRole(FEE_MANAGER_ROLE) {
    if (rwaToken == address(0) || stablecoin == address(0)) {
      revert InvalidAddress();
    }
    if (userID == 0) revert InvalidUserID();
    if (userFeeConfig.feeConfig.bpsFee > FEE_PRECISION) revert InvalidBpsFee();

    userFeeOverride[rwaToken][stablecoin][userID] = userFeeConfig;

    emit UserFeeConfigOverrideUpdated(
      rwaToken,
      stablecoin,
      userID,
      userFeeConfig.feeConfig.active,
      userFeeConfig.feeConfig.flatFee,
      userFeeConfig.feeConfig.bpsFee,
      userFeeConfig.userFeeMode,
      userFeeConfig.limitVolume,
      userFeeConfig.currentVolume,
      userFeeConfig.lastReset,
      userFeeConfig.volumeWindow
    );
  }
}
