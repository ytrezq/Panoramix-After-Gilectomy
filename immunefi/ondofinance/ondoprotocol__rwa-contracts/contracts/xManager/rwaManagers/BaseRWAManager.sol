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
import {IOndoTokenRouter} from "contracts/xManager/interfaces/IOndoTokenRouter.sol";
import {IOndoIDRegistry} from "contracts/xManager/interfaces/IOndoIDRegistry.sol";
import {IOndoCompliance} from "contracts/xManager/interfaces/IOndoCompliance.sol";
import {IOndoRateLimiter} from "contracts/xManager/interfaces/IOndoRateLimiter.sol";
import {IOndoOracle} from "contracts/xManager/interfaces/IOndoOracle.sol";
import {IOndoFees} from "contracts/xManager/interfaces/IOndoFees.sol";
import {
  IAdminSubscriptionChecker
} from "contracts/xManager/interfaces/IAdminSubscriptionChecker.sol";
import {IBaseRWAManagerEvents} from "contracts/xManager/rwaManagers/IBaseRWAManagerEvents.sol";
import {IBaseRWAManagerErrors} from "contracts/xManager/rwaManagers/IBaseRWAManagerErrors.sol";
import {IERC20Metadata} from "contracts/external/openzeppelin/contracts/token/IERC20Metadata.sol";
import {
  AccessControlEnumerable
} from "contracts/external/openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {
  ReentrancyGuard
} from "contracts/external/openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "contracts/external/openzeppelin/contracts/token/SafeERC20.sol";
import {IERC20} from "contracts/external/openzeppelin/contracts/token/IERC20.sol";

/**
 * @title  BaseRWAManager
 * @author Ondo Finance
 * @notice The BaseRWAManager contract contains the core logic for processing subscriptions
 *         and redemptions of RWA tokens. The abstract logic of this contract never touches
 *         RWA tokens, so inheriting child classes may implement the RWA token processing as they
 *         see fit.
 *         The responsibilities of this contract are:
 *          - Receiving deposits of tokens and depositing them into the OndoTokenRouter
 *          - Calculating the amount of RWA tokens to mint and/or transfer
 *            based on the deposit amount of subscriptions
 *          - Calculating the amount of tokens to return to users based on the redemption amount
 *          - Withdrawing tokens from the OndoTokenRouter and sending them to users
 *          - Enforcing the minimum deposit and redemption amounts
 *          - Ensuring users are registered with the OndoIDRegistry
 *          - Ensuring users are compliant with the OndoCompliance contract
 *         -  Checking user-specific and global rate limits
 *         -  Calculating the fees incurred by users for subscriptions and
 *            redemptions
 */
