// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { EmergencyModule } from "../../contracts/EmergencyModule.sol";

import { MockGlobals, MockToken } from "../utils/Mocks.sol";
import { TestBase }               from "../utils/TestBase.sol";

contract EmergencyModuleTets is TestBase {

    address governor = makeAddr("governor");
    address treasury = makeAddr("treasury");

    EmergencyModule module;
    MockGlobals     globals;
    MockToken       token;

    function setUp() external {
        globals = new MockGlobals();

        globals.__setGovernor(governor);
        globals.__setMapleTreasury(treasury);

        token = new MockToken();

        module = new EmergencyModule(address(globals), address(token));
    }

    function test_constructor() external {
        assertEq(module.globals(), address(globals));
        assertEq(module.token(),   address(token));
    }

    function test_mint_notGovernor() external {
        vm.expectRevert("EM:NOT_GOVERNOR");
        module.mint(1);
    }

    function test_mint_success() external {
        token.__expectCall();
        token.mint(treasury, 1);

        vm.prank(governor);
        module.mint(1);
    }

    function test_burn_notGovernor() external {
        vm.expectRevert("EM:NOT_GOVERNOR");
        module.burn(address(0x1), 1);
    }

    function test_burn_success() external {
        token.__expectCall();
        token.burn(address(0x1), 1);

        vm.prank(governor);
        module.burn(address(0x1), 1);
    }

}
