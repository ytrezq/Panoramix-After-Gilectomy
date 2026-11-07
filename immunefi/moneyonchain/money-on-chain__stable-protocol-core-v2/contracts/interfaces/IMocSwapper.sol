// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

interface IMocSwapper {
    error MissingProviderData(address dataProviderAddress_);

    /**
     * @notice wrap coinbase and swap it for another RC20 using exact input
     * @param tokenOut_ RC20 token to receive
     * @param amountOutMin_ minimum amount of tokens to receive
     * @param recipient_ address who receives the tokens
     * @return amountOut amount of RC20 tokens received
     */
    function swapCoinbase(
        address tokenOut_,
        uint256 amountOutMin_,
        address recipient_
    ) external payable returns (uint256 amountOut);

    /**
     * @notice wrap coinbase and swap it for another RC20 using exact output
     * @param tokenOut_ RC20 token to receive
     * @param amountOut_ amount of tokens to receive in the swap
     * @param recipient_ address who receives the tokens
     * @return amountIn amount of RC20 tokens spent
     */
    function swapCoinbaseExactOutput(
        address tokenOut_,
        uint256 amountOut_,
        address recipient_
    ) external payable returns (uint256 amountIn);

    /**
     * @notice swap RC20 token using exact input
     * @param tokenIn_ RC20 token to send
     * @param tokenOut_ token to receive. If address(0), unwrap it and send coinbase to the `recipient_`
     * @param amountIn_ amount of tokens to swap
     * @param amountOutMin_ minimum amount of tokens to receive
     * @param recipient_ address who receives the tokens
     * @return amountOut amount of RC20 tokens or coinbase received
     */
    function swapRC20(
        address tokenIn_,
        address tokenOut_,
        uint256 amountIn_,
        uint256 amountOutMin_,
        address recipient_
    ) external returns (uint256 amountOut);

    /**
     * @notice swap RC20 token using exact output
     * @param tokenIn_ RC20 token to send
     * @param tokenOut_ token to receive. If address(0), unwrap it and send coinbase to the `recipient_`
     * @param amountOut_ amount of tokens to receive in the swap
     * @param amountInMax_ maximum amount of tokens to spend
     * @param recipient_ address who receives the tokens
     * @return amountIn amount of RC20 tokens or coinbase spent
     */
    function swapRC20ExactOutput(
        address tokenIn_,
        address tokenOut_,
        uint256 amountOut_,
        uint256 amountInMax_,
        address recipient_
    ) external returns (uint256 amountIn);

    /**
     * @notice get the safe maximum amount of tokens to swap
     * @dev this function is used to prevent critical losses by a pool liquidity manipulation
     * @param tokenIn_ token to send
     * @param tokenOut_ token to receive
     * @return maxAmountToSwap maximum amount of tokens to swap
     */
    function getSafeMaxAmountToSwap(
        address tokenIn_,
        address tokenOut_
    ) external view returns (uint256 maxAmountToSwap);
}
