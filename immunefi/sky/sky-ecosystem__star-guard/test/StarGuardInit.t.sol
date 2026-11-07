// SPDX-FileCopyrightText: © 2025 Dai Foundation <www.daifoundation.org>
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

import {DssTest, MCD, ScriptTools} from "dss-test/DssTest.sol";
import {DssInstance} from "dss-test/MCD.sol";
import {SubProxy} from "endgame-toolkit/src/SubProxy.sol";
import {StarGuard} from "../src/StarGuard.sol";
import {StandardStarSpell} from "./mocks/StandardStarSpell.sol";
import {StarGuardInit, StarGuardConfig} from "../deploy/StarGuardInit.sol";

contract StarGuardInitTest is DssTest {
    address constant LOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;
    address pauseProxy;
    DssInstance dss;

    function setUp() public {
        vm.createSelectFork("mainnet");
        dss = MCD.loadFromChainlog(LOG);
        pauseProxy = dss.chainlog.getAddress("MCD_PAUSE_PROXY");
    }

    function _deployStarGuard(address subProxy) private returns (address starGuard) {
        starGuard = address(new StarGuard(subProxy));
        ScriptTools.switchOwner(starGuard, address(this), pauseProxy);
    }

    function _initPlotAndExecute(StarGuardConfig memory cfg) external {
        // Check values before init call
        assertEq(StarGuard(cfg.starGuard).maxDelay(), 0);
        assertEq(SubProxy(cfg.subProxy).wards(cfg.starGuard), 0);

        // Execute StarGuardInit.init
        vm.startPrank(pauseProxy);
        StarGuardInit.init(LOG, cfg);
        vm.stopPrank();

        // Check effects of the init call
        assertEq(StarGuard(cfg.starGuard).maxDelay(), cfg.maxDelay);
        assertEq(SubProxy(cfg.subProxy).wards(cfg.starGuard), 1);

        // Plot and execute actual spell
        address starSpell = address(new StandardStarSpell());
        vm.prank(pauseProxy);
        StarGuard(cfg.starGuard).plot(starSpell, starSpell.codehash);
        vm.warp(block.timestamp + 10 hours);
        StarGuard(cfg.starGuard).exec();
    }

    function testSparkInit() public {
        // Spark Proxy can be found here https://github.com/marsfoundation/sparklend-deployments/blob/bba4c57d54deb6a14490b897c12a949aa035a99b/script/output/1/primary-sce-latest.json#L2
        address subProxy = 0x3300f198988e4C9C63F75dF86De36421f06af8c4;

        this._initPlotAndExecute(
            StarGuardConfig({
                subProxy: subProxy,
                subProxyKey: "SPARK_STAR_PROXY",
                starGuard: _deployStarGuard(subProxy),
                starGuardKey: "SPARK_STAR_GUARD",
                maxDelay: 24 hours
            })
        );
    }

    function testGroveInit() public {
        // Grove Proxy can be found at https://forum.sky.money/t/technical-scope-of-the-star-2-allocator-launch/26190
        address subProxy = 0x1369f7b2b38c76B6478c0f0E66D94923421891Ba;

        this._initPlotAndExecute(
            StarGuardConfig({
                subProxy: subProxy,
                subProxyKey: "GROVE_STAR_PROXY",
                starGuard: _deployStarGuard(subProxy),
                starGuardKey: "GROVE_STAR_GUARD",
                maxDelay: 24 hours
            })
        );
    }

    function testPrePlottedSpell() public {
        address subProxy = address(new SubProxy());
        address starGuard = address(new StarGuard(subProxy));

        // Plot a spell before switching ownership
        StarGuard(starGuard).plot(address(123), keccak256(""));
        ScriptTools.switchOwner(starGuard, address(this), pauseProxy);

        vm.expectRevert("StarGuardInit/unexpected-plotted-spell");
        this._initPlotAndExecute(
            StarGuardConfig({
                subProxy: subProxy,
                subProxyKey: "TEST_STAR_PROXY",
                starGuard: starGuard,
                starGuardKey: "TEST_STAR_GUARD",
                maxDelay: 24 hours
            })
        );
    }
}
