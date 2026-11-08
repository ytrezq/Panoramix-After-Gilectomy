// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import { NonTransparentProxy } from "../../modules/ntp/contracts/NonTransparentProxy.sol";

import { MaplePoolPermissionManager } from "../../contracts/MaplePoolPermissionManager.sol";

import { TestBase } from "../utils/TestBase.sol";

contract SetImplementationTests is TestBase {

    function test_setImplementation_unauthorized() external {
        vm.expectRevert("NTP:SI:NOT_ADMIN");
        NonTransparentProxy(address(ppm)).setImplementation(address(0x1));
    }

    function test_setImplementation_success() external {
        address newImplementation = address(new MaplePoolPermissionManager());

        assertEq(ppm.implementation(), implementation);

        vm.prank(governor);
        NonTransparentProxy(address(ppm)).setImplementation(newImplementation);

        assertEq(ppm.implementation(), newImplementation);
    }

}
