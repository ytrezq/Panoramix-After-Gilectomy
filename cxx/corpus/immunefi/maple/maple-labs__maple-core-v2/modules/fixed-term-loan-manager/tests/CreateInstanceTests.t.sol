// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test } from "../modules/forge-std/src/Test.sol";

import { LoanManager }            from "../contracts/LoanManager.sol";
import { LoanManagerFactory }     from "../contracts/proxy/LoanManagerFactory.sol";
import { LoanManagerInitializer } from "../contracts/proxy/LoanManagerInitializer.sol";

import { MockFactory, MockGlobals, MockPoolManager } from "./mocks/Mocks.sol";

contract CreateInstanceTests is Test {

    address governor;
    address implementation;
    address initializer;

    address asset        = makeAddr("asset");
    address poolDeployer = makeAddr("poolDeployer");

    MockFactory     poolManagerFactory;
    MockGlobals     globals;
    MockPoolManager poolManager;

    LoanManagerFactory factory;

    function setUp() public virtual {
        governor       = makeAddr("governor");
        implementation = address(new LoanManager());
        initializer    = address(new LoanManagerInitializer());

        globals            = new MockGlobals(governor);
        poolManager        = new MockPoolManager();
        poolManagerFactory = new MockFactory();

        vm.startPrank(governor);
        factory = new LoanManagerFactory(address(globals));
        factory.registerImplementation(1, implementation, initializer);
        factory.setDefaultVersion(1);
        vm.stopPrank();

        globals.setValidPoolDeployer(poolDeployer, true);

        poolManager.__setAsset(asset);
    }

    function test_createInstance_notPoolDeployer() external {
        vm.expectRevert();
        LoanManager(factory.createInstance(abi.encode(address(poolManager)), "SALT"));
    }

    function testFail_createInstance_notPool() external {
        factory.createInstance(abi.encode(address(1)), "SALT");
    }

    function testFail_createInstance_collision() external {
        factory.createInstance(abi.encode(address(poolManager)), "SALT");
        factory.createInstance(abi.encode(address(poolManager)), "SALT");
    }

    function test_createInstance_success_asPoolDeployer() external {
        vm.prank(poolDeployer);
        LoanManager loanManager_ = LoanManager(factory.createInstance(abi.encode(address(poolManager)), "SALT"));

        assertEq(loanManager_.fundsAsset(),  asset);
        assertEq(loanManager_.poolManager(), address(poolManager));
    }

}
