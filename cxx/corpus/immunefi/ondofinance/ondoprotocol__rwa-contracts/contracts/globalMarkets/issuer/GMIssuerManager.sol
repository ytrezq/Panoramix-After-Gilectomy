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
  ReentrancyGuardTransient
} from "contracts/external/openzeppelin/contracts/security/ReentrancyGuardTransient.sol";
import {
  AccessControlEnumerableUpgradeable
} from "contracts/external/openzeppelin-v5/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {
  Initializable
} from "contracts/external/openzeppelin-v5/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
  EIP712Upgradeable
} from "contracts/external/openzeppelin-v5/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSA} from "contracts/external/openzeppelin-v5/contracts/utils/cryptography/ECDSA.sol";
import {IssuerLib} from "contracts/globalMarkets/issuer/issuerLib/IssuerLib.sol";
import {IssuerTypes} from "contracts/globalMarkets/issuer/issuerLib/IssuerTypes.sol";
import {IssuerStorage} from "contracts/globalMarkets/issuer/issuerLib/IssuerStorage.sol";
import {RateLimitLib} from "contracts/globalMarkets/issuer/rateLimit/RateLimitLib.sol";
import {IGMIssuerManager} from "contracts/globalMarkets/issuer/IGMIssuerManager.sol";

/**
 * @title  GMIssuerManager
 * @author Ondo Finance
 * @notice Ondo's Issuer entry point on Alpaca's ITN. APs mint/redeem GM tokens in-kind, 24/7, with
 *         no human step: Alpaca signs each mint request via EIP-712/secp256k1, and redemptions are
 *         user-initiated on-chain burns the backend listens for and settles with Alpaca off-chain.
 *         Both flows require the wallet to be GM-registered and ITN-approved. A composable menu of
 *         USD rate limits (global / per-token / per-user gross + a net-notional bound) and a
 *         per-tx mint cap bound blast radius.
 * @dev    Trust model: the signed `qty` is NOT reconciled against the submitted `amount` on-chain
 *         (S is off-chain), so a compromised SUBMITTER key can mint up to the per-tx cap × the
 *         enabled rate limits regardless of what Alpaca signed. Also intentionally omitted:
 *         `created` freshness (requests may be relayed long after signing during corporate-action
 *         pauses — replay is covered by the permanent nonce store).
 */
