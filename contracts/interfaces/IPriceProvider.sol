// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.6;

/**
 * @title IPriceProvider
 * @notice Interface for peeking the price and last publication block of a given asset
 * @dev https://github.com/money-on-chain/OMoC-Decentralized-Oracle
 */
interface IPriceProvider {
  /**
   * @notice returns the given `price` for the asset if `valid`
   * @return price assetPrice
   * @return valid true if the price is valid
   */
  function peek() external view returns (bytes32 price, bool valid);

  /**
   * @notice returns the last publication block of an asset price
   * @dev only valid for decentralized oracles
   * @return lastPublicationBlock
   */
  function getLastPublicationBlock() external view returns (uint256 lastPublicationBlock);
}
