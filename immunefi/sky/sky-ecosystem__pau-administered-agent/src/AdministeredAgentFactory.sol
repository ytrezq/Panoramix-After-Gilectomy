// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IAdministeredAgentFactory } from "./interfaces/IAdministeredAgentFactory.sol";

import { AdministeredAgent } from "./AdministeredAgent.sol";

contract AdministeredAgentFactory is IAdministeredAgentFactory {

    mapping(address => bool) public isInstance;

    function deploy(address admin, bytes32 salt) external returns (address administeredAgent) {
        administeredAgent = address(
            new AdministeredAgent{ salt: keccak256(abi.encode(msg.sender, salt)) }(admin)
        );

        emit AdministeredAgentDeployed(administeredAgent);

        isInstance[administeredAgent] = true;
    }

}
