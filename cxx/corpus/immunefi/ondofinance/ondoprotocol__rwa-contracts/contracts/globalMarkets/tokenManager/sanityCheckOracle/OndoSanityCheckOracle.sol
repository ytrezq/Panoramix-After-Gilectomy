/**
 * SPDX-License-Identifier: BUSL-1.1
 *       ▄▄█████████▄
 *    ╓██▀└ ,╓▄▄▄, '▀██▄
 *   ██▀ ▄██▀▀╙╙▀▀██▄ └██µ           ,,       ,,      ,     ,,,            ,,,
 *  ██ ,██¬ ▄████▄  ▀█▄ ╙█▄      ▄███▀▀███▄   ███▄    ██  ███▀▀▀███▄    ▄███▀▀███,
 * ██  ██ ╒█▀'   ╙█▌ ╙█▌ ██     ▐██      ███  █████,  ██  ██▌    └██▌  ██▌     └██▌
 * ██ ▐█▌ ██      ╟█  █▌ ╟█     ██▌      ▐██  ██ └███ ██  ██▌     ╟██ j██       ╟██
 * ╟█  ██ ╙██    ▄█▀ ▐█▌ ██     ╙██      ██▌  ██   ╙████  ██▌    ▄██▀  ██▌     ,██▀
 *  ██ "██, ╙▀▀███████████⌐      ╙████████▀   ██     ╙██  ███████▀▀     ╙███████▀`
 *   ██▄ ╙▀██▄▄▄▄▄,,,                ¬─                                    '─¬
 *    ╙▀██▄ '╙╙╙▀▀▀▀▀▀▀▀
 *       ╙▀▀██████R⌐
 */
pragma solidity 0.8.33;

import {
  IOndoSanityCheckOracle
} from "contracts/globalMarkets/tokenManager/sanityCheckOracle/IOndoSanityCheckOracle.sol";
import {
  AccessControlEnumerable
} from "contracts/external/openzeppelin/contracts/access/AccessControlEnumerable.sol";

/**
 * @title  OndoSanityCheckOracle
 * @author Ondo Finance
 * @notice This contract is used to post and validate prices to be referenced as a sanity check when
 *         minting and redeeming tokens. Prices are only valid if they are within some bps-based
 *         deviation from the posted price and are not stale.
 */
