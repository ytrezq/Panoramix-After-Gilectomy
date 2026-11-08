// SPDX-FileCopyrightText: 2025 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
pragma solidity ^0.8.21;

import "dss-test/DssTest.sol";

import { StUsdsRateSetter } from "src/StUsdsRateSetter.sol";
import { StUsds } from "src/StUsds.sol";
import { StUsdsInstance } from "deploy/StUsdsInstance.sol";
import { StUsdsDeploy } from "deploy/StUsdsDeploy.sol";
import { StUsdsInit, StUsdsConfig } from "deploy/StUsdsInit.sol";
import { ClipMock } from "test/mocks/ClipMock.sol";

interface ConvLike {
    function btor(uint256) external pure returns (uint256);
    function rtob(uint256) external pure returns (uint256);
}

interface StUsdsLike {
    function wards(address) external view returns (uint256);
    function str() external view returns (uint256);
}

interface SPBEAMLike {
    function conv() external view returns (address);
}

contract MockBrokenConv {
    ConvLike immutable internal conv;

    constructor(address _conv) {
        conv = ConvLike(_conv);
    }

    function btor(uint256 /* bps */ ) public pure returns (uint256) {
        return 0;
    }

    function rtob(uint256 ray) public view returns (uint256) {
        return conv.rtob(ray);
    }
}

