// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { MapleToken }            from "../../contracts/MapleToken.sol";
import { MapleTokenInitializer } from "../../contracts/MapleTokenInitializer.sol";
import { MapleTokenProxy }       from "../../contracts/MapleTokenProxy.sol";

import { TestBase }    from "../utils/TestBase.sol";
import { MockGlobals } from "../utils/Mocks.sol";

contract MapleTokenInitializerTests is TestBase {

    event Initialized(address tokenMigrator, address treasury);

    address governor = makeAddr("governor");
    address migrator = makeAddr("migrator");
    address treasury = makeAddr("treasury");

    address implementation;
    address initializer;

    MockGlobals globals;

    function setUp() external {
        globals = new MockGlobals();

        globals.__setGovernor(governor);
        globals.__setMapleTreasury(treasury);

        implementation = address(new MapleToken());
        initializer    = address(new MapleTokenInitializer());
    }

    function test_initialize() external {
        vm.expectEmit();
        emit Initialized(migrator, treasury);

        MapleToken token = MapleToken(address(new MapleTokenProxy(address(globals), implementation, initializer, migrator)));

        assertEq(token.governor(),       governor);
        assertEq(token.globals(),        address(globals));
        assertEq(token.implementation(), implementation);

        assertEq(token.name(),     "Maple Token");
        assertEq(token.symbol(),   "MPL");
        assertEq(token.decimals(), 18);

        assertEq(token.balanceOf(migrator), 10_000_000e18);
        assertEq(token.balanceOf(treasury), 1_000_000e18);

        assertEq(token.totalSupply(), 11_000_000e18);
    }

}
