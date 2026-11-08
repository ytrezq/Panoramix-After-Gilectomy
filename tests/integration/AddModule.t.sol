// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { NonTransparentProxy } from "../../modules/ntp/contracts/NonTransparentProxy.sol";

import { IMapleToken } from "../../contracts/interfaces/IMapleToken.sol";

import { IGlobalsLike } from "../utils/Interfaces.sol";

import { MapleToken }            from "../../contracts/MapleToken.sol";
import { MapleTokenInitializer } from "../../contracts/MapleTokenInitializer.sol";
import { MapleTokenProxy }       from "../../contracts/MapleTokenProxy.sol";

import { TestBase } from "../utils/TestBase.sol";

contract AddModuleIntegrationTests is TestBase {

    address governor = makeAddr("governor");
    address treasury = makeAddr("treasury");
    address migrator = makeAddr("migrator");
    address module   = makeAddr("module");

    uint256 start;

    IGlobalsLike globals;
    IMapleToken  token;

    function setUp() public virtual {
        globals = IGlobalsLike(address(new NonTransparentProxy(governor, deployGlobals())));

        token = IMapleToken(address(
            new MapleTokenProxy(address(globals), address(new MapleToken()), address(new MapleTokenInitializer()), migrator)
        ));

        vm.prank(governor);
        globals.setTimelockWindow(address(token), "MT:ADD_MODULE", 7 days, 2 days);

        start = block.timestamp;
    }

    function test_addModule_notGovernor() external {
        vm.expectRevert("MT:NOT_GOVERNOR");
        token.addModule(module);
    }

    function test_addModule_notScheduled() external {
        vm.prank(governor);
        vm.expectRevert("MT:NOT_SCHEDULED");
        token.addModule(module);
    }

    function test_addModule_notScheduled_beforeDelay() external {
        vm.startPrank(governor);

        globals.scheduleCall(address(token), "MT:ADD_MODULE", abi.encodeWithSelector(IMapleToken.addModule.selector, module));

        vm.warp(start + 7 days - 1);

        vm.expectRevert("MT:NOT_SCHEDULED");
        token.addModule(module);

        vm.warp(start + 7 days + 1);

        token.addModule(module);

        vm.stopPrank();
    }

    function test_addModule_notScheduled_afterWindow() external {
        vm.startPrank(governor);

        globals.scheduleCall(address(token), "MT:ADD_MODULE", abi.encodeWithSelector(IMapleToken.addModule.selector, module));

        vm.warp(start + 9 days + 1);

        vm.expectRevert("MT:NOT_SCHEDULED");
        token.addModule(module);

        vm.warp(start + 9 days);

        token.addModule(module);

        vm.stopPrank();
    }

    function test_addModule_success() external {
        vm.startPrank(governor);
        globals.scheduleCall(address(token), "MT:ADD_MODULE", abi.encodeWithSelector(IMapleToken.addModule.selector, module));

        vm.warp(start + 8 days);

        token.addModule(module);
        vm.stopPrank();

        assertTrue(token.isModule(module));
    }

}
