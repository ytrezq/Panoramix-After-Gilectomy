// SPDX-FileCopyrightText: © 2026 Sky Ecosystem
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
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SubProxyMethods} from "../src/SubProxyMethods.sol";

interface ChainlogLike {
    function getAddress(bytes32 _key) external view returns (address addr);
}

interface SubProxyLike {
    function exec(address target, bytes memory args) external payable returns (bytes memory out);
    function wards(address) external view returns (uint256);
}

contract SubProxyMethodsTest is Test {
    /// @dev ChainLog on Ethereum mainnet.
    ChainlogLike internal constant chainlog = ChainlogLike(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);

    /// @dev USDS token
    IERC20 internal usds;

    /// @dev The deployed `Grove SubProxy` contract bytecode matches the `GROVE_SUBPROXY` deployed from the `endgame-toolkit` repo at `a98f53d` (audited commit).
    SubProxyLike internal subProxy;

    /// @dev The authed address for the `Grove SubProxy`.
    address internal pauseProxy;

    /// @dev Pinned mainnet block for deterministic forking.
    uint256 internal constant FORK_BLOCK = 25383500;

    address internal constant DESTINATION = address(0xDE57);

    uint256 internal constant WAD = 10 ** 18;

    SubProxyMethods internal methods;

    function setUp() public {
        vm.createSelectFork("mainnet", FORK_BLOCK);

        usds = IERC20(chainlog.getAddress("USDS"));
        subProxy = SubProxyLike(chainlog.getAddress("GROVE_SUBPROXY"));
        pauseProxy = chainlog.getAddress("MCD_PAUSE_PROXY");

        methods = new SubProxyMethods();
    }

    /// @dev Encodes a `SubProxyMethods.transfer(token, to, amount)` call as `exec` would receive it.
    function _transferCalldata(address token_, address to_, uint256 amount_) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(SubProxyMethods.transfer.selector, token_, to_, amount_);
    }

    function testTransferMovesFundsFromSubProxy() public {
        uint256 amount = 1_000 * WAD;
        deal(address(usds), address(subProxy), amount);
        assertEq(usds.balanceOf(address(methods)), 0, "methods contract must hold no funds");

        vm.prank(pauseProxy);
        subProxy.exec(address(methods), _transferCalldata(address(usds), DESTINATION, amount));

        assertEq(usds.balanceOf(address(subProxy)), 0, "SubProxy balance not debited");
        assertEq(usds.balanceOf(DESTINATION), amount, "destination not credited");
    }

    function testTransferPartialBalance() public {
        deal(address(usds), address(subProxy), 1_000 * WAD);

        vm.prank(pauseProxy);
        subProxy.exec(address(methods), _transferCalldata(address(usds), DESTINATION, 400 * WAD));

        assertEq(usds.balanceOf(address(subProxy)), 600 * WAD, "remainder wrong");
        assertEq(usds.balanceOf(DESTINATION), 400 * WAD, "destination wrong");
    }

    function testRevertWhenSubProxyBalanceInsufficient() public {
        deal(address(usds), address(subProxy), 1 * WAD);

        vm.prank(pauseProxy);
        vm.expectRevert("SubProxy/delegatecall-error");
        subProxy.exec(address(methods), _transferCalldata(address(usds), DESTINATION, 2 * WAD));
    }

    function testRevertWhenCallerNotAuthorized() public {
        deal(address(usds), address(subProxy), 1 * WAD);

        vm.prank(address(0xBAD));
        vm.expectRevert("SubProxy/not-authorized");
        subProxy.exec(address(methods), _transferCalldata(address(usds), DESTINATION, 1 * WAD));
    }

    function testExecDoesNotCorruptSubProxyStorage() public {
        deal(address(usds), address(subProxy), 1 * WAD);
        assertEq(subProxy.wards(pauseProxy), 1, "pauseProxy is ward");

        vm.prank(pauseProxy);
        subProxy.exec(address(methods), _transferCalldata(address(usds), DESTINATION, 1 * WAD));

        assertEq(subProxy.wards(pauseProxy), 1, "ward bit clobbered");
        assertEq(subProxy.wards(address(methods)), 0, "unexpected ward granted");
    }

    function testFuzzTransfer(address to, uint96 amount) public {
        vm.assume(to != address(0) && to != address(subProxy) && to != address(methods) && to != address(usds));
        vm.assume(usds.balanceOf(to) == 0);

        deal(address(usds), address(subProxy), amount);
        vm.prank(pauseProxy);
        subProxy.exec(address(methods), _transferCalldata(address(usds), to, amount));

        assertEq(usds.balanceOf(to), amount, "fuzz: destination not credited");
        assertEq(usds.balanceOf(address(subProxy)), 0, "fuzz: SubProxy not fully debited");
    }
}
