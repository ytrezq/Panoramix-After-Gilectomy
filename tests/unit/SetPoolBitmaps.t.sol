// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import { TestBase } from "../utils/TestBase.sol";

contract SetPoolBitmapsTests is TestBase {

    function test_setPoolBitmaps_protocolPaused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("PPM:PAUSED");
        ppm.setPoolBitmaps(poolManager, functionIds, bitmaps);
    }

    function test_setPoolBitmaps_unauthorized() external {
        globals.__setOwnedPoolManager(poolDelegate, poolManager, false);

        vm.expectRevert("PPM:NOT_PD_GOV_OR_OA");
        ppm.setPoolBitmaps(poolManager, functionIds, bitmaps);
    }

    function test_setPoolBitmaps_empty() external {
        vm.prank(poolDelegate);
        vm.expectRevert("PPM:SPB:NO_FUNCTIONS");
        ppm.setPoolBitmaps(poolManager, functionIds, bitmaps);
    }

    function test_setPoolBitmaps_mismatch() external {
        functionIds.push(functionId);

        vm.prank(poolDelegate);
        vm.expectRevert("PPM:SPB:LENGTH_MISMATCH");
        ppm.setPoolBitmaps(poolManager, functionIds, bitmaps);
    }

    function test_setPoolBitmaps_success_poolDelegate() external {
        _setPoolBitmaps_withActor(poolDelegate);
    }

    function test_setPoolBitmaps_success_governor() external {
        _setPoolBitmaps_withActor(governor);
    }

    function test_setPoolBitmaps_success_operationalAdmin() external {
        _setPoolBitmaps_withActor(operationalAdmin);
    }

    function test_setPoolBitmaps_batch() external {
        functionIds.push("P:deposit");
        functionIds.push("P:mint");
        functionIds.push("P:withdraw");
        functionIds.push("P:redeem");

        bitmaps.push(generateBitmap([0, 1]));
        bitmaps.push(generateBitmap([0, 2]));
        bitmaps.push(generateBitmap([2, 3, 4]));
        bitmaps.push(generateBitmap([1, 2, 3]));

        assertEq(ppm.poolBitmaps(poolManager, "P:deposit"),  0);
        assertEq(ppm.poolBitmaps(poolManager, "P:mint"),     0);
        assertEq(ppm.poolBitmaps(poolManager, "P:withdraw"), 0);
        assertEq(ppm.poolBitmaps(poolManager, "P:redeem"),   0);

        vm.prank(poolDelegate);
        ppm.setPoolBitmaps(poolManager, functionIds, bitmaps);

        assertEq(ppm.poolBitmaps(poolManager, "P:deposit"),  generateBitmap([0, 1]));
        assertEq(ppm.poolBitmaps(poolManager, "P:mint"),     generateBitmap([0, 2]));
        assertEq(ppm.poolBitmaps(poolManager, "P:withdraw"), generateBitmap([2, 3, 4]));
        assertEq(ppm.poolBitmaps(poolManager, "P:redeem"),   generateBitmap([1, 2, 3]));
    }

    function _setPoolBitmaps_withActor(address actor) internal {
        functionIds.push(functionId);
        bitmaps.push(generateBitmap([0, 2]));

        assertEq(ppm.poolBitmaps(poolManager, functionId), 0);

        vm.prank(actor);
        ppm.setPoolBitmaps(poolManager, functionIds, bitmaps);

        assertEq(ppm.poolBitmaps(poolManager, functionId), generateBitmap([0, 2]));
    }

}
