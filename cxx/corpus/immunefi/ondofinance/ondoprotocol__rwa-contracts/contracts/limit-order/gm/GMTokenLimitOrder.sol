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

import {IGMTokenManager} from "contracts/globalMarkets/tokenManager/IGMTokenManager.sol";
import {IERC20} from "contracts/external/openzeppelin/contracts/token/IERC20.sol";
import {SafeERC20} from "contracts/external/openzeppelin/contracts/token/SafeERC20.sol";
import {LimitOrderLib} from "contracts/limit-order/LimitOrderLib.sol";
import {LimitOrderTypes} from "contracts/limit-order/LimitOrderTypes.sol";
import {LimitOrderBase} from "contracts/limit-order/LimitOrderBase.sol";

/**
 * @title  GMTokenLimitOrder
 * @author Ondo Finance
 * @notice Limit order contract for buying and selling GM tokens (e.g., AAPLon, TSLAon).
 *         Extends LimitOrderBase with GM-specific mint/redeem calls.
 */
contract GMTokenLimitOrder is LimitOrderBase {
  using SafeERC20 for IERC20;

  constructor(
    address _gmTokenManager,
    address _ondoIDRegistry,
    address _defaultAdmin,
    uint256 _maxOrderDuration
  ) LimitOrderBase(_gmTokenManager, _ondoIDRegistry, _defaultAdmin, _maxOrderDuration) {}

  // ─────────────────────────────────────────────────────────────────────────────
  // Abstract Hook Implementations
  // ─────────────────────────────────────────────────────────────────────────────

  function _executeBuy(
    LimitOrderTypes.LimitOrder storage order,
    LimitOrderTypes.Quote calldata quote,
    bytes calldata signature,
    uint256 quoteAmount
  ) internal override {
    IGMTokenManager tm = IGMTokenManager(LimitOrderLib.getTokenManager());

    IERC20(order.quoteToken).safeTransferFrom(order.user, address(this), quoteAmount);
    IERC20(order.quoteToken).forceApprove(address(tm), quoteAmount);
    tm.mintWithAttestation(_toGMQuote(quote), signature, order.quoteToken, quoteAmount);
    IERC20(order.assetToken).safeTransfer(order.user, quote.quantity);
  }

  function _executeSell(
    LimitOrderTypes.LimitOrder storage order,
    LimitOrderTypes.Quote calldata quote,
    bytes calldata signature,
    uint256 quoteAmount
  ) internal override {
    IGMTokenManager tm = IGMTokenManager(LimitOrderLib.getTokenManager());

    IERC20(order.assetToken).safeTransferFrom(order.user, address(this), quote.quantity);
    IERC20(order.assetToken).forceApprove(address(tm), quote.quantity);
    tm.redeemWithAttestation(_toGMQuote(quote), signature, order.quoteToken, quoteAmount);
    IERC20(order.quoteToken).safeTransfer(order.user, quoteAmount);
  }

  function _validateTokens(address assetToken, address) internal view override {
    if (!IGMTokenManager(LimitOrderLib.getTokenManager()).gmTokenAccepted(assetToken)) {
      revert LimitOrderTypes.AssetTokenNotAccepted();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Internal — Quote conversion
  // ─────────────────────────────────────────────────────────────────────────────

  function _toGMQuote(LimitOrderTypes.Quote calldata q)
    internal
    pure
    returns (IGMTokenManager.Quote memory)
  {
    return IGMTokenManager.Quote({
      chainId: q.chainId,
      attestationId: q.attestationId,
      userId: q.userId,
      asset: q.asset,
      price: q.price,
      quantity: q.quantity,
      expiration: q.expiration,
      side: IGMTokenManager.QuoteSide(uint8(q.side)),
      additionalData: q.additionalData
    });
  }
}
