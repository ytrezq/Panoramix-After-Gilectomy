// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { StrategyState }              from "../../interfaces/IMapleStrategy.sol";
import { IMapleBasicStrategyStorage } from "../../interfaces/basicStrategy/IMapleBasicStrategyStorage.sol";

contract MapleBasicStrategyStorage is IMapleBasicStrategyStorage {

    /**************************************************************************************************************************************/
    /*** State Variables                                                                                                                ***/
    /**************************************************************************************************************************************/

    uint256 public locked;  // Used when checking for reentrancy.

    address public override fundsAsset;
    address public override pool;
    address public override poolManager;
    address public override strategyVault;

    uint256 public override lastRecordedTotalAssets;
    uint256 public override strategyFeeRate;

    StrategyState public override strategyState;

}
