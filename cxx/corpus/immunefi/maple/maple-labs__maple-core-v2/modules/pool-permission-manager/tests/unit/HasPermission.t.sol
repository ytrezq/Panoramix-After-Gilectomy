// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import { TestBase } from "../utils/TestBase.sol";

contract HasPermissionTests is TestBase {

    /**************************************************************************************************************************************/
    /*** Failure Test                                                                                                                   ***/
    /**************************************************************************************************************************************/

    function test_hasPermission_multiLender_noLenders() external {
        assertEq(lenders.length, 0);

        vm.expectRevert("PPM:HP:NO_LENDERS");
        ppm.hasPermission(poolManager, lenders, functionId);

        lenders.push(lender);
        booleans.push(true);

        assertEq(lenders.length, 1);

        vm.prank(poolDelegate);
        ppm.setLenderAllowlist(poolManager, lenders, booleans);

        bool hasPermission = ppm.hasPermission(poolManager, lenders, functionId);

        assertTrue(hasPermission);
    }

    /**************************************************************************************************************************************/
    /*** Private Permission Level                                                                                                       ***/
    /**************************************************************************************************************************************/

    function test_hasPermission_private_unauthorized() external {
        bool hasPermission = ppm.hasPermission(poolManager, lender, functionId);

        assertFalse(hasPermission);
    }

    function test_hasPermission_private_whitelisted() external {
        lenders.push(lender);
        booleans.push(true);

        vm.prank(poolDelegate);
        ppm.setLenderAllowlist(poolManager, lenders, booleans);

        bool hasPermission = ppm.hasPermission(poolManager, lender, functionId);

        assertTrue(hasPermission);
    }

    function testFuzz_hasPermission_private_whitelisted(address poolManager_, address lender_, bytes32 functionId_) external {
        globals.__setOwnedPoolManager(poolDelegate, poolManager_, true);

        lenders.push(lender_);
        booleans.push(true);

        vm.prank(poolDelegate);
        ppm.setLenderAllowlist(poolManager_, lenders, booleans);

        bool hasPermission = ppm.hasPermission(poolManager_, lender_, functionId_);

        assertTrue(hasPermission);
    }

    function testFuzz_hasPermission_multiLender_private_whitelisted(
        address poolManager_,
        address[] calldata lenders_,
        bytes32 functionId_
    )
        external
    {
        vm.assume(lenders_.length > 1);

        globals.__setOwnedPoolManager(poolDelegate, poolManager_, true);

        lenders = lenders_;

        // Set all lenders, except last one to true
        for (uint256 i; i < lenders.length - 1; ++i) {
            booleans.push(true);
        }
        booleans.push(false);

        vm.prank(poolDelegate);
        ppm.setLenderAllowlist(poolManager_, lenders, booleans);

        bool hasPermission = ppm.hasPermission(poolManager_, lenders_, functionId_);

        // Since there's at least one lender without permission, the check should fail.
        assertFalse(hasPermission);

        booleans[booleans.length - 1] = true;

        // Authorize last lender
        vm.prank(poolDelegate);
        ppm.setLenderAllowlist(poolManager_, lenders, booleans);

        hasPermission = ppm.hasPermission(poolManager_, lenders_, functionId_);

        // Permission now is allowed.
        assertTrue(hasPermission);
    }

    function testFuzz_hasPermission_private_unauthorized(address poolManager_, address lender_, bytes32 functionId_) external {
        bool hasPermission = ppm.hasPermission(poolManager_, lender_, functionId_);

        assertFalse(hasPermission);
    }

    /**************************************************************************************************************************************/
    /*** Function Permission Level                                                                                                      ***/
    /**************************************************************************************************************************************/

    function test_hasPermission_functionLevel_whitelisted() external {
        vm.prank(poolDelegate);
        ppm.setPoolPermissionLevel(poolManager, 1);

        lenders.push(lender);
        booleans.push(true);

        vm.prank(poolDelegate);
        ppm.setLenderAllowlist(poolManager, lenders, booleans);

        bool hasPermission = ppm.hasPermission(poolManager, lender, functionId);

        assertTrue(hasPermission);
    }

    function testFuzz_hasPermission_functionLevel_multiLender_whitelisted(address[] calldata lenders_) external {
        vm.assume(lenders_.length > 1);

        lenders = lenders_;

        // Set all lenders, except last one to true
        for (uint256 i; i < lenders.length - 1; ++i) {
            booleans.push(true);
        }

        booleans.push(false);

        vm.prank(poolDelegate);
        ppm.setLenderAllowlist(poolManager, lenders, booleans);

        bool hasPermission = ppm.hasPermission(poolManager, lenders_, functionId);

        // Since there's at least one lender without permission, the check should fail.
        assertFalse(hasPermission);

        booleans[booleans.length - 1] = true;

        // Authorize last lender
        vm.prank(poolDelegate);
        ppm.setLenderAllowlist(poolManager, lenders, booleans);

        hasPermission = ppm.hasPermission(poolManager, lenders_, functionId);

        // Permission now is allowed.
        assertTrue(hasPermission);
    }

    function test_hasPermission_functionLevel_zeroLenderBitmap() external {
        vm.prank(poolDelegate);
        ppm.setPoolPermissionLevel(poolManager, 1);

        functionIds.push(functionId);
        bitmaps.push(generateBitmap([0, 1]));

        vm.prank(poolDelegate);
        ppm.setPoolBitmaps(poolManager, functionIds, bitmaps);

        bool hasPermission = ppm.hasPermission(poolManager, lender, functionId);

        assertFalse(hasPermission);
    }

    function test_hasPermission_functionLevel_zeroFunctionBitmap_zeroLenderBitmap() external {
        vm.prank(poolDelegate);
        ppm.setPoolPermissionLevel(poolManager, 1);

        // NOTE: As function bitmap has not been set, the lender has permission.
        bool hasPermission = ppm.hasPermission(poolManager, lender, functionId);

        assertTrue(hasPermission);
    }

    function test_hasPermission_functionLevel_mismatch() external {
        vm.prank(poolDelegate);
        ppm.setPoolPermissionLevel(poolManager, 1);

        functionIds.push(functionId);
        bitmaps.push(generateBitmap([0, 1]));

        vm.prank(poolDelegate);
        ppm.setPoolBitmaps(poolManager, functionIds, bitmaps);

        lenders.push(lender);
        bitmaps[0] = generateBitmap([0, 2, 3]);

        vm.prank(permissionAdmin);
        ppm.setLenderBitmaps(lenders, bitmaps);

        bool hasPermission = ppm.hasPermission(poolManager, lender, functionId);

        assertFalse(hasPermission);
    }

    function test_hasPermission_functionLevel_match() external {
        vm.prank(poolDelegate);
        ppm.setPoolPermissionLevel(poolManager, 1);

        functionIds.push(functionId);
        bitmaps.push(generateBitmap([0, 1]));

        vm.prank(poolDelegate);
        ppm.setPoolBitmaps(poolManager, functionIds, bitmaps);

        lenders.push(lender);
        bitmaps[0] = generateBitmap([0, 1, 3]);

        vm.prank(permissionAdmin);
        ppm.setLenderBitmaps(lenders, bitmaps);

        bool hasPermission = ppm.hasPermission(poolManager, lender, functionId);

        assertTrue(hasPermission);
    }

    function test_hasPermission_multiLender_functionLevel(address[] calldata lenders_) external {
        vm.assume(lenders_.length > 1);

        lenders = lenders_;

        vm.prank(poolDelegate);
        ppm.setPoolPermissionLevel(poolManager, 1);

        uint256 functionBitmap = generateBitmap([1, 2]);

        functionIds.push(functionId);
        bitmaps.push(functionBitmap);

        // Set pool bitmap
        vm.prank(poolDelegate);
        ppm.setPoolBitmaps(poolManager, functionIds, bitmaps);

        bitmaps = new uint256[](lenders.length);

        // Set all lenders, except last one to matching bitmaps
        for (uint256 i; i < lenders.length - 1; ++i) {
            bitmaps[i] = functionBitmap;
        }

        bitmaps[lenders.length - 1] = generateBitmap([0, 1, 3]);

        vm.prank(permissionAdmin);
        ppm.setLenderBitmaps(lenders, bitmaps);

        bool hasPermission = ppm.hasPermission(poolManager, lenders, functionId);

        assertFalse(hasPermission);

        // Set the last lender to matching bitmap
        bitmaps[lenders.length - 1] = functionBitmap;

        vm.prank(permissionAdmin);
        ppm.setLenderBitmaps(lenders, bitmaps);

        hasPermission = ppm.hasPermission(poolManager, lenders, functionId);

        assertTrue(hasPermission);
    }

    /**************************************************************************************************************************************/
    /*** Pool Permission Level                                                                                                          ***/
    /**************************************************************************************************************************************/

    function test_hasPermission_poolLevel_whitelisted() external {
        vm.prank(poolDelegate);
        ppm.setPoolPermissionLevel(poolManager, 2);

        lenders.push(lender);
        booleans.push(true);

        vm.prank(poolDelegate);
        ppm.setLenderAllowlist(poolManager, lenders, booleans);

        bool hasPermission = ppm.hasPermission(poolManager, lender, functionId);

        assertTrue(hasPermission);
    }

    function test_hasPermission_poolLevel_zeroLenderBitmap() external {
        vm.prank(poolDelegate);
        ppm.setPoolPermissionLevel(poolManager, 2);

        functionIds.push(bytes32(0));
        bitmaps.push(generateBitmap([1, 2]));

        vm.prank(poolDelegate);
        ppm.setPoolBitmaps(poolManager, functionIds, bitmaps);

        bool hasPermission = ppm.hasPermission(poolManager, lender, functionId);

        assertFalse(hasPermission);
    }

    function test_hasPermission_poolLevel_zeroLenderBitmap_zeroPoolBitmap() external {
        vm.prank(poolDelegate);
        ppm.setPoolPermissionLevel(poolManager, 2);

        functionIds.push(bytes32(0));
        bitmaps.push(uint256(0));

        vm.prank(poolDelegate);
        ppm.setPoolBitmaps(poolManager, functionIds, bitmaps);

        // NOTE: As function bitmap has not been set, the lender has permission.
        bool hasPermission = ppm.hasPermission(poolManager, lender, functionId);

        assertTrue(hasPermission);
    }

    function test_hasPermission_poolLevel_mismatch() external {
        vm.prank(poolDelegate);
        ppm.setPoolPermissionLevel(poolManager, 2);

        functionIds.push(bytes32(0));
        bitmaps.push(generateBitmap([1, 2]));

        vm.prank(poolDelegate);
        ppm.setPoolBitmaps(poolManager, functionIds, bitmaps);

        lenders.push(lender);
        bitmaps[0] = generateBitmap([0, 2, 3]);

        vm.prank(permissionAdmin);
        ppm.setLenderBitmaps(lenders, bitmaps);

        bool hasPermission = ppm.hasPermission(poolManager, lender, functionId);

        assertFalse(hasPermission);
    }

    function test_hasPermission_poolLevel_multiLender_mismatch() external {
        vm.prank(poolDelegate);
        ppm.setPoolPermissionLevel(poolManager, 2);

        functionIds.push(bytes32(0));
        bitmaps.push(generateBitmap([1, 2]));

        vm.prank(poolDelegate);
        ppm.setPoolBitmaps(poolManager, functionIds, bitmaps);

        lenders.push(lender);
        bitmaps[0] = generateBitmap([0, 2, 3]);

        lenders.push(makeAddr("newLender"));
        bitmaps.push(generateBitmap([1, 2]));

        vm.prank(permissionAdmin);
        ppm.setLenderBitmaps(lenders, bitmaps);

        bool hasPermission = ppm.hasPermission(poolManager, lender, functionId);

        // One of the lenders doesn't have the correct permission so the check returns false.
        assertFalse(hasPermission);
    }

    function test_hasPermission_poolLevel_match() external {
        vm.prank(poolDelegate);
        ppm.setPoolPermissionLevel(poolManager, 2);

        functionIds.push(bytes32(0));
        bitmaps.push(generateBitmap([1, 2]));

        vm.prank(poolDelegate);
        ppm.setPoolBitmaps(poolManager, functionIds, bitmaps);

        lenders.push(lender);
        bitmaps[0] = generateBitmap([0, 1, 2]);

        vm.prank(permissionAdmin);
        ppm.setLenderBitmaps(lenders, bitmaps);

        bool hasPermission = ppm.hasPermission(poolManager, lender, functionId);

        assertTrue(hasPermission);
    }

    /**************************************************************************************************************************************/
    /*** Public Permission Level                                                                                                        ***/
    /**************************************************************************************************************************************/

    function test_hasPermission_public_success() external {
        vm.prank(poolDelegate);
        ppm.setPoolPermissionLevel(poolManager, 3);

        bool hasPermission = ppm.hasPermission(poolManager, lender, functionId);

        assertEq(hasPermission, true);
    }

    function testFuzz_hasPermission_public(address poolManager_, address lender_, bytes32 functionId_) external {
        globals.__setOwnedPoolManager(poolDelegate, poolManager_, true);

        vm.prank(poolDelegate);
        ppm.setPoolPermissionLevel(poolManager_, 3);

        bool hasPermission = ppm.hasPermission(poolManager_, lender_, functionId_);

        assertEq(hasPermission, true);
    }

    function testFuzz_hasPermission_multiLender_public_(address poolManager_, address[] calldata lenders_, bytes32 functionId_) external {
        vm.assume(lenders_.length > 1);

        globals.__setOwnedPoolManager(poolDelegate, poolManager_, true);

        vm.prank(poolDelegate);
        ppm.setPoolPermissionLevel(poolManager_, 3);

        bool hasPermission = ppm.hasPermission(poolManager_, lenders_, functionId_);

        assertEq(hasPermission, true);
    }

}
