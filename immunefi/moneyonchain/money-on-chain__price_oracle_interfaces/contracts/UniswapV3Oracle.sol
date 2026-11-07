// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.8.0;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import "./interfaces/IERC20Metadata.sol";

contract UniswapV3Oracle {
  address public immutable _uniswapV3Pool;
  uint32 public immutable _twapInterval;
  address public immutable _quoteToken;
  address public immutable _baseToken;
  uint128 public immutable _baseAmount;
  uint256 public immutable _scaleFactor;

  /// @param pool The Uniswap v3 pool to get the price of the token
  /// @param twapInterval The time interval in seconds to get the twap over
  /// @param quoteToken The token to quote the price in terms of
  constructor(IUniswapV3Pool pool, uint32 twapInterval, address quoteToken) {
    require(
      pool.token0() == quoteToken || pool.token1() == quoteToken,
      "at least one token from the pool must be the quoted token"
    );
    require(twapInterval > 0, "twap interval must be > 0");

    address baseToken = pool.token0() == quoteToken ? pool.token1() : pool.token0();
    uint256 baseDecimals = IERC20Metadata(baseToken).decimals();
    uint256 quoteDecimals = IERC20Metadata(quoteToken).decimals();

    // prevent underflow
    require(quoteDecimals <= 18, "Quote token decimals must be <= 18");

    _uniswapV3Pool = address(pool);
    _twapInterval = twapInterval;
    _quoteToken = quoteToken;
    _baseToken = baseToken;
    // Base amount is 1 unit of the base token (scaled by its decimals)
    _baseAmount = uint128(10 ** baseDecimals);
    // Scale factor to normalize to 18 decimals
    _scaleFactor = 10 ** (18 - quoteDecimals);
  }

  function getPrice() public view virtual returns (uint256) {
    return getPriceFromPool(_uniswapV3Pool, _twapInterval);
  }

  /// legacy peek function
  function peek() external view virtual returns (bytes32, bool) {
    return (bytes32(getPrice()), getIsValid());
  }

  // From an oracle perspective, these prices are 'live'.
  function getLastPublicationBlock() external view returns (uint256) {
    return block.number;
  }

  // Live prices, are always vaild.
  function getIsValid() public view virtual returns (bool) {
    return true;
  }

  /// @notice Get the price of a token
  /// @param pool The Uniswap v3 pool to get the price of the token
  /// @param twapInterval The time interval in seconds to get the twap over
  function getPriceFromPool(address pool, uint32 twapInterval) internal view returns (uint256) {
    (int24 arithmeticMeanTick, ) = OracleLibrary.consult(pool, twapInterval);
    uint256 quoteAmount = OracleLibrary.getQuoteAtTick(
      arithmeticMeanTick,
      _baseAmount,
      _baseToken,
      _quoteToken
    );
    return quoteAmount * _scaleFactor;
  }
}
