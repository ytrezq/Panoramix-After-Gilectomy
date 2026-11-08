// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

struct Hooks {
    address target;
    uint96 flags;
}

interface IHook {
    // USER ACTION HOOKS
    function preDeposit(address sender, uint256 assets, address receiver, uint256 totalAssets) external;
    function preMint(address sender, uint256 shares, address receiver, uint256 totalAssets) external;
    function preWithdraw(address sender, uint256 assets, address receiver, address owner, uint256 totalAssets) external;
    function preRedeem(address sender, uint256 shares, address receiver, address owner, uint256 totalAssets) external;
    function postDeposit(address sender, uint256 assets, uint256 shares, address receiver, uint256 totalAssets) external;
    function postMint(address sender, uint256 assets, uint256 shares, address receiver, uint256 totalAssets) external;
    function postWithdraw(address sender, uint256 assets, uint256 shares, address receiver, uint256 totalAssets)
        external;
    function postRedeem(address sender, uint256 assets, uint256 shares, address receiver, uint256 totalAssets) external;
}
