// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { IMapleStrategy } from "../IMapleStrategy.sol";

import { IMapleSkyStrategyStorage } from "./IMapleSkyStrategyStorage.sol";

interface IMapleSkyStrategy is IMapleStrategy, IMapleSkyStrategyStorage {

    /**************************************************************************************************************************************/
    /*** Events                                                                                                                         ***/
    /**************************************************************************************************************************************/

    /**
     *  @dev Emitted when the address of the Sky Peg Stability Module (PSM) contract is set.
     *  @param psm Address of the new PSM contract.
     */
    event PsmSet(address indexed psm);

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
     *  @dev   Sets the address of the Sky Peg Stability Module (PSM) contract.
     *  @param psm Address of the new PSM contract.
     */
    function setPsm(address psm) external;

}
