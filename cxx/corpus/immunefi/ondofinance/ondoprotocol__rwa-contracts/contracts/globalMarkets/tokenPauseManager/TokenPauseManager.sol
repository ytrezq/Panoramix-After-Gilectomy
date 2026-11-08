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
import {ITokenPauseManager} from "contracts/globalMarkets/tokenPauseManager/ITokenPauseManager.sol";

/**
 * @title  TokenPauseManager
 * @author Ondo Finance
 * @notice This contract manages the pausing and unpausing of client contracts that inherit from
 *         `PauseManagerClient`. Pausers require the 'PAUSE_TOKEN_ROLE' and unpausers require the
 *         'UNPAUSE_TOKEN_ROLE'.
 */
contract TokenPauseManager is ITokenPauseManager, AccessControlEnumerable {
  /// Role required to pause tokens
  bytes32 public constant PAUSE_TOKEN_ROLE = keccak256("PAUSE_TOKEN_ROLE");

  /// Role required to unpause tokens
  bytes32 public constant UNPAUSE_TOKEN_ROLE = keccak256("UNPAUSE_TOKEN_ROLE");

  /// Tracks paused state of individual tokens
  mapping(address => bool) public pausedTokens;

  /// Tracks global paused state for all token recipient tokens
  bool public allTokensPaused;

  /**
   * @notice Emitted when a token is paused
   * @param  token  The address of the paused token
   * @param  pauser The address that initiated the pause
   */
  event TokenPaused(address indexed token, address indexed pauser);

  /**
   * @notice Emitted when a token is unpaused
   * @param  token  The address of the unpaused token
   * @param  pauser The address that initiated the unpause
   */
  event TokenUnpaused(address indexed token, address indexed pauser);

  /**
   * @notice Emitted when all token tokens are paused
   * @param  pauser The address that initiated the pause
   */
  event AllTokensPaused(address indexed pauser);

  /**
   * @notice Emitted when all tokens are unpaused
   * @param  pauser The address that initiated the unpause
   */
  event AllTokensUnpaused(address indexed pauser);

  /**
   * @param guardian The address which will be granted admin, pause and unpause roles
   */
  constructor(address guardian) {
    _grantRole(DEFAULT_ADMIN_ROLE, guardian);
    _grantRole(PAUSE_TOKEN_ROLE, guardian);
    _grantRole(UNPAUSE_TOKEN_ROLE, guardian);
  }

  /**
   * @notice Pauses a token
   * @param  token The address of the token to pause
   * @dev    Only callable by addresses with the `PAUSE_TOKEN_ROLE`
   */
  function pauseToken(address token) external onlyRole(PAUSE_TOKEN_ROLE) {
    pausedTokens[token] = true;
    emit TokenPaused(token, msg.sender);
  }

  /**
   * @notice Unpauses a token
   * @param  token The address of the token to unpause
   * @dev    Only callable by addresses with the `UNPAUSE_TOKEN_ROLE`
   *
   */
  function unpauseToken(address token) external onlyRole(UNPAUSE_TOKEN_ROLE) {
    pausedTokens[token] = false;
    emit TokenUnpaused(token, msg.sender);
  }

  /**
   * @notice Pauses all tokens
   * @dev    Only callable by addresses with the `PAUSE_TOKEN_ROLE`
   */
  function pauseAllTokens() external onlyRole(PAUSE_TOKEN_ROLE) {
    allTokensPaused = true;
    emit AllTokensPaused(msg.sender);
  }

  /**
   * @notice Unpauses all tokens
   * @dev    Only callable by addresses with the `UNPAUSE_TOKEN_ROLE`.
   */
  function unpauseAllTokens() external onlyRole(UNPAUSE_TOKEN_ROLE) {
    allTokensPaused = false;
    emit AllTokensUnpaused(msg.sender);
  }

  /**
   * @notice Checks if a specific token is paused
   * @param  _token The address of the token to check
   * @return True if the token is paused, false otherwise
   * @dev    Returns true if the specific token is paused or if all tokens are paused
   */
  function isTokenPaused(address _token) external view override returns (bool) {
    return pausedTokens[_token] || allTokensPaused;
  }
}
