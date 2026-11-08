// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IAdministeredAgent }        from "../../src/interfaces/IAdministeredAgent.sol";
import { IAdministeredAgentFactory } from "../../src/interfaces/IAdministeredAgentFactory.sol";

import { AdministeredAgentFactory } from "../../src/AdministeredAgentFactory.sol";

contract AdministeredAgentFactory_UnitTests is Test {

    AdministeredAgentFactory internal factory;

    function setUp() external {
        factory = new AdministeredAgentFactory();
    }

    /**********************************************************************************************/
    /*** deploy Tests                                                                           ***/
    /**********************************************************************************************/

    function test_deploy() external {
        address admin = makeAddr("admin");
        uint256 nonce = vm.getNonce(address(factory));

        vm.expectEmit(address(factory));
        emit IAdministeredAgentFactory.AdministeredAgentDeployed(vm.computeCreateAddress(address(factory), nonce));

        assertEq(factory.deploy(admin), vm.computeCreateAddress(address(factory), nonce));
    }
}
