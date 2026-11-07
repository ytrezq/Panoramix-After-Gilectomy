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

import {IssuerStorage} from "contracts/globalMarkets/issuer/issuerLib/IssuerStorage.sol";
import {IssuerTypes} from "contracts/globalMarkets/issuer/issuerLib/IssuerTypes.sol";
import {IGMTokenManager} from "contracts/globalMarkets/tokenManager/IGMTokenManager.sol";
import {IRWALike} from "contracts/interfaces/IRWALike.sol";
import {IERC20} from "contracts/external/openzeppelin/contracts/token/IERC20.sol";
import {IERC20Metadata} from "contracts/external/openzeppelin/contracts/token/IERC20Metadata.sol";
import {SafeERC20} from "contracts/external/openzeppelin/contracts/token/SafeERC20.sol";
import {IOndoIDRegistry} from "contracts/xManager/interfaces/IOndoIDRegistry.sol";

/**
 * @title  IssuerLib
 * @author Ondo Finance
 * @notice Business logic for the GM issuer: mint flow post-recovery, user-initiated redeem burn,
 *         USD notional pricing, and config/pause internals
 */
library IssuerLib {
  using SafeERC20 for IERC20;

  // ─────────────────────────────────────────────────────────────────────────────
  // Constants
  // ─────────────────────────────────────────────────────────────────────────────

  /// Normalizer for 18 decimal USD precision
  uint256 internal constant NORMALIZER_18 = 1e18;

  /// Identifier used for GM token operations in OndoIDRegistry
  address internal constant GM_IDENTIFIER =
    address(uint160(uint256(keccak256(abi.encodePacked("global_markets")))));

  /// Identifier signalling a wallet is approved for Alpaca ITN
  address internal constant ALPACA_ITN_IDENTIFIER =
    address(uint160(uint256(keccak256(abi.encodePacked("alpaca_itn")))));

  /// EIP-712 type hash for Alpaca mint requests
  bytes32 internal constant MINT_TYPEHASH = keccak256(
    "Mint(string targetUri,string method,string tokenizationRequestId,string underlyingSymbol,string tokenSymbol,uint256 qty,address walletAddress,string network,string clientAccountId,string clientExternalAccountId,string clientRequestId,uint256 created,uint256 nonce)"
  );

  // ─────────────────────────────────────────────────────────────────────────────
  // Initialization
  // ─────────────────────────────────────────────────────────────────────────────

  function initialize(address gmTokenManager, string memory network) internal {
    s().gmTokenManager = gmTokenManager;
    s().network = network;
    s().networkHash = keccak256(bytes(network));
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Mint
  // ─────────────────────────────────────────────────────────────────────────────

  function hashMintRequest(IssuerTypes.MintRequest calldata req) internal pure returns (bytes32) {
    return keccak256(
      abi.encode(
        MINT_TYPEHASH,
        keccak256(bytes(req.targetUri)),
        keccak256(bytes(req.method)),
        keccak256(bytes(req.tokenizationRequestId)),
        keccak256(bytes(req.underlyingSymbol)),
        keccak256(bytes(req.tokenSymbol)),
        req.qty,
        req.walletAddress,
        keccak256(bytes(req.network)),
        keccak256(bytes(req.clientAccountId)),
        keccak256(bytes(req.clientExternalAccountId)),
        keccak256(bytes(req.clientRequestId)),
        req.created,
        req.nonce
      )
    );
  }

  function authorizeMint(
    IssuerTypes.MintRequest calldata req,
    address signer,
    uint256 gmTokenAmount
  ) internal view returns (address gmToken, bytes32 requestIdHash, uint256 usd, bytes32 userId) {
    if (gmTokenAmount == 0) revert IssuerTypes.ZeroAmount();
    if (s().mintsPaused) revert IssuerTypes.MintsArePaused();

    gmToken = s().gmTokenBySymbol[req.tokenSymbol];
    if (gmToken == address(0)) revert IssuerTypes.TokenNotSupported();

    if (keccak256(bytes(req.network)) != s().networkHash) revert IssuerTypes.NetworkMismatch();

    requestIdHash = keccak256(bytes(req.tokenizationRequestId));
    if (s().processedTokenizationRequestIds[requestIdHash]) {
      revert IssuerTypes.RequestAlreadyProcessed();
    }

    if (s().usedNonces[signer][req.nonce]) revert IssuerTypes.NonceAlreadyUsed();

    usd = usdNotional(gmToken, gmTokenAmount);
    // A $0 charge consumes nothing, so it would pass every rate-limit tier — an active zero-limit
    // halt included. Rejected here so every tier only ever sees usd > 0.
    if (usd == 0) revert IssuerTypes.ZeroNotional();

    uint256 cap = s().perTxMintCapUSD;
    if (usd > cap) revert IssuerTypes.PerTxMintCapExceeded(usd, cap);

    userId = _requireEligible(req.walletAddress);
  }

  function executeMint(
    IssuerTypes.MintRequest calldata req,
    address signer,
    address gmToken,
    bytes32 requestIdHash,
    uint256 gmTokenAmount,
    uint256 usd,
    bytes32 userId
  ) internal {
    // Effects
    s().usedNonces[signer][req.nonce] = true;
    s().processedTokenizationRequestIds[requestIdHash] = true;

    // Interaction — mint via MINTER_ROLE; GMToken hooks enforce compliance + token pause.
    IRWALike(gmToken).mint(req.walletAddress, gmTokenAmount);

    _emitIssuerMint(req, signer, gmToken, gmTokenAmount, usd, userId);
  }

  // Separate function so executeMint stays within the stack limit
  function _emitIssuerMint(
    IssuerTypes.MintRequest calldata req,
    address signer,
    address gmToken,
    uint256 gmTokenAmount,
    uint256 usd,
    bytes32 userId
  ) private {
    emit IssuerTypes.IssuerMint(
      req.walletAddress,
      userId,
      gmToken,
      gmTokenAmount,
      keccak256(bytes(req.tokenizationRequestId)),
      req.tokenizationRequestId,
      usd,
      signer,
      req.nonce
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Redeem
  // ─────────────────────────────────────────────────────────────────────────────

  function authorizeRedeem(address gmToken, uint256 amount)
    internal
    view
    returns (uint256 usd, bytes32 userId)
  {
    if (s().redeemsPaused) revert IssuerTypes.RedeemsArePaused();
    if (amount == 0) revert IssuerTypes.ZeroAmount();
    if (bytes(s().symbolByGmToken[gmToken]).length == 0) revert IssuerTypes.TokenNotSupported();
    userId = _requireEligible(msg.sender);
    usd = usdNotional(gmToken, amount);
    if (usd == 0) revert IssuerTypes.ZeroNotional();
  }

  function executeRedeem(address gmToken, uint256 amount, uint256 usd, bytes32 userId) internal {
    IERC20(gmToken).safeTransferFrom(msg.sender, address(this), amount);
    IRWALike(gmToken).burn(amount);
    emit IssuerTypes.IssuerRedeem(msg.sender, userId, gmToken, amount, usd);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Shared helpers
  // ─────────────────────────────────────────────────────────────────────────────

  function usdNotional(address gmToken, uint256 gmTokenAmount) internal view returns (uint256) {
    (uint256 price, uint64 lastUpdated, uint32 maxTimeDelay,) =
      IGMTokenManager(s().gmTokenManager).sanityCheckOracle().prices(gmToken);
    if (price == 0) revert IssuerTypes.PriceNotSet();
    if (block.timestamp - lastUpdated > maxTimeDelay) revert IssuerTypes.StalePrice();
    return (gmTokenAmount * price) / NORMALIZER_18;
  }

  function _requireEligible(address wallet) internal view returns (bytes32 userId) {
    IOndoIDRegistry registry = IGMTokenManager(s().gmTokenManager).ondoIDRegistry();
    userId = registry.getRegisteredID(GM_IDENTIFIER, wallet);
    if (userId == bytes32(0)) revert IssuerTypes.UserNotRegistered();
    if (registry.getRegisteredID(ALPACA_ITN_IDENTIFIER, wallet) == bytes32(0)) {
      revert IssuerTypes.NotItnApproved();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Config
  // ─────────────────────────────────────────────────────────────────────────────

  function setSupportedGmToken(string memory tokenSymbol, address gmToken) internal {
    if (bytes(tokenSymbol).length == 0) revert IssuerTypes.TokenSymbolEmpty();
    if (gmToken == address(0)) revert IssuerTypes.GmTokenZeroAddress();
    // Also reverts for EOAs/non-tokens (the decimals() call fails)
    if (IERC20Metadata(gmToken).decimals() != 18) revert IssuerTypes.InvalidGmTokenDecimals();

    address prev = s().gmTokenBySymbol[tokenSymbol];
    if (prev != address(0)) delete s().symbolByGmToken[prev];

    string storage mappedSymbol = s().symbolByGmToken[gmToken];
    if (
      bytes(mappedSymbol).length != 0
        && keccak256(bytes(mappedSymbol)) != keccak256(bytes(tokenSymbol))
    ) revert IssuerTypes.TokenAlreadyMapped();
    s().symbolByGmToken[gmToken] = tokenSymbol;

    s().gmTokenBySymbol[tokenSymbol] = gmToken;

    emit IssuerTypes.SupportedGmTokenSet(tokenSymbol, gmToken);
  }

  function removeSupportedGmToken(string memory tokenSymbol) internal {
    if (bytes(tokenSymbol).length == 0) revert IssuerTypes.TokenSymbolEmpty();

    address prev = s().gmTokenBySymbol[tokenSymbol];
    if (prev == address(0)) revert IssuerTypes.TokenNotSupported();

    delete s().symbolByGmToken[prev];
    delete s().gmTokenBySymbol[tokenSymbol];

    emit IssuerTypes.SupportedGmTokenSet(tokenSymbol, address(0));
  }

  function setPerTxMintCap(uint256 cap) internal {
    s().perTxMintCapUSD = cap;
    emit IssuerTypes.PerTxMintCapSet(cap);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Pause (per direction)
  // ─────────────────────────────────────────────────────────────────────────────

  function pauseMints() internal {
    s().mintsPaused = true;
    emit IssuerTypes.MintsPaused(msg.sender);
  }

  function unpauseMints() internal {
    s().mintsPaused = false;
    emit IssuerTypes.MintsUnpaused(msg.sender);
  }

  function pauseRedeems() internal {
    s().redeemsPaused = true;
    emit IssuerTypes.RedeemsPaused(msg.sender);
  }

  function unpauseRedeems() internal {
    s().redeemsPaused = false;
    emit IssuerTypes.RedeemsUnpaused(msg.sender);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Storage Accessor
  // ─────────────────────────────────────────────────────────────────────────────

  function s() internal pure returns (IssuerStorage.Layout storage) {
    return IssuerStorage.layout();
  }
}
