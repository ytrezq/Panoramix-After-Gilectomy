/**
 * SPDX-License-Identifier: BUSL-1.1
 *
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
 *
 */

pragma solidity 0.8.33;

import {
  IIssuanceHours
} from "contracts/globalMarkets/tokenManager/issuanceHours/IIssuanceHours.sol";
import {IOndoIDRegistry} from "contracts/xManager/interfaces/IOndoIDRegistry.sol";
import {IOndoRateLimiter} from "contracts/xManager/interfaces/IOndoRateLimiter.sol";
import {IRWALike} from "contracts/interfaces/IRWALike.sol";
import {
  IGMTokenManagerErrors
} from "contracts/globalMarkets/tokenManager/IGMTokenManagerErrors.sol";
import {
  IGMTokenManagerEvents
} from "contracts/globalMarkets/tokenManager/IGMTokenManagerEvents.sol";
import {
  AccessControlEnumerable
} from "contracts/external/openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {
  ReentrancyGuard
} from "contracts/external/openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "contracts/external/openzeppelin/contracts/token/SafeERC20.sol";
import {EIP712} from "contracts/external/openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "contracts/external/openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IGMTokenManager} from "contracts/globalMarkets/tokenManager/IGMTokenManager.sol";
import {
  IOndoSanityCheckOracle
} from "contracts/globalMarkets/tokenManager/sanityCheckOracle/IOndoSanityCheckOracle.sol";
import {IUSDonManager} from "contracts/globalMarkets/USDonManager/IUSDonManager.sol";
import {IERC20} from "contracts/external/openzeppelin/contracts/token/IERC20.sol";

/**
 * @title  GMTokenManager
 * @author Ondo Finance
 * @notice Contract for managing tokenized equity assets
 * @notice The GMTokenManager contract contains the core logic for processing minting
 *         and redemptions of GM tokens.
 *         The responsibilities of this contract are:
 *          - Verifying attestation signatures
 *          - Calculating the amount of GM tokens and USDon to mint and burn
 *            based on the quote attestation that was received
 *          - Performing appropriate sanity checks on the quote attestation
 *          - Enforcing the minimum deposit and redemption amounts and ensuring the
 *            quote price is in line with the rough oracle price
 *          - Ensuring users are registered with the OndoIDRegistry
 *          - Checking user-specific and global rate limits
 */
