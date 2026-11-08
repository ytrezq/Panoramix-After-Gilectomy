// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IChainlinkAggregator} from "src/interfaces/external/IChainlinkAggregator.sol";

/// @title OneToOneAggregator Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Aggregator that returns ONE
contract OneToOneAggregator is IChainlinkAggregator {
    uint8 private constant DECIMALS = 18;
    int256 private constant ONE = 10 ** 18;

    function decimals() external pure override returns (uint8 decimals_) {
        return DECIMALS;
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80, int256 answer_, uint256, uint256 updatedAt_, uint80)
    {
        return (0, ONE, 0, block.timestamp, 0);
    }
}
