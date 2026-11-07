// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.8.0;

import "./UniswapV3Oracle.sol";
import "./interfaces/IPriceProvider.sol";

// Gets the price from a pool and converts it to USD using a price provider.
// The pool price would be expressed as QUOTE currency, usually BTC.
// The price provider will yield teh price for QUOTE/USD, usually BTCUSD.
contract UniswapV3OracleUSD is UniswapV3Oracle {
  address public _wrappedToken;
  IPriceProvider public _btcPriceProvider;

  /// @param pool The Uniswap v3 pool to get the price of the token
  /// @param twapInterval The time interval in seconds to get the twap over
  /// @param wrappedToken The Wrapped BTC token address
  /// @param btcPriceProvider The BTC/USD Price Provider address
  constructor(
    IUniswapV3Pool pool,
    uint32 twapInterval,
    address wrappedToken,
    IPriceProvider btcPriceProvider
  ) UniswapV3Oracle(pool, twapInterval, wrappedToken) {
    _wrappedToken = wrappedToken;
    _btcPriceProvider = btcPriceProvider;
  }

  /// legacy peek function
  function peek() public view override returns (bytes32 price, bool isValid) {
    (bytes32 btcPrice, bool btcPriceIsValid) = _btcPriceProvider.peek();
    uint256 priceFromPool = getPriceFromPool(_uniswapV3Pool, _twapInterval);
    price = bytes32((uint256(btcPrice) * priceFromPool) / 10 ** 18);
    isValid = btcPriceIsValid;
  }

  // Return the current price.
  function getPrice() public view override returns (uint256) {
    (bytes32 peek_price, ) = peek();
    return uint256(peek_price);
  }

  // Unlike parent UniswapV3Oracle, this can be invalid depending on the _btcPriceProvider.
  function getIsValid() public view virtual override returns (bool isValid) {
    (, isValid) = peek();
  }
}
