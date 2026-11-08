// SPDX-FileCopyrightText: © 2022 Dai Foundation <www.daifoundation.org>
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

pragma solidity ^0.8.14;

import "dss-test/DssTest.sol";

import {D3MMom} from "../D3MMom.sol";

contract PlanMock {
    bool public disabled;
    function disable() external {
        disabled = true;
    }
}

contract D3MMomTest is DssTest {

    PlanMock plan;
    
    D3MMom mom;

    function setUp() public {
        plan = new PlanMock();

        mom = new D3MMom();
    }

    function test_can_disable_plan_owner() public {
        assertEq(plan.disabled(), false);

        mom.disable(address(plan));

        assertEq(plan.disabled(), true);
    }

    function test_disable_no_auth() public {
        mom.setOwner(address(0));
        assertEq(mom.authority(), address(0));
        assertEq(mom.owner(), address(0));

        assertRevert(address(mom), abi.encodeWithSignature("disable(address)", plan), "D3MMom/not-authorized");
    }
    
}
