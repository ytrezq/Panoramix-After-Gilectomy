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

import {IRWADynamicOracle} from "contracts/rwaOracles/IRWADynamicOracle.sol";
import {IRWAOracle} from "contracts/rwaOracles/IRWAOracle.sol";

/**
 * @title  ScheduledOracleSwitch
 * @author Ondo Finance
 * @notice This contract serves the price of an RWA token from one of two oracles depending on
 *         the current time. Before `switchTimestamp` every read is forwarded to `oldOracle`;
 *         from `switchTimestamp` on every read is forwarded to `newOracle`. It allows consumers
 *         to be repointed ahead of a cutover and switched atomically at a predetermined time.
 * @dev    The contract has no admin and cannot be retargeted; a wrong oracle or timestamp
 *         requires a new deployment. `switchTimestamp` must be the end of an `oldOracle` range,
 *         and `newOracle`'s price at `switchTimestamp` must equal `oldOracle`'s price at
 *         `switchTimestamp - 1`, the close of that range, before it arrives.
 */
contract ScheduledOracleSwitch is IRWADynamicOracle, IRWAOracle {
  /// The oracle served before `switchTimestamp`
  IRWAOracle public immutable oldOracle;
  /// The oracle served from `switchTimestamp` on
  IRWAOracle public immutable newOracle;
  /// The timestamp at which reads switch from `oldOracle` to `newOracle`
  uint64 public immutable switchTimestamp;

  /// Error thrown when an oracle address is the zero address
  error ZeroAddress();
  /// Error thrown when `oldOracle` and `newOracle` are the same address
  error SameOracle();
  /// Error thrown when `switchTimestamp` is not in the future at deployment
  error SwitchTimestampInPast();

  /**
   * @param  _oldOracle       The oracle served before `_switchTimestamp`
   * @param  _newOracle       The oracle served from `_switchTimestamp` on
   * @param  _switchTimestamp The timestamp at which reads switch from `_oldOracle` to `_newOracle`
   */
  constructor(address _oldOracle, address _newOracle, uint64 _switchTimestamp) {
    if (_oldOracle == address(0) || _newOracle == address(0)) revert ZeroAddress();
    if (_oldOracle == _newOracle) revert SameOracle();
    if (_switchTimestamp <= block.timestamp) revert SwitchTimestampInPast();

    oldOracle = IRWAOracle(_oldOracle);
    newOracle = IRWAOracle(_newOracle);
    switchTimestamp = _switchTimestamp;
  }

  /**
   * @notice Get the current price of the RWA token from the active oracle
   * @return price The current price of the RWA token, with 18 decimals of precision
   */
  function getPrice() external view returns (uint256 price) {
    (price,) = _resolve();
  }

  /**
   * @notice Get the current price and timestamp of the RWA token from the active oracle
   * @return price     The current price of the RWA token, with 18 decimals of precision
   * @return timestamp The timestamp this price is accurate to, as reported by the active oracle
   */
  function getPriceData() external view returns (uint256 price, uint256 timestamp) {
    return _resolve();
  }

  /**
   * @notice Get the price data of the oracle active at the current time
   * @return price     The current price of the RWA token, with 18 decimals of precision
   * @return timestamp The timestamp this price is accurate to, as reported by the active oracle
   */
  function _resolve() internal view returns (uint256 price, uint256 timestamp) {
    return block.timestamp < switchTimestamp ? oldOracle.getPriceData() : newOracle.getPriceData();
  }
}
