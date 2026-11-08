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

import {IOndoIDRegistry} from "contracts/xManager/interfaces/IOndoIDRegistry.sol";
import {IERC20Metadata} from "contracts/external/openzeppelin/contracts/token/IERC20Metadata.sol";
import {IERC20} from "contracts/external/openzeppelin/contracts/token/IERC20.sol";
import {SafeERC20} from "contracts/external/openzeppelin/contracts/token/SafeERC20.sol";
import {LimitOrderStorage} from "contracts/limit-order/LimitOrderStorage.sol";
import {LimitOrderTypes} from "contracts/limit-order/LimitOrderTypes.sol";

/**
 * @title  LimitOrderLib
 * @author Ondo Finance
 * @notice Library containing shared business logic for limit order contracts,
 *         including order creation, cancellation, validation, and calculations.
 *         Token-manager-specific execution (mint/redeem calls) is handled by
 *         the consuming contracts.
 */
library LimitOrderLib {
  using SafeERC20 for IERC20;

  // ─────────────────────────────────────────────────────────────────────────────
  // Constants
  // ─────────────────────────────────────────────────────────────────────────────

  /// Normalizer for 18 decimal precision calculations
  uint256 internal constant NORMALIZER_18 = 1e18;

  /// Number of decimals used for USD value calculations
  uint8 internal constant USD_DECIMALS = 18;

  /// Identifier used for GM token operations in OndoIDRegistry
  address internal constant GM_IDENTIFIER =
    address(uint160(uint256(keccak256(abi.encodePacked("global_markets")))));

  // ─────────────────────────────────────────────────────────────────────────────
  // Storage Accessor
  // ─────────────────────────────────────────────────────────────────────────────

  function s() internal pure returns (LimitOrderStorage.Layout storage) {
    return LimitOrderStorage.layout();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Initialization
  // ─────────────────────────────────────────────────────────────────────────────

  function initialize(address tokenManager, address ondoIDRegistry, uint256 maxOrderDuration)
    internal
  {
    s().tokenManager = tokenManager;
    s().ondoIDRegistry = IOndoIDRegistry(ondoIDRegistry);
    s().maxOrderDuration = maxOrderDuration;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Pause Functions
  // ─────────────────────────────────────────────────────────────────────────────

  function whenNotPaused() internal view {
    if (s().paused) revert LimitOrderTypes.ContractPaused();
  }

  function pause() internal {
    s().paused = true;
    emit LimitOrderTypes.Paused(msg.sender);
  }

  function unpause() internal {
    s().paused = false;
    emit LimitOrderTypes.Unpaused(msg.sender);
  }

  function paused() internal view returns (bool) {
    return s().paused;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Order Creation
  // ─────────────────────────────────────────────────────────────────────────────

  function createOrder(LimitOrderTypes.CreateOrderParams memory params)
    internal
    returns (uint256 orderId)
  {
    validateCreateParams(
      params.assetToken, params.quoteToken, params.exactAmount, params.limitPrice, params.expiry
    );

    LimitOrderTypes.LimitOrder memory order = LimitOrderTypes.LimitOrder({
      user: msg.sender,
      assetToken: params.assetToken,
      quoteToken: params.quoteToken,
      side: params.side,
      exactType: params.exactType,
      exactAmount: params.exactAmount,
      limitPrice: params.limitPrice,
      expiry: params.expiry,
      status: LimitOrderTypes.OrderStatus.ACTIVE
    });

    orderId = s().orders.length;
    s().orders.push(order);

    emit LimitOrderTypes.OrderCreated(orderId, msg.sender, params.assetToken);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Order Cancellation
  // ─────────────────────────────────────────────────────────────────────────────

  function cancelOrder(uint256 orderId) internal {
    LimitOrderTypes.LimitOrder storage order = s().orders[orderId];

    if (order.user != msg.sender) revert LimitOrderTypes.NotOrderMaker();
    if (order.status != LimitOrderTypes.OrderStatus.ACTIVE) {
      revert LimitOrderTypes.OrderNotActive();
    }

    order.status = LimitOrderTypes.OrderStatus.CANCELLED;
    emit LimitOrderTypes.OrderCancelled(orderId, msg.sender);
  }

  function adminCancelOrder(uint256 orderId) internal {
    LimitOrderTypes.LimitOrder storage order = s().orders[orderId];

    if (order.status != LimitOrderTypes.OrderStatus.ACTIVE) {
      revert LimitOrderTypes.OrderNotActive();
    }

    order.status = LimitOrderTypes.OrderStatus.CANCELLED;
    emit LimitOrderTypes.OrderCancelled(orderId, msg.sender);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Order Execution — Validate & Prepare
  // ─────────────────────────────────────────────────────────────────────────────

  function validateAndPrepare(uint256 orderId, LimitOrderTypes.Quote calldata quote)
    internal
    view
    returns (uint256 quoteAmount)
  {
    LimitOrderTypes.LimitOrder storage order = s().orders[orderId];

    validateExecution(order, quote);

    quoteAmount = order.exactType == LimitOrderTypes.ExactType.EXACT_ASSET
      ? calculateQuoteAmount(quote, order.quoteToken)
      : order.exactAmount;
  }

  function finalizeExecution(
    uint256 orderId,
    LimitOrderTypes.Quote calldata quote,
    uint256 quoteAmount
  ) internal {
    LimitOrderTypes.LimitOrder storage order = s().orders[orderId];
    order.status = LimitOrderTypes.OrderStatus.EXECUTED;

    emit LimitOrderTypes.OrderExecuted(
      orderId, msg.sender, order.side, quote.attestationId, quote.quantity, quoteAmount
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Validation Functions
  // ─────────────────────────────────────────────────────────────────────────────

  function validateCreateParams(
    address assetToken,
    address quoteToken,
    uint256 exactAmount,
    uint256 limitPrice,
    uint256 expiry
  ) internal view {
    if (assetToken == address(0)) {
      revert LimitOrderTypes.AssetTokenZeroAddress();
    }
    if (quoteToken == address(0)) {
      revert LimitOrderTypes.QuoteTokenZeroAddress();
    }
    if (assetToken == quoteToken) revert LimitOrderTypes.SameToken();
    if (exactAmount == 0) revert LimitOrderTypes.ZeroQuantity();
    if (limitPrice == 0) revert LimitOrderTypes.ZeroLimitPrice();
    if (expiry <= block.timestamp) revert LimitOrderTypes.ExpiryInPast();
    if (expiry > block.timestamp + s().maxOrderDuration) {
      revert LimitOrderTypes.ExpiryTooFarInFuture();
    }
  }

  function checkCompliance(address user) internal view {
    bytes32 userId = s().ondoIDRegistry.getRegisteredID(GM_IDENTIFIER, user);
    if (userId == bytes32(0)) revert LimitOrderTypes.UserNotRegistered();
  }

  function validateExecution(
    LimitOrderTypes.LimitOrder storage order,
    LimitOrderTypes.Quote calldata quote
  ) internal view {
    // Order state validation
    if (order.status != LimitOrderTypes.OrderStatus.ACTIVE) {
      revert LimitOrderTypes.OrderNotActive();
    }
    if (block.timestamp > order.expiry) {
      revert LimitOrderTypes.OrderExpired();
    }

    // Quote parameter validation
    if (quote.asset != order.assetToken) {
      revert LimitOrderTypes.AssetMismatch();
    }
    if (block.timestamp > quote.expiration) {
      revert LimitOrderTypes.QuoteExpired();
    }
    if (quote.side != order.side) revert LimitOrderTypes.SideMismatch();

    // Price limit validation
    if (order.side == LimitOrderTypes.QuoteSide.BUY) {
      if (quote.price > order.limitPrice) {
        revert LimitOrderTypes.PriceTooHigh();
      }
    } else if (order.side == LimitOrderTypes.QuoteSide.SELL) {
      if (quote.price < order.limitPrice) {
        revert LimitOrderTypes.PriceTooLow();
      }
    }

    // Fill-or-kill quantity validation (only for EXACT_ASSET orders)
    if (order.exactType == LimitOrderTypes.ExactType.EXACT_ASSET) {
      if (quote.quantity != order.exactAmount) {
        revert LimitOrderTypes.QuantityMismatch();
      }
    }

    // Asset quantity validation for EXACT_QUOTE orders
    // SELL: prevents executor from overspending user's asset token allowance
    // BUY: prevents user from receiving fewer asset tokens than expected
    if (order.exactType == LimitOrderTypes.ExactType.EXACT_QUOTE) {
      validateAssetQuantity(
        order.exactAmount, order.limitPrice, order.quoteToken, order.side, quote.quantity
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Utility Functions
  // ─────────────────────────────────────────────────────────────────────────────

  function calculateQuoteAmount(LimitOrderTypes.Quote calldata quote, address quoteToken)
    internal
    view
    returns (uint256)
  {
    uint8 tokenDecimals = IERC20Metadata(quoteToken).decimals();
    // Combine into single division to avoid intermediate truncation precision loss
    uint256 numerator = quote.quantity * quote.price * (10 ** tokenDecimals);
    uint256 divisor = NORMALIZER_18 * NORMALIZER_18;
    // Round up for BUY (user pays more), round down for SELL (user receives less)
    return quote.side == LimitOrderTypes.QuoteSide.BUY
      ? (numerator + divisor - 1) / divisor
      : numerator / divisor;
  }

  function validateAssetQuantity(
    uint256 quoteAmount,
    uint256 limitPrice,
    address quoteToken,
    LimitOrderTypes.QuoteSide side,
    uint256 quoteQuantity
  ) internal view {
    uint8 tokenDecimals = IERC20Metadata(quoteToken).decimals();
    // Normalize quoteAmount to 18 decimals (USD value)
    uint256 usdValue = quoteAmount * (10 ** (USD_DECIMALS - tokenDecimals));
    if (side == LimitOrderTypes.QuoteSide.BUY) {
      // minAsset = usdValue * 1e18 / limitPrice (round down to allow for rounding tolerance)
      uint256 minAsset = (usdValue * NORMALIZER_18) / limitPrice;
      if (quoteQuantity < minAsset) revert LimitOrderTypes.QuantityTooLow();
    } else {
      // maxAsset = usdValue * 1e18 / limitPrice (round up to allow for rounding tolerance)
      uint256 maxAsset = (usdValue * NORMALIZER_18 + limitPrice - 1) / limitPrice;
      if (quoteQuantity > maxAsset) revert LimitOrderTypes.QuantityTooHigh();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // View Functions
  // ─────────────────────────────────────────────────────────────────────────────

  function getOrderCount() internal view returns (uint256) {
    return s().orders.length;
  }

  function getOrder(uint256 orderId) internal view returns (LimitOrderTypes.LimitOrder storage) {
    return s().orders[orderId];
  }

  function isOrderActive(uint256 orderId) internal view returns (bool) {
    if (orderId >= s().orders.length) {
      revert LimitOrderTypes.InvalidOrderId();
    }
    LimitOrderTypes.LimitOrder storage order = s().orders[orderId];
    return order.status == LimitOrderTypes.OrderStatus.ACTIVE && block.timestamp <= order.expiry;
  }

  function isOrderExecuted(uint256 orderId) internal view returns (bool) {
    if (orderId >= s().orders.length) {
      revert LimitOrderTypes.InvalidOrderId();
    }
    return s().orders[orderId].status == LimitOrderTypes.OrderStatus.EXECUTED;
  }

  function retrieveTokens(address token, address recipient, uint256 amount) internal {
    IERC20(token).safeTransfer(recipient, amount);
    emit LimitOrderTypes.TokensRetrieved(token, recipient, amount);
  }

  function getTokenManager() internal view returns (address) {
    return s().tokenManager;
  }

  function getOndoIDRegistry() internal view returns (address) {
    return address(s().ondoIDRegistry);
  }

  function setMaxOrderDuration(uint256 duration) internal {
    if (duration == 0) revert LimitOrderTypes.MaxOrderDurationZero();
    s().maxOrderDuration = duration;
    emit LimitOrderTypes.MaxOrderDurationSet(duration);
  }

  function getMaxOrderDuration() internal view returns (uint256) {
    return s().maxOrderDuration;
  }
}
