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
pragma solidity ^0.8.4;

import {ITokenSource} from "contracts/xManager/interfaces/ITokenSource.sol";
import {ITokenRecipient} from "contracts/xManager/interfaces/ITokenRecipient.sol";

interface IOndoTokenRouterEvents {
  /**
   * @notice Emitted when a token is deposited to the router
   * @param  rwaToken     The RWA token that the deposit is for
   * @param  depositToken The token that was deposited
   * @param  amount       The amount of the token that was deposited, in the token's
   *                      decimals
   */
  event TokenDeposited(address indexed rwaToken, address indexed depositToken, uint256 amount);

  /**
   * @notice Emitted when a token is withdrawn via the router
   * @param  rwaToken      The RWA token that the withdrawal is for
   * @param  withdrawToken The token that was withdrawn
   * @param  amount        The amount of the token that was withdrawn, in the
   *                       token's decimals
   */
  event TokenWithdrawn(address indexed rwaToken, address indexed withdrawToken, uint256 amount);

  /**
   * @notice Emitted when a token recipient is set for a token
   * @param  rwaToken          The RWA token that the recipient is being set for
   * @param  depositToken      The token that the recipient is being set for
   * @param  oldTokenRecipient The old recipient
   * @param  newTokenRecipient The new recipient
   */
  event TokenDepositRecipientSet(
    address indexed rwaToken,
    address indexed depositToken,
    ITokenRecipient oldTokenRecipient,
    ITokenRecipient newTokenRecipient
  );

  /**
   * @notice Emitted when a token source is set for a token
   * @param  rwaToken        The RWA token that the source is being set for
   * @param  withdrawToken   The token that the source is being set for
   * @param  oldTokenSources The old sources
   * @param  newTokenSources The new sources
   */
  event TokenWithdrawSourcesSet(
    address indexed rwaToken,
    address indexed withdrawToken,
    ITokenSource[] oldTokenSources,
    ITokenSource[] newTokenSources
  );

  /**
   * @notice Emitted when a user's token withdraw sources are set
   * @param  rwaToken        The RWA token that the sources are being set for
   * @param  withdrawToken   The token that the sources are being set for
   * @param  userID          The ID of the user the sources are being set for
   * @param  active          Whether the user sources are active
   * @param  oldTokenSources The old sources
   * @param  newTokenSources The new sources
   */
  event UserTokenWithdrawSourcesSet(
    address indexed rwaToken,
    address indexed withdrawToken,
    bytes32 indexed userID,
    bool active,
    ITokenSource[] oldTokenSources,
    ITokenSource[] newTokenSources
  );

  /**
   * @notice Emitted when a token's minimum price is set
   * @param  tokenAddress The token that the minimum price is being set for
   * @param  minimumPrice The new minimum price
   * @param  oracle       The new token oracle
   * @param  maxTimeDelay The maximum time delay for the oracle
   */
  event MinimumTokenPriceAndOracleSet(
    address indexed tokenAddress, uint256 minimumPrice, address oracle, uint256 maxTimeDelay
  );
}
