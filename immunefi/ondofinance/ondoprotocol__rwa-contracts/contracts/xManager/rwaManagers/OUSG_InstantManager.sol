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
import {ROUSG} from "contracts/ousg/rOUSG.sol";
import {IOUSG_InstantManager} from "contracts/xManager/interfaces/IOUSG_InstantManager.sol";

/**
 * @title  OUSG_InstantManager
 * @author Ondo Finance
 * @notice This contract manages instant subscriptions and redemptions of OUSG and rOUSG tokens,
 *         with support for conversion between OUSG and rOUSG.
 *
 *         This contract allows for:
 *         - Users to instantly subscribe to OUSG or rOUSG by depositing supported tokens
 *         - Users to redeem OUSG or rOUSG back to supported tokens
 *         - An admin to execute manual subscriptions for specialized use cases
 */
contract OUSG_InstantManager is BaseRWAManager, IOUSG_InstantManager {
  /// The rebasing OUSG token contract
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  ROUSG public immutable rousg;

  /// Helper constant for converting between OUSG tokens and rOUSG shares
  uint256 public constant OUSG_TO_ROUSG_SHARES_MULTIPLIER = 10_000;

  /**
   * @notice Event emitted when a user mints rOUSG
   * @param  recipient      Address of the recipient
   * @param  ousgAmountOut  Amount of OUSG wrapped for the user
   * @param  rousgAmountOut Amount of rOUSG sent to user
   * @param  depositToken   Address of the token deposited
   * @param  depositAmount  Amount of tokens deposited, denoted in decimals of `depositToken`
   */
  event InstantSubscriptionRebasingOUSG(
    address indexed recipient,
    uint256 ousgAmountOut,
    uint256 rousgAmountOut,
    address depositToken,
    uint256 depositAmount
  );

  /**
   * @notice Event emitted when a user redeems rOUSG
   * @param  redeemer           Address of the redeemer
   * @param  ousgAmountIn       Amount of OUSG unwrapped for the user
   * @param  rousgAmountIn      Amount of the rOUSG burned for the redemption
   * @param  receivingToken     Address of the token received
   * @param  receiveTokenAmount Amount of tokens received, denoted in decimals of `receivingToken`
   */
  event InstantRedemptionRebasingOUSG(
    address indexed redeemer,
    uint256 ousgAmountIn,
    uint256 rousgAmountIn,
    address receivingToken,
    uint256 receiveTokenAmount
  );

  /**
   * @notice Event emitted when an admin mints rOUSG
   * @param  recipient   Address of the recipient
   * @param  ousgAmount  Amount of OUSG wrapped for the user
   * @param  rousgAmount Amount of rOUSG sent to recipient
   * @param  metadata    Metadata for the subscription
   */
  event AdminSubscriptionRebasingOUSG(
    address indexed recipient, uint256 ousgAmount, uint256 rousgAmount, bytes32 metadata
  );

  /// Error emitted when setting the rOUSG address to the zero address
  error RebasingOUSGCantBeZeroAddress();

  /**
   * @param _defaultAdmin            The default admin address
   * @param _rwaToken                The OUSG token address
   * @param _rousg                   The rOUSG token address
   * @param _minimumDepositAmount    The minimum deposit amount
   * @param _minimumRedemptionAmount The minimum redemption amount
   */
  constructor(
    address _defaultAdmin,
    address _rwaToken,
    address _rousg,
    uint256 _minimumDepositAmount,
    uint256 _minimumRedemptionAmount
  ) BaseRWAManager(_defaultAdmin, _rwaToken, _minimumDepositAmount, _minimumRedemptionAmount) {
    if (_rousg == address(0)) revert RebasingOUSGCantBeZeroAddress();
    rousg = ROUSG(_rousg);
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
   * @notice Subscribes to rOUSG. This works similar to `subscribe`, but
   *         wraps the OUSG into rOUSG before transferring to the user.
   * @param  depositToken         The token to deposit
   * @param  depositAmount        Amount of tokens to deposit, denoted in decimals of the
   *                              `depositToken`
   * @param  minimumRousgReceived Minimum amount of rOUSG to receive
   * @return rousgAmountOut       Amount of rOUSG received, in decimals of rOUSG
   */
  function subscribeRebasingOUSG(
    address depositToken,
    uint256 depositAmount,
    uint256 minimumRousgReceived
  ) external nonReentrant returns (uint256 rousgAmountOut) {
    uint256 minimumOusgAmount = rousg.getSharesByROUSG(minimumRousgReceived)
    / OUSG_TO_ROUSG_SHARES_MULTIPLIER;
    uint256 ousgAmountOut = _processSubscription(depositToken, depositAmount, minimumOusgAmount);

    IRWALike(rwaToken).mint(address(this), ousgAmountOut);
    IRWALike(rwaToken).approve(address(rousg), ousgAmountOut);
    rousg.wrap(ousgAmountOut);
    rousgAmountOut =
      rousg.transferShares(_msgSender(), ousgAmountOut * OUSG_TO_ROUSG_SHARES_MULTIPLIER);

    // Verify rOUSG amount received directly, avoiding precision loss from checking OUSG values
    // in `_processSubscription`
    if (rousgAmountOut < minimumRousgReceived) {
      revert RwaReceiveAmountTooSmall();
    }

    emit InstantSubscriptionRebasingOUSG(
      _msgSender(), ousgAmountOut, rousgAmountOut, depositToken, depositAmount
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
   * @notice Performs an admin subscription to rOUSG. This works similar to
   *         `adminSubscribe`, but wraps the OUSG to rOUSG before transferring the tokens
   *         to the user.
   * @param  recipient    Recipient of the rOUSG
   * @param  rousgAmount  Amount of rOUSG to send, in decimals of rOUSG
   * @param  metadata     Metadata for the subscription
   */
  function adminSubscribeRebasingOUSG(address recipient, uint256 rousgAmount, bytes32 metadata)
    external
    nonReentrant
  {
    uint256 ousgAmount = rousg.getSharesByROUSG(rousgAmount) / OUSG_TO_ROUSG_SHARES_MULTIPLIER;
    _adminProcessSubscription(recipient, ousgAmount, metadata);
    IRWALike(rwaToken).mint(address(this), ousgAmount);
    IRWALike(rwaToken).approve(address(rousg), ousgAmount);
    rousg.wrap(ousgAmount);
    rousg.transferShares(recipient, ousgAmount * OUSG_TO_ROUSG_SHARES_MULTIPLIER);

    emit AdminSubscriptionRebasingOUSG(recipient, ousgAmount, rousgAmount, metadata);
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
   * @notice Performs a rOUSG redemption. This works similar to `redeem`, but
   *         unwraps the rOUSG to OUSG before processing the redemption.
   * @param  rousgAmount            Amount of rOUSG to redeem
   * @param  receivingToken         Token to receive
   * @param  minimumTokenReceived   Minimum amount of tokens to receive, denoted in decimals of
   *                                `receivingToken`
   * @return receiveTokenAmount     Amount of tokens received, denoted in decimals of
   *                                `receivingToken`
   */
  function redeemRebasingOUSG(
    uint256 rousgAmount,
    address receivingToken,
    uint256 minimumTokenReceived
  ) external nonReentrant returns (uint256 receiveTokenAmount) {
    // forge-lint: disable-next-line(erc20-unchecked-transfer)
    rousg.transferFrom(_msgSender(), address(this), rousgAmount);
    rousg.unwrap(rousgAmount);
    uint256 ousgAmountIn = rousg.getSharesByROUSG(rousgAmount) / OUSG_TO_ROUSG_SHARES_MULTIPLIER;
    IRWALike(rwaToken).burn(ousgAmountIn);
    receiveTokenAmount = _processRedemption(ousgAmountIn, receivingToken, minimumTokenReceived);
    emit InstantRedemptionRebasingOUSG(
      _msgSender(), ousgAmountIn, rousgAmount, receivingToken, receiveTokenAmount
    );
  }
}
