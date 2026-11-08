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
  BaseTokenRecipient
} from "contracts/xManager/tokenManagers/tokenRecipients/BaseTokenRecipient.sol";
import {IERC20} from "contracts/external/openzeppelin/contracts/token/IERC20.sol";
import {SafeERC20} from "contracts/external/openzeppelin/contracts/token/SafeERC20.sol";
import {PauseManagerClient} from "contracts/xManager/tokenManagers/PauseManagerClient.sol";

/**
 * @title  BasicRecipient
 * @author Ondo Finance
 * @notice This contract handles the deposit of ERC20 tokens to a predefined address.
 * @dev    Implements access control for depositors and integrates with a pause manager
 */
contract BasicRecipient is BaseTokenRecipient {
  using SafeERC20 for IERC20;
  /// The address to which tokens are deposited.
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  address public immutable depositAddress;

  /**
   * @param  _defaultAdmin   Address granted the admin role
   * @param  _depositAddress Address to receive deposited tokens
   * @param  _pauseManager   Address of the pause manager contract
   * @dev    The `_depositAddress` must be a non-zero address
   */
  constructor(address _defaultAdmin, address _depositAddress, address _pauseManager)
    PauseManagerClient(_pauseManager)
  {
    // Set the default admin role
    _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);

    // Ensure the deposit address is valid
    if (_depositAddress == address(0)) revert ZeroAddressNotAllowed();

    depositAddress = _depositAddress;
  }

  /**
   * @notice Deposits a specified amount of tokens to the designated deposit address
   * @param  depositTokenAddress Address of the ERC20 token to deposit
   * @param  depositAmount       Amount of tokens to deposit, denominated in decimals of the token
   * @dev    The caller must have the `DEPOSITOR_ROLE` and provide sufficient allowance for the
   *         transfer, otherwise it reverts. This function is restricted by the
   *         `whenRecipientNotPaused` modifier to ensure operations can be paused appropriately.
   */
  function depositToken(address depositTokenAddress, uint256 depositAmount)
    external
    override
    onlyRole(DEPOSITOR_ROLE)
    whenRecipientNotPaused
  {
    // Transfer the tokens from the sender to the deposit address
    IERC20(depositTokenAddress).safeTransferFrom(msg.sender, depositAddress, depositAmount);

    emit TokensDeposited(depositTokenAddress, depositAddress, depositAmount);
  }
}
