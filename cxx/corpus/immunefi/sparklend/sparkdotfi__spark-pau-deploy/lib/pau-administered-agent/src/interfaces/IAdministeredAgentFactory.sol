// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

/**
 * @title  IAdministeredAgentFactory
 * @notice Factory for deploying administered agents with expected bytecode.
 */
interface IAdministeredAgentFactory {

    /**
     * @notice Emitted when a new administered agent is deployed.
     * @param  administeredAgent The address of the deployed administered agent.
     */
    event AdministeredAgentDeployed(address indexed administeredAgent);

    /**
     * @notice Deploys a new administered agent.
     * @param  admin             The address of an admin that will control the administered agent.
     * @return administeredAgent The address of the deployed administered agent.
     */
    function deploy(address admin) external returns (address administeredAgent);

}
