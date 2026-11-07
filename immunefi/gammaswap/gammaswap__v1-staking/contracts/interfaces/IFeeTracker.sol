// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./IRewardTracker.sol";

/// @title Interface for FeeTracker contract
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @notice Track protocol fees reward to staked GS/esGS tokens
/// @dev Interface of type IRewardTracker, which is of type ERC20
interface IFeeTracker is IRewardTracker {
    /// @dev Set through initialize() function
    /// @return Get address of bonus tracker
    function bonusTracker() external view returns(address);

    /// @dev Set through initialize() function
    /// @return Returns bonus token address
    function bnGs() external view returns(address);

    /// @dev Given in the constructor, can be updated through setBonusLimit
    /// @return Max bonus rate for this fee tracker to increase the fee share
    function bnRateCap() external view returns(uint256);

    /// @dev Sum of inactive points of all users
    /// @return Get total inactive points
    function totalInactivePoints() external view returns(uint256);

    /// @dev Updated through _updateInactivePoints() function
    /// @param account - user address to track inactive points
    /// @return Get inactive points by user address
    function inactivePoints(address account) external view returns(uint256);

    /// @dev Update bonus rate cap
    /// @param _bnRateCap - new bonus rate limit
    function setBonusLimit(uint256 _bnRateCap) external;
}