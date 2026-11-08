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

import {ITokenPauseManager} from "contracts/globalMarkets/tokenPauseManager/ITokenPauseManager.sol";
import {
  Initializable
} from "contracts/external/openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

/**
 * @title  TokenPauseManagerClientUpgradeable
 * @author Ondo Finance
 * @notice Provides helper functionality to check if a token contract is paused.
 * @dev    This abstract contract integrates with the `ITokenPauseManager` to enforce pause states via modifiers.
 */
abstract contract TokenPauseManagerClientUpgradeable is Initializable {
  /// The instance of the `ITokenPauseManager` contract used to check pause states.
  ITokenPauseManager public tokenPauseManager;

  /// Thrown when the token is paused
  error TokenPaused();

  /// Thrown when attempting to set the token pause manager to the zero address
  error TokenPauseManagerCantBeZero();

  /**
   * @notice Event emitted when the token pause manager is set
   * @param  oldTokenPauseManager The old token pause manager address
   * @param  newTokenPauseManager The new token pause manager address
   */
  event TokenPauseManagerSet(
    address indexed oldTokenPauseManager, address indexed newTokenPauseManager
  );

  /**
   * @notice Initialize the contract by setting token pause manager variable
   *
   * @param  _tokenPauseManager Address of the token pause manager contract
   *
   * @dev    Function should be called by the inheriting contract on
   *         initialization
   */
  function __TokenPauseManagerClientInitializable_init(address _tokenPauseManager)
    internal
    onlyInitializing
  {
    __TokenPauseManagerClientInitializable_init_unchained(_tokenPauseManager);
  }

  /**
   * @dev Internal function to future-proof parent linearization. Matches OZ
   *      upgradeable suggestions
   */
  function __TokenPauseManagerClientInitializable_init_unchained(address _tokenPauseManager)
    internal
    onlyInitializing
  {
    _setTokenPauseManager(_tokenPauseManager);
  }

  /**
   * @notice Sets the token pause manager address for this client
   *
   * @param _tokenPauseManager The new token pause manager address
   */
  function _setTokenPauseManager(address _tokenPauseManager) internal {
    if (_tokenPauseManager == address(0)) revert TokenPauseManagerCantBeZero();

    emit TokenPauseManagerSet(address(tokenPauseManager), _tokenPauseManager);
    tokenPauseManager = ITokenPauseManager(_tokenPauseManager);
  }

  /**
   * @notice Modifier to ensure the calling token contract is not paused.
   * @dev    Checks the pause status for the token contract using the `ITokenPauseManager`.
   *         Reverts with `TokenPaused` if the contract is paused.
   */
  function _checkTokenIsPaused() internal view {
    if (tokenPauseManager.isTokenPaused(address(this))) {
      revert TokenPaused();
    }
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[49] private __gap;
}
