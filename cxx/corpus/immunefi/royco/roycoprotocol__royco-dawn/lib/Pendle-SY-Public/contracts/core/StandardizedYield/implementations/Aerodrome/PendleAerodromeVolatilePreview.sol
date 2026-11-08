// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../../../libraries/math/PMath.sol";
import "../../../../interfaces/Aerodrome/IAerodromePool.sol";
import "../../../../interfaces/Aerodrome/IAerodromeRouter.sol";
import "../../../../interfaces/Aerodrome/IAerodromeFactory.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract PendleAerodromeVolatilePreview {
    address public immutable factory;

    uint256 private constant FEE_DENOMINATOR = 10000;
    uint256 private constant ONE = 1 * FEE_DENOMINATOR;
    uint256 private constant TWO = 2 * FEE_DENOMINATOR;
    uint256 private constant FOUR = 4 * FEE_DENOMINATOR;

    struct AerodromePoolData {
        address pool;
        address token0;
        address token1;
        uint256 reserve0;
        uint256 reserve1;
        uint256 fee;
    }

    constructor(address _factory) {
        factory = _factory;
    }

    /**
     * ==================================================================
     *                              MATH
     * ==================================================================
     */

    // @reference: https://www.notion.so/pendle/Research-Knowledge-Vault-c348747730e348c29ba363b19d0fe7e3?pvs=4#fde647f251d8464a93b7b2b6c86c8d5c
    function _getZapInSwapAmount(uint256 amountIn, uint256 reserve, uint256 fee) private pure returns (uint256) {
        uint256 a = PMath.square((TWO - fee) * reserve) + 4 * PMath.square(ONE - fee) * amountIn * reserve;
        uint256 b = reserve * (TWO - fee);
        uint256 c = 2 * PMath.square(ONE - fee);

        return ((PMath.sqrt(a) - b) * ONE) / c;
    }

    /**
     * @notice The Aerodrome.swap() function takes reserve() as the previously recorded at the start
     * and take into account ALL floating balances after.
     */
    function previewZapIn(
        address pool,
        address tokenIn,
        uint256 amountTokenIn
    ) external view returns (uint256 amountLpOut) {
        AerodromePoolData memory data = _getAerodromePoolData(pool);

        bool isToken0 = tokenIn == data.token0;

        uint256 amountToSwap = isToken0
            ? _getZapInSwapAmount(amountTokenIn, data.reserve0, data.fee)
            : _getZapInSwapAmount(amountTokenIn, data.reserve1, data.fee);

        uint256 amountSwapInAfterFee = _getAmountInAfterFee(amountToSwap, data.fee);
        uint256 amountSwapOut = _getSwapAmountOut(data, tokenIn, amountSwapInAfterFee);

        uint256 amount0ToAddLiq;
        uint256 amount1ToAddLiq;

        if (isToken0) {
            data.reserve0 = _getPoolBalance0(data) + amountSwapInAfterFee;
            data.reserve1 = _getPoolBalance1(data) - amountSwapOut;

            amount0ToAddLiq = amountTokenIn - amountToSwap;
            amount1ToAddLiq = amountSwapOut;
        } else {
            data.reserve0 = _getPoolBalance0(data) - amountSwapOut;
            data.reserve1 = _getPoolBalance1(data) + amountSwapInAfterFee;

            amount0ToAddLiq = amountSwapOut;
            amount1ToAddLiq = amountTokenIn - amountToSwap;
        }

        return _calcAmountLpOut(data, amount0ToAddLiq, amount1ToAddLiq);
    }

    function previewZapOut(address pair, address tokenOut, uint256 amountLpIn) external view returns (uint256) {
        AerodromePoolData memory data = _getAerodromePoolData(pair);

        uint256 totalSupply = IAerodromePool(pair).totalSupply();

        data.reserve0 = _getPoolBalance0(data);
        data.reserve1 = _getPoolBalance1(data);

        uint256 amount0Removed = (data.reserve0 * amountLpIn) / totalSupply;
        uint256 amount1Removed = (data.reserve1 * amountLpIn) / totalSupply;

        data.reserve0 -= amount0Removed;
        data.reserve1 -= amount1Removed;

        if (tokenOut == data.token0) {
            return
                amount0Removed + _getSwapAmountOut(data, data.token1, _getAmountInAfterFee(amount1Removed, data.fee));
        } else {
            return
                amount1Removed + _getSwapAmountOut(data, data.token0, _getAmountInAfterFee(amount0Removed, data.fee));
        }
    }

    function _getAerodromePoolData(address pool) private view returns (AerodromePoolData memory data) {
        data.pool = pool;
        data.token0 = IAerodromePool(pool).token0();
        data.token1 = IAerodromePool(pool).token1();
        (data.reserve0, data.reserve1, ) = IAerodromePool(pool).getReserves();
        data.fee = IAerodromeFactory(factory).getFee(pool, false);
    }

    function _getPoolBalance0(AerodromePoolData memory data) private view returns (uint256) {
        return IERC20(data.token0).balanceOf(data.pool);
    }

    function _getPoolBalance1(AerodromePoolData memory data) private view returns (uint256) {
        return IERC20(data.token1).balanceOf(data.pool);
    }

    function _getSwapAmountOut(
        AerodromePoolData memory data,
        address tokenIn,
        uint256 amountInAfterFee
    ) private pure returns (uint256) {
        (uint256 reserve0, uint256 reserve1) = tokenIn == data.token0
            ? (data.reserve0, data.reserve1)
            : (data.reserve1, data.reserve0);
        return (amountInAfterFee * reserve1) / (reserve0 + amountInAfterFee);
    }

    function _getAmountInAfterFee(uint256 amountIn, uint256 fee) private pure returns (uint256) {
        return amountIn - (amountIn * fee) / FEE_DENOMINATOR;
    }

    // /**
    //  * @notice This function simulates Aerodrome router so any precision issues from their calculation
    //  * is preserved in preview functions...
    //  */
    function _calcAmountLpOut(
        AerodromePoolData memory data,
        uint256 amount0ToAddLiq,
        uint256 amount1ToAddLiq
    ) private view returns (uint256 amountLpOut) {
        uint256 amount1Optimal = _quote(amount0ToAddLiq, data.reserve0, data.reserve1);
        if (amount1Optimal <= amount1ToAddLiq) {
            amount1ToAddLiq = amount1Optimal;
        } else {
            amount0ToAddLiq = _quote(amount1ToAddLiq, data.reserve1, data.reserve0);
        }

        uint256 supply = IAerodromePool(data.pool).totalSupply();
        return PMath.min((amount0ToAddLiq * supply) / data.reserve0, (amount1ToAddLiq * supply) / data.reserve1);
    }

    function _quote(uint amountA, uint reserveA, uint reserveB) private pure returns (uint amountB) {
        amountB = (amountA * reserveB) / reserveA;
    }
}
