// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { MapleBasicStrategy  } from "../../contracts/MapleBasicStrategy.sol";
import { MapleAaveStrategy }   from "../../contracts/MapleAaveStrategy.sol";
import { MapleSkyStrategy }    from "../../contracts/MapleSkyStrategy.sol";

import { AaveStrategyTestBase, BasicStrategyTestBase, SkyStrategyTestBase } from "../utils/TestBase.sol";

contract MapleBasicStrategySetImplementationTests is BasicStrategyTestBase {

    address internal newImplementation;

    function setUp() public override {
        super.setUp();

        newImplementation = address(new MapleBasicStrategy());
    }

    function test_setImplementation_protocolPaused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("MS:PAUSED");
        strategy.setImplementation(newImplementation);
    }

    function test_setImplementation_notFactory() external {
        vm.expectRevert("MS:SI:NOT_FACTORY");
        strategy.setImplementation(newImplementation);
    }

    function test_setImplementation_success() external {
        assertEq(strategy.implementation(), implementation);

        vm.prank(strategy.factory());
        strategy.setImplementation(newImplementation);

        assertEq(strategy.implementation(), newImplementation);
    }

}

contract MapleSkyStrategySetImplementationTests is SkyStrategyTestBase {

    address internal newImplementation;

    function setUp() public override {
        super.setUp();

        newImplementation = address(new MapleSkyStrategy());
    }

    function test_setImplementation_protocolPaused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("MS:PAUSED");
        strategy.setImplementation(newImplementation);
    }

    function test_setImplementation_notFactory() external {
        vm.expectRevert("MS:SI:NOT_FACTORY");
        strategy.setImplementation(newImplementation);
    }

    function test_setImplementation_success() external {
        assertEq(strategy.implementation(), implementation);

        vm.prank(strategy.factory());
        strategy.setImplementation(newImplementation);

        assertEq(strategy.implementation(), newImplementation);
    }

}

contract MapleAaveStrategySetImplementationTests is AaveStrategyTestBase {

    address internal newImplementation;

    function setUp() public override {
        super.setUp();

        newImplementation = address(new MapleAaveStrategy());
    }

    function test_setImplementation_protocolPaused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("MS:PAUSED");
        strategy.setImplementation(newImplementation);
    }

    function test_setImplementation_notFactory() external {
        vm.expectRevert("MS:SI:NOT_FACTORY");
        strategy.setImplementation(newImplementation);
    }

    function test_setImplementation_success() external {
        assertEq(strategy.implementation(), implementation);

        vm.prank(strategy.factory());
        strategy.setImplementation(newImplementation);

        assertEq(strategy.implementation(), newImplementation);
    }

}
