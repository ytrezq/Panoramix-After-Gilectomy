// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import { NonTransparentProxy } from "../../modules/ntp/contracts/NonTransparentProxy.sol";

import { MaplePoolPermissionManagerInitializer } from "../../contracts/proxy/MaplePoolPermissionManagerInitializer.sol";

import { MaplePoolPermissionManager } from "../../contracts/MaplePoolPermissionManager.sol";

import { GlobalsMock } from "../utils/Mocks.sol";
import { TestBase }    from "../utils/TestBase.sol";

contract InitializeTests is TestBase {

    event Initialized(address implementation, address globals);

    function setUp() public override {
        ppm = MaplePoolPermissionManager(address(new NonTransparentProxy(governor, initializer)));
    }

    function test_initializer_notGovernor() external {
        vm.expectRevert("PPMI:I:NOT_GOVERNOR");
        MaplePoolPermissionManagerInitializer(address(ppm)).initialize(implementation, address(globals));
    }

    function test_initializer_success() external {
        vm.expectEmit(address(ppm));
        emit Initialized(implementation, address(globals));

        vm.prank(governor);
        MaplePoolPermissionManagerInitializer(address(ppm)).initialize(implementation, address(globals));

        assertEq(ppm.admin(),          address(governor));
        assertEq(ppm.globals(),        address(globals));
        assertEq(ppm.implementation(), address(implementation));
    }

}
