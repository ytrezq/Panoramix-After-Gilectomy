// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "tests/Base.t.sol";

import { MathLib } from "contracts/libraries/MathLib.sol";

contract MathLib_Min_Test is Base_Test {
    using MathLib for uint256;

    function test_min_zero(uint256 b) external pure{
        uint256 a = 0;
        assertEq(a.min(b), a);
    }

    function test_min_aIsGreaterThanB(uint256 a, uint256 b) external pure{
        vm.assume(a > b);
        assertEq(a.min(b), b);
    }

    function test_min_bIsGreaterThanA(uint256 a, uint256 b) external pure{
        vm.assume(a < b);
        assertEq(a.min(b), a);
    }
    
}
