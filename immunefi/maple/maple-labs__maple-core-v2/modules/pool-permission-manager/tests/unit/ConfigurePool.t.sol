// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import { TestBase } from "../utils/TestBase.sol";

contract ConfigurePoolTests is TestBase {

    function test_configurePool_protocolPaused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("PPM:PAUSED");
        ppm.configurePool(poolManager, 3, functionIds, bitmaps);
    }

    function test_configurePool_unauthorized() external {
        globals.__setOwnedPoolManager(poolDelegate, poolManager, false);

        vm.expectRevert("PPM:NOT_PD_GOV_OR_OA");
        ppm.configurePool(poolManager, 3, functionIds, bitmaps);
    }

    function test_configurePool_public() external {
        vm.prank(poolDelegate);
        ppm.setPoolPermissionLevel(poolManager, 3);

        vm.prank(poolDelegate);
        vm.expectRevert("PPM:CP:PUBLIC_POOL");
        ppm.configurePool(poolManager, 0, functionIds, bitmaps);
    }

    function test_configurePool_invalid() external {
        vm.prank(poolDelegate);
        vm.expectRevert("PPM:CP:INVALID_LEVEL");
        ppm.configurePool(poolManager, 4, functionIds, bitmaps);
    }

    function test_configurePool_noFunctionIds() external {
        vm.prank(poolDelegate);
        vm.expectRevert("PPM:CP:NO_FUNCTIONS");
        ppm.configurePool(poolManager, 2, functionIds, bitmaps);
    }

    function test_configurePool_lengthMismatch() external {
        functionIds.push(functionId);

        vm.prank(poolDelegate);
        vm.expectRevert("PPM:CP:LENGTH_MISMATCH");
        ppm.configurePool(poolManager, 2, functionIds, bitmaps);
    }

    function test_configurePool_success_poolDelegate() external {
        _configurePool_withActor(poolDelegate);
    }

    function test_configurePool_success_governor() external {
        _configurePool_withActor(governor);
    }

    function test_configurePool_success_operationalAdmin() external {
        _configurePool_withActor(operationalAdmin);
    }

    function _configurePool_withActor(address actor) internal {
        functionIds.push(functionId);
        bitmaps.push(generateBitmap([0, 2]));

        assertEq(ppm.poolBitmaps(poolManager, functionId), 0);
        assertEq(ppm.permissionLevels(poolManager),        0);

        vm.prank(actor);
        ppm.configurePool(poolManager, 1, functionIds, bitmaps);

        assertEq(ppm.poolBitmaps(poolManager, functionId), generateBitmap([0, 2]));
        assertEq(ppm.permissionLevels(poolManager),        1);
    }

}
