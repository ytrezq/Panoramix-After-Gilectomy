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
import {IUSDonManager} from "contracts/globalMarkets/USDonManager/IUSDonManager.sol";
import {IERC20} from "contracts/external/openzeppelin/contracts/token/IERC20.sol";
import {SafeERC20} from "contracts/external/openzeppelin/contracts/token/SafeERC20.sol";

/**
 * @title  USDonManager
 * @author Ondo Finance
 * @notice This contract manages instant USDon swaps for users.
 */
contract USDonManager is BaseRWAManager, IUSDonManager {
  using SafeERC20 for IERC20;

  /**
   * @param _defaultAdmin            The default admin address
   * @param _rwaToken                The USDon token address
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
    override
    nonReentrant
    returns (uint256 rwaAmountOut)
  {
    rwaAmountOut = _processSubscription(depositToken, depositAmount, minimumRwaReceived);

    // Withdraw USDon and send to the user
    ondoTokenRouter.withdrawToken(
      address(rwaToken),
      address(rwaToken),
      // We don't need additional checks here since the id is validated in _processSubscription
      ondoIDRegistry.getRegisteredID(rwaToken, _msgSender()),
      rwaAmountOut
    );
    IERC20(rwaToken).safeTransfer(_msgSender(), rwaAmountOut);
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
    override
    nonReentrant
    returns (uint256 receiveTokenAmount)
  {
    // Deposit the USDon into the ondoTokenRouter
    IERC20(rwaToken).safeTransferFrom(_msgSender(), address(this), rwaAmount);
    IERC20(rwaToken).forceApprove(address(ondoTokenRouter), rwaAmount);
    ondoTokenRouter.depositToken(rwaToken, rwaToken, rwaAmount);

    receiveTokenAmount = _processRedemption(rwaAmount, receivingToken, minimumTokenReceived);
  }
}