contract OndoSanityCheckOracle is IOndoSanityCheckOracle, AccessControlEnumerable {
  /// Basis points denominator (10,000 = 100%)
  uint256 public constant BPS_DENOMINATOR = 10_000;
  /// Role for posting prices
  bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");
  /// Role for configuring oracle parameters
  bytes32 public constant CONFIGURER_ROLE = keccak256("CONFIGURER_ROLE");

  /**
   * @notice Struct to store price data for a token
   * @param  price               The price of the token in USD with 18 decimals
   * @param  lastUpdated         Unix timestamp of when the price was last updated
   * @param  maxTimeDelay        Number of seconds before the price is considered stale
   * @param  allowedDeviationBps Allowed deviation from posted price in basis points
   */
  struct PriceData {
    uint256 price;
    uint64 lastUpdated;
    uint32 maxTimeDelay;
    uint16 allowedDeviationBps;
  }

  /// How long a price remains valid for in seconds. Can be overridden on a per-token basis
  uint32 public defaultMaxTimeDelay;

  /// The default allowed deviation in basis points. Can be overridden on a per-token basis
  uint16 public defaultDeviationBps;

  /// Mapping of token address to price data
  mapping(address => PriceData) public prices;

  /**
   * @notice Emitted when a new price is posted for a token
   * @param  token           The address of the token
   * @param  lastPricePosted The last price posted for the token in USD with 18 decimals
   * @param  lastUpdated     The last time the price was updated
   * @param  newPrice        The new price of the token in USD with 18 decimals
   * @param  updateAt        The timestamp when the price was updated
   */
  event PricePosted(
    address indexed token,
    uint256 lastPricePosted,
    uint256 lastUpdated,
    uint256 newPrice,
    uint256 updateAt
  );

  /**
   * @notice Emitted when the allowed deviation is set for a token
   * @param  token               The address of the token
   * @param  allowedDeviationBps The allowed deviation in basis points
   */
  event AllowedDeviationSet(address indexed token, uint16 allowedDeviationBps);

  /**
   * @notice Emitted when the default allowed deviation is set
   * @param  oldDeviationBps The old allowed deviation in basis points
   * @param  newDeviationBps The new allowed deviation in basis points
   */
  event DefaultAllowedDeviationSet(uint16 oldDeviationBps, uint16 newDeviationBps);

  /**
   * @notice Emitted when the maximum time before a price is considered stale is set
   * @param token           The address of the token
   * @param maxTimeDelay    The maximum time before a price is considered stale
   */
  event MaxTimeDelaySet(address indexed token, uint256 maxTimeDelay);

  /**
   * @notice Emitted when the default maximum time before a price is considered stale is set
   * @param  oldMaxTimeDelay The old maximum time before a price is considered stale
   * @param  newMaxTimeDelay The new maximum time before a price is considered stale
   */
  event DefaultMaxTimeDelaySet(uint32 oldMaxTimeDelay, uint32 newMaxTimeDelay);

  /// Error thrown when an address is invalid (zero address)
  error InvalidAddress();
  /// Error thrown when trying to validate a price that hasn't been set
  error PriceNotSet();
  /// Error thrown when deviation bps is invalid (0 or >= 10,000)
  error InvalidDeviationBps();
  /// Error thrown when maximum time delay is invalid (0)
  error InvalidMaxTimeDelay();
  /// Error thrown when the price deviates too much from the posted price
  error PriceOutOfRange();
  /// Error thrown when the posted price is stale
  error StalePrice();
  /// Error thrown when array lengths don't match
  error LengthMismatch();

  /**
   * @param admin                   The admin address that is initialized with all roles
   * @param _defaultDeviationBps    The default allowed deviation in basis points
   * @param _defaultMaxTimeDelay    The default maximum time before a price is considered stale
   */
  constructor(address admin, uint16 _defaultDeviationBps, uint32 _defaultMaxTimeDelay) {
    if (admin == address(0)) {
      revert InvalidAddress();
    }

    _grantRole(DEFAULT_ADMIN_ROLE, admin);
    _grantRole(SETTER_ROLE, admin);
    _grantRole(CONFIGURER_ROLE, admin);

    setDefaultAllowedDeviationBps(_defaultDeviationBps);
    setDefaultMaxTimeDelay(_defaultMaxTimeDelay);
  }

  /**
   * @notice Checks if a price is valid for a token
   * @param  token The address of the token
   * @param  price The price to check
   * @dev    Reverts if the price is not valid
   */
  function validatePrice(address token, uint256 price) external view override {
    uint256 postedPrice = prices[token].price;

    if (token == address(0)) revert InvalidAddress();
    if (postedPrice == 0) revert PriceNotSet();
    if (prices[token].lastUpdated + prices[token].maxTimeDelay < block.timestamp) {
      revert StalePrice();
    }

    uint16 bps = prices[token].allowedDeviationBps;
    uint256 allowedDiff = (postedPrice * bps) / BPS_DENOMINATOR;
    uint256 diff = price > postedPrice ? price - postedPrice : postedPrice - price;

    if (diff > allowedDiff) revert PriceOutOfRange();
  }

  /**
   * @notice Posts a price for a token
   * @param  token The address of the token
   * @param  price The price of the token in USD with 18 decimals
   */
  function postPrice(address token, uint256 price) public onlyRole(SETTER_ROLE) {
    if (token == address(0)) revert InvalidAddress();
    if (price == 0) revert PriceNotSet();
    uint64 timestamp = uint64(block.timestamp);

    PriceData storage priceData = prices[token];
    if (priceData.maxTimeDelay == 0) {
      priceData.maxTimeDelay = defaultMaxTimeDelay;
      emit MaxTimeDelaySet(token, priceData.maxTimeDelay);
    }

    if (priceData.allowedDeviationBps == 0) {
      priceData.allowedDeviationBps = defaultDeviationBps;
      emit AllowedDeviationSet(token, priceData.allowedDeviationBps);
    }

    uint256 lastPostedPrice = priceData.price;
    uint64 lastUpdated = priceData.lastUpdated;
    priceData.price = price;
    priceData.lastUpdated = timestamp;

    emit PricePosted(token, lastPostedPrice, lastUpdated, price, timestamp);
  }

  /**
   * @notice Posts prices for multiple tokens
   * @param  tokens      The addresses of the tokens
   * @param  tokenPrices The prices of the tokens in USD with 18 decimals
   */
  function postPrices(address[] calldata tokens, uint256[] calldata tokenPrices)
    external
    onlyRole(SETTER_ROLE)
  {
    if (tokens.length != tokenPrices.length) revert LengthMismatch();
    for (uint256 i = 0; i < tokens.length; ++i) {
      postPrice(tokens[i], tokenPrices[i]);
    }
  }

  /**
   * @notice Sets the allowed deviation in basis points for a token
   * @param  token The address of the token
   * @param  bps   The allowed deviation in basis points
   */
  function setAllowedDeviationBps(address token, uint16 bps) external onlyRole(CONFIGURER_ROLE) {
    if (bps == 0) revert InvalidDeviationBps();
    if (bps >= BPS_DENOMINATOR) revert InvalidDeviationBps();

    prices[token].allowedDeviationBps = bps;
    emit AllowedDeviationSet(token, bps);
  }

  /**
   * @notice Sets the default allowed deviation in basis points
   * @param  bps The allowed deviation in basis points
   * @dev    This does not affect deviation for tokens that have already been posted
   */
  function setDefaultAllowedDeviationBps(uint16 bps) public onlyRole(CONFIGURER_ROLE) {
    if (bps == 0) revert InvalidDeviationBps();
    if (bps >= BPS_DENOMINATOR) revert InvalidDeviationBps();

    emit DefaultAllowedDeviationSet(defaultDeviationBps, bps);
    defaultDeviationBps = bps;
  }

  /**
   * @notice Sets the maximum time before a price is considered stale
   * @param  token           The address of the token
   * @param  maxTimeDelay    The maximum time before a price is considered stale
   */
  function setMaxTimeDelay(address token, uint32 maxTimeDelay) external onlyRole(CONFIGURER_ROLE) {
    prices[token].maxTimeDelay = maxTimeDelay;
    emit MaxTimeDelaySet(token, maxTimeDelay);
  }

  /**
   * @notice Sets the default maximum time before a price is considered stale
   * @param  maxTimeDelay The maximum time before a price is considered stale
   * @dev    This does not affect time delay for tokens that have already been posted
   */
  function setDefaultMaxTimeDelay(uint32 maxTimeDelay) public onlyRole(CONFIGURER_ROLE) {
    if (maxTimeDelay == 0) revert InvalidMaxTimeDelay();

    emit DefaultMaxTimeDelaySet(defaultMaxTimeDelay, maxTimeDelay);
    defaultMaxTimeDelay = maxTimeDelay;
  }
}
