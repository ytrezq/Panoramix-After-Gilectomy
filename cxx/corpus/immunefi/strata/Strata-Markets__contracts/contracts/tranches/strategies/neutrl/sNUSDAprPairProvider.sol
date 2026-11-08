// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IsNUSD} from "./IsNUSD.sol";
import {IsUSDe} from "../ethena/IsUSDe.sol";
import {IStrategyAprPairProvider} from "../../interfaces/IAprPairFeed.sol";

/**
 * @title sNUSD AprPairProvider
 * @notice Fetches target APR from Ethena's sUSDe and base APR from Neutrl's sNUSD
 */
contract sNUSDAprPairProvider is IStrategyAprPairProvider {
    uint256 constant SECONDS_PER_YEAR = 31_536_000;
    uint256 constant VESTING_PERIOD_sUSDe = 8 hours;

    IsUSDe public immutable sUSDe;
    IsNUSD public immutable sNUSD;

    constructor(IsUSDe _sUSDe, IsNUSD _sNUSD) {
        sUSDe = _sUSDe;
        sNUSD = _sNUSD;
    }

    function getAprPair() external view returns (int64 aprTarget, int64 aprBase, uint64 timestamp) {
        timestamp = uint64(block.timestamp);
        aprTarget = getAPRtarget();
        aprBase = getAPRbase();
    }

    /**
     * @notice Calculates the target APR based on Ethena's sUSDe vesting
     * @dev Uses the same calculation as sUSDeAprPairProvider's getAPRbase
     * @return The target APR as an int64, scaled by 1e12 (12 decimal places)
     */
    function getAPRtarget() public view returns (int64) {
        uint256 t1 = block.timestamp;
        uint256 t0 = sUSDe.lastDistributionTimestamp();
        uint256 deltaT = t1 - t0;

        if (deltaT >= VESTING_PERIOD_sUSDe) {
            // No active vesting
            return 0;
        }

        uint256 unvestedAmount = sUSDe.getUnvestedAmount();
        uint256 totalAssets = sUSDe.totalAssets();

        uint256 apr = unvestedAmount * SECONDS_PER_YEAR * 1e18
            / (VESTING_PERIOD_sUSDe - deltaT)
            / totalAssets;

        return int64(int256(apr * 1e12 / 1e18));
    }

    /**
     * @notice Calculates the base APR for sNUSD based on the current vesting amount
     * @dev sNUSD has a configurable vesting period, unlike sUSDe's fixed 8 hours
     * @return The base APR as an int64, scaled by 1e12 (12 decimal places)
     */
    function getAPRbase() public view returns (int64) {
        uint256 vestingPeriod = sNUSD.vestingPeriod();
        uint256 t1 = block.timestamp;
        uint256 t0 = sNUSD.lastDistributionTimestamp();
        uint256 deltaT = t1 - t0;

        if (deltaT >= vestingPeriod) {
            // No active vesting
            return 0;
        }

        uint256 unvestedAmount = sNUSD.getUnvestedAmount();
        uint256 totalAssets = sNUSD.totalAssets();

        uint256 apr = unvestedAmount * SECONDS_PER_YEAR * 1e18
            / (vestingPeriod - deltaT)
            / totalAssets;

        return int64(int256(apr * 1e12 / 1e18));
    }
}

