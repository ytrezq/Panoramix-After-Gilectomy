// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "tests/Base.t.sol";

import { MathLib } from "contracts/libraries/MathLib.sol";

contract MathLib_Abs_Test is Base_Test {
    using MathLib for int256;

    function test_abs_negValue(int256 value) external pure{
        vm.assume(value < 0 && value > (type(int256).min + 1));
        assertEq(value.abs(), uint256(-value));
    }

    function test_abs_zero() external pure{
        int256 value = 0;
        assertEq(value.abs(), 0);
    }

    function test_abs_posValue(int256 value) external pure{
        vm.assume(value > 0);
        assertEq(value.abs(), uint256(value));
    }
}
