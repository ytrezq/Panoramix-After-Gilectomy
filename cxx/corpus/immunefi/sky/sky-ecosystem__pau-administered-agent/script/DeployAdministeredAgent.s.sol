// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { console } from "../lib/forge-std/src/console.sol";

import { Script } from "../lib/forge-std/src/Script.sol";

import { IAdministeredAgent }        from "../src/interfaces/IAdministeredAgent.sol";
import { IAdministeredAgentFactory } from "../src/interfaces/IAdministeredAgentFactory.sol";

contract DeployAdministeredAgent is Script {

    function run(uint256 chainId, address factory, address admin, bytes32 salt) external {
        vm.createSelectFork(getChain(vm.envString("CHAIN")).rpcUrl);

        require(block.chainid == chainId, "DeployAdministeredAgent/chain-id-mismatch");

        vm.startBroadcast();

        address administeredAgent = IAdministeredAgentFactory(factory).deploy(admin, salt);

        vm.stopBroadcast();

        console.log("Administered Agent:", administeredAgent);
        console.log("Admin:             ", IAdministeredAgent(administeredAgent).getAdmin(0));
    }

}
