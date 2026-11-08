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

import {GMTokenManager} from "contracts/globalMarkets/tokenManager/GMTokenManager.sol";
import {OndoRateLimiter} from "contracts/xManager/OndoRateLimiter.sol";
import {IRegistrar} from "contracts/globalMarkets/tokenFactory/registrars/IRegistrar.sol";
import {
  AccessControlEnumerable
} from "contracts/external/openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {Pausable} from "contracts/external/openzeppelin/contracts/security/Pausable.sol";
import {
  IAccessControlEnumerable
} from "contracts/external/openzeppelin/contracts/access/IAccessControlEnumerable.sol";

/**
 * @title  TokenManagerRegistrar
 * @author Ondo Finance
 * @notice This contract is responsible for registering new tokens with the GM Token Management
 *         system. It allows for the registration of new tokens, setting the GM Token Manager,
 *         and configuring rate limits for those tokens.
 */
contract TokenManagerRegistrar is IRegistrar, AccessControlEnumerable, Pausable {
  /// Role for changing the token manager, rate limiter and configs
  bytes32 public constant CONFIGURER_ROLE = keccak256("CONFIGURER_ROLE");
  /// Role for the token factory that can register new tokens
  bytes32 public constant TOKEN_FACTORY_ROLE = keccak256("TOKEN_FACTORY_ROLE");
  /// Role allowed to pause the registrar
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
  /// Role allowed to unpause the registrar
  bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

  /**
   * @notice Configuration for the rate limits initialized for new tokens
   * @param  subscriptionLimit  The subscription limit over the time window in USD with 18 decimals
   * @param  redemptionLimit    The redemption limit over the time window in USD with 18 decimals
   * @param  subscriptionWindow The time window in seconds for subscription limits
   * @param  redemptionWindow   The time window in seconds for redemption limits
   */
  struct RateLimitConfig {
    uint256 subscriptionLimit;
    uint256 redemptionLimit;
    uint48 subscriptionWindow;
    uint48 redemptionWindow;
  }

  /// Global rate limit configuration
  RateLimitConfig public globalLimits;

  /// Default user rate limit configuration
  RateLimitConfig public defaultUserLimits;

  /// Address of the GM Token Manager that will handle minting/redeeming
  GMTokenManager public gmTokenManager;

  /// Address of the rate limiter that will handle token limits
  OndoRateLimiter public ondoRateLimiter;

  /**
   * @notice Emitted when the `GMTokenManager` is set
   * @param  oldManager The old `GMTokenManager` address
   * @param  newManager The new `GMTokenManager` address
   */
  event GMTokenManagerSet(address indexed oldManager, address indexed newManager);

  /**
   * @notice Emitted when the `OndoRateLimiter` address is updated
   * @param  oldRateLimiter The old rate limiter address
   * @param  newRateLimiter The new rate limiter address
   */
  event RateLimiterSet(address indexed oldRateLimiter, address indexed newRateLimiter);

  /**
   * @notice Emitted when the global limit configurations used for new tokens are updated
   * @param  subscriptionLimit  The new global subscription limit amount in USD with 18 decimals
   * @param  subscriptionWindow The new global subscription time window in seconds
   * @param  redemptionLimit    The new global redemption limit amount in USD with 18 decimals
   * @param  redemptionWindow   The new global redemption time window in seconds
   */
  event GlobalLimitConfigsSet(
    uint256 subscriptionLimit,
    uint48 subscriptionWindow,
    uint256 redemptionLimit,
    uint48 redemptionWindow
  );

  /**
   * @notice Emitted when the default user limit configurations used for new tokens are updated
   * @param  subscriptionLimit  The new default user subscription limit amount in USD with 18 decimals
   * @param  subscriptionWindow The new default user subscription time window in seconds
   * @param  redemptionLimit    The new default user redemption limit amount in USD with 18 decimals
   * @param  redemptionWindow   The new default user redemption time window in seconds
   */
  event DefaultUserLimitConfigsSet(
    uint256 subscriptionLimit,
    uint48 subscriptionWindow,
    uint256 redemptionLimit,
    uint48 redemptionWindow
  );

  /**
   * @notice Emitted when a new token is registered
   * @param token The address of the token that was registered following a deployment
   */
  event TokenRegistered(address indexed token);

  /// Error thrown when attempting to set the GM Token Manager to zero address
  error GMTokenManagerCantBeZero();

  /// Error thrown when attempting to set the rate limiter to zero address
  error RateLimiterCantBeZero();

  /// Error thrown when attempting to register a token with zero address
  error TokenAddressCantBeZero();

  /**
   * @notice Constructor to initialize the contract with the GM Token Manager and rate limiter
   * @param  guardian         The address of the admin account that begins with the default admin role
   * @param  _gmTokenManager  The address of the GM Token Manager contract
   * @param  _ondoRateLimiter The address of the Ondo Rate Limiter contract
   */
  constructor(address guardian, address _gmTokenManager, address _ondoRateLimiter) {
    if (_gmTokenManager == address(0)) {
      revert GMTokenManagerCantBeZero();
    }
    if (_ondoRateLimiter == address(0)) revert RateLimiterCantBeZero();
    gmTokenManager = GMTokenManager(_gmTokenManager);
    ondoRateLimiter = OndoRateLimiter(_ondoRateLimiter);

    _grantRole(DEFAULT_ADMIN_ROLE, guardian);
    _grantRole(CONFIGURER_ROLE, guardian);
    _grantRole(PAUSER_ROLE, guardian);
    _grantRole(UNPAUSER_ROLE, guardian);
  }

  /**
   * @notice Pauses the registrar, disabling registration
   */
  function pause() external onlyRole(PAUSER_ROLE) {
    _pause();
  }

  /**
   * @notice Unpauses the registrar, enabling registration
   */
  function unpause() external onlyRole(UNPAUSER_ROLE) {
    _unpause();
  }

  /**
   * @notice Registers a new token with the GM Token Manager and configures rate limits
   * @param  token The address of the token to register
   * @dev    Only callable by accounts with TOKEN_FACTORY_ROLE
   */
  function register(address token) external override onlyRole(TOKEN_FACTORY_ROLE) whenNotPaused {
    if (token == address(0)) revert TokenAddressCantBeZero();

    gmTokenManager.setGMTokenRegistrationStatus(token, true);
    // Grant minter role to GM Token Manager
    IAccessControlEnumerable(token).grantRole(keccak256("MINTER_ROLE"), address(gmTokenManager));

    // Configure rate limiter for token
    ondoRateLimiter.setGlobalSubscriptionLimit(
      token, globalLimits.subscriptionLimit, globalLimits.subscriptionWindow
    );
    ondoRateLimiter.setGlobalRedemptionLimit(
      token, globalLimits.redemptionLimit, globalLimits.redemptionWindow
    );

    ondoRateLimiter.setDefaultUserSubscriptionLimitConfig(
      token, defaultUserLimits.subscriptionLimit, defaultUserLimits.subscriptionWindow
    );
    ondoRateLimiter.setDefaultUserRedemptionLimitConfig(
      token, defaultUserLimits.redemptionLimit, defaultUserLimits.redemptionWindow
    );

    emit TokenRegistered(token);
  }

  /**
   * @notice Sets or updates the GM Token Manager address
   * @param  _gmTokenManager The new GM Token Manager address
   */
  function setGMTokenManager(address _gmTokenManager) external onlyRole(CONFIGURER_ROLE) {
    if (_gmTokenManager == address(0)) {
      revert GMTokenManagerCantBeZero();
    }

    emit GMTokenManagerSet(address(gmTokenManager), _gmTokenManager);
    gmTokenManager = GMTokenManager(_gmTokenManager);
  }

  /**
   * @notice Sets or updates the rate limiter address
   * @param  _rateLimiter The new rate limiter address
   */
  function setRateLimiter(address _rateLimiter) external onlyRole(CONFIGURER_ROLE) {
    if (_rateLimiter == address(0)) revert RateLimiterCantBeZero();

    emit RateLimiterSet(address(ondoRateLimiter), _rateLimiter);
    ondoRateLimiter = OndoRateLimiter(_rateLimiter);
  }

  /**
   * @notice Sets the global rate limit configurations for mints and redemptions
   * @param  subscriptionLimit  Global subscription limit amount in USD with 18 decimals
   * @param  subscriptionWindow Global subscription time window in seconds
   * @param  redemptionLimit    Global redemption limit amount in USD with 18 decimals
   * @param  redemptionWindow   Global redemption time window in seconds
   */
  function setGlobalLimitConfigs(
    uint256 subscriptionLimit,
    uint48 subscriptionWindow,
    uint256 redemptionLimit,
    uint48 redemptionWindow
  ) external onlyRole(CONFIGURER_ROLE) {
    globalLimits = RateLimitConfig({
      subscriptionLimit: subscriptionLimit,
      redemptionLimit: redemptionLimit,
      subscriptionWindow: subscriptionWindow,
      redemptionWindow: redemptionWindow
    });

    emit GlobalLimitConfigsSet(
      subscriptionLimit, subscriptionWindow, redemptionLimit, redemptionWindow
    );
  }

  /**
   * @notice Sets the default user rate limit configurations for mints and redemptions
   * @param  subscriptionLimit  Default user subscription limit amount in USD with 18 decimals
   * @param  subscriptionWindow Default user subscription time window in seconds
   * @param  redemptionLimit    Default user redemption limit amount in USD with 18 decimals
   * @param  redemptionWindow   Default user redemption time window in seconds
   */
  function setDefaultUserLimitConfigs(
    uint256 subscriptionLimit,
    uint48 subscriptionWindow,
    uint256 redemptionLimit,
    uint48 redemptionWindow
  ) external onlyRole(CONFIGURER_ROLE) {
    defaultUserLimits = RateLimitConfig({
      subscriptionLimit: subscriptionLimit,
      redemptionLimit: redemptionLimit,
      subscriptionWindow: subscriptionWindow,
      redemptionWindow: redemptionWindow
    });

    emit DefaultUserLimitConfigsSet(
      subscriptionLimit, subscriptionWindow, redemptionLimit, redemptionWindow
    );
  }
}
