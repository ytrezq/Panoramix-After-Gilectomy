// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../../../libraries/ArrayLib.sol";
import "../../../libraries/math/PMath.sol";
import "../../../libraries/TokenHelper.sol";
import "../../../../interfaces/Aerodrome/IAerodromePool.sol";
import "../../../../interfaces/Aerodrome/IAerodromeFactory.sol";
import "../../../../interfaces/Aerodrome/IAerodromeRouter.sol";

abstract contract PendleAerodromeZapHelper is TokenHelper {
    address public immutable router;
    address public immutable pool;
    address public immutable factory;
    address public immutable token0;
    address public immutable token1;

    // ZAP CONST
    uint256 internal constant ORIGINAL_DENOMINATOR = 10000;
    uint256 internal constant ONE = 1 * 1e6;
    uint256 internal constant TWO = 2 * 1e6;
    uint256 internal constant FOUR = 4 * 1e6;

    constructor(address _router, address _pool) {
        router = _router;
        pool = _pool;
        factory = IAerodromePool(pool).factory();

        /// pool
        token0 = IAerodromePool(pool).token0();
        token1 = IAerodromePool(pool).token1();
    }

    function _zapIn(address tokenIn, uint256 amountIn) internal returns (uint256) {
        assert(tokenIn == token0 || tokenIn == token1);

        (uint256 amount0ToAddLiq, uint256 amount1ToAddLiq) = _swapZapIn(tokenIn, amountIn);
        return _addLiquidity(amount0ToAddLiq, amount1ToAddLiq);
    }

    function _zapOut(address tokenOut, uint256 amountLpIn) internal returns (uint256) {
        assert(tokenOut == token0 || tokenOut == token1);

        (uint256 amount0, uint256 amount1) = _removeLiquidity(amountLpIn);
        if (tokenOut == token0) {
            return amount0 + _swap(token1, amount1);
        } else {
            return amount1 + _swap(token0, amount0);
        }
    }

    function _swapZapIn(
        address tokenIn,
        uint256 amountIn
    ) private returns (uint256 amount0ToAddLiq, uint256 amount1ToAddLiq) {
        if (tokenIn == token0) {
            uint256 amount0ToSwap = _getVolatileZapInAmount(tokenIn, amountIn);
            amount0ToAddLiq = amountIn - amount0ToSwap;
            amount1ToAddLiq = _swap(token0, amount0ToSwap);
        } else {
            uint256 amount1ToSwap = _getVolatileZapInAmount(tokenIn, amountIn);
            amount0ToAddLiq = _swap(token1, amount1ToSwap);
            amount1ToAddLiq = amountIn - amount1ToSwap;
        }
    }

    /**
     * ==================================================================
     *                      AERODROME ROUTER RELATED
     * ==================================================================
     */

    function _addLiquidity(uint256 amount0ToAddLiq, uint256 amount1ToAddLiq) private returns (uint256 amountLpOut) {
        (, , amountLpOut) = IAerodromeRouter(router).addLiquidity(
            token0,
            token1,
            false,
            amount0ToAddLiq,
            amount1ToAddLiq,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    function _removeLiquidity(uint256 amountLpToRemove) private returns (uint256 amountTokenA, uint256 amountTokenB) {
        return
            IAerodromeRouter(router).removeLiquidity(
                token0,
                token1,
                false,
                amountLpToRemove,
                0,
                0,
                address(this),
                block.timestamp
            );
    }

    function _swap(address tokenIn, uint256 amountTokenIn) private returns (uint256) {
        address tokenOut = tokenIn == token0 ? token1 : token0;
        uint256 preBalance = _selfBalance(tokenOut);
        uint256 expectedOut = IAerodromePool(pool).getAmountOut(amountTokenIn, tokenIn);
        IAerodromeRouter(router).UNSAFE_swapExactTokensForTokens(
            ArrayLib.create(amountTokenIn, expectedOut),
            _getRoutes(tokenIn),
            address(this),
            type(uint256).max
        );

        return _selfBalance(tokenOut) - preBalance;
    }

    /*///////////////////////////////////////////////////////////////
                                ZAP MATH
    //////////////////////////////////////////////////////////////*/

    // @notice: This function has its peak of value at ```uint256 a = ...``` with magnitude of ONE^2 * max(x,y) ^ 2
    // With limitation of 2^256 ~ 10^77, ONE = 1e6 for better precision, we manage to leave about 10^32 decimals for max(x,y)
    // Which is sufficient in most case
    function _getVolatileZapInAmount(address tokenIn, uint256 amountIn) private view returns (uint256) {
        (uint256 reserve0, uint256 reserve1, ) = IAerodromePool(pool).getReserves();
        uint256 fee = (IAerodromeFactory(factory).getFee(pool, false) * ONE) / ORIGINAL_DENOMINATOR;

        uint256 reserve = (tokenIn == token0 ? reserve0 : reserve1);
        uint256 a = PMath.square((TWO - fee) * reserve) + 4 * PMath.square(ONE - fee) * amountIn * reserve;
        uint256 b = reserve * (TWO - fee);
        uint256 c = 2 * PMath.square(ONE - fee);
        return ((PMath.sqrt(a) - b) * ONE) / c;
    }

    /*///////////////////////////////////////////////////////////////
                                MISC
    //////////////////////////////////////////////////////////////*/

    function _getRoutes(address tokenIn) internal view returns (IAerodromeRouter.Route[] memory) {
        IAerodromeRouter.Route[] memory routes = new IAerodromeRouter.Route[](1);
        routes[0] = IAerodromeRouter.Route({
            from: tokenIn,
            to: tokenIn == token0 ? token1 : token0,
            stable: false,
            factory: factory
        });
        return routes;
    }
}
