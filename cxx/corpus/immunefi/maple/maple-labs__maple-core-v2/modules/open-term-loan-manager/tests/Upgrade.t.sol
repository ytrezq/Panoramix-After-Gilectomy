// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test } from "../modules/forge-std/src/Test.sol";

import { LoanManagerHarness }                        from "./utils/Harnesses.sol";
import { MockFactory, MockGlobals, MockPoolManager } from "./utils/Mocks.sol";

contract UpgradeTests is Test {

    event Upgraded(uint256 toVersion_, bytes arguments_);

    address poolDelegate  = makeAddr("poolDelegate");
    address securityAdmin = makeAddr("securityAdmin");

    LoanManagerHarness loanManager = new LoanManagerHarness();
    MockFactory        factory     = new MockFactory();
    MockGlobals        globals     = new MockGlobals();
    MockPoolManager    poolManager = new MockPoolManager();

    function setUp() external {
        factory.__setMapleGlobals(address(globals));

        globals.__setSecurityAdmin(securityAdmin);

        loanManager.__setFactory(address(factory));
        loanManager.__setPoolManager(address(poolManager));

        poolManager.__setPoolDelegate(poolDelegate);
    }

    function test_upgrade_paused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("LM:PAUSED");
        loanManager.upgrade(1, "");
    }

    function test_upgrade_noAuth() external {
        vm.expectRevert("LM:U:NO_AUTH");
        loanManager.upgrade(1, "");
    }

    function test_upgrade_notScheduled() external {
        vm.prank(poolDelegate);
        vm.expectRevert("LM:U:INVALID_SCHED_CALL");
        loanManager.upgrade(1, "");
    }

    function test_upgrade_success_asPoolDelegate() external {
        globals.__setIsValidScheduledCall(true);

        factory.__expectCall();
        factory.upgradeInstance(1, "");

        vm.expectEmit();
        emit Upgraded(1, "");

        vm.prank(poolDelegate);
        loanManager.upgrade(1, "");
    }

    function test_upgrade_success_asSecurityAdmin() external {
        factory.__expectCall();
        factory.upgradeInstance(1, "");

        vm.expectEmit();
        emit Upgraded(1, "");

        vm.prank(securityAdmin);
        loanManager.upgrade(1, "");
    }

}
