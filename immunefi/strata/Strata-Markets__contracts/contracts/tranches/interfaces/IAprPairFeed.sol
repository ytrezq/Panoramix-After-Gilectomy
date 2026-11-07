// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;


interface IAprPairFeed {
    struct TRound {
        // SD7x12
        int64 aprTarget;
        int64 aprBase;
        uint64 updatedAt;
        uint64 answeredInRound;
    }

    function updateRoundData(int64 newAprTarget, int64 newAprBase, uint64 timestamp) external;
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function getRoundData(uint64 roundId)external view returns (TRound memory);
    function latestRoundData() external view returns (TRound memory);
}

interface IAprPairFeedListener {
    function onAprChanged() external;
}

interface IStrategyAprPairProvider {
    function getAprPair () external view returns (int64 aprTarget, int64 aprBase, uint64 timestamp);
}
interface IAprProvider {
    function getApr () external view returns (int64 apr, uint64 timestamp);
}
