// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { StrategyState } from "../IMapleStrategy.sol";

interface IMapleBasicStrategyStorage {

    /**************************************************************************************************************************************/
    /*** Functions                                                                                                                      ***/
    /**************************************************************************************************************************************/

    /**
     *  @dev    Gets the address of the funds asset.
     *  @return fundsAsset The address of the funds asset.
     */
    function fundsAsset() external view returns (address fundsAsset);

    /**
     *  @dev    Gets the last recorded total assets.
     *  @return lastRecordedTotalAssets The last recorded total assets of the strategy.
     */
    function lastRecordedTotalAssets() external view returns (uint256 lastRecordedTotalAssets);

    /**
     *  @dev    Returns the address of the pool contract.
     *  @return pool Address of the pool contract.
     */
    function pool() external view returns (address pool);

    /**
     *  @dev    Returns the address of the pool manager contract.
     *  @return poolManager Address of the pool manager contract.
     */
    function poolManager() external view returns (address poolManager);

    /**
     *  @dev    Returns the strategy fee rate.
     *  @return strategyFeeRate The strategy fee rate which denotes the proportion of the yield to take as fees.
     */
    function strategyFeeRate() external view returns (uint256 strategyFeeRate);

    /**
     *  @dev    Returns the current state of the strategy.
     *          Can be active, inactive, or impaired.
     *  @return strategyState Current state of the strategy.
     */
    function strategyState() external view returns (StrategyState strategyState);

    /**
     *  @dev    Returns the address of the ERC4626 compliant Vault.
     *  @return strategyVault Address of the ERC4626 compliant Vault.
     */
    function strategyVault() external view returns (address strategyVault);

}
