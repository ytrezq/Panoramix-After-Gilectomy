// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IPOLErrors } from "./IPOLErrors.sol";
import { IStakingRewards } from "../../base/IStakingRewards.sol";

interface IBGTStaker is IPOLErrors, IStakingRewards {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when a token has been recovered.
    /// @param token The token that has been recovered.
    /// @param amount The amount of token recovered.
    event Recovered(address token, uint256 amount);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Notify the staker of a new reward amount.
    /// @dev Can only be called by the fee collector.
    /// @param reward The amount of reward to notify.
    function notifyRewardAmount(uint256 reward) external;

    /// @notice Recover ERC20 tokens.
    /// @dev Revert if the tokenAddress is the reward token.
    /// @dev Can only be called by the owner.
    /// @param tokenAddress The address of the token to recover.
    /// @param tokenAmount The amount of token to recover.
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external;

    /// @notice Set the rewards duration.
    /// @dev Revert if the reward cycle has started.
    /// @dev Can only be called by the owner.
    /// @param _rewardsDuration The rewards duration.
    function setRewardsDuration(uint256 _rewardsDuration) external;

    /// @notice Stake BGT tokens.
    /// @dev Can only be called by the BGT contract.
    /// @param account The account to stake for.
    /// @param amount The amount of BGT to stake.
    function stake(address account, uint256 amount) external;

    /// @notice Withdraw BGT tokens.
    /// @dev Can only be called by the BGT contract.
    /// @param account The account to withdraw for.
    /// @param amount The amount of BGT to withdraw.
    function withdraw(address account, uint256 amount) external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  STATE MUTATING FUNCTIONS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Get the reward.
    /// @dev Get the reward for the caller.
    /// @return The reward amount.
    function getReward() external returns (uint256);
}
