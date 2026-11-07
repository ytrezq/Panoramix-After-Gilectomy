// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IAerodromeGauge {
    function stakingToken() external view returns (address);

    function rewardToken() external view returns (address);

    function deposit(uint256 _amount) external;

    function withdraw(uint256 _amount) external;

    function getReward(address _account) external;
}
