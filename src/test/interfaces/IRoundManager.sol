pragma solidity 0.8.9;

interface IRoundsManager {
    function initializeRound() external;

    function lastRoundLengthUpdateRound() external view returns (uint256);
    
    function lastRoundLengthUpdateStartBlock() external view returns (uint256);

    function roundLength() external view returns (uint256);

    function currentRound() external view returns (uint256);
}
