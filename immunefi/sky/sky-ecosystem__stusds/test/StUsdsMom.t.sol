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
import { StUsdsMom } from "src/StUsdsMom.sol";
import { ClipMock } from "test/mocks/ClipMock.sol";

interface ChiefLike {
    function hat() external view returns (address);
}

contract StUsdsMomTest is DssTest {
    address constant CHAINLOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    DssInstance      dss;
    ChiefLike        chief;
    StUsdsRateSetter rateSetter;
    StUsds           stusds;
    StUsdsMom        mom;
    address          pauseProxy;

    address bud = address(0xb0d);
    address bud2 = address(0xb0d2);

    event SetOwner(address indexed owner);
    event SetAuthority(address indexed authority);
    event DissRateSetterBud(address indexed rateSetter, address bud);
    event HaltRateSetter(address indexed rateSetter);
    event ZeroCap(address indexed rateSetter);
    event ZeroLine(address indexed rateSetter);

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        dss = MCD.loadFromChainlog(CHAINLOG);
        chief = ChiefLike(dss.chainlog.getAddress("MCD_ADM"));
        pauseProxy = dss.chainlog.getAddress("MCD_PAUSE_PROXY");

        StUsdsInstance memory inst = StUsdsDeploy.deploy(address(this), pauseProxy, address(new ClipMock("LSEV2-SKY-A")));
        stusds = StUsds(inst.stUsds);
        rateSetter = StUsdsRateSetter(inst.rateSetter);
        mom = StUsdsMom(inst.mom);

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
            minDutyBps  : 1,
            maxDutyBps  : 3000,
            stepDutyBps : 100,
            buds        : buds
        });
        vm.startPrank(pauseProxy);
        StUsdsInit.init(dss, inst, conf);
        vm.stopPrank();
    }

    function testDeploy() public view {
        // Mom part only
        assertEq(address(mom.stusds()), address(stusds));
        assertEq(mom.owner(), pauseProxy);
    }

    function testInit() public view {
        // Mom part only
        assertEq(stusds.wards(address(mom)), 1);
        assertEq(rateSetter.wards(address(mom)), 1);
        assertEq(mom.authority(), dss.chainlog.getAddress("MCD_ADM"));
        assertEq(dss.chainlog.getAddress("STUSDS_MOM"), address(mom));
    }

    function testConstructor() public {
        vm.expectEmit(true, true, true, true);
        emit SetOwner(address(this));
        StUsdsMom mom2 = new StUsdsMom(address(stusds));

        assertEq(address(mom2.stusds()), address(stusds));
        assertEq(mom2.owner(), address(this));
    }

    function testOnlyOwnerMethods() public {
        checkModifier(
            address(mom), "StUsdsMom/not-owner", [StUsdsMom.setOwner.selector, StUsdsMom.setAuthority.selector]
        );
    }

    function testAuthMethods() public {
        checkModifier(address(mom), "StUsdsMom/not-authorized", [StUsdsMom.haltRateSetter.selector, StUsdsMom.zeroCap.selector, StUsdsMom.zeroLine.selector]);

        vm.prank(address(pauseProxy));
        mom.setAuthority(address(0));
        checkModifier(address(mom), "StUsdsMom/not-authorized", [StUsdsMom.haltRateSetter.selector, StUsdsMom.zeroCap.selector, StUsdsMom.zeroLine.selector]);
    }

    function testSetOwner() public {
        vm.prank(address(pauseProxy));
        vm.expectEmit(true, true, true, true);
        emit SetOwner(address(0x1234));
        mom.setOwner(address(0x1234));
        assertEq(mom.owner(), address(0x1234));
    }

    function testSetAuthority() public {
        vm.prank(address(pauseProxy));
        vm.expectEmit(true, true, true, true);
        emit SetAuthority(address(0x123));
        mom.setAuthority(address(0x123));
        assertEq(mom.authority(), address(0x123));
    }

    function _checkDiss(address who) internal {
        vm.prank(who);
        vm.expectEmit(true, true, true, true);
        emit DissRateSetterBud(address(rateSetter), bud2);
        mom.dissRateSetterBud(address(rateSetter), bud2);
        assertEq(rateSetter.buds(bud), 1);
        assertEq(rateSetter.buds(bud2), 0);
    }

    function testDissOwner() public {
        _checkDiss(address(pauseProxy));
    }

    function testDissHat() public {
        _checkDiss(chief.hat());
    }

    function _checkHalt(address who) internal {
        vm.prank(who);
        vm.expectEmit(true, true, true, true);
        emit HaltRateSetter(address(rateSetter));
        mom.haltRateSetter(address(rateSetter));
        assertEq(rateSetter.bad(), 1);
    }

    function testHaltOwner() public {
        _checkHalt(address(pauseProxy));
    }

    function testHaltHat() public {
        _checkHalt(chief.hat());
    }

    function _checkZeroCap(address who) internal {
        vm.prank(who);
        vm.expectEmit(true, true, true, true);
        emit ZeroCap(address(rateSetter));
        mom.zeroCap(address(rateSetter));
        assertEq(stusds.cap(), 0);
        assertEq(rateSetter.maxCap(), 0);
    }

    function testZeroCapOwner() public {
        _checkZeroCap(address(pauseProxy));
    }

    function testZeroCapHat() public {
        _checkZeroCap(chief.hat());
    }

    function _checkZeroLine(address who) internal {
        vm.prank(who);
        vm.expectEmit(true, true, true, true);
        emit ZeroLine(address(rateSetter));
        mom.zeroLine(address(rateSetter));
        assertEq(stusds.line(), 0);
        assertEq(rateSetter.maxLine(), 0);
    }

    function testZeroLineOwner() public {
        _checkZeroLine(address(pauseProxy));
    }

    function testZeroLineHat() public {
        _checkZeroLine(chief.hat());
    }
}
