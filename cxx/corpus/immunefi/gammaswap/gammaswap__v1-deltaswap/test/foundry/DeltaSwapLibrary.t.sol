// SPDX-License-Identifier: GPL-v3
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import "../../contracts/libraries/DeltaSwapLibrary.sol";
import "../../contracts/libraries/DSMath.sol";

contract DeltaSwapLibraryTest is Test {

    function testCalcTradeLiquidity(uint128 amount, bool isToken0) public {
        uint256 reserve0 = 1_000_000_000_000 * 1e18;
        uint256 reserve1 = 1_000_000_000_000 * 1e18;
        uint256 amount0 = isToken0 ? amount : 0;
        uint256 amount1 = !isToken0 ? amount : 0;
        uint256 tradeLiquidity = DSMath.calcTradeLiquidity(amount0, amount1, reserve0, reserve1);
        if(amount0 > 0) {
            amount0 = amount0 / 2;
            amount1 = amount0 * reserve1 / reserve0;
        } else if(amount1 > 0){
            amount1 = amount1 / 2;
            amount0 = amount1 * reserve0 / reserve1;
        }
        assertEq(tradeLiquidity, DSMath.sqrt(uint256(amount0)*amount1));
        assertEq(DSMath.calcTradeLiquidity(0, 0, reserve0, reserve1), 0);
    }

    function testCalcEMAWeight() public {
        assertGt(600,DSMath.calcEMA(600, 300, 99));
        assertEq(600,DSMath.calcEMA(600, 300, 100));
        assertEq(600,DSMath.calcEMA(600, 300, 101));
    }

    function testCalcEMA0pctWeight() public {
        uint256 last = 0;
        uint256 emaLast = 0;
        uint256 emaWeight = 0; // out of 100
        uint256 ema = DSMath.calcEMA(last, emaLast, emaWeight);
        assertEq(ema, 0);

        last = 1 * 1e18;
        ema = DSMath.calcEMA(last, emaLast, emaWeight);
        assertEq(ema, last);

        emaLast = ema;

        last = 2 * 1e18;
        ema = DSMath.calcEMA(last, emaLast, emaWeight);
        assertEq(ema, 1e18);

        emaLast = ema;

        last = 3 * 1e18;
        ema = DSMath.calcEMA(last, emaLast, emaWeight);
        assertEq(ema, 1e18);

        emaLast = ema;

        last = 4 * 1e18;
        ema = DSMath.calcEMA(last, emaLast, emaWeight);
        assertEq(ema, 1e18);
    }

    function testCalcEMA100pctWeight() public {
        uint256 last = 0;
        uint256 emaLast = 0;
        uint256 emaWeight = 100; // out of 100
        uint256 ema = DSMath.calcEMA(last, emaLast, emaWeight);
        assertEq(ema, 0);
        last = 1 * 1e18;
        ema = DSMath.calcEMA(last, emaLast, emaWeight);
        assertEq(ema, last);

        emaLast = ema;

        last = 2 * 1e18;
        ema = DSMath.calcEMA(last, emaLast, emaWeight);
        assertEq(ema, last);

        emaLast = ema;

        last = 3 * 1e18;
        ema = DSMath.calcEMA(last, emaLast, emaWeight);
        assertEq(ema, last);

        emaLast = ema;

        last = 4 * 1e18;
        ema = DSMath.calcEMA(last, emaLast, emaWeight);
        assertEq(ema, last);
    }

    function testCalcEMA() public {
        uint256 last = 0;
        uint256 emaLast = 0;
        uint256 emaWeight = 20; // out of 100
        uint256 ema = DSMath.calcEMA(last, emaLast, emaWeight);
        assertEq(ema, 0);

        last = 1 * 1e18;
        ema = DSMath.calcEMA(last, emaLast, emaWeight);
        assertEq(ema, last);

        emaLast = ema;

        last = 2 * 1e18;
        ema = DSMath.calcEMA(last, emaLast, emaWeight);
        assertEq(ema, 12*1e17);

        emaLast = ema;

        last = 3 * 1e18;
        ema = DSMath.calcEMA(last, emaLast, emaWeight);
        assertEq(ema, 156*1e16);

        emaLast = ema;

        last = 4 * 1e18;
        ema = DSMath.calcEMA(last, emaLast, emaWeight);
        assertEq(ema, 2048*1e15);

        emaLast = ema;

        last = 5 * 1e18;
        ema = DSMath.calcEMA(last, emaLast, emaWeight);
        assertEq(ema, 26384*1e14);

        emaLast = ema;

        last = 4 * 1e18;
        ema = DSMath.calcEMA(last, emaLast, emaWeight);
        assertEq(ema, 291072*1e13);

        emaLast = ema;

        last = 3 * 1e18;
        ema = DSMath.calcEMA(last, emaLast, emaWeight);
        assertEq(ema, 2928576*1e12);

        emaLast = ema;

        last = 2 * 1e18;
        ema = DSMath.calcEMA(last, emaLast, emaWeight);
        assertEq(ema, 27428608*1e11);

        emaLast = ema;

        last = 1 * 1e18;
        ema = DSMath.calcEMA(last, emaLast, emaWeight);
        assertEq(ema, 239428864*1e10);
    }
}