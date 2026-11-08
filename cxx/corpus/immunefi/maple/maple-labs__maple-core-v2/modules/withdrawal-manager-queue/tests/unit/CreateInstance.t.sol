// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import { MapleWithdrawalManager }        from "../../contracts/MapleWithdrawalManager.sol";
import { MapleWithdrawalManagerFactory } from "../../contracts/proxy/MapleWithdrawalManagerFactory.sol";

import { TestBase }                      from "../utils/TestBase.sol";
import { MapleWithdrawalManagerHarness } from "../utils/Harnesses.sol";

contract CreateInstanceTests is TestBase {

    event Initialized(address indexed pool_, address indexed poolManager_);

    function setUp() public override {
        super.setUp();

        vm.startPrank(governor);
        factory = new MapleWithdrawalManagerFactory(address(globals));
        factory.registerImplementation(1, implementation, initializer);
        factory.setDefaultVersion(1);

        globals.__setCanDeploy(true);
        vm.stopPrank();
    }

    function test_createInstance_invalidCaller() external {
        bytes memory calldata_ = abi.encode(address(pool));

        globals.__setCanDeploy(false);

        vm.expectRevert("WMF:CI:CANNOT_DEPLOY");
        factory.createInstance(calldata_, "SALT");

        globals.__setCanDeploy(true);

        factory.createInstance(calldata_, "SALT");
    }

    function test_createInstance_zeroPool() external {
        bytes memory calldata_ = abi.encode(address(0));

        vm.expectRevert("MPF:CI:FAILED");
        factory.createInstance(calldata_, "SALT");
    }

    function test_createInstance_invalidFactory() external {
        bytes memory calldata_ = abi.encode(address(pool));

        globals.__setIsInstanceOf(false);

        vm.expectRevert("MPF:CI:FAILED");
        factory.createInstance(calldata_, "SALT");
    }

    function test_createInstance_invalidInstance() external {
        bytes memory calldata_ = abi.encode(address(pool));

        poolManagerFactory.__setIsInstance(false);

        vm.expectRevert("MPF:CI:FAILED");
        factory.createInstance(calldata_, "SALT");
    }

    function test_createInstance_success() external {
        bytes memory calldata_ = abi.encode(address(pool));

        vm.expectEmit();
        emit Initialized(address(pool), pm);

        MapleWithdrawalManager withdrawalManager_ = MapleWithdrawalManager(factory.createInstance(calldata_, "SALT"));

        assertEq(MapleWithdrawalManagerHarness(address(withdrawalManager_)).locked(), 1);

        assertEq(withdrawalManager_.pool(),        address(pool));
        assertEq(withdrawalManager_.poolManager(), pm);

        ( uint128 nextRequestId, ) = withdrawalManager_.queue();

        assertEq(nextRequestId, 1);
    }

}
