//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

interface IRewardsDistributor {
    function claimRewardToken(address holder) external;
}