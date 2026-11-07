// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import { TestBase } from "../utils/TestBase.sol";

contract SetLenderAllowlistTests is TestBase {

    function test_setLenderAllowlist_protocolPaused() external {
        globals.__setFunctionPaused(true);
        
        vm.expectRevert("PPM:PAUSED");
        ppm.setLenderAllowlist(poolManager, lenders, booleans);
    }

    function test_setLenderAllowlist_unauthorized() external {
        globals.__setOwnedPoolManager(poolDelegate, poolManager, false);

        vm.expectRevert("PPM:NOT_PD_GOV_OR_OA");
        ppm.setLenderAllowlist(poolManager, lenders, booleans);
    }

    function test_setLenderAllowlist_empty() external {
        vm.prank(poolDelegate);
        vm.expectRevert("PPM:SLA:NO_LENDERS");
        ppm.setLenderAllowlist(poolManager, lenders, booleans);
    }

    function test_setLenderAllowlist_mismatch() external {
        lenders.push(lender);

        vm.prank(poolDelegate);
        vm.expectRevert("PPM:SLA:LENGTH_MISMATCH");
        ppm.setLenderAllowlist(poolManager, lenders, booleans);
    }

    function test_setLenderAllowlist_success_poolDelegate() external {
        _setLenderAllowlist_withActor(poolDelegate);
    }

    function test_setLenderAllowlist_success_governor() external {
        _setLenderAllowlist_withActor(governor);
    }

    function test_setLenderAllowlist_success_operationalAdmin() external {
        _setLenderAllowlist_withActor(operationalAdmin);
    }

    function test_setLenderAllowlist_batch() external {
        lenders.push(address(1));
        lenders.push(address(2));
        lenders.push(address(3));

        booleans.push(true);
        booleans.push(false);
        booleans.push(true);

        assertEq(ppm.lenderAllowlist(poolManager, address(1)), false);
        assertEq(ppm.lenderAllowlist(poolManager, address(2)), false);
        assertEq(ppm.lenderAllowlist(poolManager, address(3)), false);

        vm.prank(poolDelegate);
        ppm.setLenderAllowlist(poolManager, lenders, booleans);

        assertEq(ppm.lenderAllowlist(poolManager, address(1)), true);
        assertEq(ppm.lenderAllowlist(poolManager, address(2)), false);
        assertEq(ppm.lenderAllowlist(poolManager, address(3)), true);
    }

    function _setLenderAllowlist_withActor(address actor) internal {
        lenders.push(lender);
        booleans.push(true);

        assertFalse(ppm.lenderAllowlist(poolManager, lender));

        vm.prank(actor);
        ppm.setLenderAllowlist(poolManager, lenders, booleans);

        assertTrue(ppm.lenderAllowlist(poolManager, lender));
    }

}
