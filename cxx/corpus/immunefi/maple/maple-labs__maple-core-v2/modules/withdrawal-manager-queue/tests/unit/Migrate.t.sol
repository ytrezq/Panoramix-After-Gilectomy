// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import { MockWithdrawalManagerMigrator } from "../utils/Mocks.sol";
import { TestBase }                      from "../utils/TestBase.sol";

contract MigrateTests is TestBase {

    address internal migrator;

    function setUp() public override {
        super.setUp();

        migrator = address(new MockWithdrawalManagerMigrator());
    }

    function test_migrate_protocolPaused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("WM:PAUSED");
        withdrawalManager.migrate(migrator, "");
    }

    function test_migrate_notFactory() external {
        vm.expectRevert("WM:M:NOT_FACTORY");
        withdrawalManager.migrate(migrator, "");
    }

    function test_migrate_internalFailure() external {
        vm.prank(address(factory));
        vm.expectRevert("WM:M:FAILED");
        withdrawalManager.migrate(migrator, "");
    }

    function test_migrate_success() external {
        assertEq(withdrawalManager.pool(), address(pool));

        vm.prank(address(factory));
        withdrawalManager.migrate(migrator, abi.encode(address(0)));

        assertEq(withdrawalManager.pool(), address(0));
    }

}
