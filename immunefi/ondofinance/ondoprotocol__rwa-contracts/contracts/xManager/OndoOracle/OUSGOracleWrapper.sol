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

import {AbstractRWAOracleWrapper} from "contracts/xManager/OndoOracle/AbstractRWAOracleWrapper.sol";
import {IRWAOracle} from "contracts/rwaOracles/IRWAOracle.sol";

/**
 * @title  OUSGOracleWrapper
 * @author Ondo Finance
 * @notice This contract serves as a view for an OUSG Oracle contract. It provides a consistent
 *         interface for querying the price of the OUSG asset across changes in the underlying
 *         logic.
 */
contract OUSGOracleWrapper is AbstractRWAOracleWrapper {
  /**
   * @param admin      The address of the admin
   * @param _rwaOracle The address of the RWA Oracle
   */
  constructor(address admin, address _rwaOracle) AbstractRWAOracleWrapper(admin, _rwaOracle) {}

  /**
   * @notice Retrieves the RWA price data
   * @return price     The price of the RWA asset
   * @return timestamp The timestamp of the price data
   */
  function getPriceData() external view override returns (uint256 price, uint256 timestamp) {
    return IRWAOracle(rwaOracle).getPriceData();
  }

  /**
   * @notice Retrieves the RWA price
   * @return price The price of the RWA asset
   */
  function getPrice() external view override returns (uint256 price) {
    (price,) = IRWAOracle(rwaOracle).getPriceData();
  }
}
