// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IAdministeredAgent }        from "../../src/interfaces/IAdministeredAgent.sol";
import { IAdministeredAgentFactory } from "../../src/interfaces/IAdministeredAgentFactory.sol";

import { AdministeredAgent }        from "../../src/AdministeredAgent.sol";
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
        address admin    = makeAddr("admin");
        address deployer = makeAddr("deployer");

        bytes32 salt        = keccak256("salt");
        bytes32 create2Salt = keccak256(abi.encode(deployer, salt));

        bytes32 creationCode = keccak256(abi.encodePacked(
            type(AdministeredAgent).creationCode,
            abi.encode(admin)
        ));

        address expectedAddress = vm.computeCreate2Address(create2Salt, creationCode, address(factory));

        assertEq(factory.isInstance(expectedAddress), false);

        vm.expectEmit(address(factory));
        emit IAdministeredAgentFactory.AdministeredAgentDeployed(expectedAddress);

        vm.prank(deployer);
        address deployedAddress = factory.deploy(admin, salt);

        assertEq(deployedAddress,                     expectedAddress);
        assertEq(factory.isInstance(expectedAddress), true);
    }

}
