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

import {IPauseManager} from "contracts/xManager/interfaces/IPauseManager.sol";

/**
 * @title  PauseManagerClient
 * @author Ondo Finance
 * @notice Provides helper functionality to check if a token source or recipient contract is paused.
 * @dev    This abstract contract integrates with the `IPauseManager` to enforce pause states via modifiers.
 */
abstract contract PauseManagerClient {
  // The instance of the `IPauseManager` contract used to check pause states.
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  IPauseManager public immutable pauseManager;

  /**
   * @notice Thrown when a recipient contract is paused.
   * @param source The contract address that is paused.
   */
  error RecipientIsPaused(address source);

  /**
   * Thrown when a source contract is paused.
   * @param source The contract address that is paused.
   */
  error SourceIsPaused(address source);

  /**
   * @param _pauseManager The address of the `IPauseManager` contract.
   * @dev   The `_pauseManager` address must be a valid, deployed contract implementing `IPauseManager`.
   */
  constructor(address _pauseManager) {
    pauseManager = IPauseManager(_pauseManager);
  }

  /**
   * @notice Modifier to ensure the calling source contract is not paused.
   * @dev    Checks the pause status for the source contract using the `IPauseManager`.
   *         Reverts with `SourceIsPaused` if the contract is paused.
   */
  modifier whenSourceNotPaused() {
    if (pauseManager.isTokenSourcePaused(address(this))) {
      revert SourceIsPaused(address(this));
    }
    _;
  }

  /**
   * @notice Modifier to ensure the calling recipient contract is not paused.
   * @dev    Checks the pause status for the recipient contract using the `IPauseManager`.
   *         Reverts with `RecipientIsPaused` if the contract is paused.
   */
  modifier whenRecipientNotPaused() {
    if (pauseManager.isTokenRecipientPaused(address(this))) {
      revert RecipientIsPaused(address(this));
    }
    _;
  }
}
