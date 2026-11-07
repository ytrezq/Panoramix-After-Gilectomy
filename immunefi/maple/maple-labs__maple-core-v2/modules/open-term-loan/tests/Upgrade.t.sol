// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test } from "../modules/forge-std/src/Test.sol";

import { MapleLoanHarness }         from "./utils/Harnesses.sol";
import { MockFactory, MockGlobals } from "./utils/Mocks.sol";

contract UpgradeTests is Test {

    event Upgraded(uint256 toVersion_, bytes arguments_);

    address borrower      = makeAddr("borrower");
    address securityAdmin = makeAddr("securityAdmin");

    MapleLoanHarness loan    = new MapleLoanHarness();
    MockFactory      factory = new MockFactory();
    MockGlobals      globals = new MockGlobals();

    function setUp() external {
        factory.__setGlobals(address(globals));

        globals.__setSecurityAdmin(securityAdmin);

        loan.__setBorrower(borrower);
        loan.__setFactory(address(factory));
    }

    function test_upgrade_paused() external {
        globals.__setFunctionPaused(true);

        vm.prank(borrower);
        vm.expectRevert("ML:PAUSED");
        loan.upgrade(1, "");
    }

    function test_upgrade_noAuth() external {
        vm.expectRevert("ML:U:NO_AUTH");
        loan.upgrade(1, "");
    }

    function test_upgrade_noAuth_asBorrower() external {
        vm.prank(borrower);
        vm.expectRevert("ML:U:NO_AUTH");
        loan.upgrade(1, "");
    }

    function test_upgrade_success_asSecurityAdmin() external {
        factory.__expectCall();
        factory.upgradeInstance(1, "");

        vm.expectEmit();
        emit Upgraded(1, "");

        vm.prank(securityAdmin);
        loan.upgrade(1, "");
    }

}
