//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

/**
 * @title Compound's CometRewards Contract
 * @notice Hold and claim token rewards
 * @author Compound
 */
interface ICometRewards {
    struct RewardOwed {
        address token;
        uint owed;
    }
    function claim(address comet, address src, bool accrue) external;
    function getRewardOwed(address comet, address account) external returns (RewardOwed memory);
}