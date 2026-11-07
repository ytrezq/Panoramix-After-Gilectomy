// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2023 Dai Foundation
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.16;

import "forge-std/Test.sol";

import "./LineMom.sol";

contract VatMock {
    mapping (address => uint256) public wards;
    function rely(address usr) external auth { wards[usr] = 1; }
    function deny(address usr) external auth { wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "Vat/not-authorized");
        _;
    }

    struct Ilk {
        uint256 Art;   // Total Normalised Debt     [wad]
        uint256 rate;  // Accumulated Rates         [ray]
        uint256 spot;  // Price with Safety Margin  [ray]
        uint256 line;  // Debt Ceiling              [rad]
        uint256 dust;  // Urn Debt Floor            [rad]
    }

    mapping (bytes32 => Ilk) public ilks;

    constructor() {
        wards[msg.sender] = 1;
    }

    function file(bytes32 ilk, bytes32 what, uint256 data) external auth {
        if (what == "line") ilks[ilk].line = data;
        else revert("Vat/file-unrecognized-param");
    }
}

contract AutoLineMock {
    struct Ilk {
        uint256   line;
        uint256    gap;
        uint48     ttl;
        uint48    last;
        uint48 lastInc;
    }

    mapping (bytes32 => Ilk)     public ilks;
    mapping (address => uint256) public wards;

    constructor() {
        wards[msg.sender] = 1;
    }

    function setIlk(bytes32 ilk, uint256 line, uint256 gap, uint256 ttl) external auth {
        ilks[ilk] = Ilk(line, gap, uint48(ttl), 0, 0);
    }

    function remIlk(bytes32 ilk) external auth {
        delete ilks[ilk];
    }

    function rely(address usr) external auth {
        wards[usr] = 1;
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
    }

    modifier auth {
        require(wards[msg.sender] == 1, "DssAutoLine/not-authorized");
        _;
    }
}

contract SimpleAuthority {
    address public authorized_caller;

    constructor(address authorized_caller_) {
        authorized_caller = authorized_caller_;
    }

    function canCall(address src, address, bytes4) public view returns (bool) {
        return src == authorized_caller;
    }
}

