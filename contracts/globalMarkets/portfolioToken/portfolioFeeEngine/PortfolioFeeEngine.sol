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
  IPortfolioFeeEngine
} from "contracts/globalMarkets/portfolioToken/portfolioFeeEngine/IPortfolioFeeEngine.sol";
import {
  IPortfolioTokenManager
} from "contracts/globalMarkets/portfolioToken/portfolioTokenManager/IPortfolioTokenManager.sol";
import {
  IPortfolioOrchestrator
} from "contracts/globalMarkets/portfolioToken/portfolioOrchestrator/IPortfolioOrchestrator.sol";
import {
  IPortfolioVault
} from "contracts/globalMarkets/portfolioToken/portfolioVault/IPortfolioVault.sol";
import {
  IOndoSanityCheckOracle
} from "contracts/globalMarkets/tokenManager/sanityCheckOracle/IOndoSanityCheckOracle.sol";
import {
  AccessControlEnumerable
} from "contracts/external/openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {
  ReentrancyGuardTransient
} from "contracts/external/openzeppelin/contracts/security/ReentrancyGuardTransient.sol";
import {Pausable} from "contracts/external/openzeppelin/contracts/security/Pausable.sol";
import {IERC20} from "contracts/external/openzeppelin/contracts/token/IERC20.sol";
import {SafeERC20} from "contracts/external/openzeppelin/contracts/token/SafeERC20.sol";

/**
 * @title  PortfolioFeeEngine
 * @author Ondo Finance
 * @notice Collateral-anchored management-fee collector for portfolio tokens. The engine anchors the
 *         fee to the value of the portfolio's collateral priced through the `OndoSanityCheckOracle`
 *         that already gates every GM mint/redeem.
 */
