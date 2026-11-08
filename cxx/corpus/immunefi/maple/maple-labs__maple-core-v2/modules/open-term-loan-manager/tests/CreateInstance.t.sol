// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test } from "../modules/forge-std/src/Test.sol";

import { LoanManager }            from "../contracts/LoanManager.sol";
import { LoanManagerFactory }     from "../contracts/LoanManagerFactory.sol";
import { LoanManagerInitializer } from "../contracts/LoanManagerInitializer.sol";

import { MockFactory, MockGlobals, MockPoolManager } from "./utils/Mocks.sol";

// TODO: This should be a test of just the initializer.

contract CreateInstanceTests is Test {

    event Initialized(address indexed poolManager_);

    address asset          = makeAddr("asset");
    address governor       = makeAddr("governor");
    address implementation = address(new LoanManager());
    address initializer    = address(new LoanManagerInitializer());
    address pool           = makeAddr("pool");
    address poolDeployer   = makeAddr("poolDeployer");
    address treasury       = makeAddr("treasury");

    MockFactory     poolManagerFactory = new MockFactory();
    MockGlobals     globals            = new MockGlobals();
    MockPoolManager poolManager        = new MockPoolManager();

    LoanManagerFactory factory;

    function setUp() public virtual {
        globals.__setGovernor(governor);
        globals.setMapleTreasury(treasury);
        globals.__setInstanceOf("POOL_MANAGER_FACTORY", address(poolManagerFactory), true);

        vm.startPrank(governor);
        factory = new LoanManagerFactory(address(globals));
        factory.registerImplementation(1, implementation, initializer);
        factory.setDefaultVersion(1);
        vm.stopPrank();

        poolManagerFactory.__setIsInstance(address(poolManager), true);

        poolManager.__setAsset(address(asset));
        poolManager.__setFactory(address(poolManagerFactory));
        poolManager.__setPool(address(pool));
    }

    function test_createInstance_cannotDeploy() external {
        vm.expectRevert("LMF:CI:CANNOT_DEPLOY");
        LoanManager(factory.createInstance(abi.encode(address(poolManager)), "SALT"));
    }

    function testFail_createInstance_notPool() external {
        globals.__setCanDeploy(true);

        factory.createInstance(abi.encode(address(1)), "SALT");
    }

    function testFail_createInstance_collision() external {
        globals.__setCanDeploy(true);

        factory.createInstance(abi.encode(address(poolManager)), "SALT");
        factory.createInstance(abi.encode(address(poolManager)), "SALT");
    }

    function test_createInstance_invalidFactory() external {
        globals.__setCanDeploy(true);
        globals.__setInstanceOf("POOL_MANAGER_FACTORY", address(poolManagerFactory), false);

        vm.expectRevert("MPF:CI:FAILED");
        factory.createInstance(abi.encode(address(poolManager)), "SALT");
    }

    function test_createInstance_invalidInstance() external {
        globals.__setCanDeploy(true);

        poolManagerFactory.__setIsInstance(address(poolManager), false);

        vm.expectRevert("MPF:CI:FAILED");
        factory.createInstance(abi.encode(address(poolManager)), "SALT");
    }

    function test_createInstance_success() external {
        globals.__setCanDeploy(true);

        vm.expectEmit();
        emit Initialized(address(poolManager));

        LoanManager loanManager_ = LoanManager(factory.createInstance(abi.encode(address(poolManager)), "SALT"));

        assertEq(loanManager_.HUNDRED_PERCENT(), 1e6);
        assertEq(loanManager_.PRECISION(),       1e27);
        assertEq(loanManager_.factory(),         address(factory));
        assertEq(loanManager_.fundsAsset(),      address(asset));
        assertEq(loanManager_.implementation(),  implementation);
        assertEq(loanManager_.poolManager(),     address(poolManager));
    }

}
