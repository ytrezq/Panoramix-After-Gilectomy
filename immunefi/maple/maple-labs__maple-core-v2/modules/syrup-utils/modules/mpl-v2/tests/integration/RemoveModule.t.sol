// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { NonTransparentProxy } from "../../modules/ntp/contracts/NonTransparentProxy.sol";

import { IMapleToken } from "../../contracts/interfaces/IMapleToken.sol";

import { IGlobalsLike } from "../utils/Interfaces.sol";

import { MapleToken }            from "../../contracts/MapleToken.sol";
import { MapleTokenInitializer } from "../../contracts/MapleTokenInitializer.sol";
import { MapleTokenProxy }       from "../../contracts/MapleTokenProxy.sol";

import { TestBase } from "../utils/TestBase.sol";

contract RemoveModuleIntegrationTests is TestBase {

    address governor = makeAddr("governor");
    address migrator = makeAddr("migrator");
    address module   = makeAddr("module");
    address treasury = makeAddr("treasury");

    uint256 start;

    IGlobalsLike globals;
    IMapleToken  token;

    function setUp() public virtual {
        globals = IGlobalsLike(address(new NonTransparentProxy(governor, deployGlobals())));

        token = IMapleToken(address(
            new MapleTokenProxy(address(globals), address(new MapleToken()), address(new MapleTokenInitializer()), migrator)
        ));

        vm.startPrank(governor);
        globals.setTimelockWindow(address(token), "MT:REMOVE_MODULE", 7 days, 2 days);
        
        globals.scheduleCall(address(token), "MT:ADD_MODULE", abi.encodeWithSelector(IMapleToken.addModule.selector, module));

        token.addModule(module);
        vm.stopPrank();

        start = block.timestamp;
    }

    function test_removeModule_notGovernor() external {
        vm.expectRevert("MT:NOT_GOVERNOR");
        token.removeModule(module);
    }

    function test_removeModule_notScheduled() external {
        vm.prank(governor);
        vm.expectRevert("MT:NOT_SCHEDULED");
        token.removeModule(module);
    }

    function test_removeModule_notScheduled_beforeDelay() external {
        vm.startPrank(governor);

        globals.scheduleCall(address(token), "MT:REMOVE_MODULE", abi.encodeWithSelector(IMapleToken.removeModule.selector, module));

        vm.warp(start + 7 days - 1);

        vm.expectRevert("MT:NOT_SCHEDULED");
        token.removeModule(module);

        vm.warp(start + 7 days + 1);

        token.removeModule(module);

        vm.stopPrank();
    }

    function test_removeModule_notScheduled_afterWindow() external {
        vm.startPrank(governor);

        globals.scheduleCall(address(token), "MT:REMOVE_MODULE", abi.encodeWithSelector(IMapleToken.removeModule.selector, module));

        vm.warp(start + 9 days + 1);

        vm.expectRevert("MT:NOT_SCHEDULED");
        token.removeModule(module);

        vm.warp(start + 9 days);

        token.removeModule(module);

        vm.stopPrank();
    }

    function test_removeModule_success() external {
        vm.startPrank(governor);
        globals.scheduleCall(address(token), "MT:REMOVE_MODULE", abi.encodeWithSelector(IMapleToken.removeModule.selector, module));

        vm.warp(start + 8 days);

        token.removeModule(module);
        vm.stopPrank();

        assertTrue(!token.isModule(module));
    }

}
