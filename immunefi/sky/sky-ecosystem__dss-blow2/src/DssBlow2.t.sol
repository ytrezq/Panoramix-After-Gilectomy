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
pragma solidity ^0.8.24;

import "dss-test/DssTest.sol";
import "./DssBlow2.sol";

contract DssBlow2Test is DssTest {
    address constant CHAINLOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    DssInstance dss;
    DssBlow2 dssBlow2;

    address usds;
    address usdsJoin;
    address vow;

    event Blow(address indexed token, uint256 amount);

    function setUp() public {
        vm.createSelectFork("mainnet");
        // get all the relevant addresses
        dss = MCD.loadFromChainlog(CHAINLOG);
        usds = dss.chainlog.getAddress("USDS");
        usdsJoin = dss.chainlog.getAddress("USDS_JOIN");
        vow = address(dss.vow);

        dssBlow2 = new DssBlow2(address(dss.daiJoin), usdsJoin, vow);

        vm.label(address(dss.dai), "Dai");
        vm.label(address(dss.daiJoin), "DaiJoin");
        vm.label(usds, "Usds");
        vm.label(usdsJoin, "UsdsJoin");
        vm.label(address(dss.vow), "Vow");
    }

    function test_blow() public {
        // send dai and usds to DssBlow2
        uint256 daiAmount = 10 ether;
        uint256 usdsAmount = 5 ether;
        deal(address(dss.dai), address(dssBlow2), daiAmount);
        deal(usds, address(dssBlow2), usdsAmount);
        // store balances before blow()
        uint256 vowDaiBalance = dss.vat.dai(vow);
        uint256 blowDaiBalance = dss.dai.balanceOf(address(dssBlow2));
        uint256 blowUsdsBalance = ERC20Like(usds).balanceOf(address(dssBlow2));
        assertEq(blowDaiBalance, daiAmount);
        assertEq(blowUsdsBalance, usdsAmount);
        // event emission
        vm.expectEmit(true, false, false, true);
        emit Blow(address(dss.dai), daiAmount);
        vm.expectEmit(true, false, false, true);
        emit Blow(usds, usdsAmount);
        // call blow()
        dssBlow2.blow();
        // check balances after blow()
        blowDaiBalance = dss.dai.balanceOf(address(dssBlow2));
        blowUsdsBalance = ERC20Like(usds).balanceOf(address(dssBlow2));
        assertEq(blowDaiBalance, 0);
        assertEq(blowUsdsBalance, 0);
        // the vat dai balance is in rad so we multiply with ray
        assertEq(dss.vat.dai(vow), vowDaiBalance + (daiAmount + usdsAmount) * RAY, "blowDaiUsds: vow balance mismatch");
    }

    function test_blowDai() public {
        // send only dai to DssBlow2
        uint256 daiAmount = 10 ether;
        deal(address(dss.dai), address(dssBlow2), daiAmount);
        // store balances before blow()
        uint256 vowDaiBalance = dss.vat.dai(vow);
        uint256 blowDaiBalance = dss.dai.balanceOf(address(dssBlow2));
        uint256 blowUsdsBalance = ERC20Like(usds).balanceOf(address(dssBlow2));
        assertEq(blowDaiBalance, daiAmount);
        // event emission
        vm.expectEmit(true, false, false, true);
        emit Blow(address(dss.dai), daiAmount);
        // call blow()
        dssBlow2.blow();
        // check balances after blow()
        blowDaiBalance = dss.dai.balanceOf(vow);
        blowUsdsBalance = ERC20Like(usds).balanceOf(vow);
        assertEq(blowDaiBalance, 0);
        assertEq(blowUsdsBalance, 0);
        // the vat dai balance is in rad so we multiply with ray
        assertEq(dss.vat.dai(vow), vowDaiBalance + daiAmount * RAY, "blowDai: vow balance mismatch");
    }

    function test_blowUsds() public {
        // send only usds to DssBlow2
        uint256 usdsAmount = 5 ether;
        deal(usds, address(dssBlow2), usdsAmount);
        // store balances before blow()
        uint256 vowDaiBalance = dss.vat.dai(vow);
        uint256 blowDaiBalance = dss.dai.balanceOf(address(dssBlow2));
        uint256 blowUsdsBalance = ERC20Like(usds).balanceOf(address(dssBlow2));
        assertEq(blowUsdsBalance, usdsAmount);
        // event emission
        vm.expectEmit(true, false, false, true);
        emit Blow(usds, usdsAmount);
        // call blow()
        dssBlow2.blow();
        // check balances after blow()
        blowDaiBalance = dss.dai.balanceOf(address(dssBlow2));
        blowUsdsBalance = ERC20Like(usds).balanceOf(address(dssBlow2));
        assertEq(blowDaiBalance, 0);
        assertEq(blowUsdsBalance, 0);
        // the vat dai balance is in rad so we multiply with ray
        assertEq(dss.vat.dai(vow), vowDaiBalance + usdsAmount * RAY, "blowUsds: vow balance mismatch");
    }
}
