// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin-contracts/interfaces/IERC20.sol";
import {IConcreteStandardVaultImpl} from "../../../src/interface/IConcreteStandardVaultImpl.sol";
import {IStrategyTemplate} from "../../../src/interface/IStrategyTemplate.sol";
import {Math} from "@openzeppelin-contracts/utils/math/Math.sol";

library InvariantUtils {
    /**
     * @dev Calculate total withdrawable assets from all active strategies
     */
    function calculateTotalWithdrawable(IConcreteStandardVaultImpl vault)
        internal
        view
        returns (uint256 totalWithdrawable)
    {
        address[] memory deallocationOrder = vault.getDeallocationOrder();
        for (uint256 i = 0; i < deallocationOrder.length; i++) {
            address strategy = deallocationOrder[i];
            IConcreteStandardVaultImpl.StrategyData memory data = vault.getStrategyData(strategy);

            if (data.status == IConcreteStandardVaultImpl.StrategyStatus.Active) {
                totalWithdrawable += IStrategyTemplate(strategy).maxWithdraw();
            }
        }
    }

    /**
     * @dev Calculate available liquidity (idle + withdrawable from strategies)
     */
    function calculateAvailableLiquidity(IConcreteStandardVaultImpl vault) internal view returns (uint256) {
        uint256 idleAssets = IERC20(vault.asset()).balanceOf(address(vault));
        uint256 withdrawableFromStrategies = calculateTotalWithdrawable(vault);
        return idleAssets + withdrawableFromStrategies;
    }

    /**
     * @dev Calculate sum of all strategy reported values
     */
    function calculateTotalReportedValue(IConcreteStandardVaultImpl vault)
        internal
        view
        returns (uint256 totalReported)
    {
        address[] memory strategies = vault.getStrategies();
        for (uint256 i = 0; i < strategies.length; i++) {
            address strategy = strategies[i];
            IConcreteStandardVaultImpl.StrategyData memory data = vault.getStrategyData(strategy);

            if (data.status != IConcreteStandardVaultImpl.StrategyStatus.Inactive) {
                totalReported += IStrategyTemplate(strategy).totalAllocatedValue();
            }
        }
    }

    /**
     * @dev Convert shares to assets using exact vault math with rounding
     * Uses same formula as vault: assets = shares * (totalAssets + 1) / (totalSupply + 10^decimalsOffset)
     * @param shares Amount of shares to convert
     * @param totalSupply Total supply of shares
     * @param totalAssets Total assets (e.g., from previewAccrueYield)
     * @param rounding Rounding direction
     * @return assets Equivalent asset amount
     */
    function convertToAssets(uint256 shares, uint256 totalSupply, uint256 totalAssets, Math.Rounding rounding)
        internal
        pure
        returns (uint256 assets)
    {
        // Use same formula as vault: shares.mulDiv(totalAssets + 1, totalSupply + 10^decimalsOffset, rounding)
        // For standard vaults, decimalsOffset is 0, so 10^decimalsOffset = 1
        return Math.mulDiv(shares, totalAssets + 1, totalSupply + 1, rounding);
    }

    /**
     * @dev Convert assets to shares using exact vault math with rounding
     * Uses same formula as vault: shares = assets * (totalSupply + 10^decimalsOffset) / (totalAssets + 1)
     * @param assets Amount of assets to convert
     * @param totalSupply Total supply of shares
     * @param totalAssets Total assets (e.g., from previewAccrueYield)
     * @param rounding Rounding direction
     * @return shares Equivalent share amount
     */
    function convertToShares(uint256 assets, uint256 totalSupply, uint256 totalAssets, Math.Rounding rounding)
        internal
        pure
        returns (uint256 shares)
    {
        // Use same formula as vault: assets.mulDiv(totalSupply + 10^decimalsOffset, totalAssets + 1, rounding)
        // For standard vaults, decimalsOffset is 0, so 10^decimalsOffset = 1
        return Math.mulDiv(assets, totalSupply + 1, totalAssets + 1, rounding);
    }
}
