// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

/**
 * @title IDataProvider
 * @notice Interface for peeking the data from an oracle,
 *         compatible with Amphiraos and OMoC-Decentralized Oracles
 * @dev https://github.com/money-on-chain/Amphiraos-Oracle
 * @dev https://github.com/money-on-chain/OMoC-Decentralized-Oracle
 */
interface IDataProvider {
  /**
   * @notice returns the given `data` if `valid`
   * @param data peeked
   * @param valid true if the data is valid
   */
  function peek() external view returns (bytes32 data, bool valid);
}
