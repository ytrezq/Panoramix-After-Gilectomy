// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
using SafeCast for uint256;

interface IMoCState {
  function bproUsdPrice() external view returns (uint256);
}

interface AggregatorV2Minimal {
  function latestAnswer() external view returns (int256);
}

contract BproUsdAggregatorV2Minimal is AggregatorV2Minimal {
  IMoCState public mocState;

  // Input decimals (from source) and output decimals (Chainlink-style)
  uint256 private constant IN_DECIMALS = 18;
  uint256 private constant OUT_DECIMALS = 8;
  uint256 private constant SCALE = 10 ** (IN_DECIMALS - OUT_DECIMALS); // 1e10

  constructor(address _mocState) {
    require(_mocState != address(0), "mocState address is zero");
    mocState = IMoCState(_mocState);
  }

  function latestAnswer() external view returns (int256) {
    // Warning!! This result is in 8 decimals precision
    uint256 raw = mocState.bproUsdPrice(); // e.g. 18d
    uint256 scaled = raw / SCALE; // -> 8d (truncates extra 10 decimals)
    return scaled.toInt256(); // safe-cast, reverts on overflow
  }
}
