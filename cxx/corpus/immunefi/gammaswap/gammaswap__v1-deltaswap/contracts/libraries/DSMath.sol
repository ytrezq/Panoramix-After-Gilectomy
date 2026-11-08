// SPDX-License-Identifier: GPL-v3
pragma solidity >=0.5.16;

// a library for performing various math operations

library DSMath {

    function max(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x > y ? x : y;
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }

    // babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    /// @dev Update pool invariant, LP tokens borrowed plus interest, interest rate index, and last block update
    /// @param last - last value added to ema calculation
    /// @param emaLast - last calculated ema
    /// @param emaWeight - weight given to last value in ema calculation compared to last ema value
    /// @return ema - result of ema calculation
    function calcEMA(uint256 last, uint256 emaLast, uint256 emaWeight) internal pure returns(uint256) {
        if(emaLast == 0) {
            return last;
        } else {
            emaWeight = min(100, emaWeight);
            // EMA_1 = last * weight + EMA_0 * (1 - weight)
            return last * emaWeight / 100 + emaLast * (100 - emaWeight) / 100;
        }
    }

    function calcSingleSideLiquidity(uint256 amount, uint256 reserve0, uint256 reserve1) internal pure returns(uint256) {
        uint256 amount0 = amount / 2;
        uint256 amount1 = amount0 * reserve1 / reserve0;
        return DSMath.sqrt(amount0 * amount1);
    }

    function calcTradeLiquidity(uint256 amount0, uint256 amount1, uint256 reserve0, uint256 reserve1) internal pure returns(uint256) {
        return max(
            calcSingleSideLiquidity(amount0, reserve0, reserve1),
                calcSingleSideLiquidity(amount1, reserve1, reserve0));
    }
}
