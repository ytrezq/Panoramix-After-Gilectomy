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
import {
  IUSDY_InstantManager
} from "contracts/xManager/interfaces/usdyInstantManager/IUSDY_InstantManager.sol";

/**
 * @title  USDY_InstantManager
 * @author Ondo Finance
 * @notice This contract manages instant subscriptions and redemptions of USDY tokens.
 *
 *         This contract allows for:
 *         - Users to instantly subscribe to USDY by depositing supported tokens
 *         - Users to redeem USDY back to supported tokens
 *         - An admin to execute manual subscriptions for specialized use cases
 */
contract USDY_InstantManager is BaseRWAManager, IUSDY_InstantManager {
  /**
   * @param _defaultAdmin            The default admin address
   * @param _rwaToken                The USDY token address
   * @param _minimumDepositAmount    The minimum deposit amount
   * @param _minimumRedemptionAmount The minimum redemption amount
   */
  constructor(
    address _defaultAdmin,
    address _rwaToken,
    uint256 _minimumDepositAmount,
    uint256 _minimumRedemptionAmount
  ) BaseRWAManager(_defaultAdmin, _rwaToken, _minimumDepositAmount, _minimumRedemptionAmount) {}

  /**
   * @notice Subscribes to USDY using the specified deposit token and amount
   * @param  depositToken       The address of the token to be deposited
   * @param  depositAmount      The amount of the deposit token to be deposited, expected to be in
   *                            decimals of `depositToken`
   * @param  minimumRwaReceived The minimum amount of USDY to be received from the subscription,
   *                            expected to be in decimals of the USDY token
   * @return rwaAmountOut       The amount of USDY received from the subscription, expected to be
   *                            in decimals of the USDY token
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
   * @notice Allows an admin to subscribe on behalf of a recipient with the specified USDY amount
   *         and metadata
   * @param  recipient The address of the recipient
   * @param  rwaAmount The amount of USDY to be subscribed, expected to be in decimals of the USDY
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
   * @notice Redeems the specified amount of USDY for the receiving token
   * @param  rwaAmount            The amount of USDY to be redeemed, expected to be in decimals of
   *                              the USDY token
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
}
