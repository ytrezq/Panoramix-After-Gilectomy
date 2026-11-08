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
import {
  AccessControlEnumerable
} from "contracts/external/openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {
  ReentrancyGuard
} from "contracts/external/openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "contracts/external/openzeppelin/contracts/token/IERC20.sol";
import {AggregatorV3Interface} from "contracts/external/chainlink/AggregatorV3Interface.sol";
import {IOndoTokenRouterEvents} from "contracts/xManager/tokenRouter/IOndoTokenRouterEvents.sol";
import {IOndoTokenRouterErrors} from "contracts/xManager/tokenRouter/IOndoTokenRouterErrors.sol";
import {SafeERC20} from "contracts/external/openzeppelin/contracts/token/SafeERC20.sol";
import {ITokenSource} from "contracts/xManager/interfaces/ITokenSource.sol";
import {ITokenRecipient} from "contracts/xManager/interfaces/ITokenRecipient.sol";

/**
 * @title  OndoTokenRouter
 * @author Ondo Finance
 * @dev    This contract manages deposits and withdrawals of tokens for Ondo's RWA token platform
 */
contract OndoTokenRouter is
  AccessControlEnumerable,
  ReentrancyGuard,
  IOndoTokenRouter,
  IOndoTokenRouterEvents,
  IOndoTokenRouterErrors
{
  using SafeERC20 for IERC20;

  /**
   * @notice Struct to store user-specific withdrawal token sources
   * @param  active       Whether the user has active withdrawal sources
   * @param  tokenSources The withdrawal sources for the given RWA token and withdraw token for a specific user
   */
  struct UserWithdrawTokenSources {
    bool active;
    ITokenSource[] tokenSources;
  }

  /**
   * @notice Struct to store AggregatorV3 oracle information
   * @param  oracle                         AggregatorV3 oracle address
   * @param  maxAggregatorV3OracleTimeDelay Max time delay in seconds for aggregatorV3 oracle
   */
  struct AggregatorV3OracleInfo {
    AggregatorV3Interface oracle;
    uint256 maxAggregatorV3OracleTimeDelay;
  }

  /// Role identifier allowing RWA managers to deposit and withdraw tokens
  bytes32 public constant RWA_MANAGER_ROLE = keccak256("RWA_MANAGER_ROLE");

  /// Maps RWA token to deposit token and recipient contract
  mapping(address => mapping(address => ITokenRecipient)) public depositTokenRecipient;

  /// Maps RWA token to withdrawal token and source contracts
  mapping(address => mapping(address => ITokenSource[])) public withdrawTokenSources;

  /// Maps RWA token, withdrawal token, and user ID to user-specific withdrawal token sources
  mapping(address => mapping(address => mapping(bytes32 => UserWithdrawTokenSources))) public
    userWithdrawTokenSources;

  /// Minimum token price mapping to prevent depegged tokens from being used
  mapping(address => uint256) public minimumTokenPrice;

  /// Maps token address to a price oracle conforming to the `AggregatorV3Interface`
  mapping(address => AggregatorV3OracleInfo) public tokenToAggregatorV3Oracle;

  /**
   * @param _defaultAdmin Address to assign the DEFAULT_ADMIN_ROLE
   */
  constructor(address _defaultAdmin) {
    _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
  }

  /**
   * @notice Deposits a specified amount of tokens into the contract
   * @param  rwaToken       The RWA token for which the deposit is involved
   * @param  tokenToDeposit The token that is being deposited
   * @param  depositAmount  The amount of tokens to deposit, in the token's native decimals
   * @dev    The `msg.sender` must set the approval for the router to spend the token amount
   */
  function depositToken(address rwaToken, address tokenToDeposit, uint256 depositAmount)
    public
    nonReentrant
    onlyRole(RWA_MANAGER_ROLE)
  {
    _assertTokenMinimumPrice(tokenToDeposit);

    ITokenRecipient tokenRecipient = depositTokenRecipient[rwaToken][tokenToDeposit];
    if (address(tokenRecipient) == address(0)) revert TokenRecipientNotSet();

    // Transfer tokens from the caller (rwaManager) to this contract
    IERC20(tokenToDeposit).safeTransferFrom(msg.sender, address(this), depositAmount);

    IERC20(tokenToDeposit).forceApprove(address(tokenRecipient), depositAmount);
    tokenRecipient.depositToken(tokenToDeposit, depositAmount);

    emit TokenDeposited(rwaToken, tokenToDeposit, depositAmount);
  }

  /**
   * @notice Withdraws a specified amount of tokens from the configured sources
   * @param  rwaTokenRedeemed The RWA token for which the withdrawal is being made
   * @param  tokenToWithdraw  The token that is being withdrawn
   * @param  userID           The ID of the user involved in token withdrawal
   * @param  withdrawAmount   The amount of tokens to be withdrawn, in the token's
   *                          decimals.
   * @dev    The userID causes the function to use the sources configured for the user if there are
   *         any set. Submit bytes32(0) to use the non user specific sources.
   */
  function withdrawToken(
    address rwaTokenRedeemed,
    address tokenToWithdraw,
    bytes32 userID,
    uint256 withdrawAmount
  ) public nonReentrant onlyRole(RWA_MANAGER_ROLE) {
    _assertTokenMinimumPrice(tokenToWithdraw);

    _gatherTokensFromWithdrawalSources(rwaTokenRedeemed, tokenToWithdraw, userID, withdrawAmount);

    IERC20(tokenToWithdraw).safeTransfer(msg.sender, withdrawAmount);

    emit TokenWithdrawn(rwaTokenRedeemed, tokenToWithdraw, withdrawAmount);
  }

  /**
   * @notice Gets the amount of tokens that are available to withdraw
   * @param  rwaToken        Address of the RWA token
   * @param  tokenToWithdraw Address of the token to withdraw
   * @param  userID          The userID to return the available amount for
   * @return totalAvailable  Total amount of tokens available
   * @dev    The userID causes the function to use the sources configured for the user if there are any set.
   *         Submit bytes32(0) to use the non user specific sources.
   *
   */
  function availableToWithdraw(address rwaToken, address tokenToWithdraw, bytes32 userID)
    external
    view
    override
    returns (uint256 totalAvailable)
  {
    ITokenSource[] memory tokenSources;

    if (userWithdrawTokenSources[rwaToken][tokenToWithdraw][userID].active) {
      tokenSources = userWithdrawTokenSources[rwaToken][tokenToWithdraw][userID].tokenSources;
    } else {
      tokenSources = withdrawTokenSources[rwaToken][tokenToWithdraw];
    }

    for (uint256 i = 0; i < tokenSources.length; ++i) {
      totalAvailable += tokenSources[i].availableToWithdraw(tokenToWithdraw);
    }
  }

  /**
   * @notice Returns whether the user has active withdrawal sources for the given RWA token
   *         and token to withdraw.
   * @param  rwaToken       The RWA token for which the user sources are being checked
   * @param  _withdrawToken The withdraw token for which the user sources are being checked
   * @param  userId         The user ID for which the sources are being checked
   * @return active         Whether their are active withdrawal sources for the given parameters
   */
  function getUserWithdrawTokenSourcesActive(
    address rwaToken,
    address _withdrawToken,
    bytes32 userId
  ) external view returns (bool active) {
    return userWithdrawTokenSources[rwaToken][_withdrawToken][userId].active;
  }

  /**
   * @notice Returns the withdraw sources for the given RWA token and withdraw token for a user
   * @param  rwaToken       The RWA token for which the user sources are being checked
   * @param  _withdrawToken The withdraw token for which the user sources are being checked
   * @param  userId         The user ID for which the sources are being checked
   * @return tokenSources   The withdraw sources for the given RWA token and withdraw token for a specific user
   */
  function getUserWithdrawTokenSources(address rwaToken, address _withdrawToken, bytes32 userId)
    external
    view
    returns (ITokenSource[] memory tokenSources)
  {
    return userWithdrawTokenSources[rwaToken][_withdrawToken][userId].tokenSources;
  }

  /**
   * @notice Gathers tokens from the available token sources
   * @param  rwaToken                The RWA token involved in the withdraw
   * @param  outputToken             The token that the caller expects to receive
   * @param  requestedWithdrawAmount The amount of outputToken that the caller expects to receive
   * @dev    Reverts if there are not enough tokens available from the sources
   */
  function _gatherTokensFromWithdrawalSources(
    address rwaToken,
    address outputToken,
    bytes32 userID,
    uint256 requestedWithdrawAmount
  ) internal {
    ITokenSource[] memory tokenSources;
    if (userWithdrawTokenSources[rwaToken][outputToken][userID].active) {
      tokenSources = userWithdrawTokenSources[rwaToken][outputToken][userID].tokenSources;
    } else {
      tokenSources = withdrawTokenSources[rwaToken][outputToken];
    }

    for (uint256 i = 0; i < tokenSources.length; ++i) {
      ITokenSource tokenSource = tokenSources[i];

      uint256 amountAvailable = tokenSource.availableToWithdraw(outputToken);

      uint256 withdrawAmount =
        amountAvailable > requestedWithdrawAmount ? requestedWithdrawAmount : amountAvailable;

      if (withdrawAmount == 0) continue;

      // INVARIANT - `TokenSource.withdrawToken` will always withdraw the amount requested
      // or revert.
      tokenSource.withdrawToken(outputToken, withdrawAmount);

      requestedWithdrawAmount -= withdrawAmount;

      if (requestedWithdrawAmount == 0) break;
    }
    if (requestedWithdrawAmount != 0) revert InsufficientWithdrawTokens();
  }

  /**
   *  @notice Sets the array of withdrawal token sources for a given RWA token and withdrawal token
   *  @param  rwaToken              The RWA token for which the source is responsible for
   *  @param  _withdrawToken        The token that the source will be withdrawing
   *  @param  _withdrawTokenSources The source contracts that will be used to withdraw
   */
  function setWithdrawTokenSources(
    address rwaToken,
    address _withdrawToken,
    ITokenSource[] memory _withdrawTokenSources
  ) public onlyRole(DEFAULT_ADMIN_ROLE) {
    if (rwaToken == address(0)) {
      revert RwaTokenCantBeZero();
    }
    if (_withdrawToken == address(0)) revert WithdrawTokenCantBeZero();
    emit TokenWithdrawSourcesSet(
      rwaToken,
      _withdrawToken,
      withdrawTokenSources[rwaToken][_withdrawToken],
      _withdrawTokenSources
    );

    withdrawTokenSources[rwaToken][_withdrawToken] = _withdrawTokenSources;
  }

  /**
   * @notice Sets the array of withdrawal token sources for a given RWA token and withdrawal token
   *         for a specific user.
   * @param  rwaToken              The RWA token for which the source is responsible for
   * @param  _withdrawToken        The token that the source will be withdrawing
   * @param  userID                The ID of the user to set sources for
   * @param  active                Whether the new user sources are active
   * @param  _withdrawTokenSources The source contracts that will be used to withdraw
   */
  function setUserWithdrawTokenSources(
    address rwaToken,
    address _withdrawToken,
    bytes32 userID,
    bool active,
    ITokenSource[] memory _withdrawTokenSources
  ) public onlyRole(DEFAULT_ADMIN_ROLE) {
    if (rwaToken == address(0)) {
      revert RwaTokenCantBeZero();
    }
    if (_withdrawToken == address(0)) revert WithdrawTokenCantBeZero();
    if (userID == bytes32(0)) revert UserIDCantBeZero();

    emit UserTokenWithdrawSourcesSet(
      rwaToken,
      _withdrawToken,
      userID,
      active,
      userWithdrawTokenSources[rwaToken][_withdrawToken][userID].tokenSources,
      _withdrawTokenSources
    );

    userWithdrawTokenSources[rwaToken][_withdrawToken][userID] =
      UserWithdrawTokenSources({active: active, tokenSources: _withdrawTokenSources});
  }

  /**
   * @notice Set the minimum price and oracle for a token
   * @param  token                          The token address
   * @param  _minimumTokenPrice             The minimum price for the token, denoted in USD with
   *                                        the oracles decimals
   * @param  aggregatorV3Oracle             The token price oracle address
   * @param  maxAggregatorV3OracleTimeDelay The maximum time delay for the oracle
   * @dev    Reverts if any of the parameters are set to zero without nullifying all the others
   *         except for the token address
   */
  function setMinimumTokenPriceAndOracle(
    address token,
    uint256 _minimumTokenPrice,
    address aggregatorV3Oracle,
    uint256 maxAggregatorV3OracleTimeDelay
  ) public onlyRole(DEFAULT_ADMIN_ROLE) {
    if (token == address(0)) revert TokenAddressCantBeZero();

    // Ensure that either all parameters are set to zero or all are set to non-zero values
    if (!(((_minimumTokenPrice == 0)
            && (aggregatorV3Oracle == address(0))
            && (maxAggregatorV3OracleTimeDelay == 0))
          || ((_minimumTokenPrice != 0)
            && (aggregatorV3Oracle != address(0))
            && (maxAggregatorV3OracleTimeDelay != 0)))) revert InconsistentMinimumTokenPriceParameters();

    minimumTokenPrice[token] = _minimumTokenPrice;
    tokenToAggregatorV3Oracle[token].oracle = AggregatorV3Interface(aggregatorV3Oracle);
    tokenToAggregatorV3Oracle[token].maxAggregatorV3OracleTimeDelay = maxAggregatorV3OracleTimeDelay;

    // Ensure that the token price check works as expected
    _assertTokenMinimumPrice(token);

    emit MinimumTokenPriceAndOracleSet(
      token, _minimumTokenPrice, aggregatorV3Oracle, maxAggregatorV3OracleTimeDelay
    );
  }

  /**
   * @notice Asserts that the token price is above the configured minimum price
   * @param token The token address
   */
  function _assertTokenMinimumPrice(address token) internal view {
    // If the minimum price is not set then we don't need to check the minimum price.
    if (minimumTokenPrice[token] == 0) return;

    // If this check is active, then the oracle must be up to date and the price must be above the minimum.
    (, int256 price,, uint256 updatedAt,) =
      tokenToAggregatorV3Oracle[token].oracle.latestRoundData();
    if (
      updatedAt < block.timestamp - tokenToAggregatorV3Oracle[token].maxAggregatorV3OracleTimeDelay
    ) revert OraclePriceOutdated();

    if (price < 0) revert TokenPriceBelowMinimum();
    // forge-lint: disable-next-line(unsafe-typecast)
    if (uint256(price) < minimumTokenPrice[token]) {
      revert TokenPriceBelowMinimum();
    }
  }

  /**
   * @notice Add a new token recipient for depositing liquidity
   * @param  rwaToken               The RWA token for which the liquidity is being added
   * @param  _depositToken          The token that the recipient expects to receive
   * @param  _depositTokenRecipient The token recipient contract
   */
  function setDepositTokenRecipient(
    address rwaToken,
    address _depositToken,
    ITokenRecipient _depositTokenRecipient
  ) public onlyRole(DEFAULT_ADMIN_ROLE) {
    if (rwaToken == address(0)) revert RwaTokenCantBeZero();
    if (_depositToken == address(0)) revert DepositTokenCantBeZero();
    emit TokenDepositRecipientSet(
      rwaToken,
      _depositToken,
      depositTokenRecipient[rwaToken][_depositToken],
      _depositTokenRecipient
    );

    depositTokenRecipient[rwaToken][_depositToken] = _depositTokenRecipient;
  }
}
