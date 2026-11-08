// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.8.0;

import "./interfaces/IPriceProvider.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";

// A price provider oracle multiplying the result from two others.
// NOTICE: Both prices must use 18 decimal places.
contract PriceProviderMul {
  IPriceProvider public immutable _priceProvider;
  IPriceProvider public immutable _priceProviderMultiplier;

  /// @param priceProvider The Price Provider address
  /// @param priceProviderMultiplier The Multiplier Price Provider address
  constructor(IPriceProvider priceProvider, IPriceProvider priceProviderMultiplier) {
    _priceProvider = priceProvider;
    _priceProviderMultiplier = priceProviderMultiplier;
  }

  /// Legacy peek function
  function peek() public view returns (bytes32 price, bool isValid) {
    (bytes32 priceBase, bool isValidBase) = _priceProvider.peek();
    (bytes32 priceMultiplier, bool isValidMultiplier) = _priceProviderMultiplier.peek();
    price = bytes32(FullMath.mulDiv(uint256(priceBase), uint256(priceMultiplier), 10 ** 18));
    isValid = isValidBase && isValidMultiplier;
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
    uint256 b = _priceProviderMultiplier.getLastPublicationBlock();
    return a < b ? a : b;
  }
}
