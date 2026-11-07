// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IStrategyAprPairProvider} from "../../interfaces/IAprPairFeed.sol";
import {
    IAccessControlManager
} from "../../../governance/interfaces/IAccessControlManager.sol";
import {IsUSDat} from "./IsUSDat.sol";
import {IStrcPriceOracle} from "./IStrcPriceOracle.sol";

/**
 * @title SaturnAprPairProvider
 * @notice Provides target APR (Senior benchmark) and base APR (STRC dividend rate) for the Saturn CDO.
 *
 * Target APR:
 *   - Represents the Senior tranche benchmark: a fixed percentage of the STRC dividend rate.
 *   - Updatable by the feed role (the Keeper reads currentDividend from STRC API
 *     and applies a ratio, e.g. 0.7, to derive the target APR).
 *
 * Base APR:
 *   - Computed on-chain from sUSDat's STRC vesting state and STRC oracle price.
 *   - Represents the current annualized STRC dividend yield.
 *   - With riskPremium = 100%, this value is canceled from the Senior APR calculation
 *     (aprSrt = max(aprTarget, aprBase * 0) = aprTarget).
 *   - Retained for informational purposes (dashboards, monitoring).
 */
contract SaturnAprPairProvider is IStrategyAprPairProvider {
    bytes32 public constant UPDATER_FEED_ROLE = keccak256("UPDATER_FEED_ROLE");

    uint256 constant SECONDS_PER_YEAR = 31_536_000;

    /// @notice Maximum allowed APR: 40% (scaled to 1e12)
    uint256 constant BOUND_MAX = .4e12;

    IAccessControlManager public immutable acm;
    IsUSDat public immutable sUSDat;
    IStrcPriceOracle public immutable strcOracle;

    /// @notice Senior benchmark APR: fixed % of STRC dividend rate
    /// @dev Updated by the Keeper when Saturn distributes new STRC rewards (~monthly).
    ///      Scaled by 1e12 (12 decimal places).
    int64 public aprTarget;

    event AprTargetUpdated(int64 oldApr, int64 newApr);

    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);

    modifier onlyRole(bytes32 role) {
        if (!acm.hasRole(role, msg.sender)) {
            revert AccessControlUnauthorizedAccount(msg.sender, role);
        }
        _;
    }

    constructor(IAccessControlManager acm_, IsUSDat sUSDat_, int64 aprTarget_) {
        acm = acm_;
        sUSDat = sUSDat_;
        strcOracle = IStrcPriceOracle(sUSDat_.getStrcOracle());
        aprTarget = aprTarget_;
    }

    function getAprPair()
        external
        view
        returns (int64 aprTarget_, int64 aprBase, uint64 timestamp)
    {
        timestamp = uint64(block.timestamp);
        aprTarget_ = aprTarget;
        aprBase = getAPRbase();
    }

    /**
     * @notice Update the target APR (benchmark for Senior tranche)
     * @dev Called by the Keeper when STRC announces the dividends.
     *      Keeper reads currentDividend from STRC API and applies seniorShare ratio.
     *      Example: currentDividend = 11.5%, seniorShare = 70% → aprTarget = 8.05%
     * @param newAprTarget The new target APR, scaled by 1e12
     */
    function setAprTarget(int64 newAprTarget) external onlyRole(UPDATER_FEED_ROLE) {
        require(
            newAprTarget >= 0 && uint64(newAprTarget) <= BOUND_MAX,
            "InvalidAprTarget"
        );
        int64 old = aprTarget;
        aprTarget = newAprTarget;
        emit AprTargetUpdated(old, newAprTarget);
    }

    /**
     * @notice Computes annualized STRC dividend yield from on-chain sUSDat vesting state
     * @dev Formula: (unvestedSTRC * strcPrice / 10^priceDecimals) * SECONDS_PER_YEAR
     *              / remainingVestingTime / totalAssets
     *      Returns 0 when there is no active vesting (between distributions).
     * @return apr The annualized base APR as int64, scaled by 1e12
     */
    function getAPRbase() public view returns (int64) {
        uint256 period = sUSDat.vestingPeriod();
        uint256 lastDist = sUSDat.lastDistributionTimestamp();

        if (lastDist == 0 || period == 0) return 0;

        uint256 elapsed = block.timestamp - lastDist;
        if (elapsed >= period) return 0; // no active vesting

        uint256 unvestedStrc = sUSDat.getUnvestedAmount();
        uint256 total = sUSDat.totalAssets();
        if (total == 0 || unvestedStrc == 0) return 0;

        // Convert unvested STRC to USD value using the STRC oracle.
        // IMPORTANT: The result (unvestedUsd) must be in the same decimal scale as
        // sUSDat.totalAssets() (USDat, 6 decimals) for the APR ratio to be correct.
        // This requires: strcDecimals == assetDecimals.
        // Verify against the real sUSDat contract before mainnet deployment.
        (uint256 strcPrice, uint8 priceDecimals) = strcOracle.getPrice();
        if (strcPrice == 0) return 0;

        uint256 unvestedUsd = unvestedStrc * strcPrice / (10 ** priceDecimals);

        // Annualize: (unvestedUsd / remainingTime) * SECONDS_PER_YEAR / totalAssets
        uint256 remainingTime = period - elapsed;

        // apr scaled to 1e12: (unvestedUsd * SECONDS_PER_YEAR * 1e12) / remainingTime / total
        uint256 apr = unvestedUsd * SECONDS_PER_YEAR * 1e12 / remainingTime / total;

        if (apr > BOUND_MAX) return 0; // sanity check

        return int64(int256(apr));
    }
}
