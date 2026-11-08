// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.8.0;

import "./interfaces/IPriceProvider.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";

// A price provider oracle returning the inverse of another provider.
// NOTICE: Input and output use 18 decimal places.
contract PriceProviderInverse {
  IPriceProvider public immutable _priceProvider;

  /// @param priceProvider The Price Provider address
  constructor(IPriceProvider priceProvider) {
    _priceProvider = priceProvider;
  }

  function peek() public view returns (bytes32 price, bool isValid) {
    (bytes32 priceBase, bool isValidBase) = _priceProvider.peek();
    uint256 baseUint = uint256(priceBase);
    uint256 inverse = FullMath.mulDiv(10 ** 18, 10 ** 18, baseUint);
    price = bytes32(inverse);
    isValid = isValidBase;
  }

  function getPrice() public view returns (uint256) {
    (bytes32 peekPrice, ) = peek();
    return uint256(peekPrice);
  }

  function getIsValid() public view returns (bool peekIsValid) {
    (, peekIsValid) = _priceProvider.peek();
  }

  function getLastPublicationBlock() external view returns (uint256) {
    return _priceProvider.getLastPublicationBlock();
  }
}
