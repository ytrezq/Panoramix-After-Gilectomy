// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IsUSDe } from "./IsUSDe.sol";
import { IStrategyAprPairProvider } from "../../interfaces/IAprPairFeed.sol";

interface IsUSDS {
    // Sky Savings Rate
    function ssr () external view returns (uint256);
    // Timestamp
    function rho () external view returns (uint64);
}

/**
 * @title sUSDe AprPairProvider
 * @notice Fetches target APR from Sky Protocol and base APR from Ethena's sUSDe
 */
contract sUSDeAprPairProvider is IStrategyAprPairProvider {

    uint256 constant SECONDS_PER_YEAR = 31_536_000;
    uint256 constant VESTING_PERIOD_sUSDe = 8 hours;

    IsUSDS public sUSDS;
    IsUSDe public sUSDe;

    constructor (
        IsUSDS _sUSDS,
        IsUSDe _sUSDe
    ) {
        sUSDS = _sUSDS;
        sUSDe = _sUSDe;
    }

    function getAprPair () external view returns (int64 aprTarget, int64 aprBase, uint64 timestamp) {
        timestamp = uint64(block.timestamp);
        aprTarget = getAPRtarget();
        aprBase = getAPRbase();
    }

    /**
     * @notice Calculates the target APR based on the Sky Savings Rate (SSR)
     * @dev Fetches the current SSR (Growth Factor) from Sky's Protocol and converts it to an annual rate
     * @return The target APR as an int64, scaled by 1e12 (12 decimal places)
     */
    function getAPRtarget () public view returns (int64) {
        // growth per second
        uint256 ssr = sUSDS.ssr();
        uint256 ONE_in = 1e27;
        uint256 ONE_out = 1e12;
        if (ssr < ONE_in) {
            // not possible, but just in case: return 0 if APRssr is negative
            return 0;
        }
        uint256 apr = (ssr - ONE_in) * SECONDS_PER_YEAR * ONE_out / ONE_in;
        return int64(int256(apr));
    }

    /**
     * @notice Calculates the base APR for sUSDe based on the current vesting amount
     */
    function getAPRbase () public view returns (int64) {
        uint256 t1 = block.timestamp;
        uint256 t0 = sUSDe.lastDistributionTimestamp();
        uint256 deltaT = t1 - t0;

        if (deltaT >= VESTING_PERIOD_sUSDe) {
            // No distribution yet;
            return 0;
        }

        uint256 unvestedAmount = sUSDe.getUnvestedAmount();
        uint256 totalAssets = sUSDe.totalAssets();

        uint256 apr = unvestedAmount * SECONDS_PER_YEAR * 1e18
            / (VESTING_PERIOD_sUSDe - deltaT)
            / totalAssets;

        return int64(int256(apr * 1e12 / 1e18));
    }
}
