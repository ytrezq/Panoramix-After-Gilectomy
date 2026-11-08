// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import { MapleWithdrawalManager } from "../../contracts/MapleWithdrawalManager.sol";

import { MockGlobals, MockWithdrawalManagerMigrator } from "../utils/Mocks.sol";
import { TestBase }                                   from "../utils/TestBase.sol";

contract UpgradeTests is TestBase {

    address internal migrator;
    address internal newImplementation;

    function setUp() public override {
        super.setUp();

        migrator          = address(new MockWithdrawalManagerMigrator());
        newImplementation = address(new MapleWithdrawalManager());

        vm.startPrank(governor);
        factory.registerImplementation(2, newImplementation, initializer);
        factory.enableUpgradePath(1, 2, migrator);
        vm.stopPrank();
    }

    function test_upgrade_protocolPaused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("WM:PAUSED");
        withdrawalManager.upgrade(2, abi.encode(address(0)));
    }

    function test_upgrade_notSecurityAdmin() external {
        vm.expectRevert("WM:U:NOT_AUTHORIZED");
        withdrawalManager.upgrade(2, "");

        vm.prank(securityAdmin);
        withdrawalManager.upgrade(2, abi.encode(address(0)));
    }

    function test_upgrade_notPoolDelegate() external {
        vm.expectRevert("WM:U:NOT_AUTHORIZED");
        withdrawalManager.upgrade(2, "");

        MockGlobals(globals).__setIsValidScheduledCall(true);

        vm.prank(poolDelegate);
        withdrawalManager.upgrade(2, abi.encode(address(0)));
    }

    function test_upgrade_notScheduled() external {
        vm.prank(poolDelegate);
        vm.expectRevert("WM:U:INVALID_SCHED_CALL");
        withdrawalManager.upgrade(2, "");
    }

    function test_upgrade_upgradeFailed() external {
        MockGlobals(globals).__setIsValidScheduledCall(true);

        vm.prank(poolDelegate);
        vm.expectRevert("MPF:UI:FAILED");
        withdrawalManager.upgrade(2, "1");
    }

    function test_upgrade_success() external {
        assertEq(withdrawalManager.implementation(), implementation);

        MockGlobals(globals).__setIsValidScheduledCall(true);

        vm.prank(poolDelegate);
        withdrawalManager.upgrade(2, abi.encode(address(0)));

        assertEq(withdrawalManager.implementation(), newImplementation);
    }

}
