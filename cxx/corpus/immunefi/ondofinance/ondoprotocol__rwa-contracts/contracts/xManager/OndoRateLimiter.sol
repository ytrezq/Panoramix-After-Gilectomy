//SPDX-License-Identifier: MIT
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

import {IOndoRateLimiter} from "contracts/xManager/interfaces/IOndoRateLimiter.sol";
import {
  AccessControlEnumerable
} from "contracts/external/openzeppelin/contracts/access/AccessControlEnumerable.sol";

/**
 * @title  OndoRateLimiter
 * @author Ondo Finance
 * @notice The OndoRateLimiter contract manages rate limits for subscriptions
 *         and redemptions. It allows the configuration of global rate limits for all users and
 *         specific rate limits for individual users. Even if a user has a specific rate limit,
 *         the global rate limit will always be respected. The rate limits are defined in
 *         terms of a maximum allowable amount (in USD with 18 decimals) within a specified window.
 */
contract OndoRateLimiter is IOndoRateLimiter, AccessControlEnumerable {
  /// Role for the client contracts using this rate limiter
  bytes32 public constant CLIENT_ROLE = keccak256("CLIENT_ROLE");

  /// Role for the admin who can configure the rate limit state for users
  bytes32 public constant CONFIGURER_ROLE = keccak256("CONFIGURER_ROLE");

  /**
   * @notice Rate Limit struct
   * @param  capacityUsed Current amount (in USD with 18 decimals) within the rate limit window
   * @param  lastUpdated  Timestamp (in seconds) representing the last time the rate limit was
   *                      checked and updated
   * @param  limit        This represents the maximum allowed amount (in USD with 18 decimals)
   *                      within a given window
   * @param  window       Defines the duration (in seconds) of the rate limiting window
   */
  struct RateLimit {
    uint256 capacityUsed;
    uint256 lastUpdated;
    uint256 limit;
    uint48 window;
  }

  /**
   * @notice Rate Limit configuration struct
   * @param  limit  The maximum allowable amount (in USD with 18 decimals) within the specified window
   * @param  window The time window (in seconds) for which the limit applies
   */
  struct RateLimitConfig {
    uint256 limit;
    uint48 window;
  }

  /// Global rate limits for subscriptions for each RWA token
  mapping(address /* rwaToken */ => RateLimit) public globalSubscriptionLimits;

  /// Global rate limits for redemptions for each RWA token
  mapping(address /* rwaToken */ => RateLimit) public globalRedemptionLimits;

  /// User-specific rate limits for subscriptions for each RWA token
  mapping(address /* rwaToken */ => mapping(bytes32 /* user ID */ => RateLimit)) public
    userSubscriptionLimits;

  /// User-specific rate limits for redemptions for each RWA token
  mapping(address /* rwaToken */ => mapping(bytes32 /* user ID */ => RateLimit)) public
    userRedemptionLimits;

  /// Default user rate limit configurations for subscriptions for each RWA token
  mapping(address /* rwaToken */ => RateLimitConfig) public defaultUserSubscriptionLimitConfigs;

  /// Default user rate limit configurations for redemptions for each RWA token
  mapping(address /* rwaToken */ => RateLimitConfig) public defaultUserRedemptionLimitConfigs;

  /**
   * @notice Event emitted when `setGlobalSubscriptionLimit` or `setGlobalRedemptionLimit` is
   *         called
   * @param  transactionType The type of transaction (SUBSCRIPTION or REDEMPTION)
   *                         the new limit applies to.
   * @param  rwaToken        The address of the RWA token the new limit applies to
   * @param  limit           The new maximum allowable amount (in USD) within the specified window
   * @param  window          The new time window (in seconds) for which the limit applies
   */
  event GlobalRateLimitSet(
    TransactionType transactionType, address rwaToken, uint256 limit, uint48 window
  );

  /**
   * @notice Event emitted when `setDefaultUserSubscriptionLimitConfig` or
   *         `setDefaultUserRedemptionLimitConfig` is called
   * @param  transactionType The type of transaction (SUBSCRIPTION or REDEMPTION) the new
   *                         limit applies to.
   * @param  rwaToken        The address of the RWA token the new limit applies to
   * @param  limit           The new maximum allowable amount (in USD) within the specified window
   * @param  window          The new time window (in seconds) for which the limit applies
   */
  event DefaultUserRateLimitSet(
    TransactionType transactionType, address rwaToken, uint256 limit, uint48 window
  );

  /**
   * @notice Event emitted when `setUserSubscriptionRateLimit` or
   *         `setUserRedemptionRateLimit` is called
   * @param  transactionType The type of transaction (SUBSCRIPTION or REDEMPTION) the new limit applies to
   * @param  rwaToken        The address of the RWA token the new limit applies to
   * @param  userID          The ID of the user the new limit applies to
   * @param  limit           The new maximum allowable amount (in USD) within the specified window
   * @param  window          The new time window (in seconds) for which the limit applies
   */
  event UserRateLimitSet(
    TransactionType transactionType, address rwaToken, bytes32 userID, uint256 limit, uint48 window
  );

  /// Error thrown when an amount exceeds the rate limiter
  error RateLimitExceeded();

  /// Error thrown when the global rate limit is not set
  error GlobalRateLimitNotSet();

  /// Error thrown when the default user rate limit is not set
  error DefaultUserRateLimitNotSet();

  /// Error thrown when attempting to set a rate limit for an RWAToken with zero address
  error RWAAddressCantBeZero();

  /// Error thrown when attempting to set a rate limit for a user with zero ID
  error UserIDCantBeZero();

  /**
   * @param guardian The address of the guardian who will be granted the default admin role
   */
  constructor(address guardian) {
    _grantRole(DEFAULT_ADMIN_ROLE, guardian);
  }

  /**
   * @notice Checks and updates the rate limit for a given user and RWA token
   * @param  transactionType The type of transaction (SUBSCRIPTION or REDEMPTION)
   * @param  rwaToken        The address of the RWA token being transacted
   * @param  userID          The ID of the user
   * @param  usdValue        The value of the transaction, in USD with 18 decimals
   */
  function checkAndUpdateRateLimit(
    TransactionType transactionType,
    address rwaToken,
    bytes32 userID,
    uint256 usdValue
  ) external onlyRole(CLIENT_ROLE) {
    RateLimit storage globalRl = transactionType == TransactionType.SUBSCRIPTION
      ? globalSubscriptionLimits[rwaToken]
      : globalRedemptionLimits[rwaToken];

    if (globalRl.lastUpdated == 0) revert GlobalRateLimitNotSet();

    // Get global available capacity based on the rate limit configuration and time elapsed
    (uint256 globalCurrentCapacityUsed, uint256 globalAvailableCapacity) =
      _calculateDecay(globalRl.capacityUsed, globalRl.lastUpdated, globalRl.limit, globalRl.window);

    if (usdValue > globalAvailableCapacity) revert RateLimitExceeded();

    RateLimit storage userRl = transactionType == TransactionType.SUBSCRIPTION
      ? userSubscriptionLimits[rwaToken][userID]
      : userRedemptionLimits[rwaToken][userID];

    // If the user rate limit has not been set, instantiate it with the default configuration
    if (userRl.lastUpdated == 0) {
      _instantiateUserRateLimits(transactionType, rwaToken, userID);
    }

    // Get user's available capacity based on the rate limit configuration and time elapsed
    (uint256 userCurrentCapacityUsed, uint256 userAvailableCapacity) =
      _calculateDecay(userRl.capacityUsed, userRl.lastUpdated, userRl.limit, userRl.window);

    if (usdValue > userAvailableCapacity) revert RateLimitExceeded();

    globalRl.capacityUsed = globalCurrentCapacityUsed + usdValue;
    globalRl.lastUpdated = block.timestamp;
    userRl.capacityUsed = userCurrentCapacityUsed + usdValue;
    userRl.lastUpdated = block.timestamp;
  }

  /**
   * @notice Instantiates the rate limit state for a new user based on the default configuration
   * @param  transactionType The type of transaction (SUBSCRIPTION or REDEMPTION) for which
   *         the rate limit is being set
   * @param  rwaToken        The address of the RWA token for which the rate limit is being set
   * @param  userID          The ID of the user for which the rate limit is being set
   * @dev    In order to transact, a default rate limit configuration must be set for users
   */
  function _instantiateUserRateLimits(
    TransactionType transactionType,
    address rwaToken,
    bytes32 userID
  ) internal {
    RateLimitConfig memory rlConfig = transactionType == TransactionType.SUBSCRIPTION
      ? defaultUserSubscriptionLimitConfigs[rwaToken]
      : defaultUserRedemptionLimitConfigs[rwaToken];
    if (rlConfig.limit == 0) revert DefaultUserRateLimitNotSet();

    RateLimit storage userRl = transactionType == TransactionType.SUBSCRIPTION
      ? userSubscriptionLimits[rwaToken][userID]
      : userRedemptionLimits[rwaToken][userID];

    userRl.capacityUsed = 0;
    userRl.lastUpdated = block.timestamp;
    userRl.limit = rlConfig.limit;
    userRl.window = rlConfig.window;
  }

  /**
   * @notice Calculates the current capacity used and the available capacity based on the rate
   *         limit configuration and time elapsed
   * @param  _capacityUsed       The total capacity used at the last update
   * @param  _lastUpdated        The timestamp (in seconds) when the last update occurred
   * @param  _limit              The maximum allowable amount within the specified window
   * @param  _window             The time window (in seconds) for which the limit applies
   * @return currentCapacityUsed The decayed amount of capacity used based on the elapsed time
   *                             since `lastUpdated`. If the time since `lastUpdated` exceeds the
   *                             window, it returns zero.
   * @return availableCapacity   The amount of capacity available for new activity. If the time
   *                             since lastUpdated exceeds the window, it returns the full limit.
   * @dev    This function applies a linear decay model to compute how much of the 'capacityUsed'
   *         remains based on the time elapsed since the last update.
   */
  function _calculateDecay(
    uint256 _capacityUsed,
    uint256 _lastUpdated,
    uint256 _limit,
    uint48 _window
  ) internal view returns (uint256 currentCapacityUsed, uint256 availableCapacity) {
    uint256 timeSinceLastUpdate = block.timestamp - _lastUpdated;
    if (timeSinceLastUpdate >= _window) {
      return (0, _limit);
    } else {
      uint256 decay = (_limit * timeSinceLastUpdate) / _window;
      currentCapacityUsed = _capacityUsed > decay ? _capacityUsed - decay : 0;
      availableCapacity = _limit > currentCapacityUsed ? _limit - currentCapacityUsed : 0;
      return (currentCapacityUsed, availableCapacity);
    }
  }

  /**
   * @notice Returns the current global subscription limit for a given RWA token,
   *         factoring in the decay
   * @param  rwaToken            The address of the RWA token
   * @return currentCapacityUsed The current capacity used based on the decay model
   * @return availableCapacity   The available capacity for new subscriptions
   */
  function getCurrentGlobalSubscriptionLimit(address rwaToken)
    external
    view
    returns (uint256 currentCapacityUsed, uint256 availableCapacity)
  {
    RateLimit memory rl = globalSubscriptionLimits[rwaToken];
    return _calculateDecay(rl.capacityUsed, rl.lastUpdated, rl.limit, rl.window);
  }

  /**
   * @notice Returns current global redemption limit for a given RWA token,
   *         factoring in the decay
   * @param  rwaToken            The address of the RWA token
   * @return currentCapacityUsed The current capacity used based on the decay model
   * @return availableCapacity   The available capacity for new redemptions
   */
  function getCurrentGlobalRedemptionLimit(address rwaToken)
    external
    view
    returns (uint256 currentCapacityUsed, uint256 availableCapacity)
  {
    RateLimit memory rl = globalRedemptionLimits[rwaToken];
    return _calculateDecay(rl.capacityUsed, rl.lastUpdated, rl.limit, rl.window);
  }

  /**
   * @notice Returns the current subscription limit for a given user,
   *         factoring in the decay
   * @param  rwaToken            The address of the RWA token
   * @param  userID              The ID of the user
   * @return currentCapacityUsed The current capacity used based on the decay model
   * @return availableCapacity   The available capacity for new subscriptions
   */
  function getCurrentUserSubscriptionLimit(address rwaToken, bytes32 userID)
    external
    view
    returns (uint256 currentCapacityUsed, uint256 availableCapacity)
  {
    RateLimit memory rl = userSubscriptionLimits[rwaToken][userID];
    return _calculateDecay(rl.capacityUsed, rl.lastUpdated, rl.limit, rl.window);
  }

  /**
   * @notice Returns the current redemption limit for a given user, factoring in
   *         the decay.
   * @param  rwaToken            The address of the RWA token
   * @param  userID              The ID of the user
   * @return currentCapacityUsed The current capacity used based on the decay model
   * @return availableCapacity   The available capacity for new redemptions
   */
  function getCurrentUserRedemptionLimit(address rwaToken, bytes32 userID)
    external
    view
    returns (uint256 currentCapacityUsed, uint256 availableCapacity)
  {
    RateLimit memory rl = userRedemptionLimits[rwaToken][userID];
    return _calculateDecay(rl.capacityUsed, rl.lastUpdated, rl.limit, rl.window);
  }

  /**
   * @notice Sets the global subscription limit for a given RWA token.
   * @param  rwaToken The address of the RWA token.
   * @param  limit    The maximum allowable amount (in USD) within the specified window.
   * @param  window   The time window (in seconds) for which the limit applies.
   */
  function setGlobalSubscriptionLimit(address rwaToken, uint256 limit, uint48 window)
    external
    onlyRole(CONFIGURER_ROLE)
  {
    if (rwaToken == address(0)) revert RWAAddressCantBeZero();

    globalSubscriptionLimits[rwaToken] =
      RateLimit({capacityUsed: 0, lastUpdated: block.timestamp, limit: limit, window: window});

    emit GlobalRateLimitSet(TransactionType.SUBSCRIPTION, rwaToken, limit, window);
  }

  /**
   * @notice Sets the global redemption limit for a given RWA token.
   * @param  rwaToken The address of the RWA token.
   * @param  limit    The maximum allowable amount (in USD) within the specified window.
   * @param  window   The time window (in seconds) for which the limit applies.
   */
  function setGlobalRedemptionLimit(address rwaToken, uint256 limit, uint48 window)
    external
    onlyRole(CONFIGURER_ROLE)
  {
    if (rwaToken == address(0)) revert RWAAddressCantBeZero();

    globalRedemptionLimits[rwaToken] =
      RateLimit({capacityUsed: 0, lastUpdated: block.timestamp, limit: limit, window: window});

    emit GlobalRateLimitSet(TransactionType.REDEMPTION, rwaToken, limit, window);
  }

  /**
   * @notice Sets the default subscription limit configuration for a given RWA token.
   * @param  rwaToken The address of the RWA token.
   * @param  limit    The maximum allowable amount (in USD) within the specified window.
   * @param  window   The time window (in seconds) for which the limit applies.
   */
  function setDefaultUserSubscriptionLimitConfig(address rwaToken, uint256 limit, uint48 window)
    external
    onlyRole(CONFIGURER_ROLE)
  {
    if (rwaToken == address(0)) revert RWAAddressCantBeZero();

    defaultUserSubscriptionLimitConfigs[rwaToken] = RateLimitConfig({limit: limit, window: window});

    emit DefaultUserRateLimitSet(TransactionType.SUBSCRIPTION, rwaToken, limit, window);
  }

  /**
   * @notice Sets the default redemption limit configuration for a given RWA token.
   * @param  rwaToken The address of the RWA token.
   * @param  limit    The maximum allowable amount (in USD) within the specified window.
   * @param  window   The time window (in seconds) for which the limit applies.
   */
  function setDefaultUserRedemptionLimitConfig(address rwaToken, uint256 limit, uint48 window)
    external
    onlyRole(CONFIGURER_ROLE)
  {
    if (rwaToken == address(0)) revert RWAAddressCantBeZero();

    defaultUserRedemptionLimitConfigs[rwaToken] = RateLimitConfig({limit: limit, window: window});

    emit DefaultUserRateLimitSet(TransactionType.REDEMPTION, rwaToken, limit, window);
  }

  /**
   * @notice Sets the subscription rate limit for a specific user.
   * @param  rwaToken           The address of the RWA token.
   * @param  userID             The ID of the user.
   * @param  subscriptionLimit  The maximum allowable amount (in USD) within the specified window.
   * @param  subscriptionWindow The time window (in seconds) for which the limit applies.
   */
  function setUserSubscriptionRateLimit(
    address rwaToken,
    bytes32 userID,
    uint256 subscriptionLimit,
    uint48 subscriptionWindow
  ) external onlyRole(CONFIGURER_ROLE) {
    if (rwaToken == address(0)) {
      revert RWAAddressCantBeZero();
    }
    if (userID == 0) revert UserIDCantBeZero();

    userSubscriptionLimits[rwaToken][userID] = RateLimit({
      capacityUsed: 0,
      lastUpdated: block.timestamp,
      limit: subscriptionLimit,
      window: subscriptionWindow
    });

    emit UserRateLimitSet(
      TransactionType.SUBSCRIPTION, rwaToken, userID, subscriptionLimit, subscriptionWindow
    );
  }

  /**
   * @notice Sets the redemption rate limit for a specific user.
   * @param  rwaToken         The address of the RWA token
   * @param  userID           The ID of the user
   * @param  redemptionLimit  The maximum allowable amount (in USD) within the specified window
   * @param  redemptionWindow The time window (in seconds) for which the limit applies
   */
  function setUserRedemptionRateLimit(
    address rwaToken,
    bytes32 userID,
    uint256 redemptionLimit,
    uint48 redemptionWindow
  ) external onlyRole(CONFIGURER_ROLE) {
    if (rwaToken == address(0)) {
      revert RWAAddressCantBeZero();
    }
    if (userID == 0) revert UserIDCantBeZero();

    userRedemptionLimits[rwaToken][userID] = RateLimit({
      capacityUsed: 0,
      lastUpdated: block.timestamp,
      limit: redemptionLimit,
      window: redemptionWindow
    });

    emit UserRateLimitSet(
      TransactionType.REDEMPTION, rwaToken, userID, redemptionLimit, redemptionWindow
    );
  }
}
