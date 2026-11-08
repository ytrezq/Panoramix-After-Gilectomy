// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title AggregatorInterface
 * @dev Interface for Chainlink Aggregator V2 functionality
 */
interface AggregatorInterface {
  /// @dev Returns the latest answer from the aggregator
  /// @return The latest price answer
  function latestAnswer() external view returns (int256);
  
  /// @dev Returns the timestamp of the latest answer
  /// @return The timestamp when the latest answer was updated
  function latestTimestamp() external view returns (uint256);
  
  /// @dev Returns the latest round ID
  /// @return The ID of the latest round
  function latestRound() external view returns (uint256);
  
  /// @dev Returns the answer for a specific round
  /// @param roundId The round ID to get the answer for
  /// @return The price answer for the specified round
  function getAnswer(uint256 roundId) external view returns (int256);
  
  /// @dev Returns the timestamp for a specific round
  /// @param roundId The round ID to get the timestamp for
  /// @return The timestamp when the specified round was updated
  function getTimestamp(uint256 roundId) external view returns (uint256);

  /// @dev Emitted when the answer is updated
  /// @param current The new answer value
  /// @param roundId The round ID associated with the answer
  /// @param updatedAt The timestamp when the answer was updated
  event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);
  
  /// @dev Emitted when a new round is started
  /// @param roundId The ID of the new round
  /// @param startedBy The address that started the round
  /// @param startedAt The timestamp when the round was started
  event NewRound(uint256 indexed roundId, address indexed startedBy, uint256 startedAt);
}

/**
 * @title AggregatorV3Interface
 * @dev Interface for Chainlink Aggregator V3 functionality with enhanced round data
 */
interface AggregatorV3Interface {
  /// @dev Returns the number of decimals used in the price representation
  /// @return The number of decimals
  function decimals() external view returns (uint8);

  /// @dev Returns a description of what this price feed represents
  /// @return A string description of the price feed
  function description() external view returns (string memory);

  /// @dev Returns the version of this aggregator interface
  /// @return The version number
  function version() external view returns (uint256);

  /// @dev Returns round data for a specific round ID
  /// @param _roundId The round ID to retrieve data for
  /// @return roundId The round ID
  /// @return answer The price answer for this round
  /// @return startedAt The timestamp when the round started
  /// @return updatedAt The timestamp when the round was last updated
  /// @return answeredInRound The round ID in which the answer was computed
  function getRoundData(
    uint80 _roundId
  ) external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

  /// @dev Returns data from the latest round
  /// @return roundId The latest round ID
  /// @return answer The latest price answer
  /// @return startedAt The timestamp when the latest round started
  /// @return updatedAt The timestamp when the latest round was last updated
  /// @return answeredInRound The round ID in which the latest answer was computed
  function latestRoundData()
    external
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/**
 * @title AggregatorV2V3Interface
 * @dev Combined interface supporting both V2 and V3 aggregator functionality
 */
interface AggregatorV2V3Interface is AggregatorInterface, AggregatorV3Interface {}