// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { StrategyState } from "../IMapleStrategy.sol";

interface IMapleAaveStrategyStorage {

    /**
     *  @dev    Returns the address of the Aave pool.
     *  @return aavePool Address of the Aave pool.
     */
    function aavePool() external view returns (address aavePool);

    /**
     *  @dev    Returns the address of the Aave token.
     *  @return aaveToken Address of the Aave token.
     */
    function aaveToken() external view returns (address aaveToken);

    /**
     *  @dev    Returns the address of the underlying asset.
     *  @return fundsAsset Address of the underlying asset.
     */
    function fundsAsset() external view returns (address fundsAsset);

    /**
     *  @dev    Returns the last recorded value of all assets managed by the strategy.
     *  @return lastRecordedTotalAssets Last recorded value of all assets managed by the strategy.
     */
    function lastRecordedTotalAssets() external view returns (uint256 lastRecordedTotalAssets);

    /**
     *  @dev    Returns the address of the underlying asset.
     *  @return pool Address of the Maple pool.
     */
    function pool() external view returns (address pool);

    /**
     *  @dev    Returns the address of the Maple pool manager.
     *  @return poolManager Address of the Maple pool manager.
     */
    function poolManager() external view returns (address poolManager);

    /**
    *  @dev    Returns the percentage of the strategy's yield collected by the Maple treasury.
    *  @return strategyFeeRate Percentage of yield collected by the treasury.
    */
    function strategyFeeRate() external view returns (uint256 strategyFeeRate);

    /**
     *  @dev    Returns the current state of the strategy.
     *          Can be active, inactive, or impaired.
     *  @return strategyState Current state of the strategy.
     */
    function strategyState() external view returns (StrategyState strategyState);

}
