// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "./DocPriceLib.sol";
import "./interfaces/ICoinPairPrice.sol";
import "./interfaces/IMocState.sol";

using SafeCast for uint256;

/// @title DocUsdPriceChainlinkCompat
/// @notice Chainlink-compatible DOC/USD adapter with 8-decimal answers.
/// @dev
/// - The underlying DOC/USD value is still derived from MoC state and the protocol BTC oracle.
/// - `latestAnswer()` and `latestRoundData()` expose the price truncated to 8 decimals.
/// - `updatedAt` is estimated from the upstream publication block and the configured average
///   block time. This provides a Chainlink-shaped freshness signal for Rootstock consumers.
/// - `getRoundData()` serves the current round only; the upstream MoC interface does not expose
///   historical round storage.
contract DocUsdPriceChainlinkCompat {
  uint8 internal constant OUT_DECIMALS = 8;
  uint256 internal constant IN_TO_OUT_SCALE = 1e10;
  uint256 internal constant DEFAULT_VERSION = 1;

  IMocState public immutable mocState;
  ICoinPairPrice public immutable btcPriceProvider;
  uint256 public immutable averageBlockTimeSeconds;

  constructor(IMocState _mocState, uint256 _averageBlockTimeSeconds) {
    require(address(_mocState) != address(0), "mocState address is zero");
    require(_averageBlockTimeSeconds > 0, "averageBlockTimeSeconds is zero");

    mocState = _mocState;
    btcPriceProvider = ICoinPairPrice(_mocState.getBtcPriceProvider());
    averageBlockTimeSeconds = _averageBlockTimeSeconds;
  }

  /// @notice Returns the DOC/USD price with 8 decimals, truncated toward zero.
  function latestAnswer() external view returns (int256) {
    return _latestAnswer8().toInt256();
  }

  /// @notice Returns the number of decimals used by `latestAnswer()` and `latestRoundData()`.
  function decimals() external pure returns (uint8) {
    return OUT_DECIMALS;
  }

  /// @notice Human-readable pair description for Chainlink-style consumers.
  function description() external pure returns (string memory) {
    return "DOC / USD";
  }

  /// @notice Compatibility version for Chainlink-style consumers.
  function version() external pure returns (uint256) {
    return DEFAULT_VERSION;
  }

  /// @notice Returns the upstream BTC oracle publication block.
  function getLastPublicationBlock() public view returns (uint256) {
    return btcPriceProvider.getLastPublicationBlock();
  }

  /// @notice Returns Chainlink-style round data for the current DOC/USD reading.
  /// @dev The returned timestamp is an estimate derived from the publication block and the
  /// configured average block time.
  function latestRoundData()
    external
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
  {
    uint80 currentRoundId = uint80(getLastPublicationBlock());
    uint256 estimatedUpdatedAt = _estimatedUpdatedAt(currentRoundId);
    int256 currentAnswer = _latestAnswer8().toInt256();

    return (currentRoundId, currentAnswer, estimatedUpdatedAt, estimatedUpdatedAt, currentRoundId);
  }

  /// @notice Returns historical round data only for the current upstream publication block.
  /// @dev The upstream MoC surface does not expose historical rounds, so this adapter only serves
  /// the current round ID and reverts for any other value.
  function getRoundData(uint80 _roundId)
    external
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
  {
    uint80 currentRoundId = uint80(getLastPublicationBlock());
    require(_roundId == currentRoundId, "No data present");

    uint256 estimatedUpdatedAt = _estimatedUpdatedAt(currentRoundId);
    int256 currentAnswer = _latestAnswer8().toInt256();

    return (currentRoundId, currentAnswer, estimatedUpdatedAt, estimatedUpdatedAt, currentRoundId);
  }

  function _latestAnswer8() internal view returns (uint256) {
    (bytes32 btcPriceInUsdBytes, ) = btcPriceProvider.peek();
    uint256 btcPriceInUsd = uint256(btcPriceInUsdBytes);
    uint256 docPriceInUsd = DocPriceLib.docUsdPriceSafe(mocState, btcPriceInUsd);
    return docPriceInUsd / IN_TO_OUT_SCALE;
  }

  function _estimatedUpdatedAt(uint256 publicationBlock) internal view returns (uint256) {
    return block.timestamp - ((block.number - publicationBlock) * averageBlockTimeSeconds);
  }
}
