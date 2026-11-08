// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IGauge {
    function TOKEN() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function rewardToken() external view returns (address);
    function deposit(uint256 amount) external;
    function getReward() external;
    function withdraw(uint256 amount) external;
    function withdrawAll() external;
    function withdrawAllAndHarvest() external;
}