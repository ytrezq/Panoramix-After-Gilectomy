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

/**
 * @title  LimitOrderTypes
 * @author Ondo Finance
 * @notice Shared types, errors, and events used by limit order contracts.
 */
library LimitOrderTypes {
  // ─────────────────────────────────────────────────────────────────────────────
  // Enums
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * @notice Buy (mint) or Sell (redeem) side
   */
  enum QuoteSide {
    /// Mint asset tokens
    BUY,
    /// Redeem asset tokens
    SELL
  }

  /**
   * @notice Specifies which amount is exact for order matching
   */
  enum ExactType {
    /// The exactAmount field represents the asset token (GM or portfolio)
    EXACT_ASSET,
    /// The exactAmount field represents quote tokens
    EXACT_QUOTE
  }

  /**
   * @notice Order lifecycle status
   */
  enum OrderStatus {
    /// Default value, order does not exist
    NOT_INITIATED,
    /// Order is open and can be executed or cancelled
    ACTIVE,
    /// Order has been fully filled
    EXECUTED,
    /// Order was cancelled by user or admin
    CANCELLED
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Structs
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * @notice Represents a limit order
   * @param  user        Address of the order maker
   * @param  assetToken  Address of the asset token to buy/sell (e.g., AAPLon)
   * @param  quoteToken  Address of the quote token for payment (e.g., USDC)
   * @param  side        BUY (mint) or SELL (redeem)
   * @param  exactType   Whether exactAmount represents asset tokens or quote tokens
   * @param  exactAmount The exact amount required (interpretation depends on exactType)
   * @param  limitPrice  Maximum price for buys, minimum price for sells (18 decimals)
   * @param  expiry      Unix timestamp after which the order cannot be executed
   * @param  status      Current order status
   */
  struct LimitOrder {
    address user;
    address assetToken;
    address quoteToken;
    QuoteSide side;
    ExactType exactType;
    uint256 exactAmount;
    uint256 limitPrice;
    uint256 expiry;
    OrderStatus status;
  }

  /**
   * @notice Parameters for creating a new limit order
   * @param  side        BUY (mint) or SELL (redeem)
   * @param  exactType   Whether exactAmount represents asset tokens or quote tokens
   * @param  assetToken  Address of the asset token to buy/sell
   * @param  quoteToken  Address of the quote token for payment
   * @param  exactAmount The exact amount required (interpretation depends on exactType)
   * @param  limitPrice  Maximum price for buys, minimum price for sells (18 decimals)
   * @param  expiry      Unix timestamp after which the order cannot be executed
   */
  struct CreateOrderParams {
    QuoteSide side;
    ExactType exactType;
    address assetToken;
    address quoteToken;
    uint256 exactAmount;
    uint256 limitPrice;
    uint256 expiry;
  }

  /**
   * @notice Attestation quote used for order execution
   * @dev    ABI-identical to both IGMTokenManager.Quote and IPortfolioTokenManager.Quote
   * @param  chainId        Chain ID for the attestation
   * @param  attestationId  Unique attestation identifier
   * @param  userId         User identifier from OndoIDRegistry
   * @param  asset          Address of the asset token
   * @param  price          Price per asset token (18 decimals)
   * @param  quantity       Quantity of asset tokens
   * @param  expiration     Unix timestamp after which the quote expires
   * @param  side           BUY or SELL
   * @param  additionalData Additional data for the attestation
   */
  struct Quote {
    uint256 chainId;
    uint256 attestationId;
    bytes32 userId;
    address asset;
    uint256 price;
    uint256 quantity;
    uint256 expiration;
    QuoteSide side;
    bytes32 additionalData;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Events
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * @notice Emitted when a new order is created
   * @param  orderId    Unique identifier for the order
   * @param  user       Address of the order maker
   * @param  assetToken Address of the asset token
   */
  event OrderCreated(uint256 indexed orderId, address indexed user, address indexed assetToken);

  /**
   * @notice Emitted when an order is executed
   * @param  orderId          Unique identifier for the order
   * @param  executor         Address that executed the order
   * @param  side             BUY or SELL
   * @param  attestationId    ID from the attestation quote
   * @param  assetQuantity    Asset tokens transferred
   * @param  quoteTokenAmount Quote tokens transferred
   */
  event OrderExecuted(
    uint256 indexed orderId,
    address indexed executor,
    QuoteSide side,
    uint256 attestationId,
    uint256 assetQuantity,
    uint256 quoteTokenAmount
  );

  /**
   * @notice Emitted when an order is cancelled
   * @param  orderId     Unique identifier for the order
   * @param  cancelledBy Address that cancelled the order
   */
  event OrderCancelled(uint256 indexed orderId, address indexed cancelledBy);

  /**
   * @notice Emitted when the contract is paused
   * @param  pauser Address that paused the contract
   */
  event Paused(address indexed pauser);

  /**
   * @notice Emitted when the contract is unpaused
   * @param  unpauser Address that unpaused the contract
   */
  event Unpaused(address indexed unpauser);

  /**
   * @notice Emitted when tokens are retrieved from the contract
   * @param  token     Address of the token retrieved
   * @param  recipient Address receiving the tokens
   * @param  amount    Amount of tokens retrieved
   */
  event TokensRetrieved(address indexed token, address indexed recipient, uint256 amount);

  /**
   * @notice Emitted when maxOrderDuration is updated
   * @param  newDuration New maximum order duration
   */
  event MaxOrderDurationSet(uint256 newDuration);

  // ─────────────────────────────────────────────────────────────────────────────
  // Errors
  // ─────────────────────────────────────────────────────────────────────────────

  /// Error emitted when assetToken address is zero
  error AssetTokenZeroAddress();

  /// Error emitted when quoteToken address is zero
  error QuoteTokenZeroAddress();

  /// Error emitted when assetToken is not accepted by the token manager
  error AssetTokenNotAccepted();

  /// Error emitted when quoteToken is not the token manager's configured stablecoin
  error QuoteTokenNotAccepted();

  /// Error emitted when assetToken and quoteToken are the same
  error SameToken();

  /// Error emitted when exactAmount is zero
  error ZeroQuantity();

  /// Error emitted when limitPrice is zero
  error ZeroLimitPrice();

  /// Error emitted when expiry is not in the future
  error ExpiryInPast();

  /// Error emitted when order status is not ACTIVE
  error OrderNotActive();

  /// Error emitted when order has expired
  error OrderExpired();

  /// Error emitted when caller is not the order maker
  error NotOrderMaker();

  /// Error emitted when user is not registered in OndoIDRegistry
  error UserNotRegistered();

  /// Error emitted when quote asset doesn't match order assetToken
  error AssetMismatch();

  /// Error emitted when quote side doesn't match order side
  error SideMismatch();

  /// Error emitted when quote price exceeds limit price for buy orders
  error PriceTooHigh();

  /// Error emitted when quote price is below limit price for sell orders
  error PriceTooLow();

  /// Error emitted when quote quantity doesn't match order's exactAmount
  error QuantityMismatch();

  /// Error emitted when quote quantity is below minimum for EXACT_QUOTE BUY orders
  error QuantityTooLow();

  /// Error emitted when quote quantity exceeds maximum for EXACT_QUOTE SELL orders
  error QuantityTooHigh();

  /// Error emitted when attestation quote has expired
  error QuoteExpired();

  /// Error emitted when contract is paused
  error ContractPaused();

  /// Error emitted when batch arrays have mismatched lengths
  error ArrayLengthMismatch();

  /// Error emitted when orderId does not exist
  error InvalidOrderId();

  /// Error emitted when tokenManager constructor argument is zero address
  error TokenManagerZeroAddress();

  /// Error emitted when ondoIDRegistry constructor argument is zero address
  error OndoIDRegistryZeroAddress();

  /// Error emitted when defaultAdmin constructor argument is zero address
  error DefaultAdminZeroAddress();

  /// Error emitted when maxOrderDuration constructor argument is zero
  error MaxOrderDurationZero();

  /// Error emitted when order expiry exceeds maxOrderDuration
  error ExpiryTooFarInFuture();
}
