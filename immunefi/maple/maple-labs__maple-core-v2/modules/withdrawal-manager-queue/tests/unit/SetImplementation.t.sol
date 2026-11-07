// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import { MapleWithdrawalManager } from "../../contracts/MapleWithdrawalManager.sol";

import { TestBase } from "../utils/TestBase.sol";

contract SetImplementationTests is TestBase {

    address internal newImplementation;

    function setUp() public override {
        super.setUp();

        newImplementation = address(new MapleWithdrawalManager());
    }

    function test_setImplementation_protocolPaused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("WM:PAUSED");
        withdrawalManager.setImplementation(newImplementation);
    }

    function test_setImplementation_notFactory() external {
        vm.expectRevert("WM:SI:NOT_FACTORY");
        withdrawalManager.setImplementation(newImplementation);
    }

    function test_setImplementation_success() external {
        assertEq(withdrawalManager.implementation(), implementation);

        vm.prank(withdrawalManager.factory());
        withdrawalManager.setImplementation(newImplementation);

        assertEq(withdrawalManager.implementation(), newImplementation);
    }

}