contract PortfolioFeeEngine is
  IPortfolioFeeEngine,
  AccessControlEnumerable,
  Pausable,
  ReentrancyGuardTransient
{
  using SafeERC20 for IERC20;

  /// Role to configure fee rates, the fee recipient, and the allowed deviation
  bytes32 public constant FEE_CONFIGURER_ROLE = keccak256("FEE_CONFIGURER_ROLE");

  /// Role to trigger fee collection (intended for an automated job)
  bytes32 public constant FEE_COLLECTOR_ROLE = keccak256("FEE_COLLECTOR_ROLE");

  /// Role to pause fee collection (unpausing is restricted to `DEFAULT_ADMIN_ROLE`)
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

  /// The maximum annualized fee rate, in basis points (3%)
  uint16 internal constant MAX_FEE_RATE_BPS = 300;

  /// The maximum allowed deviation, in basis points (100%)
  uint16 internal constant MAX_ALLOWED_DEVIATION_BPS = 10_000;

  /// Basis-points denominator for the fee rate and the allowed deviation (10,000 = 100%)
  uint256 internal constant BPS = 10_000;

  /// Seconds per year, used to pro-rate the annualized fee rate
  uint256 internal constant SECONDS_PER_YEAR = 365 days;

  /// USD price precision (oracle prices and token amounts are 18 decimals)
  uint256 internal constant PRICE_NORMALIZER = 1e18;

  /// The PortfolioTokenManager that mints portfolio tokens and processes redemptions
  IPortfolioTokenManager public immutable portfolioTokenManager;

  /// The stablecoin paid out by the PTM on redemption and forwarded to `feeRecipient` on autosell.
  /// Derived from the PTM at construction (never a constructor param) so the two can't diverge.
  IERC20 public immutable stablecoin;

  /// The orchestrator used to resolve each portfolio token's collateral vault
  IPortfolioOrchestrator public immutable portfolioOrchestrator;

  /// The sanity-check oracle providing posted USD prices + staleness per token
  IOndoSanityCheckOracle public immutable sanityCheckOracle;

  /// Per-token fee configuration
  mapping(address portfolioToken => FeeConfig) public feeConfigs;

  /// Per-token destination for the stablecoin proceeds of fee collection
  mapping(address portfolioToken => address) public feeRecipients;

  /// The contract-wide allowed deviation applied to the collateral valuation to form the fee band
  uint16 public allowedDeviationBps;

  /**
   * @param guardian               The address granted `DEFAULT_ADMIN_ROLE`
   * @param _portfolioTokenManager The PortfolioTokenManager the engine mints/redeems through, and
   *                               the source of the payout stablecoin (its `stablecoin()` getter)
   * @param _portfolioOrchestrator The orchestrator resolving each portfolio's collateral vault
   * @param _sanityCheckOracle     The sanity-check oracle providing posted prices + staleness
   * @param _allowedDeviationBps   The initial contract-wide allowed deviation, basis points
   */
  constructor(
    address guardian,
    address _portfolioTokenManager,
    address _portfolioOrchestrator,
    address _sanityCheckOracle,
    uint16 _allowedDeviationBps
  ) {
    if (guardian == address(0)) revert InvalidAddress();
    if (_portfolioTokenManager == address(0)) revert InvalidAddress();
    if (_portfolioOrchestrator == address(0)) revert InvalidAddress();
    if (_sanityCheckOracle == address(0)) revert InvalidAddress();
    if (_allowedDeviationBps == 0 || _allowedDeviationBps > MAX_ALLOWED_DEVIATION_BPS) {
      revert InvalidAllowedDeviation(_allowedDeviationBps, MAX_ALLOWED_DEVIATION_BPS);
    }

    portfolioTokenManager = IPortfolioTokenManager(_portfolioTokenManager);
    stablecoin = IERC20(portfolioTokenManager.stablecoin());
    portfolioOrchestrator = IPortfolioOrchestrator(_portfolioOrchestrator);
    sanityCheckOracle = IOndoSanityCheckOracle(_sanityCheckOracle);
    allowedDeviationBps = _allowedDeviationBps;
    _grantRole(DEFAULT_ADMIN_ROLE, guardian);
  }

  /*//////////////////////////////////////////////////////////////
                          Collection
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Collects accrued fees and auto-sells them for the stablecoin.
   *         The proposal's USD value must fall within the collateral-derived
   *         plausibility band `[lower, upper]`. Mints `quote.quantity` portfolio tokens to this
   *         engine, redeems them through the PTM for the stablecoin, and forwards the proceeds to
   *         the token's configured fee recipient.
   * @param  params           The collect-and-redeem parameters: token, constituents, quote,
   *                          signature, and mint metadata
   * @return stablecoinAmount The amount of the stablecoin received and forwarded to the recipient
   */
  function collectAndRedeemFees(CollectAndRedeemParams calldata params)
    external
    nonReentrant
    whenNotPaused
    onlyRole(FEE_COLLECTOR_ROLE)
    returns (uint256 stablecoinAmount)
  {
    stablecoinAmount = _collectAndRedeemFees(params);
  }

  /**
   * @notice Collects and auto-sells accrued fees for multiple portfolio tokens in a single call,
   *         routing each portfolio's stablecoin proceeds to its own configured fee recipient.
   *         Atomic: if any item fails (bad/out-of-band quote, fee not started, nothing to collect,
   *         etc.) the entire batch reverts.
   * @param  items             Per-portfolio collection parameters (token, constituents, quote,
   *                           signature, mint metadata)
   * @return stablecoinAmounts The stablecoin received and forwarded for each item, in `items` order
   */
  function batchCollectAndRedeemFees(CollectAndRedeemParams[] calldata items)
    external
    nonReentrant
    whenNotPaused
    onlyRole(FEE_COLLECTOR_ROLE)
    returns (uint256[] memory stablecoinAmounts)
  {
    stablecoinAmounts = new uint256[](items.length);
    for (uint256 i = 0; i < items.length; ++i) {
      stablecoinAmounts[i] = _collectAndRedeemFees(items[i]);
    }
  }

  /*//////////////////////////////////////////////////////////////
                          Configuration
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Sets a token's annualized fee rate and starts its accrual timer.
   * @dev    This overwrites the accrual anchor (`lastCollectionTimestamp`) with `start`, so calling
   *         it while a fee is accruing RESETS the in-progress accrual: any fee accrued since the
   *         last collection but not yet collected is forfeited, and accrual restarts from `start`.
   *         To avoid dropping accrued-but-uncollected fees, collect first, then call this.
   * @param  token          The portfolio token to configure
   * @param  feeRateBps     The annualized fee rate, in basis points (<= `MAX_FEE_RATE_BPS`).
   *                        A rate of 0 disables collection for the token.
   * @param  startTimestamp The timestamp that fee accrual begins from; `0` means the current block.
   *                        Must not be earlier than the current block but may be in the future to
   *                        schedule a fee that has not started yet.
   */
  function setFeeRate(address token, uint16 feeRateBps, uint40 startTimestamp)
    external
    onlyRole(FEE_CONFIGURER_ROLE)
  {
    if (feeRateBps > MAX_FEE_RATE_BPS) revert InvalidFeeRate(feeRateBps, MAX_FEE_RATE_BPS);

    uint40 start = startTimestamp == 0 ? uint40(block.timestamp) : startTimestamp;
    if (start < block.timestamp) revert InvalidStartTimestamp(start, block.timestamp);

    feeConfigs[token] = FeeConfig({feeRateBps: feeRateBps, lastCollectionTimestamp: start});

    emit FeeRateSet(token, feeRateBps, start);
  }

  /**
   * @notice Sets the destination for a token's collected proceeds. Independent of the token's fee
   *         rate and accrual timer, so updating it does not disturb in-progress accrual.
   * @param  token           The portfolio token to configure
   * @param  newFeeRecipient The new fee recipient
   */
  function setFeeRecipient(address token, address newFeeRecipient)
    external
    onlyRole(FEE_CONFIGURER_ROLE)
  {
    if (newFeeRecipient == address(0)) revert InvalidAddress();
    address oldFeeRecipient = feeRecipients[token];
    feeRecipients[token] = newFeeRecipient;
    emit FeeRecipientSet(token, oldFeeRecipient, newFeeRecipient);
  }

  /**
   * @notice Sets the contract-wide allowed deviation.
   * @param  bps The allowed deviation, basis points (0 < bps <= MAX_ALLOWED_DEVIATION_BPS)
   */
  function setAllowedDeviationBps(uint16 bps) external onlyRole(FEE_CONFIGURER_ROLE) {
    if (bps == 0 || bps > MAX_ALLOWED_DEVIATION_BPS) {
      revert InvalidAllowedDeviation(bps, MAX_ALLOWED_DEVIATION_BPS);
    }
    uint16 oldBps = allowedDeviationBps;
    allowedDeviationBps = bps;
    emit AllowedDeviationBpsSet(oldBps, bps);
  }

  /*//////////////////////////////////////////////////////////////
                          Views
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Returns the two-sided plausibility band (USD, 18 decimals) that a
   *         `collectAndRedeemFees` proposal's value must fall within for a token. Lets the backend
   *         size an in-band proposal.
   * @param  token        The portfolio token to query
   * @param  constituents The strictly-ascending, unique GM tokens that back `token`
   * @return lowerUsd     The lower bound, in USD with 18 decimals (0 if no fee rate is set)
   * @return upperUsd     The upper bound, in USD with 18 decimals (0 if no fee rate is set)
   */
  function feeBoundsUsd(address token, address[] calldata constituents)
    public
    view
    returns (uint256 lowerUsd, uint256 upperUsd)
  {
    FeeConfig memory config = feeConfigs[token];
    if (config.feeRateBps == 0) return (0, 0);
    (lowerUsd, upperUsd) =
      _feeBounds(token, constituents, config.feeRateBps, config.lastCollectionTimestamp);
  }

  /*//////////////////////////////////////////////////////////////
                          Admin
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Rescue and transfer tokens locked in this contract.
   * @param  token  The address of the token
   * @param  to     The address of the recipient
   * @param  amount The amount of token to transfer
   */
  function retrieveTokens(address token, address to, uint256 amount)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    IERC20(token).safeTransfer(to, amount);
    emit TokensRetrieved(token, to, amount);
  }

  /**
   * @notice Pauses fee collection (`collectAndRedeemFees` / `batchCollectAndRedeemFees`).
   *         Configuration and `retrieveTokens` remain available while paused.
   */
  function pause() external onlyRole(PAUSER_ROLE) {
    _pause();
  }

  /**
   * @notice Resumes fee collection. Restricted to `DEFAULT_ADMIN_ROLE` — a stricter gate than
   *         pausing, so a lone `PAUSER_ROLE` holder cannot un-pause.
   */
  function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
    _unpause();
  }

  /*//////////////////////////////////////////////////////////////
                          Internal
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Core single-portfolio collect-and-redeem logic.
   * @param  params           The collect-and-redeem parameters: token, constituents, quote,
   *                          signature, and mint metadata
   * @return stablecoinAmount The amount of the stablecoin received and forwarded to the recipient
   */
  function _collectAndRedeemFees(CollectAndRedeemParams calldata params)
    internal
    returns (uint256 stablecoinAmount)
  {
    address token = params.token;
    IPortfolioTokenManager.Quote calldata quote = params.quote;

    if (quote.asset != token) revert QuoteAssetMismatch();

    address recipient;
    uint40 from;
    {
      uint16 feeRateBps;
      (feeRateBps, from, recipient) = _prepareFeeCollection(token);

      (uint256 feeLowerUsd, uint256 feeUpperUsd) =
        _feeBounds(token, params.constituents, feeRateBps, from);
      if (feeUpperUsd == 0) revert NothingToCollect();

      uint256 requestedUsd = quote.quantity * quote.price / PRICE_NORMALIZER;
      if (requestedUsd < feeLowerUsd || requestedUsd > feeUpperUsd) {
        revert FeeOutOfCollateralBand(requestedUsd, feeLowerUsd, feeUpperUsd);
      }
    }

    // Reset the accrual timer
    feeConfigs[token].lastCollectionTimestamp = uint40(block.timestamp);

    // Mint the fee tokens and then redeem them for the stablecoin via the PTM.
    portfolioTokenManager.adminProcessMint(
      token, address(this), quote.quantity, params.mintMetadata
    );
    IERC20(token).forceApprove(address(portfolioTokenManager), quote.quantity);
    stablecoinAmount = portfolioTokenManager.redeemWithAttestation(quote, params.signature);

    // Forward the proceeds to the token's fee recipient.
    stablecoin.safeTransfer(recipient, stablecoinAmount);

    emit FeesCollected(token, quote.quantity, stablecoinAmount, recipient, from, block.timestamp);
  }

  /**
   * @notice Validates a token has a fee rate, a fee recipient, and a started accrual, then returns
   *         the config the caller needs to size the fee.
   * @param  token       The portfolio token to collect fees for
   * @return feeRateBps  The token's annualized fee rate, basis points
   * @return accrualFrom The timestamp the accrual period started from
   * @return recipient   The token's configured fee recipient
   */
  function _prepareFeeCollection(address token)
    internal
    view
    returns (uint16 feeRateBps, uint40 accrualFrom, address recipient)
  {
    FeeConfig memory config = feeConfigs[token];
    feeRateBps = config.feeRateBps;
    if (feeRateBps == 0) revert FeeNotSet();

    recipient = feeRecipients[token];
    if (recipient == address(0)) revert FeeRecipientNotSet();

    accrualFrom = config.lastCollectionTimestamp;
    if (block.timestamp < accrualFrom) revert FeeNotStarted(accrualFrom, block.timestamp);
  }

  /**
   * @notice Values the basket and pro-rates it into the two-sided fee band.
   * @param  token        The portfolio token
   * @param  constituents The strictly-ascending, unique GM tokens that back `token`
   * @param  feeRateBps   The annualized fee rate, basis points
   * @param  from         The timestamp the accrual period started from
   * @return feeLowerUsd  The lower band edge, USD 18 decimals
   * @return feeUpperUsd  The upper band edge, USD 18 decimals
   */
  function _feeBounds(
    address token,
    address[] calldata constituents,
    uint16 feeRateBps,
    uint40 from
  ) internal view returns (uint256 feeLowerUsd, uint256 feeUpperUsd) {
    uint256 aum = _valueBasket(token, constituents);

    // Before the scheduled start (`from` in the future) elapsed is 0, so `_proRate` returns (0, 0)
    // rather than underflowing; the collection paths revert `FeeNotStarted` in
    // `_prepareFeeCollection`.
    uint256 elapsed = block.timestamp > from ? block.timestamp - uint256(from) : 0;
    (feeLowerUsd, feeUpperUsd) = _proRate(aum, allowedDeviationBps, feeRateBps, elapsed);
  }

  /**
   * @notice Sums each constituent's storage balance at the sanity oracle's posted price into the
   *         basket's central AUM.
   * @dev    Assumes the resolved storage (custody) address holds only this portfolio's collateral —
   *         a per-portfolio deployment invariant.
   * @param  token        The portfolio token whose vault is resolved via the orchestrator
   * @param  constituents The strictly-ascending, unique GM tokens that back `token`
   * @return aum          The summed basket value (Σ storageBalanceᵢ·priceᵢ / 1e18), USD 18 decimals
   */
  function _valueBasket(address token, address[] calldata constituents)
    internal
    view
    returns (uint256 aum)
  {
    address vault = portfolioOrchestrator.vaultAddress(token);
    if (vault == address(0)) revert VaultNotSet();
    address vaultStorage = IPortfolioVault(vault).custodyAddress();

    address prev = address(0);
    for (uint256 i = 0; i < constituents.length; ++i) {
      address c = constituents[i];
      // Strictly ascending => unique and non-zero, so the basket can't be double-counted.
      if (c <= prev) revert ConstituentsNotSorted();
      prev = c;

      // Value only the storage balance (the vault is transient staging), summed inline.
      aum += IERC20(c).balanceOf(vaultStorage) * _price(c) / PRICE_NORMALIZER;
    }
  }

  /**
   * @notice Reads a token's posted price from the sanity oracle, enforcing its staleness rule.
   * @param  token The token to read
   * @return price The posted price, USD 18 decimals
   */
  function _price(address token) internal view returns (uint256 price) {
    uint64 lastUpdated;
    uint32 maxTimeDelay;
    (price, lastUpdated, maxTimeDelay,) = sanityCheckOracle.prices(token);
    if (price == 0 || uint256(lastUpdated) + uint256(maxTimeDelay) < block.timestamp) {
      revert StaleOrUnsetPrice(token, lastUpdated, maxTimeDelay);
    }
  }

  /**
   * @notice Pro-rates `aum` into a symmetric fee band widened by `devBps`,
   *         scaled by `rateBps` over `elapsed`.
   * @dev    `feeLower <= feeUpper`. `feeUpper == 0` means nothing to collect.
   * @param  aum      The central basket value, USD 18 decimals
   * @param  devBps   The contract-wide allowed deviation, basis points
   * @param  rateBps  The annualized fee rate, basis points
   * @param  elapsed  The accrual period, seconds
   * @return feeLower The lower band edge, USD 18 decimals
   * @return feeUpper The upper band edge, USD 18 decimals
   */
  function _proRate(uint256 aum, uint256 devBps, uint256 rateBps, uint256 elapsed)
    internal
    pure
    returns (uint256 feeLower, uint256 feeUpper)
  {
    uint256 perYear = BPS * SECONDS_PER_YEAR;
    uint256 delta = aum * devBps / BPS;
    uint256 lowerAum = aum - delta;

    feeUpper = (aum + delta) * rateBps * elapsed / perYear;
    feeLower = lowerAum * rateBps * elapsed / perYear;
  }
}
