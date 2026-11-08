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

import {BaseRWAManager} from "contracts/xManager/rwaManagers/BaseRWAManager.sol";
import {IRWALike} from "contracts/interfaces/IRWALike.sol";
import {rUSDY} from "contracts/usdy/rusdy/rUSDY.sol";
import {
  IUSDY_InstantManager
} from "contracts/xManager/interfaces/usdyInstantManagerRusdy/IUSDY_InstantManager.sol";

/**
 * @title  USDY_InstantManager
 * @author Ondo Finance
 * @notice This contract manages instant subscriptions and redemptions of USDY and rUSDY tokens,
 *         with support for conversion between USDY and rUSDY.
 *
 *         This contract allows for:
 *         - Users to instantly subscribe to USDY or rUSDY by depositing supported tokens
 *         - Users to redeem USDY or rUSDY back to supported tokens
 *         - An admin to execute manual subscriptions for specialized use cases
 */
contract USDY_InstantManager is BaseRWAManager, IUSDY_InstantManager {
  /// The rebasing USDY token contract
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  rUSDY public immutable rusdy;

  /// Helper constant for converting between USDY tokens and rUSDY shares
  uint256 public constant USDY_TO_RUSDY_SHARES_MULTIPLIER = 10_000;

  /**
   * @notice Event emitted when a user mints rUSDY
   * @param  recipient      Address of the recipient
   * @param  usdyAmountOut  Amount of USDY wrapped for the user
   * @param  rusdyAmountOut Amount of rUSDY sent to user
   * @param  depositToken   Address of the token deposited
   * @param  depositAmount  Amount of tokens deposited, denoted in decimals of `depositToken`
   */
  event InstantSubscriptionRebasingUSDY(
    address indexed recipient,
    uint256 usdyAmountOut,
    uint256 rusdyAmountOut,
    address depositToken,
    uint256 depositAmount
  );

  /**
   * @notice Event emitted when a user redeems rUSDY
   * @param  redeemer           Address of the redeemer
   * @param  usdyAmountIn       Amount of USDY unwrapped for the user
   * @param  rusdyAmountIn      Amount of the rUSDY burned for the redemption
   * @param  receivingToken     Address of the token received
   * @param  receiveTokenAmount Amount of tokens received, denoted in decimals of `receivingToken`
   */
  event InstantRedemptionRebasingUSDY(
    address indexed redeemer,
    uint256 usdyAmountIn,
    uint256 rusdyAmountIn,
    address receivingToken,
    uint256 receiveTokenAmount
  );

  /**
   * @notice Event emitted when an admin mints rUSDY
   * @param  recipient   Address of the recipient
   * @param  usdyAmount  Amount of USDY wrapped for the user
   * @param  rusdyAmount Amount of rUSDY sent to recipient
   * @param  metadata    Metadata for the subscription
   */
  event AdminSubscriptionRebasingUSDY(
    address indexed recipient, uint256 usdyAmount, uint256 rusdyAmount, bytes32 metadata
  );

  /// Error emitted when setting the rUSDY address to the zero address
  error RebasingUSDYCantBeZeroAddress();

  /**
   * @param _defaultAdmin            The default admin address
   * @param _rwaToken                The USDY token address
   * @param _rusdy                   The rUSDY token address
   * @param _minimumDepositAmount    The minimum deposit amount
   * @param _minimumRedemptionAmount The minimum redemption amount
   */
  constructor(
    address _defaultAdmin,
    address _rwaToken,
    address _rusdy,
    uint256 _minimumDepositAmount,
    uint256 _minimumRedemptionAmount
  ) BaseRWAManager(_defaultAdmin, _rwaToken, _minimumDepositAmount, _minimumRedemptionAmount) {
    if (_rusdy == address(0)) revert RebasingUSDYCantBeZeroAddress();
    rusdy = rUSDY(_rusdy);
  }

  /**
   * @notice Subscribes to the RWA using the specified deposit token and amount
   * @param  depositToken       The address of the token to be deposited
   * @param  depositAmount      The amount of the deposit token to be deposited, expected to be in
   *                            decimals of `depositToken`
   * @param  minimumRwaReceived The minimum amount of RWA to be received from the subscription,
   *                            expected to be in decimals of the RWA token
   * @return rwaAmountOut       The amount of RWA received from the subscription, expected to be in
   *                            decimals of the RWA token
   */
  function subscribe(address depositToken, uint256 depositAmount, uint256 minimumRwaReceived)
    external
    nonReentrant
    returns (uint256 rwaAmountOut)
  {
    rwaAmountOut = _processSubscription(depositToken, depositAmount, minimumRwaReceived);
    IRWALike(rwaToken).mint(_msgSender(), rwaAmountOut);
  }

  /**
   * @notice Subscribes to rUSDY. This works similar to `subscribe`, but
   *         wraps the USDY into rUSDY before transferring to the user.
   * @param  depositToken         The token to deposit
   * @param  depositAmount        Amount of tokens to deposit, denoted in decimals of the
   *                              `depositToken`
   * @param  minimumRusdyReceived Minimum amount of rUSDY to receive
   * @return rusdyAmountOut       Amount of rUSDY received, in decimals of rUSDY
   */
  function subscribeRebasingUSDY(
    address depositToken,
    uint256 depositAmount,
    uint256 minimumRusdyReceived
  ) external nonReentrant returns (uint256 rusdyAmountOut) {
    uint256 minimumOusgAmount = rusdy.getSharesByRUSDY(minimumRusdyReceived)
    / USDY_TO_RUSDY_SHARES_MULTIPLIER;
    uint256 usdyAmountOut = _processSubscription(depositToken, depositAmount, minimumOusgAmount);

    IRWALike(rwaToken).mint(address(this), usdyAmountOut);
    IRWALike(rwaToken).approve(address(rusdy), usdyAmountOut);
    rusdy.wrap(usdyAmountOut);
    rusdyAmountOut =
      rusdy.transferShares(_msgSender(), usdyAmountOut * USDY_TO_RUSDY_SHARES_MULTIPLIER);

    // Verify rUSDY amount received directly, avoiding precision loss from checking USDY values
    // in `_processSubscription`
    if (rusdyAmountOut < minimumRusdyReceived) {
      revert RwaReceiveAmountTooSmall();
    }

    emit InstantSubscriptionRebasingUSDY(
      _msgSender(), usdyAmountOut, rusdyAmountOut, depositToken, depositAmount
    );
  }

  /**
   * @notice Allows an admin to subscribe on behalf of a recipient with the specified RWA amount
   *         and metadata
   * @param  recipient The address of the recipient
   * @param  rwaAmount The amount of RWA to be subscribed, expected to be in decimals of the RWA
   *                   token
   * @param  metadata  Additional metadata associated with the subscription
   */
  function adminSubscribe(address recipient, uint256 rwaAmount, bytes32 metadata)
    external
    nonReentrant
  {
    _adminProcessSubscription(recipient, rwaAmount, metadata);
    IRWALike(rwaToken).mint(recipient, rwaAmount);
  }

  /**
   * @notice Performs an admin subscription to rUSDY. This works similar to
   *         `adminSubscribe`, but wraps the USDY to rUSDY before transferring the tokens
   *         to the user.
   * @param  recipient    Recipient of the rUSDY
   * @param  rusdyAmount  Amount of rUSDY to send, in decimals of rUSDY
   * @param  metadata     Metadata for the subscription
   */
  function adminSubscribeRebasingUSDY(address recipient, uint256 rusdyAmount, bytes32 metadata)
    external
    nonReentrant
  {
    uint256 usdyAmount = rusdy.getSharesByRUSDY(rusdyAmount) / USDY_TO_RUSDY_SHARES_MULTIPLIER;
    _adminProcessSubscription(recipient, usdyAmount, metadata);
    IRWALike(rwaToken).mint(address(this), usdyAmount);
    IRWALike(rwaToken).approve(address(rusdy), usdyAmount);
    rusdy.wrap(usdyAmount);
    rusdy.transferShares(recipient, usdyAmount * USDY_TO_RUSDY_SHARES_MULTIPLIER);

    emit AdminSubscriptionRebasingUSDY(recipient, usdyAmount, rusdyAmount, metadata);
  }

  /**
   * @notice Redeems the specified amount of RWA for the receiving token
   * @param  rwaAmount            The amount of RWA to be redeemed, expected to be in decimals of
   *                              the RWA token
   * @param  receivingToken       The address of the token to receive
   * @param  minimumTokenReceived The minimum amount of the receiving token to be received,
   *                              expected to be in decimals of `receivingToken`
   * @return receiveTokenAmount   The amount of the token received from the redemption, expected
   *                              to be in decimals of the `receivingToken`
   */
  function redeem(uint256 rwaAmount, address receivingToken, uint256 minimumTokenReceived)
    external
    nonReentrant
    returns (uint256 receiveTokenAmount)
  {
    // forge-lint: disable-next-line(erc20-unchecked-transfer)
    IRWALike(rwaToken).transferFrom(_msgSender(), address(this), rwaAmount);
    IRWALike(rwaToken).burn(rwaAmount);

    receiveTokenAmount = _processRedemption(rwaAmount, receivingToken, minimumTokenReceived);
  }

  /**
   * @notice Performs a rUSDY redemption. This works similar to `redeem`, but
   *         unwraps the rUSDY to USDY before processing the redemption.
   * @param  rusdyAmount            Amount of rUSDY to redeem
   * @param  receivingToken         Token to receive
   * @param  minimumTokenReceived   Minimum amount of tokens to receive, denoted in decimals of
   *                                `receivingToken`
   * @return receiveTokenAmount     Amount of tokens received, denoted in decimals of
   *                                `receivingToken`
   */
  function redeemRebasingUSDY(
    uint256 rusdyAmount,
    address receivingToken,
    uint256 minimumTokenReceived
  ) external nonReentrant returns (uint256 receiveTokenAmount) {
    // forge-lint: disable-next-line(erc20-unchecked-transfer)
    rusdy.transferFrom(_msgSender(), address(this), rusdyAmount);
    rusdy.unwrap(rusdyAmount);
    uint256 usdyAmountIn = rusdy.getSharesByRUSDY(rusdyAmount) / USDY_TO_RUSDY_SHARES_MULTIPLIER;
    IRWALike(rwaToken).burn(usdyAmountIn);
    receiveTokenAmount = _processRedemption(usdyAmountIn, receivingToken, minimumTokenReceived);
    emit InstantRedemptionRebasingUSDY(
      _msgSender(), usdyAmountIn, rusdyAmount, receivingToken, receiveTokenAmount
    );
  }
}
