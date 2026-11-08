// SPDX-License-Identifier: GPL-3.0
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
  AccessControlEnumerable
} from "contracts/external/openzeppelin-v5/contracts/access/extensions/AccessControlEnumerable.sol";
import {ContinuousIndexingMath} from "contracts/external/m0/ContinuousIndexingMath.sol";
import {IRWADynamicOracle} from "contracts/rwaOracles/IRWADynamicOracle.sol";
import {IRWAOracle} from "contracts/rwaOracles/IRWAOracle.sol";

/**
 * @title  ContinuousPriceOracle
 * @author Ondo Finance
 * @notice Price oracle for an RWA token, accruing from the last stored price at a continuously
 *         compounded yearly rate, with an optional scheduled next yearly rate
 */
contract ContinuousPriceOracle is IRWADynamicOracle, IRWAOracle, AccessControlEnumerable {
  /// Role to set the price and yearly rate outside the ORACLE_SETTER_ROLE bounds and to set those
  /// bounds
  bytes32 public constant TIMELOCKED_ADMIN_ROLE = keccak256("TIMELOCKED_ADMIN_ROLE");

  /// Role to call `syncRateAndPriceStoredToNow`
  bytes32 public constant SYNCER_ROLE = keccak256("SYNCER_ROLE");

  /// Role to set the price and yearly rate of the RWA token within bounds set by the admin, while
  /// the current yearly rate is non-zero
  bytes32 public constant ORACLE_SETTER_ROLE = keccak256("ORACLE_SETTER_ROLE");

  /// Role to call `freezePrice`
  bytes32 public constant PRICE_FREEZER_ROLE = keccak256("PRICE_FREEZER_ROLE");

  /// The precision of the yearly rate and APY, 12 decimals (1e12 = 100%)
  uint64 public constant RATE_PRECISION = ContinuousIndexingMath.EXP_SCALED_ONE;

  /// The maximum yearly rate, 100% continuously compounded
  uint64 internal constant MAX_YEARLY_RATE = RATE_PRECISION;

  /// The maximum allowed difference between an intended APY and the APY a yearly rate produces
  uint64 internal constant INTENDED_APY_TOLERANCE = 10;

  /// The `nextRateStart` value when no next yearly rate is set
  uint64 public constant MAX_UINT64 = type(uint64).max;

  /// The precision of basis points values (1e4 = 100%)
  uint64 public constant BPS_PRECISION = 1e4;

  /// The symbol of the RWA token this oracle is serving the price for
  string public symbol;

  /// The last price stored, with 18 decimals of precision
  uint256 public priceStored;
  /// The timestamp of when `priceStored` was last stored
  uint64 public lastPriceStoredTimestamp;
  /// The yearly rate the price accrues at before `nextRateStart`, as `ln(1 + APY)` scaled by
  /// `RATE_PRECISION`
  uint64 public currentYearlyRate;

  /// The price at `nextRateStart`, with 18 decimals of precision
  uint256 public priceAtNextRateStart;
  /// The timestamp of when the next yearly rate will start, `MAX_UINT64` if unset
  uint64 public nextRateStart;
  /// The yearly rate the price accrues at from `nextRateStart`, as `ln(1 + APY)` scaled by
  /// `RATE_PRECISION`
  uint64 public nextYearlyRate;

  /// The timestamp of the last `setPriceNow`
  uint64 public lastPriceChangeTimestamp;
  /// The timestamp of the last `setRateNow` or `setNextRate`
  uint64 public lastRateChangeTimestamp;

  /// The maximum yearly rate change by the ORACLE_SETTER_ROLE, in bps of the current yearly rate
  uint64 public maxRateChangeBps;
  /// The maximum price change by the ORACLE_SETTER_ROLE, in bps of the current price
  uint64 public maxPriceChangeBps;

  /// The minimum time in seconds between ORACLE_SETTER_ROLE price changes, and between its yearly
  /// rate changes
  uint64 public minimumChangeWindow;

  /**
   * @notice Emitted when the current yearly rate is set
   * @param  yearlyRate The yearly rate set
   * @param  timestamp  The timestamp of when the yearly rate took effect
   */
  event CurrentYearlyRateSet(uint64 indexed yearlyRate, uint64 timestamp);
  /**
   * @notice Emitted when the price is stored
   * @param  price     The price set
   * @param  timestamp The timestamp of when the price was set
   */
  event PriceSet(uint256 indexed price, uint64 timestamp);
  /**
   * @notice Emitted when the next yearly rate is set or cleared
   * @param  yearlyRate The yearly rate set, 0 when cleared
   * @param  startTime  The timestamp of when the yearly rate will start, `MAX_UINT64` when cleared
   */
  event NextYearlyRateSet(uint64 indexed yearlyRate, uint64 startTime);

  /**
   * @notice Emitted when the maximum yearly rate change is set
   * @param  oldMaxRateChangeBps The old maximum yearly rate change in bps
   * @param  newMaxRateChangeBps The new maximum yearly rate change in bps
   */
  event MaxRateChangeSet(uint64 indexed oldMaxRateChangeBps, uint64 indexed newMaxRateChangeBps);
  /**
   * @notice Emitted when the maximum price change is set
   * @param  oldMaxPriceChangeBps The old maximum price change in bps
   * @param  newMaxPriceChangeBps The new maximum price change in bps
   */
  event MaxPriceChangeSet(uint64 indexed oldMaxPriceChangeBps, uint64 indexed newMaxPriceChangeBps);
  /**
   * @notice Emitted when the minimum change window is set
   * @param  oldMinimumChangeWindow The old minimum change window in seconds
   * @param  newMinimumChangeWindow The new minimum change window in seconds
   */
  event MinimumChangeWindowSet(
    uint64 indexed oldMinimumChangeWindow, uint64 indexed newMinimumChangeWindow
  );

  /// Error thrown when the ORACLE_SETTER_ROLE attempts to set the price within the window
  error PriceChangeWindowNotPassed();
  /// Error thrown when the ORACLE_SETTER_ROLE attempts to set the yearly rate within the window
  error RateChangeWindowNotPassed();
  /// Error thrown when the ORACLE_SETTER_ROLE attempts to set the price too high or too low
  error PriceChangeTooLarge();
  /// Error thrown when the ORACLE_SETTER_ROLE attempts to change the yearly rate by too much
  error RateChangeTooLarge();
  /// Error thrown when attempting to set `nextRateStart` to a time that is not in the future
  error InvalidStartTime();
  /// Error thrown when `nextRateStart` is more than a year away
  error StartTimeTooFar();
  /// Error thrown when the minimum change window is set to 0
  error ChangeWindowCantBeZero();
  /// Error thrown when the sender has neither the TIMELOCKED_ADMIN_ROLE nor the ORACLE_SETTER_ROLE
  error MsgSenderNotSetter();
  /// Error thrown when the yearly rate's APY differs from the intended APY beyond the tolerance
  error IntendedAPYMismatch();
  /// Error thrown when the yearly rate exceeds `MAX_YEARLY_RATE`
  error RateTooHigh();
  /// Error thrown when the ORACLE_SETTER_ROLE acts while the current yearly rate is zero
  error ZeroRateAdminOnly();
  /// Error thrown when the guardian is the zero address
  error ZeroAddress();
  /// Error thrown when the initial price is zero
  error ZeroInitialPrice();

  /**
   * @param  guardian           The address that will be granted the DEFAULT_ADMIN_ROLE
   * @param  _symbol            The symbol of the RWA token
   * @param  _initialPrice      The initial price to set, with 18 decimals of precision
   * @param  _initialYearlyRate The initial yearly rate to set
   * @param  _maxRateChangeBps  The maximum yearly rate change by the ORACLE_SETTER_ROLE, in bps of
   *                            the current yearly rate
   * @param  _maxPriceChangeBps The maximum price change by the ORACLE_SETTER_ROLE, in bps of the
   *                            current price
   */
  constructor(
    address guardian,
    string memory _symbol,
    uint256 _initialPrice,
    uint64 _initialYearlyRate,
    uint64 _maxRateChangeBps,
    uint64 _maxPriceChangeBps
  ) {
    if (_initialYearlyRate > MAX_YEARLY_RATE) revert RateTooHigh();
    if (guardian == address(0)) revert ZeroAddress();
    if (_initialPrice == 0) revert ZeroInitialPrice();
    _grantRole(DEFAULT_ADMIN_ROLE, guardian);

    symbol = _symbol;
    priceStored = _initialPrice;
    lastPriceStoredTimestamp = _currentTime();
    lastPriceChangeTimestamp = _currentTime();
    lastRateChangeTimestamp = _currentTime();
    currentYearlyRate = _initialYearlyRate;
    nextRateStart = MAX_UINT64;
    maxRateChangeBps = _maxRateChangeBps;
    maxPriceChangeBps = _maxPriceChangeBps;
    minimumChangeWindow = 8 hours;

    emit PriceSet(_initialPrice, _currentTime());
    emit CurrentYearlyRateSet(_initialYearlyRate, _currentTime());
  }

  /**
   * @notice Get the current price of the RWA token
   * @return price The current price of the RWA token, with 18 decimals of precision
   */
  function getPrice() public view returns (uint256 price) {
    if (_currentTime() < nextRateStart) {
      return (priceStored
          * ContinuousIndexingMath.getContinuousIndex(
          currentYearlyRate,
          // forge-lint: disable-next-line(unsafe-typecast)
          uint32(_currentTime() - lastPriceStoredTimestamp)
        )) / RATE_PRECISION;
    } else {
      return (priceAtNextRateStart
          * ContinuousIndexingMath.getContinuousIndex(
          nextYearlyRate,
          // forge-lint: disable-next-line(unsafe-typecast)
          uint32(_currentTime() - nextRateStart)
        )) / RATE_PRECISION;
    }
  }

  /**
   * @notice Get the current price and timestamp of the RWA token
   * @return price     The current price of the RWA token, with 18 decimals of precision
   * @return timestamp The timestamp this price is accurate to
   */
  function getPriceData() external view returns (uint256 price, uint256 timestamp) {
    return (getPrice(), _currentTime());
  }

  /**
   * @notice Get the current APY of the RWA token
   * @return The current APY of the RWA token, with 12 decimals of precision (1e12 = 100% APY)
   */
  function getCurrentAPY() external view returns (uint64) {
    // The set yearly rate r in this contract is used in e^rt where t is years to calculate a price
    // index so converting it to APY is just e^r - 1
    uint64 yearlyRate = _currentTime() < nextRateStart ? currentYearlyRate : nextYearlyRate;
    return ContinuousIndexingMath.getContinuousIndex(
      yearlyRate, ContinuousIndexingMath.SECONDS_PER_YEAR
    ) - RATE_PRECISION;
  }

  /**
   * @notice Get the current time
   * @return The current time, cast to a uint64
   */
  function _currentTime() internal view returns (uint64) {
    return uint64(block.timestamp);
  }

  /**
   * @notice Set the current price of the RWA token
   * @param  newPriceNow The price to set, with 18 decimals of precision
   * @dev    The TIMELOCKED_ADMIN_ROLE is not bound by the ORACLE_SETTER_ROLE bounds.
   */
  function setPriceNow(uint256 newPriceNow) external onlySetter {
    _syncRateAndPriceStoredToNow();
    _requireAdminWhenRateIsZero();

    // The TIMELOCKED_ADMIN_ROLE can set the price to any value
    if (!hasRole(TIMELOCKED_ADMIN_ROLE, _msgSender())) {
      if (minimumChangeWindow > _currentTime() - lastPriceChangeTimestamp) {
        revert PriceChangeWindowNotPassed();
      }

      uint256 currentPrice = priceStored;
      uint256 priceChange =
        newPriceNow > currentPrice ? newPriceNow - currentPrice : currentPrice - newPriceNow;
      if (priceChange > (maxPriceChangeBps * currentPrice) / BPS_PRECISION) {
        revert PriceChangeTooLarge();
      }
    }

    priceStored = newPriceNow;
    lastPriceStoredTimestamp = _currentTime();
    lastPriceChangeTimestamp = _currentTime();

    if (_isNextRateSet()) priceAtNextRateStart = _getPriceAtNextRateStart();

    emit PriceSet(priceStored, lastPriceStoredTimestamp);
  }

  /**
   * @notice Set the current yearly rate of the RWA token, clearing any pending next yearly rate
   * @param  _currentYearlyRate The yearly rate to set
   * @param  intendedApy        The APY corresponding to the yearly rate
   * @dev    The TIMELOCKED_ADMIN_ROLE is not bound by the ORACLE_SETTER_ROLE bounds. The minimum
   *         change window is shared with `setNextRate`.
   */
  function setRateNow(uint64 _currentYearlyRate, uint64 intendedApy) external onlySetter {
    _syncRateAndPriceStoredToNow();
    _requireAdminWhenRateIsZero();
    _verifyRateChange(_currentYearlyRate, intendedApy);

    currentYearlyRate = _currentYearlyRate;
    lastPriceStoredTimestamp = _currentTime();
    lastRateChangeTimestamp = _currentTime();

    // We clear the next rate if it has been set, isolating state changes of each function
    if (_isNextRateSet()) _clearNextRate();

    emit CurrentYearlyRateSet(currentYearlyRate, lastPriceStoredTimestamp);
  }

  /**
   * @notice Set the next yearly rate of the RWA token and when it starts, replacing any pending
   *         next yearly rate
   * @param  _nextYearlyRate The yearly rate to set
   * @param  intendedApy     The APY corresponding to the yearly rate
   * @param  _nextRateStart  The timestamp of when the yearly rate will start
   * @dev    The TIMELOCKED_ADMIN_ROLE is not bound by the ORACLE_SETTER_ROLE bounds. The minimum
   *         change window is shared with `setRateNow`.
   */
  function setNextRate(uint64 _nextYearlyRate, uint64 intendedApy, uint64 _nextRateStart)
    external
    onlySetter
  {
    if (_nextRateStart <= _currentTime()) {
      revert InvalidStartTime();
    }
    if (_nextRateStart - _currentTime() > ContinuousIndexingMath.SECONDS_PER_YEAR) {
      revert StartTimeTooFar();
    }
    _syncRateAndPriceStoredToNow();
    _requireAdminWhenRateIsZero();
    _verifyRateChange(_nextYearlyRate, intendedApy);

    nextYearlyRate = _nextYearlyRate;
    nextRateStart = _nextRateStart;
    priceAtNextRateStart = _getPriceAtNextRateStart();
    lastRateChangeTimestamp = _currentTime();

    emit NextYearlyRateSet(nextYearlyRate, nextRateStart);
  }

  /// Clear the pending next yearly rate
  function clearNextRate() external onlySetter {
    _syncRateAndPriceStoredToNow();
    _requireAdminWhenRateIsZero();
    // Gas optimization in case syncing the rate clears the next rate
    if (_isNextRateSet()) _clearNextRate();
  }

  /// Freeze the price by setting the current yearly rate to zero and clearing the next yearly rate
  function freezePrice() external onlyRole(PRICE_FREEZER_ROLE) {
    _syncRateAndPriceStoredToNow();
    currentYearlyRate = 0;
    emit CurrentYearlyRateSet(currentYearlyRate, lastPriceStoredTimestamp);

    if (_isNextRateSet()) _clearNextRate();
  }

  /// Store the accrued price and apply the next yearly rate if it has started
  function syncRateAndPriceStoredToNow() external onlyRole(SYNCER_ROLE) {
    _syncRateAndPriceStoredToNow();
  }

  /**
   * @notice Set the maximum yearly rate change by the ORACLE_SETTER_ROLE
   * @param  _maxRateChangeBps The maximum rate change, in bps of the current yearly rate
   */
  function setMaxRateChangeBps(uint64 _maxRateChangeBps) external onlyRole(TIMELOCKED_ADMIN_ROLE) {
    emit MaxRateChangeSet(maxRateChangeBps, _maxRateChangeBps);
    maxRateChangeBps = _maxRateChangeBps;
  }

  /**
   * @notice Set the maximum price change by the ORACLE_SETTER_ROLE
   * @param  _maxPriceChangeBps The maximum price change, in bps of the current price
   */
  function setMaxPriceChangeBps(uint64 _maxPriceChangeBps)
    external
    onlyRole(TIMELOCKED_ADMIN_ROLE)
  {
    emit MaxPriceChangeSet(maxPriceChangeBps, _maxPriceChangeBps);
    maxPriceChangeBps = _maxPriceChangeBps;
  }

  /**
   * @notice Set the minimum time in seconds between ORACLE_SETTER_ROLE price changes, and between
   *         its yearly rate changes
   * @param  _minimumChangeWindow The minimum change window in seconds
   */
  function setMinimumChangeWindow(uint64 _minimumChangeWindow)
    external
    onlyRole(TIMELOCKED_ADMIN_ROLE)
  {
    // A zero window would let the ORACLE_SETTER_ROLE bypass the bounds within one block
    if (_minimumChangeWindow == 0) revert ChangeWindowCantBeZero();
    emit MinimumChangeWindowSet(minimumChangeWindow, _minimumChangeWindow);
    minimumChangeWindow = _minimumChangeWindow;
  }

  /**
   * @notice Verify a yearly rate against `MAX_YEARLY_RATE`, the intended APY and the
   *         ORACLE_SETTER_ROLE change window and bounds
   * @param  yearlyRate  The yearly rate to verify
   * @param  intendedApy The intended APY to verify against
   */
  function _verifyRateChange(uint64 yearlyRate, uint64 intendedApy) internal view {
    if (yearlyRate > MAX_YEARLY_RATE) revert RateTooHigh();

    // Double check the yearly rate against the intended APY
    uint64 actualAPY = ContinuousIndexingMath.getContinuousIndex(
      yearlyRate, ContinuousIndexingMath.SECONDS_PER_YEAR
    ) - RATE_PRECISION;
    uint64 diff = intendedApy > actualAPY ? intendedApy - actualAPY : actualAPY - intendedApy;
    if (diff > INTENDED_APY_TOLERANCE) revert IntendedAPYMismatch();

    // Check that the yearly rate change is within bounds if the sender is not the admin
    if (!hasRole(TIMELOCKED_ADMIN_ROLE, _msgSender())) {
      if (minimumChangeWindow > _currentTime() - lastRateChangeTimestamp) {
        revert RateChangeWindowNotPassed();
      }

      uint64 rateChange = yearlyRate > currentYearlyRate
        ? yearlyRate - currentYearlyRate
        : currentYearlyRate - yearlyRate;
      if (rateChange > (uint256(maxRateChangeBps) * currentYearlyRate) / BPS_PRECISION) {
        revert RateChangeTooLarge();
      }
    }
  }

  /// Revert if the current yearly rate is zero and the sender is not the TIMELOCKED_ADMIN_ROLE
  function _requireAdminWhenRateIsZero() internal view {
    if (currentYearlyRate == 0 && !hasRole(TIMELOCKED_ADMIN_ROLE, _msgSender())) {
      revert ZeroRateAdminOnly();
    }
  }

  /// Store the accrued price and apply the next yearly rate if it has started, otherwise
  /// recompute its start price from the new anchor
  function _syncRateAndPriceStoredToNow() internal {
    priceStored = getPrice();
    lastPriceStoredTimestamp = _currentTime();

    emit PriceSet(priceStored, lastPriceStoredTimestamp);

    if (_currentTime() >= nextRateStart) {
      currentYearlyRate = nextYearlyRate;
      emit CurrentYearlyRateSet(currentYearlyRate, nextRateStart);

      _clearNextRate();
    } else if (_isNextRateSet()) {
      priceAtNextRateStart = _getPriceAtNextRateStart();
    }
  }

  /**
   * @notice Calculate the price at `nextRateStart` from `priceStored` at the current yearly rate
   * @return The price at `nextRateStart`, with 18 decimals of precision
   */
  function _getPriceAtNextRateStart() internal view returns (uint256) {
    return (priceStored
        * ContinuousIndexingMath.getContinuousIndex(
        currentYearlyRate,
        // forge-lint: disable-next-line(unsafe-typecast)
        uint32(nextRateStart - lastPriceStoredTimestamp)
      )) / RATE_PRECISION;
  }

  /// Clear the next yearly rate
  function _clearNextRate() internal {
    nextYearlyRate = 0;
    nextRateStart = MAX_UINT64;
    priceAtNextRateStart = 0;
    emit NextYearlyRateSet(nextYearlyRate, nextRateStart);
  }

  /**
   * @notice Check if the next rate has been set
   * @return True if the next rate has been set, false otherwise
   */
  function _isNextRateSet() internal view returns (bool) {
    return nextRateStart < MAX_UINT64;
  }

  /// Verify that the sender has the TIMELOCKED_ADMIN_ROLE or the ORACLE_SETTER_ROLE
  modifier onlySetter() {
    if (!(hasRole(ORACLE_SETTER_ROLE, _msgSender())
          || hasRole(TIMELOCKED_ADMIN_ROLE, _msgSender()))) revert MsgSenderNotSetter();
    _;
  }
}
