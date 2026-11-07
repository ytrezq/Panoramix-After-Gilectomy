// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface ISkyPSM3 {
    function swapExactIn(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver,
        uint256 referralCode
    ) external returns (uint256 amountOut);

    function previewSwapExactIn(
        address assetIn,
        address assetOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut);

    function convertToAssets(address asset, uint256 numShares) external view returns (uint256);
}
