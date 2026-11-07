// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

interface IRewardPrePay {
    function MORPHO() external view returns (address);
    function initializeStrategy(address _strategy, uint256 _earned, uint256 _claimed) external;
    function strategyInitialized(address _strategy) external view returns (bool);
    function claimable(address _strategy) external view returns (uint256);
    function claim() external;
    function updateReward(address _strategy, uint256 _amount) external;
    function batchUpdateReward(address[] memory _strategies, uint256[] memory _amounts) external;
    function morphoClaim(
        address strategy,
        uint256 newAmount,
        address distr,
        bytes calldata txData
    ) external;
    function batchMerklClaim(
        address[] calldata strategies,
        uint256[] calldata newAmounts,
        address[] calldata distrs,
        bytes[] calldata txDatas
    ) external;
}
