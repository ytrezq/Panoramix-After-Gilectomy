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
pragma solidity ^0.8.4;

import {RateLimitStorage} from "contracts/globalMarkets/issuer/rateLimit/RateLimitStorage.sol";

/**
 * @title  RateLimitLib
 * @author Ondo Finance
 * @notice Linear-decay ("leaky bucket") USD notional rate limits over its own EIP-7201 storage:
 *         GLOBAL / per-TOKEN / per-USER gross tiers (per direction) plus a global signed
 *         NET-notional bound. `consume(direction, …)` runs every tier and the first breach reverts;
 *         GLOBAL and USER revert if inactive, TOKEN and the net bound skip when inactive.
 * @dev    Enforcement keys on the `active` flag, not on `limit`: a `set*` activates, a `remove*`
 *         deactivates, so `limit == 0` is an active halt — zero available capacity, and every
 *         charge carries `usd > 0` (the caller's `ZeroNotional` guard).
 */
library RateLimitLib {
  // ─────────────────────────────────────────────────────────────────────────────
  // Constants
  // ─────────────────────────────────────────────────────────────────────────────

  /// Ceiling on a net limit. Keeps `limit * window` and every int256 cast on the net hot path
  /// overflow-proof (2^128 USD is far beyond any real notional).
  uint256 internal constant MAX_NET_LIMIT = type(uint128).max;

  // ─────────────────────────────────────────────────────────────────────────────
  // Types
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * @notice Unsigned linear-decay rate limit state (OndoRateLimiter shape)
   * @param  capacityUsed Current amount (USD, 18 decimals) within the window
   * @param  lastUpdated  Timestamp (seconds) of the last charge
   * @param  limit        Maximum allowed amount (USD, 18 decimals); may be 0 — zero available
   *                      capacity, so while active every charge breaches
   * @param  window       Window duration (seconds)
   * @param  active       Whether this bucket is enforced
   */
  struct RateLimit {
    uint256 capacityUsed;
    uint256 lastUpdated;
    uint256 limit;
    uint48 window;
    bool active;
  }

  /**
   * @notice Signed net-notional accumulator: bounds Σmint − Σredeem, decaying toward 0
   * @param  net         Current signed net (USD, 18 decimals), decayed toward 0; can be ±
   * @param  lastUpdated Timestamp (seconds) of the last charge
   * @param  limit       Symmetric bound: enforced |net| ≤ limit; may be 0 (blocks all charges
   *                     while active)
   * @param  window      Window over which magnitude decays from ±limit to 0 (seconds)
   * @param  active      Whether this bucket is enforced
   */
  struct NetRateLimit {
    int256 net;
    uint256 lastUpdated;
    uint256 limit;
    uint48 window;
    bool active;
  }

  /**
   * @notice All gross rate-limit buckets for one flow direction
   * @param  global      The direction-wide bucket
   * @param  token       Per-token buckets
   * @param  user        Per-user buckets, keyed by registry userId
   * @param  defaultUser Config-only template for users without an override; its usage fields are
   *                     unused (each user's usage lives in their own bucket)
   */
  struct DirectionalRateLimits {
    RateLimit global;
    mapping(address token => RateLimit) token;
    mapping(bytes32 userId => RateLimit) user;
    RateLimit defaultUser;
  }

  /// Direction of flow. Gross tiers key a separate bucket per direction; the net bucket is shared.
  enum Direction {
    /// A mint flow; adds to the signed net
    MINT,
    /// A redeem flow; subtracts from the signed net
    REDEEM
  }

  /// Rate-limit tier label. Only GLOBAL / TOKEN / USER are ever charged; DEFAULT_USER tags
  /// `RateLimitConfigured` for the per-user default, a config template that is never charged.
  enum RateLimitType {
    /// The direction-wide gross tier
    GLOBAL,
    /// A per-token gross tier
    TOKEN,
    /// A per-user gross tier
    USER,
    /// The per-user default — a config template that is never charged directly
    DEFAULT_USER
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Events
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * @notice Emitted when a gross tier's config changes. A `set*` emits `active = true`; a
   *         `remove*` emits `active = false` with zeroed limit/window.
   * @param  limitType The tier
   * @param  direction The flow direction
   * @param  key       Tier key: 0 for GLOBAL and DEFAULT_USER, token address as bytes32 for
   *                   TOKEN, userId for USER
   * @param  limit     New limit (USD, 18 decimals)
   * @param  window    New window (seconds)
   * @param  active    Whether the tier is enforced after this change
   */
  event RateLimitConfigured(
    RateLimitType indexed limitType,
    Direction indexed direction,
    bytes32 indexed key,
    uint256 limit,
    uint48 window,
    bool active
  );

  /**
   * @notice Emitted when the global net limit's config changes (see `RateLimitConfigured` on the
   *         set/remove convention)
   * @param  limit  New symmetric net bound (USD, 18 decimals)
   * @param  window New window (seconds)
   * @param  active Whether the net tier is enforced after this change
   */
  event NetRateLimitConfigured(uint256 limit, uint48 window, bool active);

  /**
   * @notice Emitted when a gross tier (GLOBAL / TOKEN / USER) is charged
   * @param  limitType    The tier charged
   * @param  direction    The flow direction
   * @param  key          Tier key: 0 for GLOBAL, token address for TOKEN, userId for USER
   * @param  usd          The USD notional (18 decimals) charged in this tx
   * @param  capacityUsed The tier's bucket level after this charge
   * @param  available    Remaining capacity in the tier after this charge (limit − capacityUsed)
   */
  event RateLimitConsumed(
    RateLimitType indexed limitType,
    Direction indexed direction,
    bytes32 indexed key,
    uint256 usd,
    uint256 capacityUsed,
    uint256 available
  );

  /**
   * @notice Emitted when the global net tier is charged (active only). `net` is a fresh
   *         checkpoint; its magnitude decays toward 0 over the `NetRateLimitConfigured` window.
   * @param  direction The flow direction
   * @param  usd       The USD notional (18 decimals) charged in this tx
   * @param  net       The signed net (USD, 18 decimals) after this charge
   */
  event NetRateLimitConsumed(Direction indexed direction, uint256 usd, int256 net);

  // ─────────────────────────────────────────────────────────────────────────────
  // Errors
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * @notice A gross tier was exceeded.
   * @param  limitType The tier that reverted
   * @param  direction The flow direction
   * @param  usd       The USD notional (18 decimals) charged
   * @param  available The remaining capacity in that tier after decay
   */
  error RateLimited(RateLimitType limitType, Direction direction, uint256 usd, uint256 available);

  /**
   * @notice The net-notional bound was exceeded.
   * @param  direction    The flow direction
   * @param  usd          The USD notional (18 decimals) charged
   * @param  projectedNet The net that would result, or a saturating sentinel (±(`limit` + 1))
   *                      when `usd > 2 * limit`; either way |projectedNet| exceeds `limit`
   * @param  limit        The symmetric net bound
   */
  error NetRateLimited(Direction direction, uint256 usd, int256 projectedNet, uint256 limit);

  /**
   * @notice A net limit above `MAX_NET_LIMIT` was configured.
   * @param  limit The rejected limit
   */
  error NetLimitTooLarge(uint256 limit);

  /// A rate limit was configured with a zero window — the leaky bucket would decay
  /// instantly and never accumulate.
  error ZeroWindow();

  /**
   * @notice A fail-closed tier has no active limit configured. For USER this means no explicit or
   *         default limit (`consumeUser`), or no explicit per-user limit (`consumeUserOnly` —
   *         privileged flows never fall back to the default).
   * @param  limitType The tier
   * @param  direction The flow direction
   */
  error RateLimitNotConfigured(RateLimitType limitType, Direction direction);

  // ─────────────────────────────────────────────────────────────────────────────
  // Composed consume (the top-level entry point)
  // ─────────────────────────────────────────────────────────────────────────────

  function consume(Direction direction, bytes32 user, address token, uint256 usd) internal {
    consumeGlobal(direction, usd);
    consumeToken(direction, token, usd);
    consumeUser(direction, user, usd);
    consumeGlobalNet(direction, usd);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Per-tier consume (GLOBAL/USER revert if inactive; TOKEN/net skip)
  // ─────────────────────────────────────────────────────────────────────────────

  function consumeGlobal(Direction direction, uint256 usd) internal {
    RateLimit storage rl = dirLimits(direction).global;
    if (!rl.active) revert RateLimitNotConfigured(RateLimitType.GLOBAL, direction);
    (uint256 limit, uint48 window) = (rl.limit, rl.window);
    (bool ok, uint256 available, uint256 capacityUsed) =
      checkAndUpdateRateLimit(rl, limit, window, usd);
    if (!ok) revert RateLimited(RateLimitType.GLOBAL, direction, usd, available);
    emit RateLimitConsumed(
      RateLimitType.GLOBAL, direction, bytes32(0), usd, capacityUsed, limit - capacityUsed
    );
  }

  function consumeToken(Direction direction, address token, uint256 usd) internal {
    RateLimit storage rl = dirLimits(direction).token[token];
    if (!rl.active) return;
    (uint256 limit, uint48 window) = (rl.limit, rl.window);
    (bool ok, uint256 available, uint256 capacityUsed) =
      checkAndUpdateRateLimit(rl, limit, window, usd);
    if (!ok) revert RateLimited(RateLimitType.TOKEN, direction, usd, available);
    emit RateLimitConsumed(
      RateLimitType.TOKEN,
      direction,
      bytes32(uint256(uint160(token))),
      usd,
      capacityUsed,
      limit - capacityUsed
    );
  }

  function consumeUser(Direction direction, bytes32 user, uint256 usd) internal {
    (RateLimit storage rl, uint256 limit, uint48 window, bool active) = userConfig(direction, user);
    if (!active) revert RateLimitNotConfigured(RateLimitType.USER, direction);
    (bool ok, uint256 available, uint256 capacityUsed) =
      checkAndUpdateRateLimit(rl, limit, window, usd);
    if (!ok) revert RateLimited(RateLimitType.USER, direction, usd, available);
    emit RateLimitConsumed(
      RateLimitType.USER, direction, user, usd, capacityUsed, limit - capacityUsed
    );
  }

  // Explicit per-user limit only — deliberately no userConfig/default fallback
  function consumeUserOnly(Direction direction, bytes32 user, uint256 usd) internal {
    RateLimit storage rl = dirLimits(direction).user[user];
    if (!rl.active) revert RateLimitNotConfigured(RateLimitType.USER, direction);
    (uint256 limit, uint48 window) = (rl.limit, rl.window);
    (bool ok, uint256 available, uint256 capacityUsed) =
      checkAndUpdateRateLimit(rl, limit, window, usd);
    if (!ok) revert RateLimited(RateLimitType.USER, direction, usd, available);
    // Only the USER tier emits — a privileged tx has no GLOBAL/TOKEN/NET checkpoint.
    emit RateLimitConsumed(
      RateLimitType.USER, direction, user, usd, capacityUsed, limit - capacityUsed
    );
  }

  function consumeGlobalNet(Direction direction, uint256 usd) internal {
    NetRateLimit storage n = s().globalNet;
    if (!n.active) return;
    (bool ok, int256 projectedNet) = checkAndUpdateNetRateLimit(n, direction, usd);
    if (!ok) revert NetRateLimited(direction, usd, projectedNet, n.limit);
    emit NetRateLimitConsumed(direction, usd, projectedNet);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // User config helper
  // ─────────────────────────────────────────────────────────────────────────────

  function userConfig(Direction direction, bytes32 user)
    internal
    view
    returns (RateLimit storage rl, uint256 limit, uint48 window, bool active)
  {
    DirectionalRateLimits storage d = dirLimits(direction);
    rl = d.user[user];
    if (rl.active) return (rl, rl.limit, rl.window, true);
    if (d.defaultUser.active) return (rl, d.defaultUser.limit, d.defaultUser.window, true);
    return (rl, 0, 0, false);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Decay math (pure read; operates on a storage pointer)
  // ─────────────────────────────────────────────────────────────────────────────

  function _calculateDecay(RateLimit storage rl)
    internal
    view
    returns (uint256 currentCapacityUsed, uint256 available)
  {
    return _calculateDecay(rl, rl.limit, rl.window);
  }

  function _calculateDecay(RateLimit storage state, uint256 limit, uint48 window)
    internal
    view
    returns (uint256 currentCapacityUsed, uint256 available)
  {
    uint256 timeSinceLastUpdate = block.timestamp - state.lastUpdated;
    if (timeSinceLastUpdate >= window) {
      return (0, limit);
    } else {
      uint256 decay = (limit * timeSinceLastUpdate) / window;
      currentCapacityUsed = state.capacityUsed > decay ? state.capacityUsed - decay : 0;
      available = limit > currentCapacityUsed ? limit - currentCapacityUsed : 0;
      return (currentCapacityUsed, available);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Check/update core (operates on a storage pointer)
  // ─────────────────────────────────────────────────────────────────────────────

  function checkAndUpdateRateLimit(
    RateLimit storage state,
    uint256 limit,
    uint48 window,
    uint256 usd
  ) internal returns (bool ok, uint256 available, uint256 capacityUsed) {
    uint256 used;
    (used, available) = _calculateDecay(state, limit, window);
    if (usd > available) return (false, available, type(uint256).max);
    state.capacityUsed = capacityUsed = used + usd;
    state.lastUpdated = block.timestamp;
    return (true, available, capacityUsed);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Signed net core (operates on a storage pointer)
  // ─────────────────────────────────────────────────────────────────────────────

  function _calculateNetDecay(NetRateLimit storage n) internal view returns (int256) {
    uint256 timeSinceLastUpdate = block.timestamp - n.lastUpdated;
    if (timeSinceLastUpdate >= n.window) return 0;
    uint256 decay = (n.limit * timeSinceLastUpdate) / n.window;
    int256 v = n.net;
    if (v > 0) return v > int256(decay) ? v - int256(decay) : int256(0);
    if (v < 0) return v < -int256(decay) ? v + int256(decay) : int256(0);
    return 0;
  }

  // Cast safety: every uint256→int256 cast on the net path is bounded, so none can wrap.
  // `lim ≤ MAX_NET_LIMIT` (2^128 - 1) covers `lim` and the `lim + 1` sentinels; the
  // `usd > 2 * lim` fast-reject bounds `int256(usd)`; `decay < lim` in `_calculateNetDecay`;
  // and `|n.net| ≤ lim` at every write, so `|decayed + delta| ≤ 3·lim` — all far inside int256.
  function checkAndUpdateNetRateLimit(NetRateLimit storage n, Direction direction, uint256 usd)
    internal
    returns (bool ok, int256 newNet)
  {
    uint256 lim = n.limit;
    if (usd > 2 * lim) {
      return (false, direction == Direction.MINT ? int256(lim) + 1 : -int256(lim) - 1);
    }

    int256 decayed = _calculateNetDecay(n);
    int256 delta = direction == Direction.MINT ? int256(usd) : -int256(usd);
    newNet = decayed + delta;

    int256 limI = int256(lim);
    if (newNet > limI || newNet < -limI) return (false, newNet);

    n.net = newNet;
    n.lastUpdated = block.timestamp;
    return (true, newNet);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Scoped setters
  // ─────────────────────────────────────────────────────────────────────────────

  function setGlobalLimit(Direction direction, uint256 limit, uint48 window) internal {
    setConfig(dirLimits(direction).global, limit, window);
    emit RateLimitConfigured(RateLimitType.GLOBAL, direction, bytes32(0), limit, window, true);
  }

  function setTokenLimit(Direction direction, address token, uint256 limit, uint48 window)
    internal
  {
    setConfig(dirLimits(direction).token[token], limit, window);
    emit RateLimitConfigured(
      RateLimitType.TOKEN, direction, bytes32(uint256(uint160(token))), limit, window, true
    );
  }

  function setUserLimit(Direction direction, bytes32 user, uint256 limit, uint48 window) internal {
    setConfig(dirLimits(direction).user[user], limit, window);
    emit RateLimitConfigured(RateLimitType.USER, direction, user, limit, window, true);
  }

  function setDefaultUserLimit(Direction direction, uint256 limit, uint48 window) internal {
    setConfig(dirLimits(direction).defaultUser, limit, window);
    emit RateLimitConfigured(RateLimitType.DEFAULT_USER, direction, bytes32(0), limit, window, true);
  }

  function setGlobalNetLimit(uint256 limit, uint48 window) internal {
    setNetConfig(s().globalNet, limit, window);
    emit NetRateLimitConfigured(limit, window, true);
  }

  function removeGlobalLimit(Direction direction) internal {
    clearConfig(dirLimits(direction).global);
    emit RateLimitConfigured(RateLimitType.GLOBAL, direction, bytes32(0), 0, 0, false);
  }

  function removeTokenLimit(Direction direction, address token) internal {
    clearConfig(dirLimits(direction).token[token]);
    emit RateLimitConfigured(
      RateLimitType.TOKEN, direction, bytes32(uint256(uint160(token))), 0, 0, false
    );
  }

  function removeUserLimit(Direction direction, bytes32 user) internal {
    clearConfig(dirLimits(direction).user[user]);
    emit RateLimitConfigured(RateLimitType.USER, direction, user, 0, 0, false);
  }

  function removeDefaultUserLimit(Direction direction) internal {
    clearConfig(dirLimits(direction).defaultUser);
    emit RateLimitConfigured(RateLimitType.DEFAULT_USER, direction, bytes32(0), 0, 0, false);
  }

  // Activates `rl` and resets its decay accounting — a re-config (even to a lower limit) grants
  // instant fresh capacity. Inert for the `defaultUser` config bucket (usage accrues in each
  // user's own bucket). Zero window is rejected; deactivation is `clearConfig`'s job.
  function setConfig(RateLimit storage rl, uint256 limit, uint48 window) internal {
    if (window == 0) revert ZeroWindow();
    rl.limit = limit;
    rl.window = window;
    rl.capacityUsed = 0;
    rl.lastUpdated = block.timestamp;
    rl.active = true;
  }

  // Deactivates `rl` and wipes its bucket — the tier stops being enforced and accrued usage is
  // cleared
  function clearConfig(RateLimit storage rl) internal {
    rl.limit = 0;
    rl.window = 0;
    rl.capacityUsed = 0;
    rl.lastUpdated = 0;
    rl.active = false;
  }

  // Activates the net bound with a fresh accumulator (`net` = 0). Reverts `NetLimitTooLarge`
  // above `MAX_NET_LIMIT`; a zero window is rejected.
  function setNetConfig(NetRateLimit storage n, uint256 limit, uint48 window) internal {
    if (limit > MAX_NET_LIMIT) revert NetLimitTooLarge(limit);
    if (window == 0) revert ZeroWindow();
    n.limit = limit;
    n.window = window;
    n.net = 0;
    n.lastUpdated = block.timestamp;
    n.active = true;
  }

  // Deactivates the global net bound and wipes the accumulator (the net tier then skips)
  function removeGlobalNetLimit() internal {
    NetRateLimit storage n = s().globalNet;
    n.limit = 0;
    n.window = 0;
    n.net = 0;
    n.lastUpdated = 0;
    n.active = false;
    emit NetRateLimitConfigured(0, 0, false);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Scoped views
  // ─────────────────────────────────────────────────────────────────────────────

  function bucketState(RateLimit storage rl)
    internal
    view
    returns (uint256 limit, uint48 window, bool active, uint256 capacityUsed, uint256 available)
  {
    if (!rl.active) return (0, 0, false, 0, 0);
    (capacityUsed, available) = _calculateDecay(rl);
    return (rl.limit, rl.window, true, capacityUsed, available);
  }

  function globalState(Direction direction)
    internal
    view
    returns (uint256 limit, uint48 window, bool active, uint256 capacityUsed, uint256 available)
  {
    return bucketState(dirLimits(direction).global);
  }

  function tokenState(Direction direction, address token)
    internal
    view
    returns (uint256 limit, uint48 window, bool active, uint256 capacityUsed, uint256 available)
  {
    return bucketState(dirLimits(direction).token[token]);
  }

  function userState(Direction direction, bytes32 user)
    internal
    view
    returns (
      uint256 limit,
      uint48 window,
      bool overrideActive,
      uint256 capacityUsed,
      uint256 available
    )
  {
    (RateLimit storage rl, uint256 effLimit, uint48 effWindow, bool active) =
      userConfig(direction, user);
    if (!active) return (0, 0, false, 0, 0);
    (capacityUsed, available) = _calculateDecay(rl, effLimit, effWindow);
    return (effLimit, effWindow, rl.active, capacityUsed, available);
  }

  function defaultUserConfig(Direction direction)
    internal
    view
    returns (uint256 limit, uint48 window, bool active)
  {
    RateLimit storage def = dirLimits(direction).defaultUser;
    return (def.limit, def.window, def.active);
  }

  function globalNetCurrent()
    internal
    view
    returns (int256 net, uint256 limit, uint48 window, bool active)
  {
    NetRateLimit storage n = s().globalNet;
    return (_calculateNetDecay(n), n.limit, n.window, n.active);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Storage accessor
  // ─────────────────────────────────────────────────────────────────────────────

  function s() internal pure returns (RateLimitStorage.Layout storage) {
    return RateLimitStorage.layout();
  }

  function dirLimits(Direction direction) internal view returns (DirectionalRateLimits storage) {
    return direction == Direction.MINT ? s().mintLimits : s().redeemLimits;
  }
}
