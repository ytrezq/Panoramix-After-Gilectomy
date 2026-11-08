// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract V3SwapRouterMock {
    uint256 public price = 1 ether;
    uint256 public lastAmountOutMinimum;

    function exactInputSingle(
        IV3SwapRouter.ExactInputSingleParams calldata params
    ) external payable returns (uint256 amountOut) {
        SafeERC20.safeTransferFrom(IERC20(params.tokenIn), msg.sender, address(this), params.amountIn);

        amountOut = (params.amountIn * price) / 10 ** 18;
        lastAmountOutMinimum = params.amountOutMinimum;

        SafeERC20.safeTransfer(IERC20(params.tokenOut), params.recipient, amountOut);
    }

    function setPrice(uint256 price_) external {
        price = price_;
    }
}
