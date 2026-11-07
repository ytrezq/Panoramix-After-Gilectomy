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

import {Ownable2Step} from "contracts/external/openzeppelin/contracts/access/Ownable2Step.sol";
import {IRWAOracleWrapper} from "contracts/xManager/interfaces/IRWAOracleWrapper.sol";

/**
 * @title  AbstractRWAOracleWrapper
 * @author Ondo Finance
 * @notice Abstract contract for RWA Oracle Wrappers that provides the basic functionality
 *         for setting the RWA oracle address and ownership.
 */
abstract contract AbstractRWAOracleWrapper is Ownable2Step, IRWAOracleWrapper {
  /// RWA Oracle address
  address public rwaOracle;

  /**
   * @notice Emitted when the oracle address is set
   * @param  oldOracle The old oracle address
   * @param  newOracle The new oracle address
   */
  event OracleSet(address indexed oldOracle, address indexed newOracle);

  /// Error emitted when attempting to set the oracle address to the zero address
  error InvalidOracleAddress();
  /// Error emitted when attempting to set the admin address to the zero address
  error InvalidAdminAddress();
  /// Error emitted when attempting to renounce ownership
  error RenounceOwnershipDisabled();

  /**
   * @param  admin      The address of the admin
   * @param  _rwaOracle The address of the RWA oracle
   */
  constructor(address admin, address _rwaOracle) {
    if (admin == address(0)) revert InvalidAdminAddress();
    if (_rwaOracle == address(0)) revert InvalidOracleAddress();
    _transferOwnership(admin);
    rwaOracle = _rwaOracle;
  }

  /**
   * @notice Retrieves the RWA price data
   * @return price     The price of the RWA asset
   * @return timestamp The timestamp of the price data
   */
  function getPriceData() external view virtual returns (uint256 price, uint256 timestamp);

  /**
   * @notice Retrieves the RWA price
   * @return price The price of the RWA asset
   */
  function getPrice() external view virtual returns (uint256 price);

  /**
   * @notice Sets the RWA oracle address
   * @param  _rwaOracle The new RWA oracle address
   */
  function setRwaOracle(address _rwaOracle) external onlyOwner {
    if (_rwaOracle == address(0)) revert InvalidOracleAddress();
    emit OracleSet(rwaOracle, _rwaOracle);

    rwaOracle = _rwaOracle;
  }

  /// Disabled, ownership can only be transferred
  function renounceOwnership() public view override onlyOwner {
    revert RenounceOwnershipDisabled();
  }
}
