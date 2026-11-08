// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test } from "../modules/forge-std/src/Test.sol";

import { MapleLoanHarness } from "./utils/Harnesses.sol";
import { Utils }            from "./utils/Utils.sol";

contract DefaultDatesTests is Test, Utils {

    MapleLoanHarness loan = new MapleLoanHarness();

    function test_isInDefault_zeroDefaultDate() external {
        assertEq(loan.isInDefault(), false);
    }

    function test_isInDefault_successBoundary() external {
        loan.__setDateImpaired(block.timestamp - 1);

        assertEq(loan.isInDefault(), true);

        loan.__setDateImpaired(block.timestamp);

        assertEq(loan.isInDefault(), false);
    }

}
