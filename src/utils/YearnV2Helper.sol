// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import { IV2Vault } from "src/interfaces/yearn/IV2Vault.sol";

library YV2Helper {
    /**
     * @notice Get free funds in a V2 vault (totalAssets - lockedProfit)
     * @dev Implements Yearn V2 locked profit degradation formula
     * @param vault V2 vault address
     * @return Amount of free funds
     */
    function _getFreeFunds(address vault) internal view returns (uint256) {
        uint256 totalAssets = IV2Vault(vault).totalAssets();
        uint256 lockedFundsRatio = (block.timestamp - IV2Vault(vault).lastReport())
            * IV2Vault(vault).lockedProfitDegradation();

        if (lockedFundsRatio < 1e18) {
            uint256 lockedProfit = IV2Vault(vault).lockedProfit();
            lockedProfit -= (lockedFundsRatio * lockedProfit) / 1e18;
            return totalAssets - lockedProfit;
        } else {
            return totalAssets;
        }
    }

    /**
     * @notice Convert shares to assets for a V2 vault accounting for locked profit
     * @dev Yearn v2-style locked profit: emulate vault's internal lockedProfit decay instead of using a v3/4626-style convertToAssets.
     * @dev Used only for quoting LP_YYB share <-> asset value.
     * @param vault V2 vault address
     * @param shares Amount of shares to convert
     * @return Amount of assets
     */
    function sharesToAmount(address vault, uint256 shares) internal view returns (uint256) {
        uint256 totalSupply = IV2Vault(vault).totalSupply();
        if (totalSupply == 0) {
            return shares;
        }
        return shares * _getFreeFunds(vault) / totalSupply;
    }

    /**
     * @notice Convert assets to shares for a V2 vault accounting for locked profit
     * @dev Yearn v2-style locked profit: emulate vault's internal lockedProfit decay instead of using a v3/4626-style convertToShares.
     * @dev Used only for quoting LP_YYB share <-> asset value.
     * @param vault V2 vault address
     * @param amount Amount of assets to convert
     * @return Amount of shares
     */
    function amountToShares(address vault, uint256 amount) internal view returns (uint256) {
        uint256 freeFunds = _getFreeFunds(vault);
        if (freeFunds == 0) {
            return amount;
        }
        return amount * IV2Vault(vault).totalSupply() / freeFunds;
    }
}