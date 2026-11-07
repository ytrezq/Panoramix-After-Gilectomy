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
import {IPauseManager} from "contracts/xManager/interfaces/IPauseManager.sol";

/**
 * @title  PauseManager
 * @author Ondo Finance
 * @notice This contract manages the pausing and unpausing of client contracts that inherit from
 *         `PauseManagerClient`. Pausers require the 'PAUSE_CONTRACT_ROLE' and unpausers require the
 *         'UNPAUSE_CONTRACT_ROLE'.
 * @dev    Utilizes `AccessControlEnumerable` for role-based permissioning
 */
contract PauseManager is IPauseManager, AccessControlEnumerable {
  /// Role required to pause contracts
  bytes32 public constant PAUSE_CONTRACT_ROLE = keccak256("PAUSE_CONTRACT_ROLE");

  /// Role required to unpause contracts
  bytes32 public constant UNPAUSE_CONTRACT_ROLE = keccak256("UNPAUSE_CONTRACT_ROLE");

  /// Tracks paused state of individual contracts
  mapping(address => bool) public pausedContracts;

  /// Tracks global paused state for all token recipient contracts
  bool public allTokenRecipientsPaused;

  /// Tracks global paused state for all token source contracts
  bool public allTokenSourcesPaused;

  /**
   * @notice Emitted when a contract is paused
   * @param  contractAddress The address of the paused contract
   * @param  pauser The address that initiated the pause
   */
  event ContractPaused(address indexed contractAddress, address indexed pauser);

  /**
   * @notice Emitted when a contract is unpaused
   * @param  contractAddress The address of the unpaused contract
   * @param  pauser The address that initiated the unpause
   */
  event ContractUnpaused(address indexed contractAddress, address indexed pauser);

  /**
   * @notice Emitted when all token recipient contracts are paused
   * @param  pauser The address that initiated the pause
   */
  event AllTokenRecipientsPaused(address indexed pauser);

  /**
   * @notice Emitted when all token recipient contracts are unpaused
   * @param  pauser The address that initiated the unpause
   */
  event AllTokenRecipientsUnpaused(address indexed pauser);

  /**
   * @notice Emitted when all token source contracts are paused
   * @param  pauser The address that initiated the pause
   */
  event AllTokenSourcesPaused(address indexed pauser);

  /**
   * @notice Emitted when all token source contracts are unpaused
   * @param  pauser The address that initiated the unpause
   */
  event AllTokenSourcesUnpaused(address indexed pauser);

  /**
   * @param _defaultAdmin The address which will be granted admin, pause and unpause roles
   */
  constructor(address _defaultAdmin) {
    _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
    _grantRole(PAUSE_CONTRACT_ROLE, _defaultAdmin);
    _grantRole(UNPAUSE_CONTRACT_ROLE, _defaultAdmin);
  }

  /**
   * @notice Pauses a contract
   * @param  contractAddress The address of the contract to pause
   * @dev    Only callable by addresses with the `PAUSE_CONTRACT_ROLE`
   */
  function pauseContract(address contractAddress) external onlyRole(PAUSE_CONTRACT_ROLE) {
    pausedContracts[contractAddress] = true;
    emit ContractPaused(contractAddress, msg.sender);
  }

  /**
   * @notice Unpauses a contract
   * @param  contractAddress The address of the contract to unpause
   * @dev    Only callable by addresses with the `UNPAUSE_CONTRACT_ROLE`
   *
   */
  function unpauseContract(address contractAddress) external onlyRole(UNPAUSE_CONTRACT_ROLE) {
    pausedContracts[contractAddress] = false;
    emit ContractUnpaused(contractAddress, msg.sender);
  }

  /**
   * @notice Pauses all token recipient contracts
   * @dev    Only callable by addresses with the `PAUSE_CONTRACT_ROLE`
   */
  function pauseAllTokenRecipients() external onlyRole(PAUSE_CONTRACT_ROLE) {
    allTokenRecipientsPaused = true;
    emit AllTokenRecipientsPaused(msg.sender);
  }

  /**
   * @notice Unpauses all token recipient contracts
   * @dev    Only callable by addresses with the `UNPAUSE_CONTRACT_ROLE`.
   *         Only affects contracts paused by the `pauseAllTokenRecipients` function
   */
  function unpauseAllTokenRecipients() external onlyRole(UNPAUSE_CONTRACT_ROLE) {
    allTokenRecipientsPaused = false;
    emit AllTokenRecipientsUnpaused(msg.sender);
  }

  /**
   * @notice Pauses all token source contracts
   * @dev    Only callable by addresses with the `PAUSE_CONTRACT_ROLE`.
   */
  function pauseAllTokenSources() external onlyRole(PAUSE_CONTRACT_ROLE) {
    allTokenSourcesPaused = true;
    emit AllTokenSourcesPaused(msg.sender);
  }

  /**
   * @notice Unpauses all token source contracts
   * @dev    Only callable by addresses with the `UNPAUSE_CONTRACT_ROLE`
   *         Only affects contracts paused by the `pauseAllTokenSources` function
   */
  function unpauseAllTokenSources() external onlyRole(UNPAUSE_CONTRACT_ROLE) {
    allTokenSourcesPaused = false;
    emit AllTokenSourcesUnpaused(msg.sender);
  }

  /**
   * @notice Checks if a specific token source contract is paused
   * @param  _source The address of the contract to check
   * @return True if the contract is paused, false otherwise
   * @dev    Returns true if the specific contract is paused or if all token sources are paused
   */
  function isTokenSourcePaused(address _source) external view override returns (bool) {
    return pausedContracts[_source] || allTokenSourcesPaused;
  }

  /**
   * @notice Checks if a specific token recipient contract is paused
   * @param  _recipient The address of the contract to check
   * @return True if the contract is paused or if all token recipients are paused, false otherwise
   * @dev    Returns true if the specific contract is paused or if all token recipients are paused
   */
  function isTokenRecipientPaused(address _recipient) external view override returns (bool) {
    return pausedContracts[_recipient] || allTokenRecipientsPaused;
  }
}
