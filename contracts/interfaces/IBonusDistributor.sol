// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./IRewardDistributor.sol";

/// @title Interface for BonusDistributor contract
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @notice Track bonus rewards for staked GS/esGS tokens
/// @dev Interface of type IRewardDistributor, which is of type ERC20
interface IBonusDistributor is IRewardDistributor {

    /// @dev Set through setBonusMultiplier
    /// @return Basis points for distribution
    function bonusMultiplierBasisPoints() external view returns(uint256);

    /// @notice Set basis points
    /// @param _bonusMultiplierBasisPoints - bonus multiplier
    function setBonusMultiplier(uint256 _bonusMultiplierBasisPoints) external;
}
