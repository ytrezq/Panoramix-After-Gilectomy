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

import {
  IPortfolioTokenManager
} from "contracts/globalMarkets/portfolioToken/portfolioTokenManager/IPortfolioTokenManager.sol";

/**
 * @title  IPortfolioFeeEngine
 * @author Ondo Finance
 * @notice Interface for the `PortfolioFeeEngine` contract — the collateral-anchored management-fee
 *         collector for portfolio tokens. The engine derives the fee from the value of the
 *         portfolio's collateral basket held at its storage address on the collateral chain, priced
 *         through the `OndoSanityCheckOracle`. The collateral basket is supplied by the caller at
 *         fee-take time as a sorted, unique list of constituent token addresses.
 *
 *         The backend proposes the fee amount; the contract hard-bounds it on-chain to a two-sided
 *         plausibility band derived from the collateral value and a single contract-wide allowed
 *         deviation.
 */
interface IPortfolioFeeEngine {
  // ─────────────────────────────────────────────────────────────────────────────
  // Structs
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * @notice Per-token fee configuration.
   * @param  feeRateBps              The annualized fee rate, in basis points (1e4 = 100%). A rate
   *                                 of 0 means no fee is set and collection reverts.
   * @param  lastCollectionTimestamp The timestamp fees were last collected, or the rate was set
   */
  struct FeeConfig {
    uint16 feeRateBps;
    uint40 lastCollectionTimestamp;
  }

  /**
   * @notice Parameters for a single collect-and-redeem; used directly by `collectAndRedeemFees` and
   *         as the array element of `batchCollectAndRedeemFees`.
   * @param  token        The portfolio token to collect fees for
   * @param  constituents The strictly-ascending, unique GM tokens that back `token`
   * @param  quote        The SELL quote attestation used to redeem the minted tokens
   * @param  signature    The PTM attestation signature over `quote`
   * @param  mintMetadata Additional metadata to emit with the underlying admin mint
   */
  struct CollectAndRedeemParams {
    address token;
    address[] constituents;
    IPortfolioTokenManager.Quote quote;
    bytes signature;
    bytes32 mintMetadata;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Events
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * @notice Emitted when a token's fee rate is set and its accrual timer (re)started
   * @param  token                   The portfolio token whose rate was set
   * @param  feeRateBps              The annualized fee rate, in basis points
   * @param  lastCollectionTimestamp The timestamp the accrual timer was (re)started at
   */
  event FeeRateSet(address indexed token, uint16 feeRateBps, uint256 lastCollectionTimestamp);

  /**
   * @notice Emitted when a token's fee recipient is updated
   * @param  token           The portfolio token whose recipient was updated
   * @param  oldFeeRecipient The previous fee recipient
   * @param  newFeeRecipient The new fee recipient
   */
  event FeeRecipientSet(
    address indexed token, address indexed oldFeeRecipient, address indexed newFeeRecipient
  );

  /**
   * @notice Emitted when the contract-wide allowed deviation is set
   * @param  oldBps The previous allowed deviation, basis points
   * @param  newBps The new allowed deviation, basis points
   */
  event AllowedDeviationBpsSet(uint16 oldBps, uint16 newBps);

  /**
   * @notice Emitted when fees are collected and auto-sold for the stablecoin
   * @param  token            The portfolio token fees were collected for
   * @param  tokenAmount      The amount of portfolio tokens minted and sold
   * @param  stablecoinAmount The amount of the stablecoin received and forwarded to the recipient
   * @param  recipient        The address that received the stablecoin
   * @param  fromTimestamp    The start of the accrual period that was collected
   * @param  toTimestamp      The end of the accrual period (the collection timestamp)
   */
  event FeesCollected(
    address indexed token,
    uint256 tokenAmount,
    uint256 stablecoinAmount,
    address indexed recipient,
    uint256 fromTimestamp,
    uint256 toTimestamp
  );

  /**
   * @notice Emitted when tokens are rescued from the contract via `retrieveTokens`
   * @param  token     The address of the token that was retrieved
   * @param  recipient The address that received the tokens
   * @param  amount    The amount retrieved, in the token's native decimals
   */
  event TokensRetrieved(address indexed token, address indexed recipient, uint256 amount);

  // ─────────────────────────────────────────────────────────────────────────────
  // Errors
  // ─────────────────────────────────────────────────────────────────────────────

  /// Error emitted when a zero address is supplied where it is not permitted
  error InvalidAddress();

  /// Error emitted when a fee rate above the cap is supplied; carries the supplied rate and the cap
  error InvalidFeeRate(uint16 feeRateBps, uint16 maxFeeRateBps);

  /// Error emitted when the supplied fee-start timestamp is earlier than the current block
  error InvalidStartTimestamp(uint40 startTimestamp, uint256 currentTimestamp);

  /// Error emitted when collecting fees before a token's scheduled fee-start timestamp
  error FeeNotStarted(uint256 startTimestamp, uint256 currentTimestamp);

  /// Error emitted when collecting fees for a token whose fee rate has not been set
  error FeeNotSet();

  /// Error emitted when collecting fees for a token whose fee recipient has not been set
  error FeeRecipientNotSet();

  /// Error emitted when there are no accrued fees to collect
  error NothingToCollect();

  /// Error emitted when the autosell quote asset does not match the token being collected
  error QuoteAssetMismatch();

  /// Error emitted when the portfolio token has no configured collateral vault on the orchestrator
  error VaultNotSet();

  /// Error emitted when the constituents array is not strictly ascending (rejects dupes and zero)
  error ConstituentsNotSorted();

  /// Error emitted when a token's oracle price is unset or stale; carries the price's last-update
  /// time and max staleness delay for debugging
  error StaleOrUnsetPrice(address token, uint64 lastUpdated, uint32 maxTimeDelay);

  /// Error emitted when the allowed deviation is 0 or above the max
  error InvalidAllowedDeviation(uint16 bps, uint16 maxBps);

  /// Error emitted when the proposed autosell fee falls outside the collateral-derived band
  error FeeOutOfCollateralBand(uint256 requestedUsd, uint256 lowerUsd, uint256 upperUsd);

  // ─────────────────────────────────────────────────────────────────────────────
  // Configuration
  // ─────────────────────────────────────────────────────────────────────────────

  function setFeeRate(address token, uint16 feeRateBps, uint40 startTimestamp) external;

  function setFeeRecipient(address token, address newFeeRecipient) external;

  function setAllowedDeviationBps(uint16 bps) external;

  function retrieveTokens(address token, address to, uint256 amount) external;

  function pause() external;

  function unpause() external;

  // ─────────────────────────────────────────────────────────────────────────────
  // Collection (collateral basket passed at fee-take; FEE_COLLECTOR_ROLE only)
  // ─────────────────────────────────────────────────────────────────────────────

  function collectAndRedeemFees(CollectAndRedeemParams calldata params)
    external
    returns (uint256 stablecoinAmount);

  function batchCollectAndRedeemFees(CollectAndRedeemParams[] calldata items)
    external
    returns (uint256[] memory stablecoinAmounts);

  // ─────────────────────────────────────────────────────────────────────────────
  // Views
  // ─────────────────────────────────────────────────────────────────────────────

  function feeBoundsUsd(address token, address[] calldata constituents)
    external
    view
    returns (uint256 lowerUsd, uint256 upperUsd);

  function allowedDeviationBps() external view returns (uint16);
}
