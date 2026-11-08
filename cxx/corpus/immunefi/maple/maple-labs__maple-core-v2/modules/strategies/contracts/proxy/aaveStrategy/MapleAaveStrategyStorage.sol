// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { StrategyState }             from "../../interfaces/IMapleStrategy.sol";
import { IMapleAaveStrategyStorage } from "../../interfaces/aaveStrategy/IMapleAaveStrategyStorage.sol";

contract MapleAaveStrategyStorage is IMapleAaveStrategyStorage {

    /**************************************************************************************************************************************/
    /*** State Variables                                                                                                                ***/
    /**************************************************************************************************************************************/

    // Used for reentrancy checks.
    uint256 public locked;

    address public override fundsAsset;
    address public override pool;
    address public override poolManager;

    address public override aavePool;
    address public override aaveToken;

    uint256 public override lastRecordedTotalAssets;
    uint256 public override strategyFeeRate;

    StrategyState public override strategyState;

}
