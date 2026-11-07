// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import { NonTransparentProxy } from "../../modules/ntp/contracts/NonTransparentProxy.sol";

import { TestBase } from "../utils/TestBase.sol";

contract FallbackTests is TestBase {

    function test_fallback_noCode() external {
        address newImplementation = makeAddr("notContract");

        vm.prank(governor);
        NonTransparentProxy(address(ppm)).setImplementation(newImplementation);

        vm.expectRevert("NTP:F:NO_CODE_ON_IMPLEMENTATION");
        ppm.implementation();
    }

}
