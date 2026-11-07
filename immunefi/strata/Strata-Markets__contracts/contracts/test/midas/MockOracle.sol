// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
    IRoundDataOracle
} from "../../tranches/strategies/midas/AaveOracleAprPairProvider.sol";

/**
 * @title MockOracle
 * @dev Chainlink-style mock oracle with setable round data
 */
contract MockOracle is IRoundDataOracle {
    struct RoundData {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    mapping(uint80 => RoundData) public rounds;
    uint80 public latestRound;

    constructor ()  {
        setRoundData(1, 1e8, 0);
    }

    function setRoundData(
        uint80 roundId,
        int256 answer,
        uint256 updatedAt
    ) public {
        if (updatedAt == 0) {
            updatedAt = block.timestamp;
        }
        rounds[roundId] = RoundData(
            roundId,
            answer,
            updatedAt,
            updatedAt,
            roundId
        );
        if (roundId > latestRound) {
            latestRound = roundId;
        }
    }

    function setRoundData(
        int256 answer
    ) external {
        setRoundData(latestRound + 1, answer, block.timestamp);
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
        RoundData memory rd = rounds[latestRound];
        return (
            rd.roundId,
            rd.answer,
            rd.startedAt,
            rd.updatedAt,
            rd.answeredInRound
        );
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
        RoundData memory rd = rounds[_roundId];
        return (
            rd.roundId,
            rd.answer,
            rd.startedAt,
            rd.updatedAt,
            rd.answeredInRound
        );
    }
}
