// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IAdministeredAgentFactory } from "./interfaces/IAdministeredAgentFactory.sol";

import { AdministeredAgent } from "./AdministeredAgent.sol";

contract AdministeredAgentFactory is IAdministeredAgentFactory {

    function deploy(address admin) external returns (address administeredAgent) {
        administeredAgent = address(new AdministeredAgent(admin));
        emit AdministeredAgentDeployed(administeredAgent);
    }

}
