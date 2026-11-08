// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { FlashParallelTokenMockV2 } from "tests/mock/FlashParallelTokenMockV2.sol";
import "tests/Units.t.sol";

contract FlashParallelToken_FlashFee_Units_Test is Units_Test {

    uint256 maxBorrowable = 1e18;
    bool isActive = true;
    function setUp() public override {
        super.setUp();
        vm.startPrank(users.dao.addr);
        flashParallelToken.setFlashLoanParameters(address(aEURp), DEFAULT_FEE_RATE, maxBorrowable, isActive);
    }

    function test_FlashFee() external view {
        assertEq(flashParallelToken.flashFee(address(aEURp), 100e18), 2.5e18);
        assertEq(flashParallelToken.flashFee(address(aEURp), 2756), 69);
    }

}