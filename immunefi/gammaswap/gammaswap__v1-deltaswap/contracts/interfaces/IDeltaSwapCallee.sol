// SPDX-License-Identifier: GPL-v3
pragma solidity >=0.5.0;

interface IDeltaSwapCallee {
    function deltaSwapCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}
