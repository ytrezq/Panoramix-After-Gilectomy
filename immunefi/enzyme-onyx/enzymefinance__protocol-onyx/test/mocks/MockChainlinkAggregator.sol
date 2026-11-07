// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

import {IChainlinkAggregator} from "src/interfaces/external/IChainlinkAggregator.sol";

contract MockChainlinkAggregator is IChainlinkAggregator {
    uint8 public decimals;

    int256 public answer;
    uint256 public updatedAt;

    uint80 dummyRoundId = 80;
    uint256 dummyStartedAt = 754982;
    uint80 dummyAnsweredInRound = 81;

    constructor(uint8 _decimals) {
        decimals = _decimals;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId_, int256 answer_, uint256 startedAt_, uint256 updatedAt_, uint80 answeredInRound_)
    {
        roundId_ = dummyRoundId;
        startedAt_ = dummyStartedAt;
        answeredInRound_ = dummyAnsweredInRound;

        answer_ = answer;
        updatedAt_ = updatedAt;
    }

    function setRate(uint256 _rate) external {
        answer = int256(_rate);
    }

    function setTimestamp(uint256 _timestamp) external {
        updatedAt = _timestamp;
    }
}
