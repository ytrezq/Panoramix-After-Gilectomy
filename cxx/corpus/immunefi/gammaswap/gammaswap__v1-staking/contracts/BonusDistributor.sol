// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "./interfaces/IBonusDistributor.sol";
import "./interfaces/IRewardTracker.sol";
import "./RewardDistributor.sol";

/// @title BonusDistributor Contract
/// @author Simon Mall
/// @notice Multiplier Points reward contract for protocol revenue share
/// @dev Rewards(bnGs) are distributed linearly for a year
contract BonusDistributor is Ownable2Step, Initializable, IBonusDistributor, RewardDistributor {
    using SafeERC20 for IERC20;

    /// @notice Max basis points for distribution
    /// @notice 10000 -> 100%
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public constant BONUS_DURATION = 365 days;

    /// @notice Limited to `BASIS_POINTS_DIVISOR`
    uint256 public override bonusMultiplierBasisPoints;

    /// @notice Reward Token - bnGs
    constructor() {
    }

    /// @inheritdoc IBonusDistributor
    function setBonusMultiplier(uint256 _bonusMultiplierBasisPoints) external override virtual onlyOwner {
        require(lastDistributionTime != 0, "BonusDistributor: invalid lastDistributionTime");
        require(_bonusMultiplierBasisPoints <= 24*BASIS_POINTS_DIVISOR, "BonusDistributor: invalid multiplier points");

        IRewardTracker(rewardTracker).updateRewards();
        bonusMultiplierBasisPoints = _bonusMultiplierBasisPoints;

        updateTokensPerInterval();

        emit BonusMultiplierChange(_bonusMultiplierBasisPoints);
    }

    /// @inheritdoc IRewardDistributor
    function updateTokensPerInterval() public override(IRewardDistributor, RewardDistributor) virtual {
        uint256 supply = IERC20(rewardTracker).totalSupply();
        tokensPerInterval = supply * bonusMultiplierBasisPoints / (BASIS_POINTS_DIVISOR * BONUS_DURATION);
    }

    /// @inheritdoc RewardDistributor
    function setTokensPerInterval(uint256 _amount) external virtual override(RewardDistributor) {
    }
}
