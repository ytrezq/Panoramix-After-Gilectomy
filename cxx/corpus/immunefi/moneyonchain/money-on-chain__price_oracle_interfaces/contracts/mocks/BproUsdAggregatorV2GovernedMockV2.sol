// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { BproUsdAggregatorV2Governed } from "../BproUsdAggregatorV2Governed.sol";

/**
 * @dev Mock V2 implementation for upgrade testing only.
 * Keeps storage layout identical to V1 and adds a trivial function.
 */
contract BproUsdAggregatorV2GovernedMockV2 is BproUsdAggregatorV2Governed {
  function version() external pure returns (uint256) {
    return 2;
  }
}
