// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./interfaces/ICoinPairPrice.sol";

/// @title Thin forwarder over an ICoinPairPrice oracle
/// @notice Exposes peek() and getLastPublicationBlock() from an underlying oracle
contract CoinPairPrice {
  ICoinPairPrice public immutable coinpairprice;

  constructor(ICoinPairPrice _coinpairprice) {
    require(address(_coinpairprice) != address(0), "coinpairprice address is zero");
    coinpairprice = _coinpairprice;
  }

  function peek() external view virtual returns (bytes32, bool) {
    return coinpairprice.peek();
  }

  function getLastPublicationBlock() external view returns (uint256) {
    return coinpairprice.getLastPublicationBlock();
  }
}
