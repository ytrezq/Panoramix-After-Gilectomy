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

import {Vm} from "forge-std/Vm.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {DssTest} from "dss-test/DssTest.sol";
import {SubProxy} from "endgame-toolkit/src/SubProxy.sol";
import {StarGuard} from "../src/StarGuard.sol";
import {StandardStarSpell} from "./mocks/StandardStarSpell.sol";
import {DelayedStarSpell} from "./mocks/DelayedStarSpell.sol";
import {MaliciousStarSpell} from "./mocks/MaliciousStarSpell.sol";
import {ReentrancyStarSpell} from "./mocks/ReentrancyStarSpell.sol";

contract StarGuardTest is DssTest {
    using stdStorage for StdStorage;

    StarGuard internal starGuard;
    address internal subProxy;
    address internal starSpell;

    address internal constant unauthedUser = address(0xB0B);

    function setUp() public {
        // Deploy required contracts
        subProxy = address(new SubProxy());
        starSpell = address(new StandardStarSpell());
        starGuard = new StarGuard(subProxy);

        // SubProxy is expected to authorize StarGuard
        SubProxy(subProxy).rely(address(starGuard));
    }

    function testConstructor() public {
        vm.recordLogs();

        // Deploy contract
        StarGuard newStarGuard = new StarGuard(subProxy);

        // Check emitted log
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("Rely(address)"));
        assertEq(address(uint160(uint256(entries[0].topics[1]))), address(this));

        // Check constructor effects
        assertEq(newStarGuard.wards(address(this)), 1);
        assertEq(address(newStarGuard.subProxy()), subProxy);

        // Check default values
        assertEq(newStarGuard.maxDelay(), 0);
    }

    function testFile() public {
        checkFileUint(address(starGuard), "StarGuard", ["maxDelay"]);
    }

    function testAuth() public {
        checkAuth(address(starGuard), "StarGuard");
    }

    function testAuthModifiers() public {
        bytes4[] memory authedMethods = new bytes4[](2);
        authedMethods[0] = starGuard.plot.selector;
        authedMethods[1] = starGuard.drop.selector;

        vm.startPrank(unauthedUser);
        checkModifier(address(starGuard), "StarGuard/not-authorized", authedMethods);
        vm.stopPrank();
    }

    function testPlotAndDrop(address spell, bytes32 spellTag) public {
        vm.assume(spell != address(0)); // this case is tested separately in testPlotZeroAddress

        vm.recordLogs();
        // Check initial state
        {
            (address addr, bytes32 tag, uint256 deadline) = starGuard.spellData();
            assertEq(addr, address(0));
            assertEq(tag, bytes32(0));
            assertEq(deadline, uint256(0));
        }

        // Plot
        starGuard.plot(spell, spellTag);
        {
            (address addr, bytes32 tag, uint256 deadline) = starGuard.spellData();
            assertEq(addr, spell);
            assertEq(tag, spellTag);
            assertEq(deadline, block.timestamp + starGuard.maxDelay());
        }

        // Drop
        starGuard.drop();
        {
            (address addr, bytes32 tag, uint256 deadline) = starGuard.spellData();
            assertEq(addr, address(0));
            assertEq(tag, bytes32(0));
            assertEq(deadline, uint256(0));
        }

        // Check logs
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 2);
        assertEq(entries[0].topics[0], keccak256("Plot(address,bytes32,uint256)"));
        assertEq(address(uint160(uint256(entries[0].topics[1]))), spell);
        assertEq(entries[0].data, abi.encodePacked(spellTag, block.timestamp + starGuard.maxDelay()));
        assertEq(entries[1].topics[0], keccak256("Drop(address)"));
        assertEq(address(uint160(uint256(entries[1].topics[1]))), spell);
    }

    function testExec() public {
        starGuard.plot(starSpell, starSpell.codehash);
        assertTrue(starGuard.prob());

        vm.recordLogs();
        vm.prank(unauthedUser);
        address spell = starGuard.exec();
        assertEq(spell, starSpell);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("Exec(address)"));
        assertEq(address(uint160(uint256(entries[0].topics[1]))), starSpell);
    }

    function testPlotZeroAddress() public {
        vm.expectRevert("StarGuard/zero-spell-address");
        starGuard.plot(address(0), address(0).codehash);
    }

    function testDropZeroAddress() public {
        vm.recordLogs();
        starGuard.drop();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);
    }

    function testPlotOverNotYetExecuted() public {
        // Plot the first spell
        starGuard.plot(starSpell, starSpell.codehash);

        // Plot the second spell over the first one
        assertTrue(starGuard.prob());
        vm.recordLogs();
        address secondStarSpell = address(new StandardStarSpell());
        starGuard.plot(secondStarSpell, secondStarSpell.codehash);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Check that Drop was emitted
        assertEq(entries.length, 2);
        assertEq(entries[0].topics[0], keccak256("Drop(address)"));
        assertEq(address(uint160(uint256(entries[0].topics[1]))), starSpell);
        assertEq(entries[1].topics[0], keccak256("Plot(address,bytes32,uint256)"));
        assertEq(address(uint160(uint256(entries[1].topics[1]))), secondStarSpell);
    }

    function testPlotBeforeDeploy() public {
        // plot empty address
        address addressForTheNewSpell = address(0xC0FFEE);
        starGuard.plot(addressForTheNewSpell, starSpell.codehash);
        // try to execute address without a payload deployed there
        vm.prank(unauthedUser);
        vm.expectRevert("StarGuard/wrong-codehash");
        starGuard.exec();
        // deploy spell into the address
        vm.etch(addressForTheNewSpell, starSpell.code);
        // execute it
        vm.prank(unauthedUser);
        starGuard.exec();
    }

    function testExecUnplotted() public {
        assertFalse(starGuard.prob());
        vm.prank(unauthedUser);
        vm.expectRevert("StarGuard/unplotted-spell");
        starGuard.exec();
    }

    function testExecWrongCodehash() public {
        starGuard.plot(starSpell, bytes32("irrelevant codehash"));
        assertFalse(starGuard.prob());
        vm.prank(unauthedUser);
        vm.expectRevert("StarGuard/wrong-codehash");
        starGuard.exec();
    }

    function testExecExpiredSpell() public {
        starGuard.plot(starSpell, starSpell.codehash);
        assertTrue(starGuard.prob());
        vm.warp(block.timestamp + starGuard.maxDelay() + 1);
        assertFalse(starGuard.prob());
        vm.prank(unauthedUser);
        vm.expectRevert("StarGuard/expired-spell");
        starGuard.exec();
    }

    function testDeadlineUnchanged() public {
        starGuard.file("maxDelay", 24 hours);
        starGuard.plot(starSpell, starSpell.codehash);
        (,, uint256 deadlineBefore) = starGuard.spellData();
        assertEq(deadlineBefore, block.timestamp + 24 hours);
        starGuard.file("maxDelay", 0);
        (,, uint256 deadlineAfter) = starGuard.spellData();
        assertEq(deadlineAfter, deadlineBefore);
    }

    function testExecDelayedSpell() public {
        uint256 executableAt = block.timestamp + 30 days;
        // set maximum maxDelay to avoid conflicts with tested functionality
        starGuard.file("maxDelay", type(uint160).max);
        // deploy and plot "delayed" spell
        address delayedStarSpell = address(new DelayedStarSpell(executableAt));
        starGuard.plot(delayedStarSpell, delayedStarSpell.codehash);
        // "delayed" spell is not executable before executableAt
        vm.warp(executableAt - 1);
        assertFalse(DelayedStarSpell(delayedStarSpell).isExecutable());
        assertFalse(starGuard.prob());
        vm.expectRevert("StarGuard/not-yet-executable");
        starGuard.exec();
        // "delayed" spell is executable at executableAt or after
        vm.warp(executableAt);
        assertTrue(DelayedStarSpell(delayedStarSpell).isExecutable());
        assertTrue(starGuard.prob());
        vm.prank(unauthedUser);
        starGuard.exec();
    }

    function testExecOwnerChange() public {
        // deploy and plot malicious spell
        address maliciousStarSpell = address(new MaliciousStarSpell(address(starGuard)));
        starGuard.plot(maliciousStarSpell, maliciousStarSpell.codehash);
        // execution should fail
        vm.prank(unauthedUser);
        vm.expectRevert("StarGuard/subProxy-owner-change");
        starGuard.exec();
    }

    function testPreventReentrancy() public {
        // deploy and plot reentrancy spell
        address reentrancyStarSpell = address(new ReentrancyStarSpell(address(starGuard)));
        starGuard.plot(reentrancyStarSpell, reentrancyStarSpell.codehash);
        // execution should fail
        vm.prank(unauthedUser);
        vm.expectRevert("SubProxy/delegatecall-error");
        starGuard.exec();
    }
}
