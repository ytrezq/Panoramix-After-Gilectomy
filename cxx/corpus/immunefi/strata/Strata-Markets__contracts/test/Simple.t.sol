// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Test} from "forge-std/Test.sol";
import "forge-std/console2.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


contract SimpleTest is Test {

    function test_Flow() public {
        string memory rpcUrl = vm.envString("MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(rpcUrl, 23_641_000);
        vm.selectFork(forkId);


        address tokenIn  = address(0xdAC17F958D2ee523a2206206994597C13D831ec7); // usdt
        address tokenOut = address(0x4c9EDD5852cd905f086C759E8383e09bff1E68B3); // usde
        address router   = address(0xE592427A0AEce92De3Edee1F18E0157C05861564);

        address someUsdtHolder = address(0x6AC38D1b2f0c0c3b9E816342b1CA14d91D5Ff60B);
        vm.startPrank(someUsdtHolder);

        SafeERC20.forceApprove(IERC20(tokenIn), router, type(uint256).max);

        // Create the params for the swap
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: 100,
            recipient: address(this),
            deadline: block.timestamp + 15 minutes,
            amountIn: 1e6,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0 // No price limit
        });
        // Execute the swap
        uint256 amountOut = ISwapRouter(router).exactInputSingle(params);
        console2.log("Amount out: ", amountOut);
    }

    // function swapExactOutputSingle(
    //     address tokenIn,
    //     address tokenOut,
    //     uint24 fee,
    //     uint256 amountOut,
    //     uint256 amountInMaximum
    // ) external returns (uint256 amountIn) {
    //     // Approve the router to spend the token
    //     IERC20(tokenIn).approve(address(swapRouter), amountInMaximum);

    //     // Create the params for the swap
    //     ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
    //         tokenIn: tokenIn,
    //         tokenOut: tokenOut,
    //         fee: fee,
    //         recipient: address(this),
    //         deadline: block.timestamp + 15 minutes,
    //         amountOut: amountOut,
    //         amountInMaximum: amountInMaximum,
    //         sqrtPriceLimitX96: 0 // No price limit
    //     });

    //     // Execute the swap
    //     amountIn = swapRouter.exactOutputSingle(params);

    //     // Refund any unused input tokens
    //     if (amountIn < amountInMaximum) {
    //         IERC20(tokenIn).approve(address(swapRouter), 0);
    //     }

    //     return amountIn;
    // }
}


interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another along the specified path
    /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactInputParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);

    struct ExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps as little as possible of one token for `amountOut` of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactOutputSingleParams` in calldata
    /// @return amountIn The amount of the input token
    function exactOutputSingle(ExactOutputSingleParams calldata params) external payable returns (uint256 amountIn);

    struct ExactOutputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
    }

    /// @notice Swaps as little as possible of one token for `amountOut` of another along the specified path (reversed)
    /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactOutputParams` in calldata
    /// @return amountIn The amount of the input token
    function exactOutput(ExactOutputParams calldata params) external payable returns (uint256 amountIn);
}
