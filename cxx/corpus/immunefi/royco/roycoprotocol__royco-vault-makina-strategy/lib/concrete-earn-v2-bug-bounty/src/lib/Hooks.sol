// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Hooks, IHook} from "../interface/IHook.sol";

/// @title HooksMainLib
/// @dev Hooks library for four user action hooks: pre-deposit, pre-mint, pre-withdraw, pre-redeem.
/// @dev Hooks library for two strategy hooks: pre-add-strategy, pre-remove-strategy.
library HooksLibV1 {
    uint8 constant PRE_DEPOSIT = 1;
    uint8 constant POST_DEPOSIT = 2;
    uint8 constant PRE_MINT = 3;
    uint8 constant POST_MINT = 4;
    uint8 constant PRE_WITHDRAW = 5;
    uint8 constant POST_WITHDRAW = 6;
    uint8 constant PRE_REDEEM = 7;
    uint8 constant POST_REDEEM = 8;

    uint8 constant PRE_ADD_STRATEGY = 9;
    uint8 constant PRE_REMOVE_STRATEGY = 10;

    /// @dev Checks if a specific flag is set in the Hooks struct
    /// @param h The Hooks storage reference
    /// @param flagIndex The flag index to check (0-95)
    /// @return True if the flag is set, false otherwise
    function flagIsSet(Hooks memory h, uint8 flagIndex) internal pure returns (bool) {
        if (flagIndex >= 96) return false;
        return (uint96(h.flags) & (1 << flagIndex)) != 0;
    }

    function checkIsValid(Hooks memory h, uint8 flagIndex) internal pure returns (bool) {
        if (!flagIsSet(h, flagIndex) || h.target == address(0)) return false;
        return true;
    }

    function preDeposit(Hooks memory h, address sender, uint256 assets, address receiver, uint256 totalAssets)
        internal
    {
        IHook(h.target).preDeposit(sender, assets, receiver, totalAssets);
    }

    function preMint(Hooks memory h, address sender, uint256 shares, address receiver, uint256 totalAssets) internal {
        IHook(h.target).preMint(sender, shares, receiver, totalAssets);
    }

    function preWithdraw(
        Hooks memory h,
        address sender,
        uint256 assets,
        address receiver,
        address owner,
        uint256 totalAssets
    ) internal {
        IHook(h.target).preWithdraw(sender, assets, receiver, owner, totalAssets);
    }

    function preRedeem(
        Hooks memory h,
        address sender,
        uint256 shares,
        address receiver,
        address owner,
        uint256 totalAssets
    ) internal {
        IHook(h.target).preRedeem(sender, shares, receiver, owner, totalAssets);
    }

    function postDeposit(
        Hooks memory h,
        address sender,
        uint256 assets,
        uint256 shares,
        address receiver,
        uint256 totalAssets
    ) internal {
        IHook(h.target).postDeposit(sender, assets, shares, receiver, totalAssets);
    }

    function postMint(
        Hooks memory h,
        address sender,
        uint256 assets,
        uint256 shares,
        address receiver,
        uint256 totalAssets
    ) internal {
        IHook(h.target).postMint(sender, assets, shares, receiver, totalAssets);
    }

    function postWithdraw(
        Hooks memory h,
        address sender,
        uint256 assets,
        uint256 shares,
        address receiver,
        uint256 totalAssets
    ) internal {
        IHook(h.target).postWithdraw(sender, assets, shares, receiver, totalAssets);
    }

    function postRedeem(
        Hooks memory h,
        address sender,
        uint256 assets,
        uint256 shares,
        address receiver,
        uint256 totalAssets
    ) internal {
        IHook(h.target).postRedeem(sender, assets, shares, receiver, totalAssets);
    }
}
