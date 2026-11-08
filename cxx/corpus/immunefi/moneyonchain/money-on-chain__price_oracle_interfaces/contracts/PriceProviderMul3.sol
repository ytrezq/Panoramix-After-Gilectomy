// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.8.0;

import "./interfaces/IPriceProvider.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";

// A price provider oracle multiplying the result from three others.
// NOTICE: All prices must use 18 decimal places.
contract PriceProviderMul3 {
  IPriceProvider public immutable priceOne;
  IPriceProvider public immutable priceTwo;
  IPriceProvider public immutable priceThree;

  /// @param _priceOne The First Price Provider address
  /// @param _priceTwo The Second Price Provider address
  /// @param _priceThree The Third Price Provider address
  constructor(IPriceProvider _priceOne, IPriceProvider _priceTwo, IPriceProvider _priceThree) {
    priceOne = _priceOne;
    priceTwo = _priceTwo;
    priceThree = _priceThree;
  }

  function peek() public view returns (bytes32 price, bool isValid) {
    (bytes32 one, bool isValidOne) = priceOne.peek();
    (bytes32 two, bool isValidTwo) = priceTwo.peek();
    (bytes32 three, bool isValidThree) = priceThree.peek();
    uint256 mulOneTwo = FullMath.mulDiv(uint256(one), uint256(two), 10 ** 18);
    price = bytes32(FullMath.mulDiv(mulOneTwo, uint256(three), 10 ** 18));
    isValid = isValidOne && isValidTwo && isValidThree;
  }

  function getPrice() public view returns (uint256) {
    (bytes32 peekPrice, ) = peek();
    return uint256(peekPrice);
  }

  function getIsValid() public view returns (bool peekIsValid) {
    (, peekIsValid) = peek();
  }

  // Price is as old as the oldest provider.
  function getLastPublicationBlock() external view returns (uint256) {
    uint256 a = priceOne.getLastPublicationBlock();
    uint256 b = priceTwo.getLastPublicationBlock();
    uint256 c = priceThree.getLastPublicationBlock();
    uint256 min = a < b ? a : b;
    return min < c ? min : c;
  }
}
