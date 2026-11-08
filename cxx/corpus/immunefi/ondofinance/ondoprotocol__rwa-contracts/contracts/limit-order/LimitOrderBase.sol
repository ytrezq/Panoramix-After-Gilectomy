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
  AccessControlEnumerable
} from "contracts/external/openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {LimitOrderLib} from "contracts/limit-order/LimitOrderLib.sol";
import {LimitOrderTypes} from "contracts/limit-order/LimitOrderTypes.sol";
import {ILimitOrder} from "contracts/limit-order/ILimitOrder.sol";

/**
 * @title  LimitOrderBase
 * @author Ondo Finance
 * @notice Abstract base contract for limit order contracts. Contains all shared logic
 *         including order creation, cancellation, execution orchestration, views, and admin.
 *         Subcontracts implement token-manager-specific execution and validation via
 *         abstract hooks: `_executeBuy`, `_executeSell`, and `_validateTokens`.
 */
abstract contract LimitOrderBase is ReentrancyGuardTransient, AccessControlEnumerable, ILimitOrder {
  // ─────────────────────────────────────────────────────────────────────────────
  // Constants
  // ─────────────────────────────────────────────────────────────────────────────

  /// Role identifier for addresses permitted to execute orders
  bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

  /// Role identifier for addresses permitted to pause the contract
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

  /// Role identifier for addresses permitted to unpause the contract
  bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

  /// Role identifier for addresses permitted to retrieve tokens from the contract
  bytes32 public constant TOKEN_RETRIEVER_ROLE = keccak256("TOKEN_RETRIEVER_ROLE");

  /// Role identifier for addresses permitted to cancel any order
  bytes32 public constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");

  // ─────────────────────────────────────────────────────────────────────────────
  // Constructor
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * @notice Initializes the limit order contract
   * @param  _tokenManager     Address of the token manager contract for minting/redeeming
   * @param  _ondoIDRegistry   Address of the OndoIDRegistry for compliance checks
   * @param  _defaultAdmin     Address to receive the DEFAULT_ADMIN_ROLE
   * @param  _maxOrderDuration Maximum duration (in seconds) that an order expiry can be set into the future
   */
  constructor(
    address _tokenManager,
    address _ondoIDRegistry,
    address _defaultAdmin,
    uint256 _maxOrderDuration
  ) {
    if (_tokenManager == address(0)) {
      revert LimitOrderTypes.TokenManagerZeroAddress();
    }
    if (_ondoIDRegistry == address(0)) revert LimitOrderTypes.OndoIDRegistryZeroAddress();
    if (_defaultAdmin == address(0)) revert LimitOrderTypes.DefaultAdminZeroAddress();
    if (_maxOrderDuration == 0) revert LimitOrderTypes.MaxOrderDurationZero();

    LimitOrderLib.initialize(_tokenManager, _ondoIDRegistry, _maxOrderDuration);
    _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // External Functions - Order Creation
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * @notice Create a buy order specifying exact quote token amount to spend
   * @param  assetToken  Address of the asset token to buy
   * @param  quoteToken  Address of the quote token to spend
   * @param  quoteAmount Exact amount of quote tokens to spend
   * @param  limitPrice  Maximum price per asset token (18 decimals)
   * @param  expiry      Unix timestamp after which order expires
   * @return Unique identifier for the created order
   */
  function createBuyOrderExactIn(
    address assetToken,
    address quoteToken,
    uint256 quoteAmount,
    uint256 limitPrice,
    uint256 expiry
  ) external whenNotPaused onlyCompliant(msg.sender) returns (uint256) {
    _validateTokens(assetToken, quoteToken);
    return LimitOrderLib.createOrder(
      LimitOrderTypes.CreateOrderParams({
        side: LimitOrderTypes.QuoteSide.BUY,
        exactType: LimitOrderTypes.ExactType.EXACT_QUOTE,
        assetToken: assetToken,
        quoteToken: quoteToken,
        exactAmount: quoteAmount,
        limitPrice: limitPrice,
        expiry: expiry
      })
    );
  }

  /**
   * @notice Create a buy order specifying exact asset token amount to receive
   * @param  assetToken  Address of the asset token to buy
   * @param  quoteToken  Address of the quote token to spend
   * @param  assetAmount Exact amount of asset tokens to receive
   * @param  limitPrice  Maximum price per asset token (18 decimals)
   * @param  expiry      Unix timestamp after which order expires
   * @return Unique identifier for the created order
   */
  function createBuyOrderExactOut(
    address assetToken,
    address quoteToken,
    uint256 assetAmount,
    uint256 limitPrice,
    uint256 expiry
  ) external whenNotPaused onlyCompliant(msg.sender) returns (uint256) {
    _validateTokens(assetToken, quoteToken);
    return LimitOrderLib.createOrder(
      LimitOrderTypes.CreateOrderParams({
        side: LimitOrderTypes.QuoteSide.BUY,
        exactType: LimitOrderTypes.ExactType.EXACT_ASSET,
        assetToken: assetToken,
        quoteToken: quoteToken,
        exactAmount: assetAmount,
        limitPrice: limitPrice,
        expiry: expiry
      })
    );
  }

  /**
   * @notice Create a sell order specifying exact asset token amount to sell
   * @param  assetToken  Address of the asset token to sell
   * @param  quoteToken  Address of the quote token to receive
   * @param  assetAmount Exact amount of asset tokens to sell
   * @param  limitPrice  Minimum price per asset token (18 decimals)
   * @param  expiry      Unix timestamp after which order expires
   * @return Unique identifier for the created order
   */
  function createSellOrderExactIn(
    address assetToken,
    address quoteToken,
    uint256 assetAmount,
    uint256 limitPrice,
    uint256 expiry
  ) external whenNotPaused onlyCompliant(msg.sender) returns (uint256) {
    _validateTokens(assetToken, quoteToken);
    return LimitOrderLib.createOrder(
      LimitOrderTypes.CreateOrderParams({
        side: LimitOrderTypes.QuoteSide.SELL,
        exactType: LimitOrderTypes.ExactType.EXACT_ASSET,
        assetToken: assetToken,
        quoteToken: quoteToken,
        exactAmount: assetAmount,
        limitPrice: limitPrice,
        expiry: expiry
      })
    );
  }

  /**
   * @notice Create a sell order specifying exact quote token amount to receive
   * @param  assetToken  Address of the asset token to sell
   * @param  quoteToken  Address of the quote token to receive
   * @param  quoteAmount Exact amount of quote tokens to receive
   * @param  limitPrice  Minimum price per asset token (18 decimals)
   * @param  expiry      Unix timestamp after which order expires
   * @return Unique identifier for the created order
   */
  function createSellOrderExactOut(
    address assetToken,
    address quoteToken,
    uint256 quoteAmount,
    uint256 limitPrice,
    uint256 expiry
  ) external whenNotPaused onlyCompliant(msg.sender) returns (uint256) {
    _validateTokens(assetToken, quoteToken);
    return LimitOrderLib.createOrder(
      LimitOrderTypes.CreateOrderParams({
        side: LimitOrderTypes.QuoteSide.SELL,
        exactType: LimitOrderTypes.ExactType.EXACT_QUOTE,
        assetToken: assetToken,
        quoteToken: quoteToken,
        exactAmount: quoteAmount,
        limitPrice: limitPrice,
        expiry: expiry
      })
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // External Functions - Order Cancellation
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * @notice Cancel an order (only callable by order maker)
   * @param  orderId The order to cancel
   */
  function cancelOrder(uint256 orderId) external {
    LimitOrderLib.cancelOrder(orderId);
  }

  /**
   * @notice Cancel an order as admin (requires CANCELLER_ROLE)
   * @param  orderId The order to cancel
   */
  function adminCancelOrder(uint256 orderId) external onlyRole(CANCELLER_ROLE) {
    LimitOrderLib.adminCancelOrder(orderId);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // External Functions - Order Execution
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * @notice Execute an order with an attestation quote (requires EXECUTOR_ROLE)
   * @param  orderId   The order to execute
   * @param  quote     Attestation quote
   * @param  signature EIP-712 signature of the quote
   */
  function executeOrder(
    uint256 orderId,
    LimitOrderTypes.Quote calldata quote,
    bytes calldata signature
  ) external nonReentrant whenNotPaused onlyRole(EXECUTOR_ROLE) onlyCompliant(msg.sender) {
    LimitOrderLib.checkCompliance(LimitOrderLib.getOrder(orderId).user);
    uint256 quoteAmount = LimitOrderLib.validateAndPrepare(orderId, quote);
    LimitOrderTypes.LimitOrder storage order = LimitOrderLib.getOrder(orderId);

    if (order.side == LimitOrderTypes.QuoteSide.BUY) {
      _executeBuy(order, quote, signature, quoteAmount);
    } else {
      _executeSell(order, quote, signature, quoteAmount);
    }

    LimitOrderLib.finalizeExecution(orderId, quote, quoteAmount);
  }

  /**
   * @notice Execute multiple orders in a single transaction (requires EXECUTOR_ROLE)
   * @param  orderIds   Array of order IDs to execute
   * @param  quotes     Array of attestation quotes
   * @param  signatures Array of EIP-712 signatures
   */
  function executeOrderBatch(
    uint256[] calldata orderIds,
    LimitOrderTypes.Quote[] calldata quotes,
    bytes[] calldata signatures
  ) external nonReentrant whenNotPaused onlyRole(EXECUTOR_ROLE) onlyCompliant(msg.sender) {
    if (orderIds.length != quotes.length || quotes.length != signatures.length) {
      revert LimitOrderTypes.ArrayLengthMismatch();
    }

    for (uint256 i = 0; i < orderIds.length; i++) {
      LimitOrderLib.checkCompliance(LimitOrderLib.getOrder(orderIds[i]).user);
      uint256 quoteAmount = LimitOrderLib.validateAndPrepare(orderIds[i], quotes[i]);
      LimitOrderTypes.LimitOrder storage order = LimitOrderLib.getOrder(orderIds[i]);

      if (order.side == LimitOrderTypes.QuoteSide.BUY) {
        _executeBuy(order, quotes[i], signatures[i], quoteAmount);
      } else {
        _executeSell(order, quotes[i], signatures[i], quoteAmount);
      }

      LimitOrderLib.finalizeExecution(orderIds[i], quotes[i], quoteAmount);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // View Functions
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * @notice Get total number of orders created
   * @return Total order count
   */
  function getOrderCount() external view returns (uint256) {
    return LimitOrderLib.getOrderCount();
  }

  /**
   * @notice Get order details by ID
   * @param  orderId The order to look up
   * @return The order struct
   */
  function orders(uint256 orderId) external view returns (LimitOrderTypes.LimitOrder memory) {
    return LimitOrderLib.getOrder(orderId);
  }

  /**
   * @notice Check if an order is active and not expired
   * @param  orderId The order to check
   * @return True if order is active and not expired
   */
  function isOrderActive(uint256 orderId) external view returns (bool) {
    return LimitOrderLib.isOrderActive(orderId);
  }

  /**
   * @notice Check if an order has been executed
   * @param  orderId The order to check
   * @return True if order has been executed
   */
  function isOrderExecuted(uint256 orderId) external view returns (bool) {
    return LimitOrderLib.isOrderExecuted(orderId);
  }

  /**
   * @notice Check if contract is paused
   * @return True if paused
   */
  function paused() external view returns (bool) {
    return LimitOrderLib.paused();
  }

  /**
   * @notice Get token manager address
   * @return Token manager contract address
   */
  function tokenManager() external view returns (address) {
    return LimitOrderLib.getTokenManager();
  }

  /**
   * @notice Get OndoIDRegistry address
   * @return OndoIDRegistry contract address
   */
  function ondoIDRegistry() external view returns (address) {
    return LimitOrderLib.getOndoIDRegistry();
  }

  /**
   * @notice Get GM identifier for OndoIDRegistry operations
   * @return GM identifier address
   */
  function gmIdentifier() external pure returns (address) {
    return LimitOrderLib.GM_IDENTIFIER;
  }

  /**
   * @notice Get maximum order duration
   * @return Maximum order duration in seconds
   */
  function maxOrderDuration() external view returns (uint256) {
    return LimitOrderLib.getMaxOrderDuration();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Admin Functions
  // ─────────────────────────────────────────────────────────────────────────────

  /// Pause the contract (requires PAUSER_ROLE)
  function pause() external onlyRole(PAUSER_ROLE) {
    LimitOrderLib.pause();
  }

  /// Unpause the contract (requires UNPAUSER_ROLE)
  function unpause() external onlyRole(UNPAUSER_ROLE) {
    LimitOrderLib.unpause();
  }

  /**
   * @notice Retrieve tokens from the contract (requires TOKEN_RETRIEVER_ROLE)
   * @param  token     Address of token to retrieve
   * @param  recipient Address to send tokens to
   * @param  amount    Amount of tokens to retrieve
   */
  function retrieveTokens(address token, address recipient, uint256 amount)
    external
    onlyRole(TOKEN_RETRIEVER_ROLE)
  {
    LimitOrderLib.retrieveTokens(token, recipient, amount);
  }

  /**
   * @notice Set maximum order duration (requires DEFAULT_ADMIN_ROLE)
   * @param  duration Maximum duration (in seconds) that an order expiry can be set into the future
   */
  function setMaxOrderDuration(uint256 duration) external onlyRole(DEFAULT_ADMIN_ROLE) {
    LimitOrderLib.setMaxOrderDuration(duration);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Abstract Hooks — implemented by subcontracts
  // ─────────────────────────────────────────────────────────────────────────────

  function _executeBuy(
    LimitOrderTypes.LimitOrder storage order,
    LimitOrderTypes.Quote calldata quote,
    bytes calldata signature,
    uint256 quoteAmount
  ) internal virtual;

  function _executeSell(
    LimitOrderTypes.LimitOrder storage order,
    LimitOrderTypes.Quote calldata quote,
    bytes calldata signature,
    uint256 quoteAmount
  ) internal virtual;

  function _validateTokens(address assetToken, address quoteToken) internal view virtual;

  // ─────────────────────────────────────────────────────────────────────────────
  // Modifiers
  // ─────────────────────────────────────────────────────────────────────────────

  /// Reverts if the contract is paused
  modifier whenNotPaused() {
    LimitOrderLib.whenNotPaused();
    _;
  }

  /**
   * @notice Reverts if the user is not registered in OndoIDRegistry
   * @param  user The address to check compliance for
   */
  modifier onlyCompliant(address user) {
    LimitOrderLib.checkCompliance(user);
    _;
  }
}
