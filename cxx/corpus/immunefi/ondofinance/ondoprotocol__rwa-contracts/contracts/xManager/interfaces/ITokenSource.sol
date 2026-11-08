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

interface ITokenSource {
  /**
   * @notice Emitted when tokens are withdrawn from the source
   * @param  requestedBy    The address of the account that requested the withdraw
   * @param  withdrawnFrom  The address of the source contract from which the tokens were withdrawn
   * @param  withdrawToken  The address of the token that was withdrawn
   * @param  withdrawAmount The amount of tokens that were withdrawn, denoted in the decimals of
   *                        `withdrawToken`
   */
  event TokensWithdrawn(
    address indexed requestedBy,
    address indexed withdrawnFrom,
    address indexed withdrawToken,
    uint256 withdrawAmount
  );

  /// Thrown when the requested token is not the expected token
  error InvalidTokenAddressForTokenSource();

  /// Thrown when attempting to set an address to address(0) which is not allowed
  error ZeroAddressNotAllowed();

  function withdrawToken(address tokenToWithdraw, uint256 withdrawAmount) external;

  function availableToWithdraw(address tokenToWithdraw) external view returns (uint256);
}
