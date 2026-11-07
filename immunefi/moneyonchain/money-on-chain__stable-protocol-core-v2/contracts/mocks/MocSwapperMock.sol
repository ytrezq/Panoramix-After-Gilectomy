// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { IMocSwapper } from "../interfaces/IMocSwapper.sol";

contract MocSwapperMock is IMocSwapper {
    uint256 public maxAmountToSwap = type(uint256).max;
    uint256 public swapResult;

    function setMaxAmountToSwap(uint256 maxAmountToSwap_) external {
        maxAmountToSwap = maxAmountToSwap_;
    }

    function setSwapResult(uint256 swapResult_) external {
        swapResult = swapResult_;
    }

    function swapCoinbase(address, uint256, address) external payable returns (uint256 amountOut) {
        return swapResult == 0 ? msg.value : swapResult;
    }

    function swapCoinbaseExactOutput(address, uint256 amountOut_, address) external payable returns (uint256 amountIn) {
        return amountOut_;
    }

    function swapRC20(address, address, uint256 amountIn_, uint256, address) external returns (uint256 amountOut) {
        return swapResult == 0 ? amountIn_ : swapResult;
    }

    function swapRC20ExactOutput(
        address,
        address,
        uint256 amountOut_,
        uint256,
        address
    ) external returns (uint256 amountIn) {
        return amountOut_;
    }

    function getSafeMaxAmountToSwap(address, address) external view returns (uint256 maxAmountToSwap_) {
        return maxAmountToSwap;
    }
}
