// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "tests/Base.t.sol";

import { PercentageMathLib } from "contracts/libraries/PercentageMathLib.sol";

contract PercentageMathLib_PercentDiv_Test is Base_Test {
    using PercentageMathLib for uint256;

    function test_PercentDiv() external pure{
        uint256 amount = 100e18;
        assertEq(amount.percentDiv(1000), 1e21); // 10%
        assertEq(amount.percentDiv(100_000), 1e19); // 1000%
    }
    /// forge-config: default.allow_internal_expect_revert = true
    function test_PercentDiv_RevertWhen_ValueIsZero() external {
        uint256 amount = 100e18;
        vm.expectRevert();
        amount.percentDiv(0);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_PercentDiv_RevertWhen_OverFlow() external {
        uint256 amount = type(uint256).max;
        uint256 percentage = 1000; // 10%
        vm.expectRevert();
        amount.percentDiv(percentage);
    }
}