contract GMTokenManager is
  EIP712,
  IGMTokenManager,
  IGMTokenManagerEvents,
  IGMTokenManagerErrors,
  ReentrancyGuard,
  AccessControlEnumerable
{
  using SafeERC20 for IERC20;

  /// The identifier address used in OndoIDRegistry to validate KYC for all GM token issuance
  address public gmIdentifier =
    address(uint160(uint256(keccak256(abi.encodePacked("global_markets")))));

  /// Role for signing attestations
  bytes32 public constant ATTESTATION_SIGNER_ROLE = keccak256("ATTESTATION_SIGNER_ROLE");

  /// Type hash for EIP-712 quote signatures
  bytes32 public constant QUOTE_TYPEHASH = keccak256(
    "Quote(uint256 chainId,uint256 attestationId,bytes32 userId,address asset,uint256 price,uint256 quantity,uint256 expiration,uint8 side,bytes32 additionalData)"
  );

  /// Mapping of attestation IDs to whether they have been redeemed
  mapping(uint256 => bool) public executedAttestationIds;

  /// Monotonically increasing ID for each execution of a quote
  uint256 public executionId = 0;

  /// The decimals normalizer for the GM token
  uint256 public constant GM_NORMALIZER = 1e18;

  /// Role to configure the contract
  bytes32 public constant CONFIGURER_ROLE = keccak256("CONFIGURER_ROLE");

  /// Role to pause minting and redemptions
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

  /// Role to unpause functionality
  bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

  /// Role to manually service a mint of GM tokens
  bytes32 public constant ADMIN_MINT_ROLE = keccak256("ADMIN_MINT_ROLE");

  /// The token that can be used to subscribe to a GM token and can be received when redeeming a GM token
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  address public immutable usdon;

  /// The address of the USDon manager used for swapping with other tokens
  IUSDonManager public usdonManager;

  /**
   * @notice Minimum USD amount required to subscribe to a GM token, denoted in USD with 18
   *         decimals.
   */
  uint256 public minimumDepositUSD;

  /**
   * @notice Minimum USD amount required to perform an GM token redemption to be allowed,
   *         denoted in USD with 18 decimals
   */
  uint256 public minimumRedemptionUSD;

  /// Whether mints are paused for this contract
  bool public globalMintingPaused;

  /// Whether redemptions are paused for this contract
  bool public globalRedeemingPaused;

  /// Whether mints are paused for a specific gm asset
  mapping(address => bool) public gmTokenMintingPaused;

  /// Whether redemptions are paused for a specific gm asset
  mapping(address => bool) public gmTokenRedemptionsPaused;

  /// The `OndoIDRegistry` contract address
  IOndoIDRegistry public ondoIDRegistry;

  /// The `OndoRateLimiter` contract address
  IOndoRateLimiter public ondoRateLimiter;

  /// The `IssuanceHours` contract for managing market hours
  IIssuanceHours public issuanceHours;

  /// The `OndoSanityCheckOracle` contract for validating the price of the GM token
  IOndoSanityCheckOracle public sanityCheckOracle;

  /// Map of all GM tokens that are accepted for minting and redemptions
  mapping(address => bool) public gmTokenAccepted;

  /**
   * @param _defaultAdmin         The default admin role for the contract
   * @param _usdon                The address of the USDon token used for minting and redemptions
   * @param _minimumDepositUSD    The minimum subscription amount, denoted in USD with 18 decimals
   * @param _minimumRedemptionUSD The minimum redemption amount, denoted in USD with 18 decimals
   */
  constructor(
    address _defaultAdmin,
    address _usdon,
    uint256 _minimumDepositUSD,
    uint256 _minimumRedemptionUSD
  ) EIP712("OndoGMTokenManager", "1") {
    if (_usdon == address(0)) {
      revert USDonAddressCantBeZero();
    }
    usdon = _usdon;
    minimumDepositUSD = _minimumDepositUSD;
    minimumRedemptionUSD = _minimumRedemptionUSD;
    _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
  }

  /**
   * @notice Called by users to mint GM tokens with a quote attestation using USDon
   * @param  quote              The quote to mint GM tokens with
   * @param  signature          The signature of the quote attestation
   * @param  depositToken       The token the user would like to deposit in return for GM Tokens.
   *                            If not USDon, this will be reliant on the ability to swap for USDon in the USDonManager
   * @param  depositTokenAmount The amount of depositToken the user wishes to spend to purchase USDon atomically in the transaction
   * @return The amount of GM tokens minted to the user
   * @dev    If the deposit token is not USDon and the depositTokenAmount is not enough to swap for USDon
   *         worth quantity * price as specified in the quote, the transaction will fail as the `mintUSDonValue`
   *         is passed in to the minimum RWA received field in `subscribe`.
   */
  function mintWithAttestation(
    Quote calldata quote,
    bytes memory signature,
    address depositToken,
    uint256 depositTokenAmount
  ) public override nonReentrant whenMintingNotPaused(quote.asset) returns (uint256) {
    if (depositToken == address(0)) {
      revert TokenAddressCantBeZero();
    }
    if (quote.side != QuoteSide.BUY) revert InvalidQuoteSide();

    bytes32 userId = ondoIDRegistry.getRegisteredID(gmIdentifier, _msgSender());
    if (userId == bytes32(0)) revert UserNotRegistered();

    _verifyQuote(quote, signature, userId);
    executedAttestationIds[quote.attestationId] = true;

    // USD values are normalized to 18 decimals
    uint256 mintUSDonValue = (quote.quantity * quote.price) / GM_NORMALIZER;
    if (mintUSDonValue < minimumDepositUSD) revert DepositAmountTooSmall();

    ondoRateLimiter.checkAndUpdateRateLimit(
      IOndoRateLimiter.TransactionType.SUBSCRIPTION, quote.asset, userId, mintUSDonValue
    );

    // Transfer usdon into the contract
    if (depositToken == address(usdon)) {
      IERC20(usdon).safeTransferFrom(_msgSender(), address(this), mintUSDonValue);
    } else {
      if (address(usdonManager) == address(0)) revert USDonManagerNotEnabled();
      IERC20(depositToken).safeTransferFrom(_msgSender(), address(this), depositTokenAmount);
      IERC20(depositToken).forceApprove(address(usdonManager), depositTokenAmount);
      uint256 receivedOnUsd =
        usdonManager.subscribe(depositToken, depositTokenAmount, mintUSDonValue);

      // If the deposit token is not USDon, we need to refund the user if they sent more than
      // the required amount of USDon to mint the GM tokens
      uint256 refund = receivedOnUsd - mintUSDonValue;
      if (refund > 0) {
        IERC20(usdon).safeTransfer(_msgSender(), refund);
      }
    }

    IRWALike(usdon).burn(mintUSDonValue);

    // actually mint the token to the user
    IRWALike(quote.asset).mint(_msgSender(), quote.quantity);

    _emitTradeExecuted(quote);

    return quote.quantity;
  }

  /**
   * @notice Called by users to redeem GM tokens for USDon
   * @param  quote                The quote to redeem GM tokens with
   * @param  signature            The signature of the quote attestation
   * @param  receiveToken         The token the user would like to receive. If it is not USDon,
   *                              transaction success will depend on liquidity in USDonManager
   * @param  minimumReceiveAmount The minimum amount of tokens the user would like to receive
   *                              - ONLY applicable if the user requests a non-USDon token
   * @return The amount of USDon minted
   */
  function redeemWithAttestation(
    Quote calldata quote,
    bytes memory signature,
    address receiveToken,
    uint256 minimumReceiveAmount
  ) public override nonReentrant whenRedeemNotPaused(quote.asset) returns (uint256) {
    if (receiveToken == address(0)) {
      revert TokenAddressCantBeZero();
    }
    if (quote.side != QuoteSide.SELL) revert InvalidQuoteSide();

    bytes32 userId = ondoIDRegistry.getRegisteredID(gmIdentifier, _msgSender());
    if (userId == bytes32(0)) revert UserNotRegistered();

    _verifyQuote(quote, signature, userId);
    executedAttestationIds[quote.attestationId] = true;

    // burn the GM tokens
    IERC20(quote.asset).safeTransferFrom(_msgSender(), address(this), quote.quantity);
    IRWALike(quote.asset).burn(quote.quantity);

    // USD values are normalized to 18 decimals
    uint256 redemptionUSDonValue = (quote.quantity * quote.price) / GM_NORMALIZER;

    if (redemptionUSDonValue < minimumRedemptionUSD) {
      revert RedemptionAmountTooSmall();
    }

    ondoRateLimiter.checkAndUpdateRateLimit(
      IOndoRateLimiter.TransactionType.REDEMPTION, quote.asset, userId, redemptionUSDonValue
    );

    // Mint USDon to the contract
    IRWALike(usdon).mint(address(this), redemptionUSDonValue);

    if (receiveToken == address(usdon)) {
      IERC20(usdon).safeTransfer(_msgSender(), redemptionUSDonValue);
    } else {
      if (address(usdonManager) == address(0)) revert USDonManagerNotEnabled();
      IERC20(usdon).approve(address(usdonManager), redemptionUSDonValue);
      uint256 receiveAmount =
        usdonManager.redeem(redemptionUSDonValue, receiveToken, minimumReceiveAmount);
      IERC20(receiveToken).safeTransfer(_msgSender(), receiveAmount);
    }

    _emitTradeExecuted(quote);

    return redemptionUSDonValue;
  }

  /**
   * @notice Verifies the signature of the quote
   * @param  quote     The quote to verify
   * @param  signature The signature to verify
   * @param  userId    The user ID of the user executing the quote
   */
  function _verifyQuote(Quote calldata quote, bytes memory signature, bytes32 userId) internal {
    // Ensure the attestation isn't being reused
    if (executedAttestationIds[quote.attestationId]) {
      revert AttestationAlreadyExecuted();
    }

    if (block.timestamp > quote.expiration) revert AttestationExpired();

    if (userId != quote.userId) revert UserIdMismatch(userId, quote.userId);

    issuanceHours.checkIsValidHours();

    sanityCheckOracle.validatePrice(quote.asset, quote.price);

    if (gmTokenAccepted[quote.asset] == false) revert GMTokenNotRegistered();

    if (quote.chainId != block.chainid) revert InvalidChainId();

    bytes32 digest = _hashTypedDataV4(
      keccak256(
        abi.encode(
          QUOTE_TYPEHASH,
          quote.chainId,
          quote.attestationId,
          quote.userId,
          quote.asset,
          quote.price,
          quote.quantity,
          quote.expiration,
          quote.side,
          quote.additionalData
        )
      )
    );

    address signer = ECDSA.recover(digest, signature);
    if (!hasRole(ATTESTATION_SIGNER_ROLE, signer)) {
      revert InvalidAttestationSigner();
    }
  }

  /**
   * @notice Emits a `TradeExecuted` event and increments the `executionId`
   * @param  quote The quote to emit the event for
   * @dev    The only purpose of this is to prevent stack too deep errors from unpacking the large struct.
   *         Increments executionId before emitting to provide a unique ID for each trade.
   */
  function _emitTradeExecuted(Quote calldata quote) internal {
    emit TradeExecuted(
      ++executionId,
      quote.attestationId,
      quote.chainId,
      quote.userId,
      quote.side,
      quote.asset,
      quote.price,
      quote.quantity,
      quote.expiration,
      quote.additionalData
    );
  }

  /**
   * @notice Admin function to service a subscription whose corresponding deposit been made outside
   *         of this contracts system.
   * @param  gmToken       The address of the GM token to mint
   * @param  recipient     The address to send the GM tokens to
   * @param  gmTokenAmount The amount of GM tokens to mint and/or transfer
   * @param  metadata      Additional metadata to emit with the subscription
   */
  function adminProcessMint(
    address gmToken,
    address recipient,
    uint256 gmTokenAmount,
    bytes32 metadata
  ) external whenMintingNotPaused(gmToken) onlyRole(ADMIN_MINT_ROLE) {
    if (!gmTokenAccepted[gmToken]) revert GMTokenNotRegistered();

    bytes32 userId = ondoIDRegistry.getRegisteredID(gmIdentifier, recipient);
    if (userId == bytes32(0)) revert UserNotRegistered();

    // Actually mint the token to the user
    IRWALike(gmToken).mint(recipient, gmTokenAmount);

    emit AdminMint(recipient, userId, gmToken, gmTokenAmount, metadata);
  }

  /**
   * @notice Sets the `IssuanceHours` contract
   * @param  _issuanceHours The `IssuanceHours` contract address
   */
  function setIssuanceHours(address _issuanceHours) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_issuanceHours == address(0)) {
      revert IssuanceHoursAddressCantBeZero();
    }
    emit IssuanceHoursSet(address(issuanceHours), _issuanceHours);
    issuanceHours = IIssuanceHours(_issuanceHours);
  }

  /**
   * @notice Sets the `OndoSanityCheckOracle` contract
   * @param  _sanityCheckOracle The new `OndoSanityCheckOracle` contract address
   */
  function setSanityCheckOracle(address _sanityCheckOracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_sanityCheckOracle == address(0)) {
      revert SanityCheckOracleAddressCantBeZero();
    }
    emit OndoSanityCheckOracleSet(address(sanityCheckOracle), _sanityCheckOracle);
    sanityCheckOracle = IOndoSanityCheckOracle(_sanityCheckOracle);
  }

  /**
   * @notice Sets the `OndoIDRegistry` contract
   * @param  _ondoIDRegistry The `OndoIDRegistry` contract address
   */
  function setOndoIDRegistry(address _ondoIDRegistry) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_ondoIDRegistry == address(0)) {
      revert IDRegistryAddressCantBeZero();
    }
    emit OndoIDRegistrySet(address(ondoIDRegistry), _ondoIDRegistry);
    ondoIDRegistry = IOndoIDRegistry(_ondoIDRegistry);
    // Ensure that the `OndoIDRegistry` interface is supported
    ondoIDRegistry.getRegisteredID(gmIdentifier, address(this));
  }

  /**
   * @notice Sets the `OndoRateLimiter` contract
   * @param  _ondoRateLimiter The `OndoRateLimiter` contract address
   */
  function setOndoRateLimiter(address _ondoRateLimiter) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_ondoRateLimiter == address(0)) {
      revert RateLimiterAddressCantBeZero();
    }
    emit OndoRateLimiterSet(address(ondoRateLimiter), _ondoRateLimiter);
    ondoRateLimiter = IOndoRateLimiter(_ondoRateLimiter);
  }

  /**
   * @notice Sets the `USDonManager` contract
   * @param  _usdonManager The `USDonManager` contract address
   */
  function setUSDonManager(address _usdonManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
    emit USDonManagerSet(address(usdonManager), _usdonManager);
    usdonManager = IUSDonManager(_usdonManager);
  }

  /**
   * @notice Sets whether a token is accepted for mints and redemptions on this contract
   * @param  token    The address of the token
   * @param  accepted Whether the token is accepted for mints and redemptions
   */
  function setGMTokenRegistrationStatus(address token, bool accepted)
    external
    onlyRole(CONFIGURER_ROLE)
  {
    if (token == address(0)) revert TokenAddressCantBeZero();
    gmTokenAccepted[token] = accepted;
    emit GMTokenRegistered(token, accepted);
  }

  /**
   * @notice Sets the minimum amount required for a subscription
   * @param  _minimumDepositUSD The minimum amount required to subscribe, denoted in
   *                            USD with 18 decimals
   */
  function setMinimumDepositAmount(uint256 _minimumDepositUSD) external onlyRole(CONFIGURER_ROLE) {
    emit MinimumDepositAmountSet(minimumDepositUSD, _minimumDepositUSD);
    minimumDepositUSD = _minimumDepositUSD;
  }

  /**
   * @notice Sets the minimum amount to redeem
   * @param  _minimumRedemptionUSD The minimum amount required to redeem,
   *                               denoted in USD with 18.
   */
  function setMinimumRedemptionAmount(uint256 _minimumRedemptionUSD)
    external
    onlyRole(CONFIGURER_ROLE)
  {
    emit MinimumRedemptionAmountSet(minimumRedemptionUSD, _minimumRedemptionUSD);
    minimumRedemptionUSD = _minimumRedemptionUSD;
  }

  /**
   * @notice Rescue and transfer tokens locked in this contract
   * @param  token  The address of the token
   * @param  to     The address of the recipient
   * @param  amount The amount of token to transfer
   */
  function retrieveTokens(address token, address to, uint256 amount)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    IERC20(token).safeTransfer(to, amount);
  }

  /**
   * @notice Returns the domain separator for EIP712
   * @return The domain separator
   */
  function getDomainSeparator() public view returns (bytes32) {
    return _domainSeparatorV4();
  }

  /*//////////////////////////////////////////////////////////////
                          Pause/Unpause
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Globally pause the minting functionality
   */
  function pauseGlobalMints() external onlyRole(PAUSER_ROLE) {
    globalMintingPaused = true;
    emit GlobalMintingPaused();
  }

  /**
   * @notice Globally unpause the minting functionality
   */
  function unpauseGlobalMints() external onlyRole(UNPAUSER_ROLE) {
    globalMintingPaused = false;
    emit GlobalMintingUnpaused();
  }

  /**
   * @notice Globally pause the redeem functionality
   */
  function pauseGlobalRedeems() external onlyRole(PAUSER_ROLE) {
    globalRedeemingPaused = true;
    emit GlobalRedeemingPaused();
  }

  /**
   * @notice Globally unpause the redeem functionality
   */
  function unpauseGlobalRedeems() external onlyRole(UNPAUSER_ROLE) {
    globalRedeemingPaused = false;
    emit GlobalRedeemingUnpaused();
  }

  /**
   * @notice Pauses minting for a specific GM token
   * @param  gmToken The address of the GM token
   */
  function pauseGMTokenMints(address gmToken) external onlyRole(PAUSER_ROLE) {
    gmTokenMintingPaused[gmToken] = true;
    emit GMTokenMintingPaused(gmToken);
  }

  /**
   * @notice Unpauses minting for a specific GM token
   * @param  gmToken The address of the GM token
   */
  function unpauseGMTokenMints(address gmToken) external onlyRole(UNPAUSER_ROLE) {
    gmTokenMintingPaused[gmToken] = false;
    emit GMTokenMintingUnpaused(gmToken);
  }

  /**
   * @notice Pauses redemption for a specific GM token
   * @param  gmToken The address of the GM token
   */
  function pauseGMTokenRedemptions(address gmToken) external onlyRole(PAUSER_ROLE) {
    gmTokenRedemptionsPaused[gmToken] = true;
    emit GMTokenRedeemingPaused(gmToken);
  }

  /**
   * @notice Unpauses redemption for a specific GM token
   * @param  gmToken The address of the GM token
   */
  function unpauseGMTokenRedemptions(address gmToken) external onlyRole(UNPAUSER_ROLE) {
    gmTokenRedemptionsPaused[gmToken] = false;
    emit GMTokenRedeemingUnpaused(gmToken);
  }

  /**
   * @notice Ensure that the subscribe functionality is not paused
   * @param  gmToken The address of the GM token to check
   * @dev    Reverts if either global minting or token-specific minting is paused
   */
  modifier whenMintingNotPaused(address gmToken) {
    if (globalMintingPaused) revert GlobalMintsPaused();
    if (gmTokenMintingPaused[gmToken]) revert GMTokenMintsPaused();
    _;
  }

  /**
   * @notice Ensure that the redeem functionality is not paused
   * @param  gmToken The address of the GM token to check
   * @dev    Reverts if either global redemptions or token-specific redemptions are paused
   */
  modifier whenRedeemNotPaused(address gmToken) {
    if (globalRedeemingPaused) revert GlobalRedemptionsPaused();
    if (gmTokenRedemptionsPaused[gmToken]) revert GMTokenRedemptionsPaused();
    _;
  }
}
