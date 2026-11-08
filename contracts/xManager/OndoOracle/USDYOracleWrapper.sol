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
 * @title  USDYOracleWrapper
 * @author Ondo Finance
 * @notice This contract serves as an abstraction over a non-upgradeable USDY Oracle contract,
 *         allowing swapping in new logic without third parties needing to repoint their contracts.
 */
contract USDYOracleWrapper is AbstractRWAOracleWrapper {
  constructor(address admin, address _rwaOracle) AbstractRWAOracleWrapper(admin, _rwaOracle) {}

  /**
   * @notice Retrieves the RWA price data.
   * @return price     The price of the RWA asset.
   * @return timestamp The timestamp of the price data.
   */
  function getPriceData() external view override returns (uint256 price, uint256 timestamp) {
    return IRWAOracle(rwaOracle).getPriceData();
  }

  /**
   * @notice Retrieves the RWA price.
   * @return price The price of the RWA asset.
   */
  function getPrice() external view override returns (uint256 price) {
    (price,) = IRWAOracle(rwaOracle).getPriceData();
  }
}
