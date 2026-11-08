// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { IMapleStrategy } from "../IMapleStrategy.sol";

import { IMapleAaveStrategyStorage } from "./IMapleAaveStrategyStorage.sol";

interface IMapleAaveStrategy is IMapleStrategy, IMapleAaveStrategyStorage {

    /**************************************************************************************************************************************/
    /*** Events                                                                                                                         ***/
    /**************************************************************************************************************************************/

    /**
     *  @dev   Emitted when rewards are claimed from the Aave Rewards Controller.
     *  @param rewardToken The address of the reward token.
     *  @param amount      The amount of rewardToken claimed.
     */
    event RewardsClaimed(address indexed rewardToken, uint256 amount);

    /**************************************************************************************************************************************/
    /*** Strategy Manager Functions                                                                                                     ***/
    /**************************************************************************************************************************************/

    /**
     *  @dev   Deploys assets from the Maple pool into the strategy.
     *         Funding can only be attempted when the strategy is active.
     *  @param assetsIn Amount of assets to deploy.
     */
    function fundStrategy(uint256 assetsIn) external;

    /**
     *  @dev   Withdraw assets from the strategy back into the Maple pool.
     *         Withdrawals can be attempted even if the strategy is impaired or inactive.
     *  @param assetsOut Amount of assets to withdraw.
     */
    function withdrawFromStrategy(uint256 assetsOut) external;

    /**************************************************************************************************************************************/
    /*** Strategy Admin Functions                                                                                                       ***/
    /**************************************************************************************************************************************/

    /**
     *  @dev   Claims rewards from the Aave Incentives Controller.
     *  @param assets      The list of assets to check eligible distributions before claiming rewards. Pass a/s/vToken addresses
     *  @param amount      The amount of rewards to claim, expressed in wei. Pass MAX_UINT to claim the entire unclaimed reward balance
     *  @param rewardToken The address of the reward token (e.g., stkAAVE)
     */
    function claimRewards(address[] calldata assets, uint256 amount, address rewardToken) external;

}
