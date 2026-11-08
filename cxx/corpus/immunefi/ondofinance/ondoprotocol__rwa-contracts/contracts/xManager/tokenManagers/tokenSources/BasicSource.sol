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

import {BaseTokenSource} from "contracts/xManager/tokenManagers/tokenSources/BaseTokenSource.sol";
import {IERC20} from "contracts/external/openzeppelin/contracts/token/IERC20.sol";
import {SafeERC20} from "contracts/external/openzeppelin/contracts/token/SafeERC20.sol";
import {PauseManagerClient} from "contracts/xManager/tokenManagers/PauseManagerClient.sol";

/**
 * @title  BasicSource
 * @author Ondo Finance
 * @notice This contract facilitates token withdraws from a designated address and provides
 *         an interface to check the available withdrawal amount.
 * @dev    Implements access control for withdrawers and integrates with a pause manager
 */
contract BasicSource is BaseTokenSource {
  using SafeERC20 for IERC20;
  /// Address from which tokens are withdrawn
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  address public immutable withdrawAddress;

  /// Address of the token managed by this contract
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  address public immutable tokenAddress;

  /**
   * @param  _defaultAdmin    Address granted the admin role
   * @param  _withdrawAddress Address from which tokens are withdrawn
   * @param  _tokenAddress    Address of the ERC20 token managed by this contract
   * @param  _pauseManager    Address of the pause manager contract
   * @dev    The `_withdrawAddress` and `_tokenAddress` must be valid, non-zero addresses
   */
  constructor(
    address _defaultAdmin,
    address _withdrawAddress,
    address _tokenAddress,
    address _pauseManager
  ) PauseManagerClient(_pauseManager) {
    _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);

    // Ensure the withdraw and token addresses are non-zero
    if (_withdrawAddress == address(0)) revert ZeroAddressNotAllowed();
    if (_tokenAddress == address(0)) revert ZeroAddressNotAllowed();

    withdrawAddress = _withdrawAddress;
    tokenAddress = _tokenAddress;
  }

  /**
   * @notice Withdraws a specified amount of tokens from the designated withdraw address
   * @param  withdrawTokenAddress    Address of the token to withdraw
   * @param  requestedWithdrawAmount Amount of tokens to withdraw, denominated in the token's
   *                                 decimals
   * @dev    The caller must have the `WITHDRAWER_ROLE` and the contract must not be paused.
   *         The token address must match the managed token address, and the requested amount
   *         must not exceed the available balance.
   *         Reverts if:
   *          - `withdrawTokenAddress` is not the managed token address.
   *          - Insufficient tokens are available for withdrawal.
   */
  function withdrawToken(address withdrawTokenAddress, uint256 requestedWithdrawAmount)
    external
    override
    onlyRole(WITHDRAWER_ROLE)
    whenSourceNotPaused
  {
    // Validate the token address
    if (withdrawTokenAddress != tokenAddress) {
      revert InvalidTokenAddressForTokenSource();
    }

    // Transfer tokens from the withdraw address to the caller
    IERC20(withdrawTokenAddress)
      .safeTransferFrom(withdrawAddress, msg.sender, requestedWithdrawAmount);

    emit TokensWithdrawn(msg.sender, withdrawAddress, withdrawTokenAddress, requestedWithdrawAmount);
  }

  /**
   * @notice Returns the amount of tokens available for withdrawal
   * @param  tokenToWithdraw Address of the token to check
   * @return The amount of tokens available for withdrawal
   * @dev    The token address must match the managed token address. The available amount is the
   *         lesser of the token allowance and balance. Reverts if `tokenToWithdraw` is not the
   *         managed token address.
   */
  function availableToWithdraw(address tokenToWithdraw) public view override returns (uint256) {
    // Validate the token address
    if (tokenToWithdraw != tokenAddress) {
      revert InvalidTokenAddressForTokenSource();
    }
    // If this source is paused, 0 tokens are available for withdrawal.
    // We don't revert so other sources can still be queried.
    if (pauseManager.isTokenSourcePaused(address(this))) return 0;

    // Retrieve the token allowance and balance for the withdraw address
    uint256 allowance = IERC20(tokenToWithdraw).allowance(withdrawAddress, address(this));
    uint256 balance = IERC20(tokenToWithdraw).balanceOf(withdrawAddress);

    // Return the lesser of allowance and balance
    return allowance < balance ? allowance : balance;
  }
}
