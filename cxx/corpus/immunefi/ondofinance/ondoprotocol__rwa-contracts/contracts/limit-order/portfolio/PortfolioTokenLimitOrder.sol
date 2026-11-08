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
  IPortfolioTokenManager
} from "contracts/globalMarkets/portfolioToken/portfolioTokenManager/IPortfolioTokenManager.sol";
import {IERC20} from "contracts/external/openzeppelin/contracts/token/IERC20.sol";
import {SafeERC20} from "contracts/external/openzeppelin/contracts/token/SafeERC20.sol";
import {LimitOrderLib} from "contracts/limit-order/LimitOrderLib.sol";
import {LimitOrderTypes} from "contracts/limit-order/LimitOrderTypes.sol";
import {LimitOrderBase} from "contracts/limit-order/LimitOrderBase.sol";

/**
 * @title  PortfolioTokenLimitOrder
 * @author Ondo Finance
 * @notice Limit order contract for buying and selling portfolio tokens (e.g., TECH07on).
 *         Extends LimitOrderBase with portfolio-specific mint/redeem calls.
 * @dev    Deployment prerequisite: this contract must be registered in the
 *         OndoIDRegistry, since the PTM validates `getRegisteredID(gmIdentifier, msg.sender)`
 *         against the caller. Quotes must therefore be attested with THIS contract's
 *         userId (not the order maker's), and PTM-side rate limits accrue against this
 *         contract's id, shared across all limit-order users.
 */
contract PortfolioTokenLimitOrder is LimitOrderBase {
  using SafeERC20 for IERC20;

  constructor(
    address _portfolioTokenManager,
    address _ondoIDRegistry,
    address _defaultAdmin,
    uint256 _maxOrderDuration
  ) LimitOrderBase(_portfolioTokenManager, _ondoIDRegistry, _defaultAdmin, _maxOrderDuration) {}

  // ─────────────────────────────────────────────────────────────────────────────
  // Abstract Hook Implementations
  // ─────────────────────────────────────────────────────────────────────────────

  function _executeBuy(
    LimitOrderTypes.LimitOrder storage order,
    LimitOrderTypes.Quote calldata quote,
    bytes calldata signature,
    uint256 quoteAmount
  ) internal override {
    IPortfolioTokenManager ptm = IPortfolioTokenManager(LimitOrderLib.getTokenManager());

    IERC20(order.quoteToken).safeTransferFrom(order.user, address(this), quoteAmount);
    IERC20(order.quoteToken).forceApprove(address(ptm), quoteAmount);
    ptm.mintWithAttestation(_toPTMQuote(quote), signature);
    IERC20(order.assetToken).safeTransfer(order.user, quote.quantity);
  }

  function _executeSell(
    LimitOrderTypes.LimitOrder storage order,
    LimitOrderTypes.Quote calldata quote,
    bytes calldata signature,
    uint256 quoteAmount
  ) internal override {
    IPortfolioTokenManager ptm = IPortfolioTokenManager(LimitOrderLib.getTokenManager());

    IERC20(order.assetToken).safeTransferFrom(order.user, address(this), quote.quantity);
    IERC20(order.assetToken).forceApprove(address(ptm), quote.quantity);
    ptm.redeemWithAttestation(_toPTMQuote(quote), signature);
    IERC20(order.quoteToken).safeTransfer(order.user, quoteAmount);
  }

  function _validateTokens(address assetToken, address quoteToken) internal view override {
    IPortfolioTokenManager ptm = IPortfolioTokenManager(LimitOrderLib.getTokenManager());
    if (!ptm.portfolioTokenAccepted(assetToken)) {
      revert LimitOrderTypes.AssetTokenNotAccepted();
    }
    // The PTM only settles in its configured stablecoin, so the quote token must match.
    if (quoteToken != ptm.stablecoin()) {
      revert LimitOrderTypes.QuoteTokenNotAccepted();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Internal — Quote conversion
  // ─────────────────────────────────────────────────────────────────────────────

  function _toPTMQuote(LimitOrderTypes.Quote calldata q)
    internal
    pure
    returns (IPortfolioTokenManager.Quote memory)
  {
    return IPortfolioTokenManager.Quote({
      chainId: q.chainId,
      attestationId: q.attestationId,
      userId: q.userId,
      asset: q.asset,
      price: q.price,
      quantity: q.quantity,
      expiration: q.expiration,
      side: IPortfolioTokenManager.QuoteSide(uint8(q.side)),
      additionalData: q.additionalData
    });
  }
}