contract LineMomTest is Test {
    VatMock vat;
    AutoLineMock autoLine;

    LineMom mom;

    address caller = address(0x123);
    SimpleAuthority authority;

    event Wipe(bytes32 indexed ilk, uint256 line);
    event AddIlk(bytes32 indexed ilk);
    event DelIlk(bytes32 indexed ilk);

    function setUp() public {
        vat = new VatMock();
        vat.file("ETH-A", "line", 100);
        assertEq(getVatIlkLine("ETH-A"), 100);

        autoLine = new AutoLineMock();
        autoLine.setIlk("ETH-A", 1000, 100, 60);
        (uint256 l, uint256 g, uint256 t,,) = autoLine.ilks("ETH-A");
        assertEq(l, 1000);
        assertEq(g, 100);
        assertEq(t, 60);

        mom = new LineMom(address(vat));
        mom.file("autoLine", address(autoLine));
        mom.addIlk("ETH-A");

        vat.rely(address(mom));
        autoLine.rely(address(mom));

        authority = new SimpleAuthority(address(caller));
        mom.setAuthority(address(authority));
    }

    function getVatIlkLine(bytes32 ilk) internal view returns (uint256 line) {
        (,,, line,) = vat.ilks(ilk);
    }

    function testVerifySetup() public {
        assertTrue(mom.owner() == address(this));
        assertTrue(mom.authority() == address(authority));
    }

    function testSetOwner() public {
        mom.setOwner(address(0));
        assertTrue(mom.owner() == address(0));
    }

    function testSetOwnerNotOwner() public {
        // fails because the caller is not the owner
        vm.prank(caller);
        vm.expectRevert("LineMom/only-owner");
        mom.setOwner(address(0));
    }

    function testSetAuthority() public {
        mom.setAuthority(address(0));
        assertTrue(mom.authority() == address(0));
    }

    function testSetAuthorityNotOwner() public {
        // fails because the caller is not the owner
        vm.prank(caller);
        vm.expectRevert("LineMom/only-owner");
        mom.setAuthority(address(0));
    }

    function testAddDelIlk() public {
        vm.expectEmit(true, true, true, true);
        emit AddIlk("ETH-B");
        mom.addIlk("ETH-B");
        assertTrue(mom.ilks("ETH-B") == 1);
        vm.expectEmit(true, true, true, true);
        emit DelIlk("ETH-B");
        mom.delIlk("ETH-B");
        assertTrue(mom.ilks("ETH-B") == 0);
    }

    function testFileAutoLine() public {
        mom.file("autoLine", address(1));
        assertTrue(mom.autoLine() == address(1));
    }

    function testFileAutoLineNotOwner() public {
        // fails because the caller is not an owner
        vm.prank(caller);
        vm.expectRevert("LineMom/only-owner");
        mom.file("autoLine", address(1));
    }

    function testAddDelIlkNotOwner() public {
        // fails because the caller is not an owner
        vm.startPrank(caller);
        vm.expectRevert("LineMom/only-owner");
        mom.addIlk("ETH-A");
        vm.expectRevert("LineMom/only-owner");
        mom.delIlk("ETH-A");
    }

    function testWipeAuthorized() public {
        vm.prank(caller);
        vm.expectEmit(true, true, true, true);
        emit Wipe("ETH-A", 100);
        assertEq(mom.wipe("ETH-A"), 100);
        assertEq(getVatIlkLine("ETH-A"), 0);
        (uint256 l, uint256 g, uint256 t,,) = autoLine.ilks("ETH-A");
        assertEq(l, 0);
        assertEq(g, 0);
        assertEq(t, 0);
    }

    function testWipeAuthorizedMany() public {
        vm.prank(caller);
        vm.expectEmit(true, true, true, true);
        emit Wipe("ETH-A", 100);
        assertEq(mom.wipe("ETH-A"), 100);
        assertEq(getVatIlkLine("ETH-A"), 0);
        (uint256 l, uint256 g, uint256 t,,) = autoLine.ilks("ETH-A");
        assertEq(l, 0);
        assertEq(g, 0);
        assertEq(t, 0);
        vm.expectEmit(true, true, true, true);
        emit Wipe("ETH-A", 0);
        assertEq(mom.wipe("ETH-A"), 0);
        assertEq(getVatIlkLine("ETH-A"), 0);
        (l, g, t,,) = autoLine.ilks("ETH-A");
        assertEq(l, 0);
        assertEq(g, 0);
        assertEq(t, 0);
    }

    function testWipeOwner() public {
        vm.expectEmit(true, true, true, true);
        emit Wipe("ETH-A", 100);
        assertEq(mom.wipe("ETH-A"), 100);
        assertEq(getVatIlkLine("ETH-A"), 0);
        (uint256 l, uint256 g, uint256 t,,) = autoLine.ilks("ETH-A");
        assertEq(l, 0);
        assertEq(g, 0);
        assertEq(t, 0);
    }

    function testWipeCallerNotAuthorized() public {
        SimpleAuthority newAuthority = new SimpleAuthority(address(this));
        mom.setAuthority(address(newAuthority));
        // fails because the caller is no longer authorized on the mom
        vm.prank(caller);
        vm.expectRevert("LineMom/not-authorized");
        mom.wipe("ETH-A");
    }

    function testWipeNoAuthority() public {
        mom.setAuthority(address(0));
        vm.prank(caller);
        vm.expectRevert("LineMom/not-authorized");
        mom.wipe("ETH-A");
    }

    function testWipeIlkNotAdded() public {
        mom.delIlk("ETH-A");
        vm.expectRevert("LineMom/ilk-not-added");
        mom.wipe("ETH-A");
    }
}
