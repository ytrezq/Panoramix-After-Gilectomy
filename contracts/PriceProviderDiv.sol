// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.8.0;

import "./interfaces/IPriceProvider.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";

// A price provider oracle dividing the result from two others.
// NOTICE: Both prices must be expressed as wey with 18 decimal places.
contract PriceProviderDiv {
  IPriceProvider public immutable _priceProvider;
  IPriceProvider public immutable _priceProviderDivisor;

  /// @param priceProvider The Price Provider address
  /// @param priceProviderDivisor The Divisor Price Provider address
  constructor(IPriceProvider priceProvider, IPriceProvider priceProviderDivisor) {
    _priceProvider = priceProvider;
    _priceProviderDivisor = priceProviderDivisor;
  }

  /// Legacy peek function
  function peek() public view returns (bytes32 price, bool isValid) {
    (bytes32 priceBase, bool isValidBase) = _priceProvider.peek();
    (bytes32 priceDivisor, bool isValidDivisor) = _priceProviderDivisor.peek();
    price = bytes32(FullMath.mulDiv(uint256(priceBase), 10 ** 18, uint256(priceDivisor)));
    isValid = isValidBase && isValidDivisor;
  }

  // Return the current price.
  function getPrice() public view returns (uint256) {
    (bytes32 peekPrice, ) = peek();
    return uint256(peekPrice);
  }

  // Return if the price is not expired.
  function getIsValid() public view returns (bool peekIsValid) {
    (, peekIsValid) = peek();
  }

  // Price is as old as the oldest provider.
  function getLastPublicationBlock() external view returns (uint256) {
    uint256 a = _priceProvider.getLastPublicationBlock();
    uint256 b = _priceProviderDivisor.getLastPublicationBlock();
    return a < b ? a : b;
  }
}
