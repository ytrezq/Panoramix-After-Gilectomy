// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title RewardDistributor contract
/// @author Simon Mall
/// @notice Distribute reward tokens to reward trackers
/// @dev Need to implement `supportsInterface` function
interface IRewardDistributor is IERC165 {
    /// @dev Configure contract after deployment
    /// @param _rewardToken Reward token this distributor distributes
    /// @param _rewardTracker Reward tracker associated with this distributor
    function initialize(address _rewardToken, address _rewardTracker) external;

    /// @dev used to pause distributions. Must be turned on to start rewarding stakers
    /// @return True when distributor is paused
    function paused() external view returns(bool);

    /// @dev Updated with every distribution or pause
    /// @return Last distribution time
    function lastDistributionTime() external view returns (uint256);

    /// @dev Given in the constructor
    /// @return RewardTracker contract associated with this RewardDistributor
    function rewardTracker() external view returns (address);

    /// @dev Given in the constructor
    /// @return Reward token contract
    function rewardToken() external view returns (address);

    /// @dev Amount of tokens to be distributed every second
    /// @return The tokens per interval based on duration
    function tokensPerInterval() external view returns (uint256);

    /// @dev Calculates the pending rewards based on the time since the last distribution
    /// @return The pending rewards amount
    function pendingRewards() external view returns (uint256);

    /// @dev Distributes pending rewards to the reward tracker
    /// @return The amount of rewards distributed
    function distribute() external returns (uint256);

    /// @dev Updates the last distribution time to the current block timestamp
    /// @dev Can only be called by the contract owner.
    function updateLastDistributionTime() external;

    /// @dev Updates the tokens reward per interval the distributor distributes
    function updateTokensPerInterval() external;

    /// @dev Pause or resume reward emission
    /// @param _paused Indicates if the reward emission is paused
    function setPaused(bool _paused) external;

    /// @dev Withdraw tokens from this contract
    /// @param _token ERC20 token address, address(0) refers to native token(i.e. ETH)
    /// @param _recipient Recipient for the withdrawal
    /// @param _amount Amount of tokens to withdraw
    function withdrawToken(address _token, address _recipient, uint256 _amount) external;

    /// @dev Returns max withdrawable amount of reward tokens in this contract
    function maxWithdrawableAmount() external returns (uint256);

    /// @dev Emitted when rewards are distributed to reward tracker
    /// @param amount Amount of reward tokens distributed
    event Distribute(uint256 amount);

    /// @dev Emitted when `tokensPerInterval` is updated
    /// @param amount Amount of reward tokens for every second
    event TokensPerIntervalChange(uint256 amount);

    /// @dev Emitted when bonus multipler basispoint is updated
    /// @param basisPoints New basispoints for bonus multiplier
    event BonusMultiplierChange(uint256 basisPoints);

    /// @dev Emitted when reward emission is paused or resumed
    /// @param rewardTracker Reward tracker contract mapped to this distributor
    /// @param timestamp Timestamp of this event
    /// @param paused If distributor is paused or not
    event StatusChange(address indexed rewardTracker, uint256 timestamp, bool paused);
}
