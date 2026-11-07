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
  IIssuanceHours
} from "contracts/globalMarkets/tokenManager/issuanceHours/IIssuanceHours.sol";
import {IOndoIDRegistry} from "contracts/xManager/interfaces/IOndoIDRegistry.sol";
import {IRWALike} from "contracts/interfaces/IRWALike.sol";
import {
  IPortfolioTokenManager
} from "contracts/globalMarkets/portfolioToken/portfolioTokenManager/IPortfolioTokenManager.sol";
import {
  IPortfolioTokenManagerErrors
} from "contracts/globalMarkets/portfolioToken/portfolioTokenManager/IPortfolioTokenManagerErrors.sol";
import {
  IPortfolioTokenManagerEvents
} from "contracts/globalMarkets/portfolioToken/portfolioTokenManager/IPortfolioTokenManagerEvents.sol";
import {
  Initializable
} from "contracts/external/openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import {
  AccessControlEnumerableUpgradeable
} from "contracts/external/openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import {
  ReentrancyGuardTransient
} from "contracts/external/openzeppelin/contracts/security/ReentrancyGuardTransient.sol";
import {SafeERC20} from "contracts/external/openzeppelin/contracts/token/SafeERC20.sol";
import {EIP712} from "contracts/external/openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "contracts/external/openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {
  IOndoSanityCheckOracle
} from "contracts/globalMarkets/tokenManager/sanityCheckOracle/IOndoSanityCheckOracle.sol";
import {IOndoRateLimiter} from "contracts/xManager/interfaces/IOndoRateLimiter.sol";
import {IERC20} from "contracts/external/openzeppelin/contracts/token/IERC20.sol";
import {IERC20Metadata} from "contracts/external/openzeppelin/contracts/token/IERC20Metadata.sol";
import {IOndoTokenRouter} from "contracts/xManager/interfaces/IOndoTokenRouter.sol";

/**
 * @title  PortfolioTokenManager
 * @author Ondo Finance
 * @notice Contract for managing tokenized portfolio assets.
 *         The PortfolioTokenManager contract contains the core logic for processing minting
 *         and redemptions of portfolio tokens.
 *         The responsibilities of this contract are:
 *          - Verifying attestation signatures
 *          - Calculating the amount of portfolio tokens and USD to mint and burn
 *            based on the quote attestation that was received
 *          - Performing appropriate sanity checks on the quote attestation
 *          - Enforcing the minimum deposit and redemption amounts and ensuring the
 *            quote price is in line with the rough oracle price
 *          - Ensuring users are registered with the OndoIDRegistry
 *          - Routing the configured stablecoin from mints into the OndoTokenRouter
 *          - Pulling the configured stablecoin from the OndoTokenRouter to users during redemptions
 */
