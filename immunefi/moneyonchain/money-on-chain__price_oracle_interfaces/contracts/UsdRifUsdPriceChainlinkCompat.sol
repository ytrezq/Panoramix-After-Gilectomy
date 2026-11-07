// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "./PriceProviderUsdRifUsd.sol";

using SafeCast for uint256;

/// @title UsdRifUsdPriceChainlinkCompat
/// @notice Chainlink-compatible feed for the USD value of one USDRIF.
/// @dev
/// - USDRIF/USD is `min(1, RoC combined coverage)` and is exposed with 8 decimals.
///   It normally returns 1 USD and returns less than 1 USD if RoC lacks aggregate coverage.
/// - The underlying provider optimizes the usual fully covered path. Calculating an exact
///   undercoverage ratio is deliberately more expensive because it additionally requires
///   the multi-collateral guard's combined calculation.
/// - The underlying PriceProviderUsdRifUsd owns and refreshes the protocol topology cache.
/// - Round IDs always use the actual oldest component-price publication block. `updatedAt`
///   estimates that block's timestamp using the configured average block time; it is not an
///   oracle-supplied publication timestamp.
/// - `getRoundData()` serves the current round only because the sources have no historical rounds.
contract UsdRifUsdPriceChainlinkCompat {
  uint8 internal constant OUT_DECIMALS = 8;
  uint256 internal constant IN_TO_OUT_SCALE = 1e10;
  uint256 internal constant DEFAULT_VERSION = 1;

  PriceProviderUsdRifUsd public immutable priceProvider;
  uint256 public immutable averageBlockTimeSeconds;

  constructor(PriceProviderUsdRifUsd _priceProvider, uint256 _averageBlockTimeSeconds) {
    require(address(_priceProvider) != address(0), "price provider address is zero");
    require(_averageBlockTimeSeconds > 0, "averageBlockTimeSeconds is zero");

    priceProvider = _priceProvider;
    averageBlockTimeSeconds = _averageBlockTimeSeconds;
  }

  /// @notice Returns the USDRIF/USD price with 8 decimals, truncated toward zero.
  function latestAnswer() external view returns (int256) {
    return _latestAnswer8().toInt256();
  }

  function decimals() external pure returns (uint8) {
    return OUT_DECIMALS;
  }

  function description() external pure returns (string memory) {
    return "USDRIF / USD";
  }

  function version() external pure returns (uint256) {
    return DEFAULT_VERSION;
  }

  /// @notice Returns the actual oldest component-price publication block.
  function getLastPublicationBlock() public view returns (uint256) {
    return priceProvider.getLastPublicationBlock();
  }

  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    )
  {
    (uint256 usdRifPrice, , uint256 publicationBlock) = priceProvider.getPriceInfo();
    uint80 currentRoundId = uint80(publicationBlock);
    uint256 estimatedUpdatedAt = _estimatedUpdatedAt(publicationBlock);
    int256 currentAnswer = (usdRifPrice / IN_TO_OUT_SCALE).toInt256();

    return (currentRoundId, currentAnswer, estimatedUpdatedAt, estimatedUpdatedAt, currentRoundId);
  }

  function getRoundData(
    uint80 _roundId
  )
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    )
  {
    (uint256 usdRifPrice, , uint256 publicationBlock) = priceProvider.getPriceInfo();
    uint80 currentRoundId = uint80(publicationBlock);
    require(_roundId == currentRoundId, "No data present");

    uint256 estimatedUpdatedAt = _estimatedUpdatedAt(publicationBlock);
    int256 currentAnswer = (usdRifPrice / IN_TO_OUT_SCALE).toInt256();

    return (currentRoundId, currentAnswer, estimatedUpdatedAt, estimatedUpdatedAt, currentRoundId);
  }

  function _latestAnswer8() internal view returns (uint256) {
    (bytes32 usdRifPrice, ) = priceProvider.peek();
    return uint256(usdRifPrice) / IN_TO_OUT_SCALE;
  }

  function _estimatedUpdatedAt(uint256 publicationBlock) internal view returns (uint256) {
    if (publicationBlock >= block.number) return block.timestamp;

    uint256 elapsedSeconds = (block.number - publicationBlock) * averageBlockTimeSeconds;
    return elapsedSeconds < block.timestamp ? block.timestamp - elapsedSeconds : 0;
  }
}
