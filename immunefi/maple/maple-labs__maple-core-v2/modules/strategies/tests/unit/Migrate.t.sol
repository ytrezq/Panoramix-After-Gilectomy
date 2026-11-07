// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { MockStrategiesMigrator }                                           from "../utils/Mocks.sol";
import { AaveStrategyTestBase, BasicStrategyTestBase, SkyStrategyTestBase } from "../utils/TestBase.sol";

contract MapleBasicStrategyMigrateTests is BasicStrategyTestBase {

    address internal migrator;

    function setUp() public override {
        super.setUp();

        migrator = address(new MockStrategiesMigrator());
    }

    function test_migrate_protocolPaused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("MS:PAUSED");
        strategy.migrate(migrator, "");
    }

    function test_migrate_notFactory() external {
        vm.expectRevert("MS:M:NOT_FACTORY");
        strategy.migrate(migrator, "");
    }

    function test_migrate_internalFailure() external {
        vm.prank(address(factory));
        vm.expectRevert("MS:M:FAILED");
        strategy.migrate(migrator, "");
    }

    function test_migrate_success() external {
        assertEq(strategy.pool(), address(pool));

        vm.prank(address(factory));
        strategy.migrate(migrator, abi.encode(address(0)));

        assertEq(strategy.pool(), address(0));
    }

}

contract MapleSkyStrategyMigrateTests is SkyStrategyTestBase {

    address internal migrator;

    function setUp() public override {
        super.setUp();

        migrator = address(new MockStrategiesMigrator());
    }

    function test_migrate_protocolPaused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("MS:PAUSED");
        strategy.migrate(migrator, "");
    }

    function test_migrate_notFactory() external {
        vm.expectRevert("MS:M:NOT_FACTORY");
        strategy.migrate(migrator, "");
    }

    function test_migrate_internalFailure() external {
        vm.prank(address(factory));
        vm.expectRevert("MS:M:FAILED");
        strategy.migrate(migrator, "");
    }

    function test_migrate_success() external {
        assertEq(strategy.pool(), address(pool));

        vm.prank(address(factory));
        strategy.migrate(migrator, abi.encode(address(0)));

        assertEq(strategy.pool(), address(0));
    }

}

contract MapleAaveStrategyMigrateTests is AaveStrategyTestBase {

    address internal migrator;

    function setUp() public override {
        super.setUp();

        migrator = address(new MockStrategiesMigrator());
    }

    function test_migrate_protocolPaused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("MS:PAUSED");
        strategy.migrate(migrator, "");
    }

    function test_migrate_notFactory() external {
        vm.expectRevert("MS:M:NOT_FACTORY");
        strategy.migrate(migrator, "");
    }

    function test_migrate_internalFailure() external {
        vm.prank(address(factory));
        vm.expectRevert("MS:M:FAILED");
        strategy.migrate(migrator, "");
    }

    function test_migrate_success() external {
        assertEq(strategy.pool(), address(pool));

        vm.prank(address(factory));
        strategy.migrate(migrator, abi.encode(address(0)));

        assertEq(strategy.pool(), address(0));
    }

}