abstract contract BaseRWAManager is
  IBaseRWAManagerEvents,
  IBaseRWAManagerErrors,
  ReentrancyGuard,
  AccessControlEnumerable
{
  using SafeERC20 for IERC20;
  /// The decimals normalizer for USD
  uint256 public constant USD_NORMALIZER = 1e18;

  /// The decimals normalizer for the RWA token
  uint256 public immutable RWA_NORMALIZER;

  /// Role to configure the contract
  bytes32 public constant CONFIGURER_ROLE = keccak256("CONFIGURER_ROLE");

  /// Role to pause subscriptions and redemptions
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

  /// Role to manually service a subscription to RWA tokens
  bytes32 public constant ADMIN_SUBSCRIPTION_ROLE = keccak256("ADMIN_SUBSCRIPTION_ROLE");

  /**
   * @notice Minimum USD amount required to subscribe to a RWA token, denoted in USD with 18
   *         decimals.
   */
  uint256 public minimumDepositUSD;

  /**
   * @notice Minimum USD amount required to perform an RWA token redemption to be allowed,
   *         denoted in USD with 18 decimals
   */
  uint256 public minimumRedemptionUSD;

  /// Minimum price of RWA token that this contract will use, denoted in USD with 18 decimals
  uint256 public minimumRwaPrice;

  /// Whether subscriptions are paused for this contract
  bool public subscribePaused;

  /// Whether redemptions are paused for this contract
  bool public redeemPaused;

  /// The contract address for the RWA token this contract is responsible for
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  address public immutable rwaToken;

  /// The `OndoTokenRouter` contract address
  IOndoTokenRouter public ondoTokenRouter;

  /// The `OndoOracle` contract address
  IOndoOracle public ondoOracle;

  /// The `OndoCompliance` contract address
  IOndoCompliance public ondoCompliance;

  /// The `OndoIDRegistry` contract address
  IOndoIDRegistry public ondoIDRegistry;

  /// The `OndoRateLimiter` contract address
  IOndoRateLimiter public ondoRateLimiter;

  /// The `OndoFees` contract for managing subscription fees
  IOndoFees public ondoSubscriptionFees;

  /// The `OndoFees` contract for managing redemption fees
  IOndoFees public ondoRedemptionFees;

  /// The `AdminSubscriptionChecker` contract
  IAdminSubscriptionChecker public adminSubscriptionChecker;

  /// Mapping of accepted subscription tokens
  mapping(address => bool) public acceptedSubscriptionTokens;

  /// Mapping of accepted redemption tokens
  mapping(address => bool) public acceptedRedemptionTokens;

  /**
   * @param _defaultAdmin         The default admin role for the contract
   * @param _rwaToken             The RWA token address
   * @param _minimumDepositUSD    The minimum subscription amount, denoted in USD with 18 decimals
   * @param _minimumRedemptionUSD The minimum redemption amount, denoted in USD with 18 decimals
   */
  constructor(
    address _defaultAdmin,
    address _rwaToken,
    uint256 _minimumDepositUSD,
    uint256 _minimumRedemptionUSD
  ) {
    if (_rwaToken == address(0)) {
      revert TokenAddressCantBeZero();
    }

    rwaToken = _rwaToken;
    RWA_NORMALIZER = 10 ** IERC20Metadata(_rwaToken).decimals();
    minimumDepositUSD = _minimumDepositUSD;
    minimumRedemptionUSD = _minimumRedemptionUSD;
    _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
  }

  /**
   * @notice Internal function for processing subscriptions
   * @param  depositToken       The token to deposit
   * @param  depositAmount      The amount of tokens to deposit, in decimals of the
   *                            token being deposited
   * @param  minimumRwaReceived The minimum amount of RWA tokens to receive, in
   *                            decimals of the RWA token
   * @return rwaAmountOut       The amount of RWA tokens to mint or transfer, in
   *                            decimals of the RWA token
   * @dev    This function will transfer the deposit tokens from the `msg.sender` to this contract
   *         and then deposit them via the `OndoTokenRouter`. The mint or transfer of the RWA token
   *         must be done in the child class.
   */
  function _processSubscription(
    address depositToken,
    uint256 depositAmount,
    uint256 minimumRwaReceived
  ) internal whenSubscribeNotPaused returns (uint256 rwaAmountOut) {
    if (!acceptedSubscriptionTokens[depositToken]) {
      revert TokenNotAccepted();
    }

    // Reverts if user address is not compliant
    ondoCompliance.checkIsCompliant(rwaToken, _msgSender());
    bytes32 userId = ondoIDRegistry.getRegisteredID(rwaToken, _msgSender());
    if (userId == bytes32(0)) revert UserNotRegistered();

    IERC20(depositToken).safeTransferFrom(_msgSender(), address(this), depositAmount);
    IERC20(depositToken).forceApprove(address(ondoTokenRouter), depositAmount);

    ondoTokenRouter.depositToken(rwaToken, depositToken, depositAmount);

    // USD values are normalized to 18 decimals
    uint256 depositUSDValue = (ondoOracle.getAssetPrice(depositToken) * depositAmount) / 10
      ** IERC20Metadata(depositToken).decimals();

    if (depositUSDValue < minimumDepositUSD) revert DepositAmountTooSmall();

    // Fee in USD with 18 decimals
    uint256 fee =
      ondoSubscriptionFees.getAndUpdateFee(rwaToken, depositToken, userId, depositUSDValue);

    if (fee > depositUSDValue) revert FeeGreaterThanSubscription();

    // Prices are returned in 18 decimals, so multiply by the rwa normalizer to get the RWA amount
    rwaAmountOut = ((depositUSDValue - fee) * RWA_NORMALIZER) / _getRwaPrice();

    if (rwaAmountOut < minimumRwaReceived) revert RwaReceiveAmountTooSmall();

    ondoRateLimiter.checkAndUpdateRateLimit(
      IOndoRateLimiter.TransactionType.SUBSCRIPTION, rwaToken, userId, depositUSDValue
    );

    emit Subscription(
      _msgSender(), userId, rwaAmountOut, depositToken, depositAmount, depositUSDValue, fee
    );
  }

  /**
   * @notice Internal function for processing redemptions
   * @param  rwaAmount            The amount of RWA tokens to redeem, in decimals of
   *                              the RWA token
   * @param  receivingToken       The token the user receives
   * @param  minimumTokenReceived The minimum amount of tokens to receive, in
   *                              decimals of `receivingToken`
   * @return receiveTokenAmount   The amount of tokens to sent back to the caller,
   *                              in decimals of `receivingToken`
   * @dev    This function will send tokens to send back to the caller to service redemptions.
   *         The transfer/burn of the RWA itself must be done in the child class.
   */
  function _processRedemption(
    uint256 rwaAmount,
    address receivingToken,
    uint256 minimumTokenReceived
  ) internal whenRedeemNotPaused returns (uint256 receiveTokenAmount) {
    if (!acceptedRedemptionTokens[receivingToken]) revert TokenNotAccepted();

    // Reverts if the user address is not compliant
    ondoCompliance.checkIsCompliant(rwaToken, _msgSender());
    bytes32 userId = ondoIDRegistry.getRegisteredID(rwaToken, _msgSender());
    if (userId == bytes32(0)) revert UserNotRegistered();

    // USD values are normalized to 18 decimals
    uint256 redemptionUSDValue = (_getRwaPrice() * rwaAmount) / RWA_NORMALIZER;
    if (redemptionUSDValue < minimumRedemptionUSD) {
      revert RedemptionAmountTooSmall();
    }

    // Fee is denoted in USD with 18 decimals
    uint256 fee =
      ondoRedemptionFees.getAndUpdateFee(rwaToken, receivingToken, userId, redemptionUSDValue);

    if (fee > redemptionUSDValue) revert FeeGreaterThanRedemption();

    ondoRateLimiter.checkAndUpdateRateLimit(
      IOndoRateLimiter.TransactionType.REDEMPTION, rwaToken, userId, redemptionUSDValue
    );

    // Prices are returned in 18 decimals
    receiveTokenAmount =
      ((redemptionUSDValue - fee) * 10 ** IERC20Metadata(receivingToken).decimals())
        / ondoOracle.getAssetPrice(receivingToken);

    if (receiveTokenAmount < minimumTokenReceived) {
      revert ReceiveAmountTooSmall();
    }

    ondoTokenRouter.withdrawToken(address(rwaToken), receivingToken, userId, receiveTokenAmount);

    IERC20(receivingToken).safeTransfer(_msgSender(), receiveTokenAmount);

    emit Redemption(
      _msgSender(), userId, rwaAmount, receivingToken, receiveTokenAmount, redemptionUSDValue, fee
    );
  }

  /**
   * @notice Admin function to service a subscription whose corresponding deposit been made outside
   *         of this contracts system. This is almost identical to the `_processSubscription`
   *         function, but skips the deposit token transfer and fee calculation (fees are
   *         managed off-chain). The mint and/or transfer itself must be done in the child contract
   *         implementation.
   * @param  recipient The address to send the RWA tokens to
   * @param  rwaAmount The amount of RWA tokens to mint and/or transfer
   * @param  metadata  Additional metadata to emit with the subscription
   */
  function _adminProcessSubscription(address recipient, uint256 rwaAmount, bytes32 metadata)
    internal
    whenSubscribeNotPaused
    onlyRole(ADMIN_SUBSCRIPTION_ROLE)
  {
    // Will revert if the user is not compliant.
    ondoCompliance.checkIsCompliant(rwaToken, recipient);
    bytes32 userId = ondoIDRegistry.getRegisteredID(rwaToken, recipient);
    if (userId == bytes32(0)) revert UserNotRegistered();

    // All USD values are normalized to 18 decimals.
    uint256 depositUSDValue = (rwaAmount * _getRwaPrice()) / RWA_NORMALIZER;

    adminSubscriptionChecker.checkAndUpdateAdminSubscriptionAllowance(_msgSender(), depositUSDValue);
    ondoRateLimiter.checkAndUpdateRateLimit(
      IOndoRateLimiter.TransactionType.SUBSCRIPTION, rwaToken, userId, depositUSDValue
    );
    emit AdminSubscription(_msgSender(), recipient, userId, rwaAmount, depositUSDValue, metadata);
  }

  /**
   * @notice Gets the rwa token price from the oracle
   * @return rwaPrice The price of the RWA token
   */
  function _getRwaPrice() internal view returns (uint256 rwaPrice) {
    rwaPrice = ondoOracle.getAssetPrice(rwaToken);
    if (rwaPrice < minimumRwaPrice) revert RWAPriceTooLow();
  }

  /**
   * @notice Sets whether a token is accepted for subscriptions
   * @param  token    The token address
   * @param  accepted Whether the token is accepted for subscription
   */
  function setAcceptedSubscriptionToken(address token, bool accepted)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    if (token == address(0)) revert TokenAddressCantBeZero();
    // Ensure the oracle supports the token
    if (accepted) ondoOracle.getAssetPrice(token);
    emit AcceptedSubscriptionTokenSet(token, accepted);
    acceptedSubscriptionTokens[token] = accepted;
  }

  /**
   * @notice Sets whether a token is accepted for redemption.
   * @param  token    The token address
   * @param  accepted Whether the token is accepted for redemption
   */
  function setAcceptedRedemptionToken(address token, bool accepted)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    if (token == address(0)) revert TokenAddressCantBeZero();
    // Ensure the oracle supports the token
    if (accepted) ondoOracle.getAssetPrice(token);
    emit AcceptedRedemptionTokenSet(token, accepted);
    acceptedRedemptionTokens[token] = accepted;
  }

  /**
   * @notice Admin function to set the `OndoTokenRouter` contract
   * @param  _ondoTokenRouter The `OndoTokenRouter` contract address
   */
  function setOndoTokenRouter(address _ondoTokenRouter) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_ondoTokenRouter == address(0)) {
      revert RouterAddressCantBeZero();
    }
    emit OndoTokenRouterSet(address(ondoTokenRouter), _ondoTokenRouter);
    ondoTokenRouter = IOndoTokenRouter(_ondoTokenRouter);
  }

  /**
   * @notice Admin function to set the `OndoOracle` contract
   * @param  _ondoOracle The `OndoOracle` contract address
   * @dev    Will revert if new `OndoOracle` contract returns a price lower than the minimum
   *         configured price of the RWA token
   */
  function setOndoOracle(address _ondoOracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_ondoOracle == address(0)) revert OracleAddressCantBeZero();
    emit OndoOracleSet(address(ondoOracle), _ondoOracle);
    ondoOracle = IOndoOracle(_ondoOracle);

    uint256 price = ondoOracle.getAssetPrice(rwaToken);
    if (price < minimumRwaPrice) revert RWAPriceTooLow();
  }

  /**
   * @notice Sets the `OndoCompliance` contract
   * @param  _ondoCompliance The `OndoCompliance` contract address
   */
  function setOndoCompliance(address _ondoCompliance) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_ondoCompliance == address(0)) {
      revert ComplianceAddressCantBeZero();
    }
    emit OndoComplianceSet(address(ondoCompliance), _ondoCompliance);
    ondoCompliance = IOndoCompliance(_ondoCompliance);

    // Ensure that the `OndoCompliance` interface is supported and
    // this contract is compliant
    ondoCompliance.checkIsCompliant(rwaToken, address(this));
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
    ondoIDRegistry.getRegisteredID(rwaToken, address(this));
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
   * @notice Sets the `AdminSubscriptionChecker` contract
   * @param  _adminSubscriptionChecker The `AdminSubscriptionChecker` contract address
   */
  function setAdminSubscriptionChecker(address _adminSubscriptionChecker)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    if (_adminSubscriptionChecker == address(0)) {
      revert AdminSubscriptionCheckerAddressCantBeZero();
    }
    emit AdminSubscriptionCheckerSet(address(adminSubscriptionChecker), _adminSubscriptionChecker);
    adminSubscriptionChecker = IAdminSubscriptionChecker(_adminSubscriptionChecker);
  }

  /**
   * @notice Sets the `OndoFees` contract for subscriptions
   * @param  _ondoSubscriptionFees The `OndoFees` contract address
   */
  function setOndoSubscriptionFees(address _ondoSubscriptionFees)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    if (_ondoSubscriptionFees == address(0)) {
      revert FeesAddressCantBeZero();
    }
    emit OndoSubscriptionFeesSet(address(ondoSubscriptionFees), _ondoSubscriptionFees);
    ondoSubscriptionFees = IOndoFees(_ondoSubscriptionFees);
  }

  /**
   * @notice Sets the `OndoFees` contract for redemptions
   * @param  _ondoRedemptionFees The `OndoFees` contract address
   */
  function setOndoRedemptionFees(address _ondoRedemptionFees)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    if (_ondoRedemptionFees == address(0)) {
      revert FeesAddressCantBeZero();
    }
    emit OndoRedemptionFeesSet(address(ondoRedemptionFees), _ondoRedemptionFees);
    ondoRedemptionFees = IOndoFees(_ondoRedemptionFees);
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
   * @notice Sets the minimum price of RWA token
   * @param  _minimumRwaPrice The minimum price of the RWA token
   */
  function setMinimumRwaPrice(uint256 _minimumRwaPrice) external onlyRole(CONFIGURER_ROLE) {
    emit MinimumRwaPriceSet(minimumRwaPrice, _minimumRwaPrice);
    minimumRwaPrice = _minimumRwaPrice;
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

  /*//////////////////////////////////////////////////////////////
                          Pause/Unpause
  //////////////////////////////////////////////////////////////*/

  /// Pause the subscribe functionality.
  function pauseSubscribe() external onlyRole(PAUSER_ROLE) {
    subscribePaused = true;
    emit SubscribePaused();
  }

  /// Unpause the subscribe functionality.
  function unpauseSubscribe() external onlyRole(DEFAULT_ADMIN_ROLE) {
    subscribePaused = false;
    emit SubscribeUnpaused();
  }

  /// Pause the redeem functionality.
  function pauseRedeem() external onlyRole(PAUSER_ROLE) {
    redeemPaused = true;
    emit RedeemPaused();
  }

  /// Unpause the redeem functionality.
  function unpauseRedeem() external onlyRole(DEFAULT_ADMIN_ROLE) {
    redeemPaused = false;
    emit RedeemUnpaused();
  }

  /// Ensure that the subscribe functionality is not paused
  modifier whenSubscribeNotPaused() {
    if (subscribePaused) revert SubscriptionsPaused();
    _;
  }

  /// Ensure that the redeem functionality is not paused
  modifier whenRedeemNotPaused() {
    if (redeemPaused) revert RedemptionsPaused();
    _;
  }
}
