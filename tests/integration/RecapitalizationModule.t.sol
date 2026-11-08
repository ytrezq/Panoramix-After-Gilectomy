// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { NonTransparentProxy } from "../../modules/ntp/contracts/NonTransparentProxy.sol";

import { IMapleToken }            from "../../contracts/interfaces/IMapleToken.sol";
import { MapleToken }             from "../../contracts/MapleToken.sol";
import { MapleTokenInitializer }  from "../../contracts/MapleTokenInitializer.sol";
import { MapleTokenProxy }        from "../../contracts/MapleTokenProxy.sol";
import { RecapitalizationModule } from "../../contracts/RecapitalizationModule.sol";

import { TestBase }      from "../utils/TestBase.sol";
import { IGlobalsLike  } from "../utils/Interfaces.sol";

contract RecapitalizationModuleIntegrationTest is TestBase {

    address claimer  = makeAddr("claimer");
    address governor = makeAddr("governor");
    address treasury = makeAddr("treasury");
    address migrator = makeAddr("migrator");

    uint256 start;

    IGlobalsLike           globals;
    IMapleToken            token;
    RecapitalizationModule module;

    function setUp() public virtual {
        globals = IGlobalsLike(address(new NonTransparentProxy(governor, deployGlobals())));

        vm.prank(governor);
        globals.setMapleTreasury(treasury);

        token  = IMapleToken(address(new MapleTokenProxy(address(globals), address(new MapleToken()), address(new MapleTokenInitializer()), migrator)));
        module = new RecapitalizationModule(address(token));

        vm.startPrank(governor);
        globals.setValidInstanceOf("RECAPITALIZATION_CLAIMER", claimer, true);

        globals.scheduleCall(address(token), "MT:ADD_MODULE", abi.encodeWithSelector(IMapleToken.addModule.selector, module));

        token.addModule(address(module));

        uint32[] memory times = new uint32[](1);
        times[0] = uint32(block.timestamp);

        uint208[] memory rates = new uint208[](1);
        rates[0] = 1e18;

        globals.scheduleCall(address(module), "RM:SCHEDULE", abi.encodeWithSelector(module.schedule.selector, times, rates));

        module.schedule(times, rates);
        vm.stopPrank();

        start = block.timestamp;
    }

    function test_recapitalizationModule_claim_notClaimer() external {
        vm.expectRevert("RM:NOT_CLAIMER");
        module.claim();
    }

    function test_recapitalizationModule_claim_notMinter() external {
        vm.startPrank(governor);
        globals.scheduleCall(address(token), "MT:REMOVE_MODULE", abi.encodeWithSelector(IMapleToken.removeModule.selector, module));

        token.removeModule(address(module));

        vm.stopPrank();

        vm.warp(start + 1 seconds);

        vm.prank(claimer);
        vm.expectRevert("MT:M:NOT_MODULE");
        module.claim();
    }

    function test_recapitalizationModule_claim_success_sameWindow() external {
        uint256 startingBalance = token.balanceOf(treasury);
        uint256 supply          = token.totalSupply();

        vm.warp(start + 1000 seconds);

        vm.prank(claimer);
        module.claim();

        assertEq(token.balanceOf(treasury), startingBalance + 1_000e18);
        assertEq(token.totalSupply(),       supply + 1_000e18);

        assertEq(module.lastClaimedTimestamp(), start + 1000 seconds);
        assertEq(module.lastClaimedWindowId(),  1);
    }

    function test_recapitalizationModule_claim_success_multiWindow() external {
        // Schedule another window
        uint32[] memory times = new uint32[](1);
        times[0] = uint32(start + 500 seconds);

        uint208[] memory rates = new uint208[](1);
        rates[0] = 0.5e18;

        vm.startPrank(governor);
        globals.scheduleCall(address(module), "RM:SCHEDULE", abi.encodeWithSelector(module.schedule.selector, times, rates));
        module.schedule(times, rates);
        vm.stopPrank();

        uint256 startingBalance = token.balanceOf(treasury);
        uint256 supply          = token.totalSupply();

        vm.warp(start + 1000 seconds);

        vm.prank(claimer);
        module.claim();

        assertEq(token.balanceOf(treasury), startingBalance + 750e18);
        assertEq(token.totalSupply(),       supply + 750e18);

        assertEq(module.lastClaimedTimestamp(), start + 1000 seconds);
        assertEq(module.lastClaimedWindowId(),  2);
    }

}

contract RecapitalizationModuleIssuanceSimulation is TestBase {

    address claimer  = makeAddr("claimer");
    address governor = makeAddr("governor");
    address treasury = makeAddr("treasury");
    address migrator = makeAddr("migrator");

    uint256 start;

    IGlobalsLike           globals;
    IMapleToken            token;
    RecapitalizationModule module;

    function setUp() public virtual {
        globals = IGlobalsLike(address(new NonTransparentProxy(governor, deployGlobals())));

        vm.prank(governor);
        globals.setMapleTreasury(treasury);

        token  = IMapleToken(address(new MapleTokenProxy(address(globals), address(new MapleToken()), address(new MapleTokenInitializer()), migrator)));
        module = new RecapitalizationModule(address(token));

        vm.startPrank(governor);
        globals.setValidInstanceOf("RECAPITALIZATION_CLAIMER", claimer, true);

        globals.scheduleCall(address(token), "MT:ADD_MODULE", abi.encodeWithSelector(IMapleToken.addModule.selector, module));

        token.addModule(address(module));
        vm.stopPrank();

        start = block.timestamp;
    }

    function test_recapitalizationModule_issuanceSimulation() external {
        // Define the issuance schedule
        uint32[] memory times = new uint32[](4);
        times[0] = uint32(1696132800);  // October 1st 00:00 2023 EST
        times[1] = uint32(1704081600);  // January 1st 00:00 2024 EST
        times[2] = uint32(1735704000);  // January 1st 00:00 2025 EST
        times[3] = uint32(1767240000);  // January 1st 00:00 2026 EST

        uint208[] memory rates = new uint208[](4);
        rates[0] = 15725644122383252;
        rates[1] = 17922959674155030;
        rates[2] = 18887652207001524;
        rates[3] = 0;

        vm.startPrank(governor);
        globals.scheduleCall(address(module), "RM:SCHEDULE", abi.encodeWithSelector(module.schedule.selector, times, rates));

        module.schedule(times, rates);
        vm.stopPrank();

        // Beginning of the issuance
        vm.warp(times[0]);
        assertApproxEqAbs(token.totalSupply(),        11_000_000e18, 1e9);  // Allowing half of a unit as rounding error
        assertApproxEqAbs(module.claimable(times[1]), 125_000e18,    1e9);

        // End of 1st year (2023)
        vm.warp(times[1]);
        vm.prank(claimer);
        module.claim();

        assertApproxEqAbs(token.totalSupply(),        11_125_000e18, 1e9);
        assertApproxEqAbs(module.claimable(times[2]), 566_767e18,    1e9);

        // End of 2nd year (2024)
        vm.warp(times[2]);
        vm.prank(claimer);
        module.claim();

        assertApproxEqAbs(token.totalSupply(),        11_691_767e18, 1e9);
        assertApproxEqAbs(module.claimable(times[3]), 595_641e18,    1e9);

        // End of 3rd year (2025)
        vm.warp(times[3]);
        vm.prank(claimer);
        module.claim();

        assertApproxEqAbs(token.totalSupply(), 12_287_408e18, 1e9);
    }
    
}
