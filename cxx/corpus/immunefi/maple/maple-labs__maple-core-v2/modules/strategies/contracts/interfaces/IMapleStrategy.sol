// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

/**
 *  @dev Represents the current state of a Maple strategy.
 *       Can be active, impaired, or inactive.
 */
enum StrategyState {
    Active,
    Impaired,
    Inactive
}

interface IMapleStrategy {

    /**************************************************************************************************************************************/
    /*** Events                                                                                                                         ***/
    /**************************************************************************************************************************************/

    /**
     *  @dev Emitted when the strategy is deactivated.
     */
    event StrategyDeactivated();

    /**
     *  @dev   Emitted when fees on the strategy's yield are collected.
     *  @param fees Amount of assets collected by the treasury.
     */
    event StrategyFeesCollected(uint256 fees);

    /**
     *  @dev   Emitted when the fee rate on the strategy's yield is updated.
     *  @param feeRate Percentage of yield that accrues to the treasury.
     */
    event StrategyFeeRateSet(uint256 feeRate);

    /**
     *  @dev   Emitted when assets are deposited into the strategy.
     *  @param assets Amount of assets deposited.
     */
    event StrategyFunded(uint256 assets);

    /**
     *  @dev   Emitted when assets are deposited into the strategy.
     *  @param assets Amount of assets deposited.
     *  @param shares Amount of shares minted.
     */
    event StrategyFunded(uint256 assets, uint256 shares);

    /**
     *  @dev Emitted when the strategy is impaired.
     */
    event StrategyImpaired();

    /**
     *  @dev   Emitted when the strategy is reactivated.
     *  @param updateAccounting Flag that defines if lastRecordedTotalAssets should be refreshed.
     */
    event StrategyReactivated(bool updateAccounting);

    /**
     *  @dev   Emitted when assets are withdrawn from the strategy.
     *  @param assets Amount of assets withdrawn.
     */
    event StrategyWithdrawal(uint256 assets);

    /**
     *  @dev   Emitted when assets are withdrawn from the strategy.
     *  @param assets Amount of assets withdrawn.
     *  @param shares Amount of shares burned.
     */
    event StrategyWithdrawal(uint256 assets, uint256 shares);

    /**************************************************************************************************************************************/
    /*** Strategy Admin Functions                                                                                                       ***/
    /**************************************************************************************************************************************/

    /**
     *  @dev Disables funding and marks all assets under management as zero.
     */
    function deactivateStrategy() external;

    /**
     *  @dev Disables funding and marks all assets under management as unrealized losses.
     */
    function impairStrategy() external;

    /**
     *  @dev   Resumes normal operation of the strategy.
     *  @param updateAccounting Flag that defines if fee accounting should be refreshed.
     */
    function reactivateStrategy(bool updateAccounting) external;

    /**
     *  @dev    Sets a new fee rate for the strategy.
     *          Can only be called when the strategy is active.
     *  @param  feeRate Percentage of yield that accrues to the Maple treasury.
     */
    function setStrategyFeeRate(uint256 feeRate) external;

    /**************************************************************************************************************************************/
    /*** Strategy View Functions                                                                                                        ***/
    /**************************************************************************************************************************************/

    /**
     *  @dev    Returns the current amount of assets managed by the strategy.
     *  @return assetsUnderManagement Amount of assets managed by the strategy.
     */
    function assetsUnderManagement() external view returns (uint256 assetsUnderManagement);

    /**
     *  @dev    Returns the type of the strategy.
     *  @return strategyType Type of the strategy.
     */
    function STRATEGY_TYPE() external view returns (string memory strategyType);

    /**
     *  @dev    Returns the current amount of unrealized losses.
     *  @return unrealizedLosses Amount of assets marked as unrealized losses.
     */
    function unrealizedLosses() external view returns (uint256 unrealizedLosses);

}
