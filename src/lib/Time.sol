// SPDX-License-Identifier: UNLICENSED
// OpenZeppelin Contracts (last updated v5.1.0) (utils/types/Time.sol)
pragma solidity ^0.8.24;

import {SafeCast} from "@openzeppelin-contracts/utils/math/SafeCast.sol";

/**
 * @dev This library provides helpers for manipulating time-related objects.
 *
 * It uses the following types:
 * - `uint48` for timepoints
 *
 */
library Time {
    /**
     * @dev Get the block timestamp as a Timepoint.
     */
    function timestamp() internal view returns (uint32) {
        return SafeCast.toUint32(block.timestamp);
    }
}