contract StUsdsRateSetterTest is DssTest {
    address constant CHAINLOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    DssInstance      dss;
    StUsdsRateSetter rateSetter;
    ConvLike         conv;
    StUsds           stusds;
    address          pauseProxy;

    address bud = address(0xb0d);
    address bud2 = address(0xb0d2);

    bytes32 constant STR = "STR";
    bytes32 constant ILK = "LSEV2-SKY-A";

    event Kiss(address indexed usr);
    event Diss(address indexed usr);
    event File(bytes32 indexed id, bytes32 indexed what, uint256 data);
    event Set(bytes32 indexed id, uint256 bps);
    event Set(uint256 strBps, uint256 dutyBps, uint256 line, uint256 cap);

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        dss = MCD.loadFromChainlog(CHAINLOG);
        pauseProxy = dss.chainlog.getAddress("MCD_PAUSE_PROXY");

        StUsdsInstance memory inst = StUsdsDeploy.deploy(address(this), pauseProxy, address(new ClipMock(ILK)));
        stusds = StUsds(inst.stUsds);
        rateSetter = StUsdsRateSetter(inst.rateSetter);
        conv = ConvLike(address(rateSetter.conv()));

        address[] memory buds = new address[](2);
        buds[0] = bud;
        buds[1] = bud2;

        StUsdsConfig memory conf = StUsdsConfig({
            clip        : address(stusds.clip()),
            str         : 1000000001547125957863212448,
            cap         : type(uint256).max,
            line        : type(uint256).max,
            tau         : 1 hours,
            maxLine     : 1e9 * RAD,
            maxCap      : 1e9 * WAD,
            minStrBps   : 1,
            maxStrBps   : 3000,
            stepStrBps  : 100,
            minDutyBps  : 2,
            maxDutyBps  : 4000,
            stepDutyBps : 200,
            buds        : buds
        });
        vm.startPrank(pauseProxy);
        StUsdsInit.init(dss, inst, conf);
        vm.stopPrank();
    }

    function _strBps() internal view returns (uint256 strBps) {
        strBps = conv.rtob(stusds.str());
    }

    function _duty() internal view returns (uint256 duty){
        (duty, ) = dss.jug.ilks(ILK);
    }

    function _dutyBps() internal view returns (uint256 dutyBps) {
        dutyBps = conv.rtob(_duty());
    }

    function _currentBps() internal view returns (uint256 strBps, uint256 dutyBps) {
        strBps  = _strBps();
        dutyBps = _dutyBps();
    }

    function testDeploy() public view {
        // Rate setter part only
        assertEq(address(rateSetter.jug()), address(dss.jug));
        assertEq(address(rateSetter.stusds()), address(stusds));
        assertEq(address(rateSetter.conv()), address(conv));
        assertEq(rateSetter.ilk(), ILK);
        assertEq(rateSetter.wards(address(this)), 0);
        assertEq(rateSetter.wards(pauseProxy), 1);
    }

    function testInit() public view {
        // Rate setter part only
        assertEq(dss.jug.wards(address(rateSetter)), 1);
        assertEq(stusds.wards(address(rateSetter)), 1);
        assertEq(rateSetter.tau(), 1 hours);
        assertEq(rateSetter.maxLine(), 1e9 * RAD);
        assertEq(rateSetter.maxCap(), 1e9 * WAD);
        (uint16 minStr, uint16 maxStr, uint256 strStep) = rateSetter.strCfg();
        assertEq(minStr, 1);
        assertEq(maxStr, 3000);
        assertEq(strStep, 100);
        (uint16 minDuty, uint16 maxDuty, uint256 dutyStep) = rateSetter.dutyCfg();
        assertEq(minDuty, 2);
        assertEq(maxDuty, 4000);
        assertEq(dutyStep, 200);
        assertEq(rateSetter.buds(bud), 1);
        assertEq(rateSetter.buds(bud2), 1);
        assertEq(dss.chainlog.getAddress("STUSDS_RATE_SETTER"), address(rateSetter));
    }

    function testConstructor() public {
        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        StUsdsRateSetter rateSetter2 = new StUsdsRateSetter(
            dss.chainlog.getAddress("STUSDS"),
            SPBEAMLike(dss.chainlog.getAddress("MCD_SPBEAM")).conv()
        );

        assertEq(address(rateSetter2.stusds()), address(stusds));
        assertEq(address(rateSetter2.conv()), address(conv));
        assertEq(address(rateSetter2.jug()), address(dss.jug));
        assertEq(rateSetter2.ilk(), ILK);
        assertEq(rateSetter2.wards(address(this)), 1);
    }

    function testAuth() public {
        checkAuth(address(rateSetter), "StUsdsRateSetter");
    }

    function testAuthMethods() public {
        checkModifier(address(rateSetter), "StUsdsRateSetter/not-authorized", [StUsdsRateSetter.kiss.selector, StUsdsRateSetter.diss.selector]);
    }

    function testTollMethods() public {
        checkModifier(address(rateSetter), "StUsdsRateSetter/not-facilitator", [StUsdsRateSetter.set.selector]);
    }

    function testGoodMethods() public {
        vm.startPrank(pauseProxy);
        rateSetter.file("bad", 1);
        rateSetter.kiss(address(this));
        vm.stopPrank();

        checkModifier(address(rateSetter), "StUsdsRateSetter/module-halted", [StUsdsRateSetter.set.selector]);
    }

    function testKissDiss() public {
        address who = address(0x0ddaf);
        assertEq(rateSetter.buds(who), 0);

        vm.expectEmit(true, true, true, true);
        emit Kiss(who);
        vm.prank(pauseProxy); rateSetter.kiss(who);
        assertEq(rateSetter.buds(who), 1);

        vm.expectEmit(true, true, true, true);
        emit Diss(who);
        vm.prank(pauseProxy); rateSetter.diss(who);
        assertEq(rateSetter.buds(who), 0);
    }

    function testFile() public {
        checkFileUint(address(rateSetter), "StUsdsRateSetter", ["bad", "tau", "toc", "maxLine", "maxCap"]);

        vm.startPrank(pauseProxy);

        vm.expectRevert("StUsdsRateSetter/invalid-bad-value");
        rateSetter.file("bad", 2);

        vm.expectRevert("StUsdsRateSetter/invalid-tau-value");
        rateSetter.file("tau", uint256(type(uint64).max) + 1);

        vm.expectRevert("StUsdsRateSetter/invalid-toc-value");
        rateSetter.file("toc", uint256(type(uint128).max) + 1);

        vm.expectRevert("StUsdsRateSetter/maxLine-irrelevant-value");
        rateSetter.file("maxLine", RAD - 1);

        vm.expectRevert("StUsdsRateSetter/maxCap-insane-value");
        rateSetter.file("maxCap", RAD);

        vm.stopPrank();

        vm.expectRevert("StUsdsRateSetter/not-authorized");
        rateSetter.file("bad", 1);
    }

    function testFileStr() public {
        (uint16 min, uint16 max, uint16 step) = rateSetter.strCfg();
        assertEq(min, 1);
        assertEq(max, 3000);
        assertEq(step, 100);

        vm.startPrank(pauseProxy);
        vm.expectEmit(true, true, true, true);
        emit File(STR, "min", 100);
        rateSetter.file(STR, "min", 100);
        vm.expectEmit(true, true, true, true);
        emit File(STR, "max", 2000);
        rateSetter.file(STR, "max", 2000);
        vm.expectEmit(true, true, true, true);
        emit File(STR, "step", 420);
        rateSetter.file(STR, "step", 420);
        vm.stopPrank();

        (min, max, step) = rateSetter.strCfg();
        assertEq(min, 100);
        assertEq(max, 2000);
        assertEq(step, 420);
    }

    function testFileIlk() public {
        (uint16 min, uint16 max, uint16 step) = rateSetter.dutyCfg();
        assertEq(min, 2);
        assertEq(max, 4000);
        assertEq(step, 200);

        vm.startPrank(pauseProxy);
        vm.expectEmit(true, true, true, true);
        emit File(ILK, "min", 100);
        rateSetter.file(ILK, "min", 100);
        vm.expectEmit(true, true, true, true);
        emit File(ILK, "max", 2000);
        rateSetter.file(ILK, "max", 2000);
        vm.expectEmit(true, true, true, true);
        emit File(ILK, "step", 420);
        rateSetter.file(ILK, "step", 420);
        vm.stopPrank();

        (min, max, step) = rateSetter.dutyCfg();
        assertEq(min, 100);
        assertEq(max, 2000);
        assertEq(step, 420);
    }

    function testRevertFileInvalid() public {
        vm.startPrank(pauseProxy);
        (uint16 min, uint16 max,) = rateSetter.dutyCfg();

        vm.expectRevert("StUsdsRateSetter/min-too-high");
        rateSetter.file(ILK, "min", max + 1);

        vm.expectRevert("StUsdsRateSetter/max-too-low");
        rateSetter.file(ILK, "max", min - 1);

        vm.expectRevert("StUsdsRateSetter/file-unrecognized-param");
        rateSetter.file(ILK, "unknown", 100);

        vm.expectRevert("StUsdsRateSetter/invalid-value");
        rateSetter.file(ILK, "max", uint256(type(uint16).max) + 1);

        vm.expectRevert("StUsdsRateSetter/file-unrecognized-id");
        rateSetter.file("MOG-A", "min", 100);

        vm.stopPrank();

        vm.expectRevert("StUsdsRateSetter/not-authorized");
        rateSetter.file(ILK, "min", 100);
    }

    function testSet() public {
        (uint256 strTarget, uint256 dutyTarget) = (_strBps() + 50, _dutyBps() + 50);

        vm.expectEmit(true, true, true, true);
        emit Set(strTarget, dutyTarget, 50_000_000 * RAD, 60_000_000 * WAD);
        vm.prank(bud); rateSetter.set(strTarget, dutyTarget, 50_000_000 * RAD, 60_000_000 * WAD);

        assertEq(stusds.str(), conv.btor(strTarget));
        assertEq(_duty(), conv.btor(dutyTarget));
        assertEq(stusds.line(), 50_000_000 * RAD);
        assertEq(stusds.cap(), 60_000_000 * WAD);
    }

    // following tests check that can still set rates,
    // even if previously the rates were outside of the range.
    function testSetRatesAboveMax() public {
        dss.jug.drip(ILK);
        vm.startPrank(pauseProxy);
        stusds.file("str", conv.btor(3050)); // outside range
        dss.jug.file(ILK, "duty", conv.btor(4050)); // outside range
        vm.stopPrank();

        vm.startPrank(bud);
        rateSetter.set(2999, 3999, 0, 0);
        vm.stopPrank();

        assertEq(stusds.str(), conv.btor(2999));
        assertEq(_duty(), conv.btor(3999));
    }

    function testSetRatesBelowMin() public {
        dss.jug.drip(ILK);
        vm.startPrank(pauseProxy);
        stusds.file("str", conv.btor(0)); // outside range
        dss.jug.file(ILK, "duty", conv.btor(0)); // outside range
        vm.stopPrank();

        vm.startPrank(bud);
        rateSetter.set(50, 50, 0, 0);
        vm.stopPrank();

        assertEq(stusds.str(), conv.btor(50));
        assertEq(_duty(), conv.btor(50));
    }

    function testRevertSetStrNotConfiguredRate() public {
        vm.prank(pauseProxy); rateSetter.file(STR, "step", 0);
        (uint256 strBps, uint256 dutyBps) = _currentBps();
        vm.expectRevert("StUsdsRateSetter/rate-not-configured");
        vm.prank(bud); rateSetter.set(strBps, dutyBps, 0, 0);
    }

    function testRevertSetDutyNotConfiguredRate() public {
        vm.prank(pauseProxy); rateSetter.file(ILK, "step", 0);
        (uint256 strBps, uint256 dutyBps) = _currentBps();
        vm.expectRevert("StUsdsRateSetter/rate-not-configured");
        vm.prank(bud); rateSetter.set(strBps, dutyBps, 0, 0);
    }

    function testRevertSetStrBelowMin() public {
        vm.prank(pauseProxy); rateSetter.file(STR, "min", 100);
        uint256 dutyBps = _dutyBps();
        vm.expectRevert("StUsdsRateSetter/below-min");
        vm.prank(bud); rateSetter.set(50, dutyBps, 0, 0);
    }

    function testRevertSetDutyBelowMin() public {
        vm.prank(pauseProxy); rateSetter.file(ILK, "min", 100);
        uint256 strBps = _strBps();
        vm.expectRevert("StUsdsRateSetter/below-min");
        vm.prank(bud); rateSetter.set(strBps, 50, 0, 0);
    }

    function testRevertSetStrAboveMax() public {
        vm.prank(pauseProxy); rateSetter.file(STR, "max", 100);
        uint256 dutyBps = _dutyBps();
        vm.expectRevert("StUsdsRateSetter/above-max");
        vm.prank(bud); rateSetter.set(150, dutyBps, 0, 0);
    }

    function testRevertSetDutyAboveMax() public {
        vm.prank(pauseProxy); rateSetter.file(ILK, "max", 100);
        uint256 strBps = _strBps();
        vm.expectRevert("StUsdsRateSetter/above-max");
        vm.prank(bud); rateSetter.set(strBps, 150, 0, 0);
    }

    function testRevertSetStrDeltaAboveStep() public {
        vm.prank(pauseProxy); rateSetter.file(STR, "step", 100);
        (uint256 strBps, uint256 dutyBps) = _currentBps();
        vm.expectRevert("StUsdsRateSetter/delta-above-step");
        vm.prank(bud); rateSetter.set(strBps + 101, dutyBps, 0, 0);
    }

    function testRevertSetDutyDeltaAboveStep() public {
        vm.prank(pauseProxy); rateSetter.file(ILK, "step", 100);
        (uint256 strBps, uint256 dutyBps) = _currentBps();
        vm.expectRevert("StUsdsRateSetter/delta-above-step");
        vm.prank(bud); rateSetter.set(strBps, dutyBps + 101, 0, 0);
    }

    function testRevertLineTooHigh() public {
        vm.prank(pauseProxy); rateSetter.file("maxLine", 100 * RAD);
        (uint256 strBps, uint256 dutyBps) = _currentBps();
        vm.expectRevert("StUsdsRateSetter/line-too-high");
        vm.prank(bud); rateSetter.set(strBps, dutyBps, 100 * RAD + 1, 0);
    }

    function testRevertCapTooHigh() public {
        vm.prank(pauseProxy); rateSetter.file("maxCap", 100 * WAD);
        (uint256 strBps, uint256 dutyBps) = _currentBps();
        vm.expectRevert("StUsdsRateSetter/cap-too-high");
        vm.prank(bud); rateSetter.set(strBps, dutyBps, 0, 100 * WAD + 1);
    }

    function testRevertSetBeforeCooldown() public {
        vm.prank(pauseProxy); rateSetter.file("tau", 100);
        (uint256 strBps, uint256 dutyBps) = _currentBps();
        vm.prank(bud); rateSetter.set(strBps, dutyBps, 0, 0);

        vm.warp(block.timestamp + 99);

        vm.expectRevert("StUsdsRateSetter/too-early");
        vm.prank(bud); rateSetter.set(strBps, dutyBps, 0, 0);
    }

    function testRevertSetMalfunctioningConv() public {
        // Clone the good conv code (before we break it below), so we can call conv.rtob() in MockBrokenConv
        vm.etch(address(0x123), address(conv).code);

        // Mutate the conv code that is used in rateSetter
        vm.etch(address(conv), address(new MockBrokenConv(address(0x123))).code);

        (uint256 strBps, uint256 dutyBps) = _currentBps();
        vm.expectRevert("StUsdsRateSetter/invalid-rate-conv");
        vm.prank(bud); rateSetter.set(strBps, dutyBps, 0, 0);
    }
}
