// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { IAccessManaged } from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";

import { FlashParallelTokenMockV2 } from "tests/mock/FlashParallelTokenMockV2.sol";
import "tests/Units.t.sol";

contract FlashParallelToken_UpgradeAndCall_Units_Test is Units_Test {
    FlashParallelTokenMockV2 newFlashParallelToken = new FlashParallelTokenMockV2();

    function test_UpgradeAndCall() external {
        vm.startPrank(users.dao.addr);
        flashParallelToken.upgradeToAndCall(address(newFlashParallelToken),"");
        assertEq(FlashParallelTokenMockV2(address(flashParallelToken)).version(), 2);
    }

    function test_revertWhen_CallerIsNotAllowed() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, users.hacker.addr));
        flashParallelToken.upgradeToAndCall(address(newFlashParallelToken),"");
    }

}