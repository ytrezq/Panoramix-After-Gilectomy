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
 * @title  IssuerTypes
 * @author Ondo Finance
 * @notice Shared types, errors, and events used by the GM issuer contracts
 */
library IssuerTypes {
  // ─────────────────────────────────────────────────────────────────────────────
  // Structs
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * @notice Alpaca-signed mint request. Field order MUST match `MINT_TYPEHASH` exactly.
   * @param  targetUri               Alpaca journal target URI
   * @param  method                  Alpaca operation method
   * @param  tokenizationRequestId   Alpaca-unique request id
   * @param  underlyingSymbol        Underlying equity symbol
   * @param  tokenSymbol             GM token symbol (routing + whitelist key)
   * @param  qty                     Signed underlying quantity (S off-chain, unused in math)
   * @param  walletAddress           Recipient of the minted GM tokens
   * @param  network                 Target network name (belt-and-suspenders vs domain chainId)
   * @param  clientAccountId         Alpaca client account id
   * @param  clientExternalAccountId Alpaca client external account id
   * @param  clientRequestId         Alpaca client request id
   * @param  created                 Signing timestamp (freshness NOT enforced)
   * @param  nonce                   Per-signer replay nonce
   */
  struct MintRequest {
    string targetUri;
    string method;
    string tokenizationRequestId;
    string underlyingSymbol;
    string tokenSymbol;
    uint256 qty;
    address walletAddress;
    string network;
    string clientAccountId;
    string clientExternalAccountId;
    string clientRequestId;
    uint256 created;
    uint256 nonce;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Events
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * @notice Emitted when a mint request is processed
   * @param  recipient             Recipient of the minted GM tokens
   * @param  userId                OndoIDRegistry id of the recipient
   * @param  gmToken               Minted GM token
   * @param  gmTokenAmount         Amount minted
   * @param  requestIdHash         keccak256(bytes(tokenizationRequestId))
   * @param  tokenizationRequestId Alpaca-unique request id
   * @param  usdNotional           USD value (18 decimals) of the mint
   * @param  alpacaSigner          Recovered Alpaca signer
   * @param  nonce                 Per-signer nonce consumed
   */
  event IssuerMint(
    address indexed recipient,
    bytes32 indexed userId,
    address indexed gmToken,
    uint256 gmTokenAmount,
    bytes32 requestIdHash,
    string tokenizationRequestId,
    uint256 usdNotional,
    address alpacaSigner,
    uint256 nonce
  );

  /**
   * @notice Emitted when a wallet redeems (burns) GM tokens. The backend listens for this and
   *         settles the underlying with Alpaca off-chain.
   * @param  wallet        The redeemer, whose tokens were burned
   * @param  userId        OndoIDRegistry id of the redeemer
   * @param  gmToken       Burned GM token
   * @param  gmTokenAmount Burned amount
   * @param  usdNotional   USD value (18 decimals) of the redeemed amount
   */
  event IssuerRedeem(
    address indexed wallet,
    bytes32 indexed userId,
    address indexed gmToken,
    uint256 gmTokenAmount,
    uint256 usdNotional
  );

  /**
   * @notice Emitted when a GM token is added or removed from the supported set
   * @param  tokenSymbol Token symbol key
   * @param  gmToken     GM token address (zero when removing)
   */
  event SupportedGmTokenSet(string tokenSymbol, address indexed gmToken);

  /**
   * @notice Emitted when the per-tx mint cap is updated
   * @param  cap New per-tx mint cap (USD, 18 decimals)
   */
  event PerTxMintCapSet(uint256 cap);

  /**
   * @notice Emitted when mints are paused
   * @param  pauser The caller that paused
   */
  event MintsPaused(address indexed pauser);

  /**
   * @notice Emitted when mints are unpaused
   * @param  unpauser The caller that unpaused
   */
  event MintsUnpaused(address indexed unpauser);

  /**
   * @notice Emitted when redeems are paused
   * @param  pauser The caller that paused
   */
  event RedeemsPaused(address indexed pauser);

  /**
   * @notice Emitted when redeems are unpaused
   * @param  unpauser The caller that unpaused
   */
  event RedeemsUnpaused(address indexed unpauser);

  // ─────────────────────────────────────────────────────────────────────────────
  // Errors
  // ─────────────────────────────────────────────────────────────────────────────

  /// Error thrown when gmTokenManager initializer argument is zero address
  error GMTokenManagerZeroAddress();

  /// Error thrown when defaultAdmin initializer argument is zero address
  error DefaultAdminZeroAddress();

  /// Error thrown when the network initializer argument is empty
  error NetworkEmpty();

  /// Error thrown when a token symbol argument is empty
  error TokenSymbolEmpty();

  /// Error thrown when mapping a token symbol to the zero address (use removeSupportedGmToken)
  error GmTokenZeroAddress();

  /// Error thrown when mapping a gmToken already mapped under a different symbol
  error TokenAlreadyMapped();

  /// Error thrown when a supported GM token does not have 18 decimals
  error InvalidGmTokenDecimals();

  /// Error thrown when mints are paused
  error MintsArePaused();

  /// Error thrown when redeems are paused
  error RedeemsArePaused();

  /// Error thrown when the request's tokenizationRequestId has already been processed
  error RequestAlreadyProcessed();

  /// Error thrown when the signer's nonce has already been used
  error NonceAlreadyUsed();

  /// Error thrown when the recovered signer does not hold ALPACA_SIGNER_ROLE
  error InvalidSigner();

  /// Error thrown when the request's token symbol is not supported
  error TokenNotSupported();

  /// Error thrown when the request's network does not match this contract's network
  error NetworkMismatch();

  /// Error thrown when the sanity oracle has no price set for the token
  error PriceNotSet();

  /// Error thrown when the sanity oracle price is older than its configured max delay
  error StalePrice();

  /**
   * @notice Error thrown when the mint USD notional exceeds the per-tx cap
   * @param  usd The mint USD notional
   * @param  cap The configured per-tx cap
   */
  error PerTxMintCapExceeded(uint256 usd, uint256 cap);

  /// Error thrown when a mint or redeem amount is zero
  error ZeroAmount();

  /// Error thrown when an amount's USD notional rounds to zero
  error ZeroNotional();

  /// Error thrown when the caller is not registered in the OndoIDRegistry
  error UserNotRegistered();

  /// Error thrown when a wallet is not approved for Alpaca ITN (no id under ALPACA_ITN_IDENTIFIER)
  error NotItnApproved();

  /// Error thrown when processMintPrivileged's recipient lacks PRIVILEGED_USER_ROLE
  error NotPrivilegedUser();
}