contract GMIssuerManager is
  Initializable,
  EIP712Upgradeable,
  IGMIssuerManager,
  ReentrancyGuardTransient,
  AccessControlEnumerableUpgradeable
{
  // ─────────────────────────────────────────────────────────────────────────────
  // Constants
  // ─────────────────────────────────────────────────────────────────────────────

  /// Role for the relayer that submits Alpaca-signed mints (processMint)
  bytes32 public constant SUBMITTER_ROLE = keccak256("SUBMITTER_ROLE");

  /// Role for the Alpaca signing keys whose EIP-712 signatures authorize mints
  bytes32 public constant ALPACA_SIGNER_ROLE = keccak256("ALPACA_SIGNER_ROLE");

  /// Wallets exempted from the shared rate-limit tiers: their mints/redeems run only the per-user
  /// tier via the privileged entry points. Granted per wallet by DEFAULT_ADMIN_ROLE.
  bytes32 public constant PRIVILEGED_USER_ROLE = keccak256("PRIVILEGED_USER_ROLE");

  /// Role to configure tokens, caps, and limits
  bytes32 public constant CONFIGURER_ROLE = keccak256("CONFIGURER_ROLE");

  /// Role to pause mints and/or redeems
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

  /// Role to unpause mints and/or redeems
  bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

  /// EIP-712 type hash for Alpaca mint requests
  bytes32 public constant MINT_TYPEHASH = IssuerLib.MINT_TYPEHASH;

  // ─────────────────────────────────────────────────────────────────────────────
  // Constructor
  // ─────────────────────────────────────────────────────────────────────────────

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
   * @notice Initializes the proxy's issuer state and EIP-712 domain
   * @param  _gmTokenManager Core GMTokenManager address (registry/oracle source)
   * @param  _defaultAdmin   Address to receive DEFAULT_ADMIN_ROLE
   * @param  _network        Target network name
   * @param  _domainName     EIP-712 domain name
   * @param  _domainVersion  EIP-712 domain version
   */
  function initialize(
    address _gmTokenManager,
    address _defaultAdmin,
    string memory _network,
    string memory _domainName,
    string memory _domainVersion
  ) external initializer {
    __EIP712_init(_domainName, _domainVersion);
    __AccessControlEnumerable_init();

    if (_gmTokenManager == address(0)) revert IssuerTypes.GMTokenManagerZeroAddress();
    if (_defaultAdmin == address(0)) revert IssuerTypes.DefaultAdminZeroAddress();
    if (bytes(_network).length == 0) revert IssuerTypes.NetworkEmpty();

    IssuerLib.initialize(_gmTokenManager, _network);
    _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Mint
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * @notice Processes an Alpaca-signed mint request
   * @param  req           The Alpaca mint request
   * @param  signature     Alpaca's EIP-712/secp256k1 signature over `req`
   * @param  amount        The GM token amount to mint (the token is resolved from
   *                       `req.tokenSymbol`)
   * @dev    Check order: recover signer → signer role → zero amount → pause → token supported →
   *         network → requestId idempotency → nonce unused → price set + fresh → zero notional →
   *         per-tx cap → recipient GM-registered + ITN-approved → rate limit → effects → mint
   */
  function processMint(
    IssuerTypes.MintRequest calldata req,
    bytes calldata signature,
    uint256 amount
  ) external nonReentrant onlyRole(SUBMITTER_ROLE) {
    (address gmToken, bytes32 requestIdHash, address signer, uint256 usd, bytes32 userId) =
      _authorizeSignedMint(req, signature, amount);
    RateLimitLib.consume(RateLimitLib.Direction.MINT, userId, gmToken, usd);
    IssuerLib.executeMint(req, signer, gmToken, requestIdHash, amount, usd, userId);
  }

  /**
   * @notice Same as `processMint` but for a wallet holding `PRIVILEGED_USER_ROLE`: the mint runs
   *         ONLY the per-user rate-limit tier, bypassing global/token/net rate limits
   * @param  req           The Alpaca mint request
   * @param  signature     Alpaca's EIP-712/secp256k1 signature over `req`
   * @param  amount        The GM token amount to mint (the token is resolved from
   *                       `req.tokenSymbol`)
   * @dev    Fail-closed: the recipient must have an active EXPLICIT per-user limit — the
   *         privileged tier never falls back to the default, so an unconfigured privileged
   *         wallet reverts `RateLimitNotConfigured`
   */
  function processMintPrivileged(
    IssuerTypes.MintRequest calldata req,
    bytes calldata signature,
    uint256 amount
  ) external nonReentrant onlyRole(SUBMITTER_ROLE) {
    if (!hasRole(PRIVILEGED_USER_ROLE, req.walletAddress)) {
      revert IssuerTypes.NotPrivilegedUser();
    }
    (address gmToken, bytes32 requestIdHash, address signer, uint256 usd, bytes32 userId) =
      _authorizeSignedMint(req, signature, amount);
    RateLimitLib.consumeUserOnly(RateLimitLib.Direction.MINT, userId, usd);
    IssuerLib.executeMint(req, signer, gmToken, requestIdHash, amount, usd, userId);
  }

  function _authorizeSignedMint(
    IssuerTypes.MintRequest calldata req,
    bytes calldata signature,
    uint256 amount
  )
    private
    view
    returns (address gmToken, bytes32 requestIdHash, address signer, uint256 usd, bytes32 userId)
  {
    signer = ECDSA.recover(_hashTypedDataV4(IssuerLib.hashMintRequest(req)), signature);
    if (!hasRole(ALPACA_SIGNER_ROLE, signer)) revert IssuerTypes.InvalidSigner();
    (gmToken, requestIdHash, usd, userId) = IssuerLib.authorizeMint(req, signer, amount);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Redeem
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * @notice Redeems the caller's GM tokens, emitting `IssuerRedeem` for the backend to
   *         settle the underlying with Alpaca off-chain. Caller must be GM-registered AND
   *         ITN-approved; the issuer pulls the tokens and self-burns.
   * @param  gmToken The GM token to redeem
   * @param  amount  The amount of `gmToken` to burn
   */
  function redeem(address gmToken, uint256 amount) external nonReentrant {
    (uint256 usd, bytes32 userId) = IssuerLib.authorizeRedeem(gmToken, amount);
    RateLimitLib.consume(RateLimitLib.Direction.REDEEM, userId, gmToken, usd);
    IssuerLib.executeRedeem(gmToken, amount, usd, userId);
  }

  /**
   * @notice Same as `redeem` but for a caller holding `PRIVILEGED_USER_ROLE`: the burn runs ONLY
   *         the per-user rate-limit tier, bypassing global/token/net rate limits
   * @param  gmToken The GM token to redeem
   * @param  amount  The amount of `gmToken` to burn
   * @dev    Fail-closed: the caller must have an active EXPLICIT per-user limit — the privileged
   *         tier never falls back to the default, so an unconfigured privileged wallet reverts
   *         `RateLimitNotConfigured`
   */
  function redeemPrivileged(address gmToken, uint256 amount)
    external
    nonReentrant
    onlyRole(PRIVILEGED_USER_ROLE)
  {
    (uint256 usd, bytes32 userId) = IssuerLib.authorizeRedeem(gmToken, amount);
    RateLimitLib.consumeUserOnly(RateLimitLib.Direction.REDEEM, userId, usd);
    IssuerLib.executeRedeem(gmToken, amount, usd, userId);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Views
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * @notice EIP-712 struct hash of a mint request (no domain separator)
   * @param  req The Alpaca mint request
   * @return The EIP-712 struct hash of `req`
   */
  function hashMintRequest(IssuerTypes.MintRequest calldata req) public pure returns (bytes32) {
    return IssuerLib.hashMintRequest(req);
  }

  /**
   * @notice EIP-712 digest of a mint request (domain-separated)
   * @param  req The Alpaca mint request
   * @return The EIP-712 digest of `req` — what the Alpaca signer actually signs
   */
  function digestMintRequest(IssuerTypes.MintRequest calldata req) external view returns (bytes32) {
    return _hashTypedDataV4(hashMintRequest(req));
  }

  /**
   * @notice The EIP-712 domain separator
   * @return The domain separator bound to this proxy and chain
   */
  function DOMAIN_SEPARATOR() external view returns (bytes32) {
    return _domainSeparatorV4();
  }

  /**
   * @notice Whether a signer's nonce has been consumed
   * @param  signer The Alpaca signer the nonce belongs to
   * @param  nonce  The nonce to check
   * @return True if the nonce has been consumed
   */
  function isNonceUsed(address signer, uint256 nonce) external view returns (bool) {
    return IssuerStorage.layout().usedNonces[signer][nonce];
  }

  /**
   * @notice Whether a `tokenizationRequestId` hash has been processed
   * @param  requestIdHash keccak256 of the request's `tokenizationRequestId` string
   * @return True if a mint with this requestId hash has been processed
   */
  function isRequestProcessed(bytes32 requestIdHash) external view returns (bool) {
    return IssuerStorage.layout().processedTokenizationRequestIds[requestIdHash];
  }

  /**
   * @notice The GM token mapped to a symbol
   * @param  tokenSymbol The Alpaca token symbol to look up
   * @return The GM token address, or address(0) if the symbol is unsupported
   */
  function gmTokenBySymbol(string calldata tokenSymbol) external view returns (address) {
    return IssuerStorage.layout().gmTokenBySymbol[tokenSymbol];
  }

  /**
   * @notice Whether a GM token is supported (derived from the symbol reverse map)
   * @param  gmToken The GM token to check
   * @return True if the token is supported
   */
  function isSupportedGmToken(address gmToken) external view returns (bool) {
    return bytes(IssuerStorage.layout().symbolByGmToken[gmToken]).length != 0;
  }

  /**
   * @notice The GLOBAL MINT rate limit: its config plus its decayed usage
   * @return limit        The maximum USD notional (18 decimals) allowed within `window`
   * @return window       The rolling window (seconds) over which usage decays
   * @return active       Whether the tier is configured — tells "tier off" from an active
   *                      zero-limit halt; an inactive tier reads all zeros
   * @return capacityUsed The decayed usage (USD, 18 decimals) counted against `limit`
   * @return available    The remaining capacity (USD, 18 decimals)
   */
  function globalMintRateLimit()
    external
    view
    returns (uint256 limit, uint48 window, bool active, uint256 capacityUsed, uint256 available)
  {
    return RateLimitLib.globalState(RateLimitLib.Direction.MINT);
  }

  /**
   * @notice The GLOBAL REDEEM rate limit: its config plus its decayed usage
   * @return limit        The maximum USD notional (18 decimals) allowed within `window`
   * @return window       The rolling window (seconds) over which usage decays
   * @return active       Whether the tier is configured — tells "tier off" from an active
   *                      zero-limit halt; an inactive tier reads all zeros
   * @return capacityUsed The decayed usage (USD, 18 decimals) counted against `limit`
   * @return available    The remaining capacity (USD, 18 decimals)
   */
  function globalRedeemRateLimit()
    external
    view
    returns (uint256 limit, uint48 window, bool active, uint256 capacityUsed, uint256 available)
  {
    return RateLimitLib.globalState(RateLimitLib.Direction.REDEEM);
  }

  /**
   * @notice A token's MINT rate limit: its config plus its decayed usage
   * @param  token        The GM token to read the limit for
   * @return limit        The maximum USD notional (18 decimals) allowed within `window`
   * @return window       The rolling window (seconds) over which usage decays
   * @return active       Whether the tier is configured — tells "tier off" from an active
   *                      zero-limit halt; an inactive tier reads all zeros
   * @return capacityUsed The decayed usage (USD, 18 decimals) counted against `limit`
   * @return available    The remaining capacity (USD, 18 decimals)
   */
  function tokenMintRateLimit(address token)
    external
    view
    returns (uint256 limit, uint48 window, bool active, uint256 capacityUsed, uint256 available)
  {
    return RateLimitLib.tokenState(RateLimitLib.Direction.MINT, token);
  }

  /**
   * @notice A token's REDEEM rate limit: its config plus its decayed usage
   * @param  token        The GM token to read the limit for
   * @return limit        The maximum USD notional (18 decimals) allowed within `window`
   * @return window       The rolling window (seconds) over which usage decays
   * @return active       Whether the tier is configured — tells "tier off" from an active
   *                      zero-limit halt; an inactive tier reads all zeros
   * @return capacityUsed The decayed usage (USD, 18 decimals) counted against `limit`
   * @return available    The remaining capacity (USD, 18 decimals)
   */
  function tokenRedeemRateLimit(address token)
    external
    view
    returns (uint256 limit, uint48 window, bool active, uint256 capacityUsed, uint256 available)
  {
    return RateLimitLib.tokenState(RateLimitLib.Direction.REDEEM, token);
  }

  /**
   * @notice A user's EFFECTIVE MINT rate limit: their override if active, else the default, with
   *         the user's own decayed usage against it. With neither active the view reads all zeros.
   * @param  userId         The registry userId to read the limit for
   * @return limit          The maximum USD notional (18 decimals) allowed within `window`
   * @return window         The rolling window (seconds) over which usage decays
   * @return overrideActive Whether the user's OWN override is active (false when on the default)
   * @return capacityUsed   The decayed usage (USD, 18 decimals) counted against `limit`
   * @return available      The remaining capacity (USD, 18 decimals)
   * @dev    On the default path `capacityUsed` can exceed `limit` (a lowered default does not
   *         reset per-user accrued usage) — `available` is authoritative and reads 0 there.
   */
  function userMintRateLimit(bytes32 userId)
    external
    view
    returns (
      uint256 limit,
      uint48 window,
      bool overrideActive,
      uint256 capacityUsed,
      uint256 available
    )
  {
    return RateLimitLib.userState(RateLimitLib.Direction.MINT, userId);
  }

  /**
   * @notice A user's EFFECTIVE REDEEM rate limit: their override if active, else the default,
   *         with the user's own decayed usage against it. With neither active the view reads all
   *         zeros.
   * @param  userId         The registry userId to read the limit for
   * @return limit          The maximum USD notional (18 decimals) allowed within `window`
   * @return window         The rolling window (seconds) over which usage decays
   * @return overrideActive Whether the user's OWN override is active (false when on the default)
   * @return capacityUsed   The decayed usage (USD, 18 decimals) counted against `limit`
   * @return available      The remaining capacity (USD, 18 decimals)
   * @dev    On the default path `capacityUsed` can exceed `limit` (a lowered default does not
   *         reset per-user accrued usage) — `available` is authoritative and reads 0 there.
   */
  function userRedeemRateLimit(bytes32 userId)
    external
    view
    returns (
      uint256 limit,
      uint48 window,
      bool overrideActive,
      uint256 capacityUsed,
      uint256 available
    )
  {
    return RateLimitLib.userState(RateLimitLib.Direction.REDEEM, userId);
  }

  /**
   * @notice The default per-user MINT limit config
   * @return limit  The maximum USD notional (18 decimals) allowed within `window`
   * @return window The rolling window (seconds) over which usage decays
   * @return active Whether a default is configured; inactive reads all zeros
   */
  function defaultUserMintRateLimit()
    external
    view
    returns (uint256 limit, uint48 window, bool active)
  {
    return RateLimitLib.defaultUserConfig(RateLimitLib.Direction.MINT);
  }

  /**
   * @notice The default per-user REDEEM limit config
   * @return limit  The maximum USD notional (18 decimals) allowed within `window`
   * @return window The rolling window (seconds) over which usage decays
   * @return active Whether a default is configured; inactive reads all zeros
   */
  function defaultUserRedeemRateLimit()
    external
    view
    returns (uint256 limit, uint48 window, bool active)
  {
    return RateLimitLib.defaultUserConfig(RateLimitLib.Direction.REDEEM);
  }

  /**
   * @notice The current signed net notional and the net tier's config
   * @return net    The decayed signed net USD notional (18 decimals)
   * @return limit  The maximum absolute net USD notional (18 decimals)
   * @return window The window (seconds) over which the net magnitude decays
   * @return active Whether the net tier is configured; inactive reads all zeros
   */
  function globalNetRateLimit()
    external
    view
    returns (int256 net, uint256 limit, uint48 window, bool active)
  {
    return RateLimitLib.globalNetCurrent();
  }

  /**
   * @notice The per-tx mint cap
   * @return The maximum USD notional (18 decimals) a single mint may carry
   */
  function perTxMintCapUSD() external view returns (uint256) {
    return IssuerStorage.layout().perTxMintCapUSD;
  }

  /**
   * @notice The GMTokenManager address (registry/oracle source)
   * @return The GMTokenManager address
   */
  function gmTokenManager() external view returns (address) {
    return IssuerStorage.layout().gmTokenManager;
  }

  /**
   * @notice The configured network name
   * @return The network name mint requests must match
   */
  function network() external view returns (string memory) {
    return IssuerStorage.layout().network;
  }

  /**
   * @notice The GM identifier used for OndoIDRegistry lookups
   * @return The GM identifier address constant
   */
  function gmIdentifier() external pure returns (address) {
    return IssuerLib.GM_IDENTIFIER;
  }

  /**
   * @notice The Alpaca ITN eligibility identifier used for OndoIDRegistry lookups
   * @return The Alpaca ITN identifier address constant
   */
  function alpacaItnIdentifier() external pure returns (address) {
    return IssuerLib.ALPACA_ITN_IDENTIFIER;
  }

  /**
   * @notice Whether mints are paused
   * @return True if mints are paused
   */
  function mintsPaused() external view returns (bool) {
    return IssuerStorage.layout().mintsPaused;
  }

  /**
   * @notice Whether new redeem requests are paused
   * @return True if redeems are paused
   */
  function redeemsPaused() external view returns (bool) {
    return IssuerStorage.layout().redeemsPaused;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Config (CONFIGURER)
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * @notice Maps a token symbol to a GM token
   * @param  tokenSymbol The Alpaca token symbol
   * @param  gmToken     The GM token address the symbol resolves to
   * @dev    Maintains the symbol map and its strict inverse atomically: a remap clears the old
   *         reverse entry; mapping a token already bound to a different symbol reverts
   */
  function setSupportedGmToken(string calldata tokenSymbol, address gmToken)
    external
    onlyRole(CONFIGURER_ROLE)
  {
    IssuerLib.setSupportedGmToken(tokenSymbol, gmToken);
  }

  /**
   * @notice Removes a supported token symbol (both directions of the mapping)
   * @param  tokenSymbol The Alpaca token symbol to remove
   */
  function removeSupportedGmToken(string calldata tokenSymbol) external onlyRole(CONFIGURER_ROLE) {
    IssuerLib.removeSupportedGmToken(tokenSymbol);
  }

  /**
   * @notice Sets the per-tx mint cap
   * @param  cap The maximum USD notional (18 decimals) a single mint may carry
   */
  function setPerTxMintCap(uint256 cap) external onlyRole(CONFIGURER_ROLE) {
    IssuerLib.setPerTxMintCap(cap);
  }

  /**
   * @notice Sets the global gross rate limit for the MINT direction
   * @param  limit  The maximum USD notional (18 decimals) allowed within `window`; 0 is a halt
   * @param  window The rolling window (seconds) over which usage decays; must be nonzero
   * @dev    Re-configuring resets accrued usage — even a lowered limit grants instant fresh
   *         capacity
   */
  function setGlobalMintRateLimit(uint256 limit, uint48 window) external onlyRole(CONFIGURER_ROLE) {
    RateLimitLib.setGlobalLimit(RateLimitLib.Direction.MINT, limit, window);
  }

  /**
   * @notice Sets the global gross rate limit for the REDEEM direction
   * @param  limit  The maximum USD notional (18 decimals) allowed within `window`; 0 is a halt
   * @param  window The rolling window (seconds) over which usage decays; must be nonzero
   * @dev    Re-configuring resets accrued usage — even a lowered limit grants instant fresh
   *         capacity
   */
  function setGlobalRedeemRateLimit(uint256 limit, uint48 window)
    external
    onlyRole(CONFIGURER_ROLE)
  {
    RateLimitLib.setGlobalLimit(RateLimitLib.Direction.REDEEM, limit, window);
  }

  /**
   * @notice Sets a per-token gross rate limit for the MINT direction
   * @param  token  The GM token the limit applies to
   * @param  limit  The maximum USD notional (18 decimals) allowed within `window`; 0 is a halt
   * @param  window The rolling window (seconds) over which usage decays; must be nonzero
   * @dev    Re-configuring resets accrued usage — even a lowered limit grants instant fresh
   *         capacity
   */
  function setTokenMintRateLimit(address token, uint256 limit, uint48 window)
    external
    onlyRole(CONFIGURER_ROLE)
  {
    RateLimitLib.setTokenLimit(RateLimitLib.Direction.MINT, token, limit, window);
  }

  /**
   * @notice Sets a per-token gross rate limit for the REDEEM direction
   * @param  token  The GM token the limit applies to
   * @param  limit  The maximum USD notional (18 decimals) allowed within `window`; 0 is a halt
   * @param  window The rolling window (seconds) over which usage decays; must be nonzero
   * @dev    Re-configuring resets accrued usage — even a lowered limit grants instant fresh
   *         capacity
   */
  function setTokenRedeemRateLimit(address token, uint256 limit, uint48 window)
    external
    onlyRole(CONFIGURER_ROLE)
  {
    RateLimitLib.setTokenLimit(RateLimitLib.Direction.REDEEM, token, limit, window);
  }

  /**
   * @notice Sets a per-user gross rate-limit override for the MINT direction
   * @param  userId The registry userId the override applies to
   * @param  limit  The maximum USD notional (18 decimals) allowed within `window`; 0 is a halt
   * @param  window The rolling window (seconds) over which usage decays; must be nonzero
   * @dev    Re-configuring resets the user's accrued usage — even a lowered limit grants instant
   *         fresh capacity
   */
  function setUserMintRateLimit(bytes32 userId, uint256 limit, uint48 window)
    external
    onlyRole(CONFIGURER_ROLE)
  {
    RateLimitLib.setUserLimit(RateLimitLib.Direction.MINT, userId, limit, window);
  }

  /**
   * @notice Sets a per-user gross rate-limit override for the REDEEM direction
   * @param  userId The registry userId the override applies to
   * @param  limit  The maximum USD notional (18 decimals) allowed within `window`; 0 is a halt
   * @param  window The rolling window (seconds) over which usage decays; must be nonzero
   * @dev    Re-configuring resets the user's accrued usage — even a lowered limit grants instant
   *         fresh capacity
   */
  function setUserRedeemRateLimit(bytes32 userId, uint256 limit, uint48 window)
    external
    onlyRole(CONFIGURER_ROLE)
  {
    RateLimitLib.setUserLimit(RateLimitLib.Direction.REDEEM, userId, limit, window);
  }

  /**
   * @notice Sets the default per-user MINT limit applied to any user without an override
   * @param  limit  The maximum USD notional (18 decimals) allowed within `window`; 0 is a halt
   * @param  window The rolling window (seconds) over which usage decays; must be nonzero
   * @dev    Never resets any user's accrued usage — each user's accrual keeps decaying against
   *         the new config
   */
  function setDefaultUserMintRateLimit(uint256 limit, uint48 window)
    external
    onlyRole(CONFIGURER_ROLE)
  {
    RateLimitLib.setDefaultUserLimit(RateLimitLib.Direction.MINT, limit, window);
  }

  /**
   * @notice Sets the default per-user REDEEM limit applied to any user without an override
   * @param  limit  The maximum USD notional (18 decimals) allowed within `window`; 0 is a halt
   * @param  window The rolling window (seconds) over which usage decays; must be nonzero
   * @dev    Never resets any user's accrued usage — each user's accrual keeps decaying against
   *         the new config
   */
  function setDefaultUserRedeemRateLimit(uint256 limit, uint48 window)
    external
    onlyRole(CONFIGURER_ROLE)
  {
    RateLimitLib.setDefaultUserLimit(RateLimitLib.Direction.REDEEM, limit, window);
  }

  /**
   * @notice Sets the global net-notional rate limit
   * @param  limit  The maximum absolute net USD notional (18 decimals) allowed within `window`
   * @param  window The window (seconds) over which the net magnitude decays; must be nonzero
   * @dev    Reverts `NetLimitTooLarge` above `MAX_NET_LIMIT` (2^128 - 1); re-configuring resets
   *         the accumulated net to 0
   */
  function setGlobalNetRateLimit(uint256 limit, uint48 window) external onlyRole(CONFIGURER_ROLE) {
    RateLimitLib.setGlobalNetLimit(limit, window);
  }

  /// Removes the global gross MINT rate limit (mints then fail closed)
  function removeGlobalMintRateLimit() external onlyRole(CONFIGURER_ROLE) {
    RateLimitLib.removeGlobalLimit(RateLimitLib.Direction.MINT);
  }

  /// Removes the global gross REDEEM rate limit (redeems then fail closed)
  function removeGlobalRedeemRateLimit() external onlyRole(CONFIGURER_ROLE) {
    RateLimitLib.removeGlobalLimit(RateLimitLib.Direction.REDEEM);
  }

  /**
   * @notice Removes a per-token gross MINT rate limit (the TOKEN tier then skips)
   * @param  token The GM token whose limit is removed
   */
  function removeTokenMintRateLimit(address token) external onlyRole(CONFIGURER_ROLE) {
    RateLimitLib.removeTokenLimit(RateLimitLib.Direction.MINT, token);
  }

  /**
   * @notice Removes a per-token gross REDEEM rate limit (the TOKEN tier then skips)
   * @param  token The GM token whose limit is removed
   */
  function removeTokenRedeemRateLimit(address token) external onlyRole(CONFIGURER_ROLE) {
    RateLimitLib.removeTokenLimit(RateLimitLib.Direction.REDEEM, token);
  }

  /**
   * @notice Removes a per-user MINT rate-limit override (the user falls back to the default)
   * @param  userId The registry userId whose override is removed
   * @dev    Also clears the bucket's accumulated usage — the user restarts the default window
   *         with a fresh allowance
   */
  function removeUserMintRateLimit(bytes32 userId) external onlyRole(CONFIGURER_ROLE) {
    RateLimitLib.removeUserLimit(RateLimitLib.Direction.MINT, userId);
  }

  /**
   * @notice Removes a per-user REDEEM rate-limit override (the user falls back to the default)
   * @param  userId The registry userId whose override is removed
   * @dev    Also clears the bucket's accumulated usage — the user restarts the default window
   *         with a fresh allowance
   */
  function removeUserRedeemRateLimit(bytes32 userId) external onlyRole(CONFIGURER_ROLE) {
    RateLimitLib.removeUserLimit(RateLimitLib.Direction.REDEEM, userId);
  }

  /// Removes the default per-user MINT limit (users without an override then fail closed)
  function removeDefaultUserMintRateLimit() external onlyRole(CONFIGURER_ROLE) {
    RateLimitLib.removeDefaultUserLimit(RateLimitLib.Direction.MINT);
  }

  /// Removes the default per-user REDEEM limit (users without an override then fail closed)
  function removeDefaultUserRedeemRateLimit() external onlyRole(CONFIGURER_ROLE) {
    RateLimitLib.removeDefaultUserLimit(RateLimitLib.Direction.REDEEM);
  }

  /// Removes the global net-notional rate limit (the net tier then skips)
  function removeGlobalNetRateLimit() external onlyRole(CONFIGURER_ROLE) {
    RateLimitLib.removeGlobalNetLimit();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Pause (per direction)
  // ─────────────────────────────────────────────────────────────────────────────

  /// Pauses mints
  function pauseMints() external onlyRole(PAUSER_ROLE) {
    IssuerLib.pauseMints();
  }

  /// Unpauses mints
  function unpauseMints() external onlyRole(UNPAUSER_ROLE) {
    IssuerLib.unpauseMints();
  }

  /// Pauses new redeem requests
  function pauseRedeems() external onlyRole(PAUSER_ROLE) {
    IssuerLib.pauseRedeems();
  }

  /// Unpauses new redeem requests
  function unpauseRedeems() external onlyRole(UNPAUSER_ROLE) {
    IssuerLib.unpauseRedeems();
  }
}
