// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { StrategyState } from "../../contracts/interfaces/IMapleStrategy.sol";

import { MapleAaveStrategy }  from "../../contracts/MapleAaveStrategy.sol";
import { MapleBasicStrategy } from "../../contracts/MapleBasicStrategy.sol";
import { MapleSkyStrategy }   from "../../contracts/MapleSkyStrategy.sol";

contract MapleBasicStrategyHarness is MapleBasicStrategy {

    function __accrueFees(address strategyVault_) external {
        _accrueFees(strategyVault_);
    }

    function __currentTotalAssets() external view returns (uint256) {
        return _currentTotalAssets(strategyVault);
    }

    function __setLocked(uint256 locked_) external {
        locked = locked_;
    }

    function __setLastRecordedTotalAssets(uint256 lastRecordedTotalAssets_) external {
        lastRecordedTotalAssets = lastRecordedTotalAssets_;
    }

    function __setStrategyFeeRate(uint256 strategyFeeRate_) external {
        strategyFeeRate = strategyFeeRate_;
    }

    function __setStrategyState(StrategyState strategyState_) external {
        strategyState = strategyState_;
    }

}

contract MapleSkyStrategyHarness is MapleSkyStrategy {

    function __accrueFees() external {
        _accrueFees(psm, savingsUsds);
    }

    function __currentTotalAssets() external view returns (uint256) {
        return _currentTotalAssets(psm, savingsUsds);
    }

    function __setLastRecordedTotalAssets(uint256 lastRecordedTotalAssets_) external {
        lastRecordedTotalAssets = lastRecordedTotalAssets_;
    }

    function __setLocked(uint256 locked_) external {
        locked = locked_;
    }

    function __setStrategyFeeRate(uint256 strategyFeeRate_) external {
        strategyFeeRate = strategyFeeRate_;
    }

    function __setStrategyState(StrategyState strategyState_) external {
        strategyState = strategyState_;
    }

}

contract MapleAaveStrategyHarness is MapleAaveStrategy {

    function __accrueFees(address aavePool_, address aaveToken_, address fundsAsset_) external {
        _accrueFees(aavePool_, aaveToken_, fundsAsset_);
    }

    function __currentTotalAssets() external view returns (uint256) {
        return _currentTotalAssets(aaveToken);
    }

    function __setLastRecordedTotalAssets(uint256 lastRecordedTotalAssets_) external {
        lastRecordedTotalAssets = lastRecordedTotalAssets_;
    }

    function __setLocked(uint256 locked_) external {
        locked = locked_;
    }

    function __setStrategyFeeRate(uint256 strategyFeeRate_) external {
        strategyFeeRate = strategyFeeRate_;
    }

    function __setStrategyState(StrategyState strategyState_) external {
        strategyState = strategyState_;
    }

}
