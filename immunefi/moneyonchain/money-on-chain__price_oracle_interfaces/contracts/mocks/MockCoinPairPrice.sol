// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../interfaces/ICoinPairPrice.sol";

contract MockCoinPairPrice is ICoinPairPrice {
  uint256 private _priceUint;
  bool private _valid;
  uint256 private _lastPubBlock;

  constructor(uint256 initialPriceUint, bool initialValid, uint256 initialLastPubBlock) {
    _priceUint = initialPriceUint;
    _valid = initialValid;
    _lastPubBlock = initialLastPubBlock;
  }

  function setPriceUint(uint256 newPriceUint, bool newValid) external {
    _priceUint = newPriceUint;
    _valid = newValid;
  }

  function setLastPublicationBlock(uint256 newBlock) external {
    _lastPubBlock = newBlock;
  }

  function peek() external view returns (bytes32 price, bool valid) {
    return (bytes32(_priceUint), _valid);
  }

  function getLastPublicationBlock() external view returns (uint256 lastPublicationBlock) {
    return _lastPubBlock;
  }
}
