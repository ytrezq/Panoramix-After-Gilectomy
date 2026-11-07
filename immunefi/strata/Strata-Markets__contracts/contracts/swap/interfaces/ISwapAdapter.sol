// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface ISwapAdapter {
    function swap(
        address router,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address recipient,
        bytes calldata data,
        uint256 value
    ) external payable returns (uint256 amountOut);
}
