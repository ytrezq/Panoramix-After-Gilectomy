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

import {LimitOrderTypes} from "contracts/limit-order/LimitOrderTypes.sol";

/**
 * @title  ILimitOrder
 * @author Ondo Finance
 * @notice Interface for limit order contracts which enable users to place
 *         limit orders for buying and selling asset tokens.
 */
interface ILimitOrder {
  // ─────────────────────────────────────────────────────────────────────────────
  // Order Creation
  // ─────────────────────────────────────────────────────────────────────────────

  function createBuyOrderExactIn(
    address assetToken,
    address quoteToken,
    uint256 quoteAmount,
    uint256 limitPrice,
    uint256 expiry
  ) external returns (uint256);

  function createBuyOrderExactOut(
    address assetToken,
    address quoteToken,
    uint256 assetAmount,
    uint256 limitPrice,
    uint256 expiry
  ) external returns (uint256);

  function createSellOrderExactIn(
    address assetToken,
    address quoteToken,
    uint256 assetAmount,
    uint256 limitPrice,
    uint256 expiry
  ) external returns (uint256);

  function createSellOrderExactOut(
    address assetToken,
    address quoteToken,
    uint256 quoteAmount,
    uint256 limitPrice,
    uint256 expiry
  ) external returns (uint256);

  // ─────────────────────────────────────────────────────────────────────────────
  // Order Cancellation
  // ─────────────────────────────────────────────────────────────────────────────

  function cancelOrder(uint256 orderId) external;

  function adminCancelOrder(uint256 orderId) external;

  // ─────────────────────────────────────────────────────────────────────────────
  // Order Execution
  // ─────────────────────────────────────────────────────────────────────────────

  function executeOrder(
    uint256 orderId,
    LimitOrderTypes.Quote calldata quote,
    bytes calldata signature
  ) external;

  function executeOrderBatch(
    uint256[] calldata orderIds,
    LimitOrderTypes.Quote[] calldata quotes,
    bytes[] calldata signatures
  ) external;

  // ─────────────────────────────────────────────────────────────────────────────
  // View Functions
  // ─────────────────────────────────────────────────────────────────────────────

  function getOrderCount() external view returns (uint256);

  function orders(uint256 orderId) external view returns (LimitOrderTypes.LimitOrder memory);

  function isOrderActive(uint256 orderId) external view returns (bool);

  function isOrderExecuted(uint256 orderId) external view returns (bool);

  function paused() external view returns (bool);

  function tokenManager() external view returns (address);

  function ondoIDRegistry() external view returns (address);

  function gmIdentifier() external pure returns (address);

  function maxOrderDuration() external view returns (uint256);

  // ─────────────────────────────────────────────────────────────────────────────
  // Admin Functions
  // ─────────────────────────────────────────────────────────────────────────────

  function pause() external;

  function unpause() external;

  function retrieveTokens(address token, address recipient, uint256 amount) external;

  function setMaxOrderDuration(uint256 duration) external;
}
