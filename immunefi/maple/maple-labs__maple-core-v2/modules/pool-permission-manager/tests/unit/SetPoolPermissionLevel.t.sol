// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import { TestBase } from "../utils/TestBase.sol";

contract SetPoolPermissionLevelTests is TestBase {

    function test_setPoolPermissionLevel_protocolPaused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("PPM:PAUSED");
        ppm.setPoolPermissionLevel(poolManager, 3);
    }

    function test_setPoolPermissionLevel_unauthorized() external {
        globals.__setOwnedPoolManager(poolDelegate, poolManager, false);

        vm.expectRevert("PPM:NOT_PD_GOV_OR_OA");
        ppm.setPoolPermissionLevel(poolManager, 3);
    }

    function test_setPoolPermissionLevel_public() external {
        vm.prank(poolDelegate);
        ppm.setPoolPermissionLevel(poolManager, 3);

        vm.prank(poolDelegate);
        vm.expectRevert("PPM:SPPL:PUBLIC_POOL");
        ppm.setPoolPermissionLevel(poolManager, 0);
    }

    function test_setPoolPermissionLevel_invalid() external {
        vm.prank(poolDelegate);
        vm.expectRevert("PPM:SPPL:INVALID_LEVEL");
        ppm.setPoolPermissionLevel(poolManager, 4);
    }

    function test_setPoolPermissionLevel_success_poolDelegate() external {
        _setPoolPermissionLevel_withActor(poolDelegate);
    }

    function test_setPoolPermissionLevel_success_governor() external {
        _setPoolPermissionLevel_withActor(governor);
    }

    function test_setPoolPermissionLevel_success_operationalAdmin() external {
        _setPoolPermissionLevel_withActor(operationalAdmin);
    }

    function testFuzz_setPoolPermissionLevel(uint256 oldPermissionLevel, uint256 newPermissionLevel) external {
        oldPermissionLevel = bound(oldPermissionLevel, 0, 3);
        newPermissionLevel = bound(newPermissionLevel, 0, 3);

        vm.prank(poolDelegate);
        ppm.setPoolPermissionLevel(poolManager, oldPermissionLevel);

        if (oldPermissionLevel == 3) {
            vm.expectRevert("PPM:SPPL:PUBLIC_POOL");
        }

        vm.prank(poolDelegate);
        ppm.setPoolPermissionLevel(poolManager, newPermissionLevel);

        assertEq(ppm.permissionLevels(poolManager), oldPermissionLevel == 3 ? oldPermissionLevel : newPermissionLevel);
    }

    function _setPoolPermissionLevel_withActor(address actor) internal {
        assertEq(ppm.permissionLevels(poolManager), 0);

        vm.prank(actor);
        ppm.setPoolPermissionLevel(poolManager, 1);

        assertEq(ppm.permissionLevels(poolManager), 1);
    }

}