// NOTE: The PTM proxy address MUST be whitelisted in the compliance system before use.
//       During redemptions, `safeTransferFrom(user, PTM, qty)` triggers GMToken._beforeTokenTransfer
//       which calls `_checkIsCompliant(to)` on the PTM address. If PTM is not compliant, all
//       redemptions will revert. This is a deployment/configuration requirement, not enforced in code.
contract PortfolioTokenManager is
  EIP712,
  IPortfolioTokenManager,
  IPortfolioTokenManagerEvents,
  IPortfolioTokenManagerErrors,
  Initializable,
  ReentrancyGuardTransient,
  AccessControlEnumerableUpgradeable
{
  using SafeERC20 for IERC20;

  /// The identifier address used in OndoIDRegistry to validate KYC for portfolio token issuance
  address public constant gmIdentifier =
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

  /// The decimals normalizer for the portfolio token
  uint256 public constant PORTFOLIO_NORMALIZER = 1e18;

  /// Role to configure the contract
  bytes32 public constant CONFIGURER_ROLE = keccak256("CONFIGURER_ROLE");

  /// Role to pause minting and redemptions
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

  /// Role to unpause functionality
  bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

  /// Role to manually service a mint of portfolio tokens
  bytes32 public constant ADMIN_MINT_ROLE = keccak256("ADMIN_MINT_ROLE");

  /// The `OndoIDRegistry` contract address
  IOndoIDRegistry public ondoIDRegistry;

  /// The `IssuanceHours` contract for managing market hours
  IIssuanceHours public issuanceHours;

  /// The `OndoSanityCheckOracle` contract for validating the price
  IOndoSanityCheckOracle public sanityCheckOracle;

  /// The `OndoRateLimiter` contract address
  IOndoRateLimiter public ondoRateLimiter;

  /// The stablecoin token used for deposits on mint and payouts on redemption
  address public immutable stablecoin;

  /// Conversion divisor from an 18-decimal USD value to the stablecoin's native units
  uint256 public immutable stablecoinNormalizer;

  /// The OndoTokenRouter contract used to route the stablecoin to/from configured
  /// recipients/sources on mint and redemption.
  IOndoTokenRouter public ondoTokenRouter;

  /// Minimum USD amount required to subscribe, denoted in USD with 18 decimals
  uint256 public minimumDepositUSD;

  /// Minimum USD amount required to redeem, denoted in USD with 18 decimals
  uint256 public minimumRedemptionUSD;

  /// Whether mints are paused for this contract
  bool public globalMintingPaused;

  /// Whether redemptions are paused for this contract
  bool public globalRedeemingPaused;

  /// Map of all portfolio tokens that are accepted for minting and redemptions
  mapping(address => bool) public portfolioTokenAccepted;

  /// Whether mints are paused for a specific portfolio token
  mapping(address => bool) public portfolioTokenMintingPaused;

  /// Whether redemptions are paused for a specific portfolio token
  mapping(address => bool) public portfolioTokenRedemptionsPaused;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(address _stablecoin) EIP712("OndoPortfolioTokenManager", "1") {
    if (_stablecoin == address(0)) revert StablecoinAddressCantBeZero();
    stablecoin = _stablecoin;
    // Reverts on underflow if the stablecoin reports > 18 decimals (unsupported).
    stablecoinNormalizer = 10 ** (18 - IERC20Metadata(_stablecoin).decimals());
    _disableInitializers();
  }

  /**
   * @param _defaultAdmin         The default admin role for the contract
   * @param _minimumDepositUSD    The minimum subscription amount, denoted in USD with 18 decimals
   * @param _minimumRedemptionUSD The minimum redemption amount, denoted in USD with 18 decimals
   * @param _ondoIDRegistry       The address of the OndoIDRegistry contract
   * @param _sanityCheckOracle    The address of the OndoSanityCheckOracle contract
   * @param _issuanceHours        The address of the IssuanceHours contract
   * @param _ondoRateLimiter      The address of the OndoRateLimiter contract
   * @param _ondoTokenRouter      The address of the OndoTokenRouter contract used for stablecoin
   *                              deposits on mint and withdrawals on redemption
   */
  function initialize(
    address _defaultAdmin,
    uint256 _minimumDepositUSD,
    uint256 _minimumRedemptionUSD,
    address _ondoIDRegistry,
    address _sanityCheckOracle,
    address _issuanceHours,
    address _ondoRateLimiter,
    address _ondoTokenRouter
  ) external initializer {
    __AccessControlEnumerable_init();
    if (_defaultAdmin == address(0)) revert DefaultAdminZeroAddress();
    if (_ondoIDRegistry == address(0)) revert IDRegistryAddressCantBeZero();
    if (_sanityCheckOracle == address(0)) revert SanityCheckOracleAddressCantBeZero();
    if (_issuanceHours == address(0)) revert IssuanceHoursAddressCantBeZero();
    if (_ondoRateLimiter == address(0)) revert RateLimiterAddressCantBeZero();
    if (_ondoTokenRouter == address(0)) revert OndoTokenRouterAddressCantBeZero();
    minimumDepositUSD = _minimumDepositUSD;
    minimumRedemptionUSD = _minimumRedemptionUSD;
    ondoIDRegistry = IOndoIDRegistry(_ondoIDRegistry);
    sanityCheckOracle = IOndoSanityCheckOracle(_sanityCheckOracle);
    issuanceHours = IIssuanceHours(_issuanceHours);
    ondoRateLimiter = IOndoRateLimiter(_ondoRateLimiter);
    ondoTokenRouter = IOndoTokenRouter(_ondoTokenRouter);
    _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
  }

  /**
   * @notice Called by users to mint portfolio tokens with a quote attestation using the
   *         configured stablecoin. The stablecoin is pulled from the user into this contract
   *         and then deposited into the OndoTokenRouter, which forwards it on to the
   *         configured deposit recipient.
   * @param  quote     The quote to mint portfolio tokens with
   * @param  signature The signature of the quote attestation
   * @return The amount of portfolio tokens minted to the user
   */
  function mintWithAttestation(Quote calldata quote, bytes memory signature)
    external
    override
    nonReentrant
    whenMintingNotPaused(quote.asset)
    returns (uint256)
  {
    if (quote.side != QuoteSide.BUY) revert InvalidQuoteSide();

    bytes32 userId = ondoIDRegistry.getRegisteredID(gmIdentifier, _msgSender());
    if (userId == bytes32(0)) revert UserNotRegistered();

    _verifyQuote(quote, signature, userId);
    executedAttestationIds[quote.attestationId] = true;

    // USD values are normalized to 18 decimals
    uint256 mintUsdValue = (quote.quantity * quote.price) / PORTFOLIO_NORMALIZER;
    if (mintUsdValue < minimumDepositUSD) revert DepositAmountTooSmall();

    ondoRateLimiter.checkAndUpdateRateLimit(
      IOndoRateLimiter.TransactionType.SUBSCRIPTION, quote.asset, userId, mintUsdValue
    );

    // Convert 18-decimal USD value to the stablecoin's native decimals, rounding up
    uint256 stablecoinAmount = (mintUsdValue + stablecoinNormalizer - 1) / stablecoinNormalizer;

    // Pull the stablecoin from the user and deposit into the OndoTokenRouter
    IERC20(stablecoin).safeTransferFrom(_msgSender(), address(this), stablecoinAmount);
    IERC20(stablecoin).forceApprove(address(ondoTokenRouter), stablecoinAmount);
    ondoTokenRouter.depositToken(gmIdentifier, stablecoin, stablecoinAmount);

    // Mint portfolio token to user
    IRWALike(quote.asset).mint(_msgSender(), quote.quantity);

    _emitTradeExecuted(quote);

    return quote.quantity;
  }

  /**
   * @notice Called by users to redeem portfolio tokens for the configured stablecoin.
   *         Pulls the stablecoin from the OndoTokenRouter and forwards to the user.
   * @param  quote     The quote to redeem portfolio tokens with
   * @param  signature The signature of the quote attestation
   * @return stablecoinAmount The amount of the stablecoin sent to the user
   */
  function redeemWithAttestation(Quote calldata quote, bytes memory signature)
    external
    override
    nonReentrant
    whenRedeemNotPaused(quote.asset)
    returns (uint256)
  {
    if (quote.side != QuoteSide.SELL) revert InvalidQuoteSide();

    bytes32 userId = ondoIDRegistry.getRegisteredID(gmIdentifier, _msgSender());
    if (userId == bytes32(0)) revert UserNotRegistered();

    _verifyQuote(quote, signature, userId);
    executedAttestationIds[quote.attestationId] = true;

    // Burn the portfolio tokens
    IERC20(quote.asset).safeTransferFrom(_msgSender(), address(this), quote.quantity);
    IRWALike(quote.asset).burn(quote.quantity);

    // USD values are normalized to 18 decimals
    uint256 redemptionUsdValue = (quote.quantity * quote.price) / PORTFOLIO_NORMALIZER;
    if (redemptionUsdValue < minimumRedemptionUSD) revert RedemptionAmountTooSmall();

    ondoRateLimiter.checkAndUpdateRateLimit(
      IOndoRateLimiter.TransactionType.REDEMPTION, quote.asset, userId, redemptionUsdValue
    );

    // Convert 18-decimal USD value to the stablecoin's native decimals
    uint256 stablecoinAmount = redemptionUsdValue / stablecoinNormalizer;

    // Pull the stablecoin from OndoTokenRouter and forward to user
    ondoTokenRouter.withdrawToken(gmIdentifier, stablecoin, userId, stablecoinAmount);
    IERC20(stablecoin).safeTransfer(_msgSender(), stablecoinAmount);

    _emitTradeExecuted(quote);

    return stablecoinAmount;
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

    if (portfolioTokenAccepted[quote.asset] == false) revert PortfolioTokenNotRegistered();

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
   * @notice Admin function to service a subscription whose corresponding deposit has been made
   *         outside of this contract's system.
   * @param  portfolioToken       The address of the portfolio token to mint
   * @param  recipient         The address to send the portfolio tokens to
   * @param  portfolioTokenAmount The amount of portfolio tokens to mint
   * @param  metadata          Additional metadata to emit with the subscription
   */
  function adminProcessMint(
    address portfolioToken,
    address recipient,
    uint256 portfolioTokenAmount,
    bytes32 metadata
  ) external nonReentrant whenMintingNotPaused(portfolioToken) onlyRole(ADMIN_MINT_ROLE) {
    if (!portfolioTokenAccepted[portfolioToken]) revert PortfolioTokenNotRegistered();

    bytes32 userId = ondoIDRegistry.getRegisteredID(gmIdentifier, recipient);
    if (userId == bytes32(0)) revert UserNotRegistered();

    // Actually mint the token to the user
    IRWALike(portfolioToken).mint(recipient, portfolioTokenAmount);

    emit AdminMint(recipient, userId, portfolioToken, portfolioTokenAmount, metadata);
  }

  /**
   * @notice Returns the domain separator for EIP712
   * @return The domain separator
   */
  function getDomainSeparator() public view returns (bytes32) {
    return _domainSeparatorV4();
  }

  /**
   * @notice Sets the `IssuanceHours` contract
   * @param  _issuanceHours The `IssuanceHours` contract address
   */
  function setIssuanceHours(address _issuanceHours) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_issuanceHours == address(0)) revert IssuanceHoursAddressCantBeZero();
    emit IssuanceHoursSet(address(issuanceHours), _issuanceHours);
    issuanceHours = IIssuanceHours(_issuanceHours);
  }

  /**
   * @notice Sets the `OndoSanityCheckOracle` contract
   * @param  _sanityCheckOracle The new `OndoSanityCheckOracle` contract address
   */
  function setSanityCheckOracle(address _sanityCheckOracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_sanityCheckOracle == address(0)) revert SanityCheckOracleAddressCantBeZero();
    emit OndoSanityCheckOracleSet(address(sanityCheckOracle), _sanityCheckOracle);
    sanityCheckOracle = IOndoSanityCheckOracle(_sanityCheckOracle);
  }

  /**
   * @notice Sets the `OndoIDRegistry` contract
   * @param  _ondoIDRegistry The `OndoIDRegistry` contract address
   */
  function setOndoIDRegistry(address _ondoIDRegistry) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_ondoIDRegistry == address(0)) revert IDRegistryAddressCantBeZero();
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
    if (_ondoRateLimiter == address(0)) revert RateLimiterAddressCantBeZero();
    emit OndoRateLimiterSet(address(ondoRateLimiter), _ondoRateLimiter);
    ondoRateLimiter = IOndoRateLimiter(_ondoRateLimiter);
  }

  /**
   * @notice Sets the OndoTokenRouter contract address
   * @param  _ondoTokenRouter The OndoTokenRouter contract address
   */
  function setOndoTokenRouter(address _ondoTokenRouter) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_ondoTokenRouter == address(0)) revert OndoTokenRouterAddressCantBeZero();
    emit OndoTokenRouterSet(address(ondoTokenRouter), _ondoTokenRouter);
    ondoTokenRouter = IOndoTokenRouter(_ondoTokenRouter);
  }

  /**
   * @notice Sets whether a portfolio token is accepted for mints and redemptions
   * @param  token    The address of the token
   * @param  accepted Whether the token is accepted
   */
  function setPortfolioTokenRegistrationStatus(address token, bool accepted)
    external
    onlyRole(CONFIGURER_ROLE)
  {
    if (token == address(0)) revert TokenAddressCantBeZero();
    portfolioTokenAccepted[token] = accepted;
    emit PortfolioTokenRegistered(token, accepted);
  }

  /**
   * @notice Sets the minimum amount required for a subscription
   * @param  _minimumDepositUSD The minimum amount, denoted in USD with 18 decimals
   */
  function setMinimumDepositAmount(uint256 _minimumDepositUSD) external onlyRole(CONFIGURER_ROLE) {
    emit MinimumDepositAmountSet(minimumDepositUSD, _minimumDepositUSD);
    minimumDepositUSD = _minimumDepositUSD;
  }

  /**
   * @notice Sets the minimum amount to redeem
   * @param  _minimumRedemptionUSD The minimum amount, denoted in USD with 18 decimals
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
    emit TokensRetrieved(token, to, amount);
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
   * @notice Pauses minting for a specific portfolio token
   * @param  portfolioToken The address of the portfolio token
   */
  function pausePortfolioTokenMints(address portfolioToken) external onlyRole(PAUSER_ROLE) {
    portfolioTokenMintingPaused[portfolioToken] = true;
    emit PortfolioTokenMintingPaused(portfolioToken);
  }

  /**
   * @notice Unpauses minting for a specific portfolio token
   * @param  portfolioToken The address of the portfolio token
   */
  function unpausePortfolioTokenMints(address portfolioToken) external onlyRole(UNPAUSER_ROLE) {
    portfolioTokenMintingPaused[portfolioToken] = false;
    emit PortfolioTokenMintingUnpaused(portfolioToken);
  }

  /**
   * @notice Pauses redemption for a specific portfolio token
   * @param  portfolioToken The address of the portfolio token
   */
  function pausePortfolioTokenRedemptions(address portfolioToken) external onlyRole(PAUSER_ROLE) {
    portfolioTokenRedemptionsPaused[portfolioToken] = true;
    emit PortfolioTokenRedeemingPaused(portfolioToken);
  }

  /**
   * @notice Unpauses redemption for a specific portfolio token
   * @param  portfolioToken The address of the portfolio token
   */
  function unpausePortfolioTokenRedemptions(address portfolioToken)
    external
    onlyRole(UNPAUSER_ROLE)
  {
    portfolioTokenRedemptionsPaused[portfolioToken] = false;
    emit PortfolioTokenRedeemingUnpaused(portfolioToken);
  }

  /*//////////////////////////////////////////////////////////////
                          Modifiers
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Ensure that the subscribe functionality is not paused
   * @param  portfolioToken The address of the portfolio token to check
   * @dev    Reverts if either global minting or token-specific minting is paused
   */
  modifier whenMintingNotPaused(address portfolioToken) {
    if (globalMintingPaused) revert GlobalMintsPaused();
    if (portfolioTokenMintingPaused[portfolioToken]) revert PortfolioTokenMintsPaused();
    _;
  }

  /**
   * @notice Ensure that the redeem functionality is not paused
   * @param  portfolioToken The address of the portfolio token to check
   * @dev    Reverts if either global redemptions or token-specific redemptions are paused
   */
  modifier whenRedeemNotPaused(address portfolioToken) {
    if (globalRedeemingPaused) revert GlobalRedemptionsPaused();
    if (portfolioTokenRedemptionsPaused[portfolioToken]) revert PortfolioTokenRedemptionsPaused();
    _;
  }

  /**
   * @dev Reserved storage gap for future upgrades
   */
  uint256[50] private __gap;
}
