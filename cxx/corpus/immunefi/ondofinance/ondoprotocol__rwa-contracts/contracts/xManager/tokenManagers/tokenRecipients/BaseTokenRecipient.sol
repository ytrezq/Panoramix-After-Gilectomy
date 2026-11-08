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
  AccessControlEnumerable
} from "contracts/external/openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {IERC20} from "contracts/external/openzeppelin/contracts/token/IERC20.sol";
import {SafeERC20} from "contracts/external/openzeppelin/contracts/token/SafeERC20.sol";
import {ITokenRecipient} from "contracts/xManager/interfaces/ITokenRecipient.sol";
import {PauseManagerClient} from "contracts/xManager/tokenManagers/PauseManagerClient.sol";

abstract contract BaseTokenRecipient is
  AccessControlEnumerable,
  PauseManagerClient,
  ITokenRecipient
{
  using SafeERC20 for IERC20;
  /// Role identifier for accounts authorized to deposit tokens
  bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");

  /// Role identifier for accounts authorized to retrieve tokens, as dust may accrue
  bytes32 public constant RETRIEVER_ROLE = keccak256("RETRIEVER_ROLE");

  /**
   * @notice Retrieves locked tokens from the contract
   * @param  token  The token address to retrieve
   * @param  to     The recipient address
   * @param  amount The amount of tokens to retrieve
   */
  function retrieveTokens(address token, address to, uint256 amount)
    external
    onlyRole(RETRIEVER_ROLE)
  {
    IERC20(token).safeTransfer(to, amount);
  }
}
