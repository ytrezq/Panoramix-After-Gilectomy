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

import {
  IPortfolioTokenManager
} from "contracts/globalMarkets/portfolioToken/portfolioTokenManager/IPortfolioTokenManager.sol";
import {IRegistrar} from "contracts/globalMarkets/tokenFactory/registrars/IRegistrar.sol";
import {
  AccessControlEnumerable
} from "contracts/external/openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {Pausable} from "contracts/external/openzeppelin/contracts/security/Pausable.sol";
import {
  IAccessControlEnumerable
} from "contracts/external/openzeppelin/contracts/access/IAccessControlEnumerable.sol";
import {OndoRateLimiter} from "contracts/xManager/OndoRateLimiter.sol";

/**
 * @title  PortfolioTokenRegistrar
 * @author Ondo Finance
 * @notice Chain-agnostic registrar that configures new portfolio tokens with the
 *         PortfolioTokenManager. Called by the PortfolioTokenFactory during
 *         deployAndRegisterToken.
 *
 *         For each new token, this registrar:
 *         - Registers the token with PortfolioTokenManager
 *         - Grants MINTER_ROLE to PortfolioTokenManager on the token
 *         - Configures rate limits on OndoRateLimiter
 *
 *         On the primary chain, orchestrator acceptance and escrow deployment
 *         are handled separately after registration.
 */
contract PortfolioTokenRegistrar is IRegistrar, AccessControlEnumerable, Pausable {
  /// Role for changing configuration
  bytes32 public constant CONFIGURER_ROLE = keccak256("CONFIGURER_ROLE");
  /// Role for the token factory that can register new tokens
  bytes32 public constant TOKEN_FACTORY_ROLE = keccak256("TOKEN_FACTORY_ROLE");
  /// Role allowed to pause the registrar
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
  /// Role allowed to unpause the registrar
  bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
  /// Minter role granted to PortfolioTokenManager on new tokens
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

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

  /// Address of the PortfolioTokenManager
  IPortfolioTokenManager public portfolioTokenManager;

  /// Address of the rate limiter that will handle token limits
  OndoRateLimiter public ondoRateLimiter;

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
   * @param  token The address of the token that was registered
   */
  event TokenRegistered(address indexed token);

  /// Error thrown when guardian address is zero
  error GuardianCantBeZero();

  /// Error thrown when attempting to set the PortfolioTokenManager to zero address
  error PortfolioTokenManagerCantBeZero();

  /// Error thrown when attempting to set the rate limiter to zero address
  error RateLimiterCantBeZero();

  /// Error thrown when attempting to register a token with zero address
  error TokenAddressCantBeZero();

  /**
   * @param guardian               The address of the admin account
   * @param _portfolioTokenManager The address of the PortfolioTokenManager contract
   * @param _ondoRateLimiter       The address of the OndoRateLimiter contract
   */
  constructor(address guardian, address _portfolioTokenManager, address _ondoRateLimiter) {
    if (guardian == address(0)) revert GuardianCantBeZero();
    if (_portfolioTokenManager == address(0)) revert PortfolioTokenManagerCantBeZero();
    if (_ondoRateLimiter == address(0)) revert RateLimiterCantBeZero();

    portfolioTokenManager = IPortfolioTokenManager(_portfolioTokenManager);
    ondoRateLimiter = OndoRateLimiter(_ondoRateLimiter);

    _grantRole(DEFAULT_ADMIN_ROLE, guardian);
    _grantRole(CONFIGURER_ROLE, guardian);
    _grantRole(PAUSER_ROLE, guardian);
    _grantRole(UNPAUSER_ROLE, guardian);
  }

  /**
   * @notice Pauses the registrar
   */
  function pause() external onlyRole(PAUSER_ROLE) {
    _pause();
  }

  /**
   * @notice Unpauses the registrar
   */
  function unpause() external onlyRole(UNPAUSER_ROLE) {
    _unpause();
  }

  /**
   * @notice Registers a new portfolio token with the PortfolioTokenManager.
   * @param  token The address of the token to register
   * @dev    Only callable by accounts with TOKEN_FACTORY_ROLE.
   *         - Registers the token with PortfolioTokenManager
   *         - Grants MINTER_ROLE on the token to the PortfolioTokenManager
   *         - Configures rate limits on OndoRateLimiter
   *         BURNER_ROLE is not needed because PortfolioTokenManager calls burn(uint256)
   *         which burns from msg.sender and has no role check.
   *
   *         On the primary chain, orchestrator acceptance and escrow deployment
   *         must be done separately after this call.
   */
  function register(address token) external override onlyRole(TOKEN_FACTORY_ROLE) whenNotPaused {
    if (token == address(0)) revert TokenAddressCantBeZero();

    portfolioTokenManager.setPortfolioTokenRegistrationStatus(token, true);

    IAccessControlEnumerable(token).grantRole(MINTER_ROLE, address(portfolioTokenManager));

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

  /*//////////////////////////////////////////////////////////////
                        Configuration
  //////////////////////////////////////////////////////////////*/

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
