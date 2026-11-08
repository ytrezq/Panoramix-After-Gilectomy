// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

/**
 * @title  IDefaultPAUAssembler
 * @notice External interface for the {DefaultPAUAssembler}, a one-shot helper that deploys and
 *         configures a full PAU stack (ALMProxy, RateLimits, Controller) with allocators as
 *         AdministeredAgent contracts, in a single transaction. It wires up roles, syncs
 *         integrations on the Controller, configures each AdministeredAgent with the uniquely
 *         supplied admins/actors/grantors/revokers.
 * @dev    All deployed contracts are returned as plain addresses; callers cast them to the
 *         relevant component interfaces as needed.
 */
interface IDefaultPAUAssembler {

    /**********************************************************************************************/
    /*** Custom Errors                                                                          ***/
    /**********************************************************************************************/

    /// @notice Thrown when an admin array for an AdministeredAgent is empty.
    error NoAgentAdmins();

    /// @notice Thrown when an admin array for a component's default admins is empty.
    error NoDefaultAdmins();

    /// @notice Thrown when the supplied PAU factory is the zero address.
    error ZeroPAUFactory();

    /// @notice Thrown when the supplied AdministeredAgent factory is the zero address.
    error ZeroAdministeredAgentFactory();

    /// @notice Thrown when a supplied default admin address is the zero address.
    error ZeroDefaultAdmin();

    /**********************************************************************************************/
    /*** Structs                                                                                ***/
    /**********************************************************************************************/

    /**
     * @notice Admins to be granted admin rights on each component of the deployed stack.
     * @param  accessControlAdmins Admins for the AccessControls contract.
     * @param  proxyAdmins         Admins for the ALMProxy contract.
     * @param  rateLimitsAdmins    Admins for the RateLimits contract.
     */
    struct AdminConfig {
        address[] accessControlAdmins;
        address[] proxyAdmins;
        address[] rateLimitsAdmins;
    }

    /**
     * @notice Configuration applied to an AdministeredAgent after deployment.
     * @param  admins   Addresses to configure as admins on the agent.
     * @param  actors   Addresses to configure as actors on the agent.
     * @param  grantors Addresses to configure as grantors on the agent.
     * @param  revokers Addresses to configure as revokers on the agent.
     */
    struct AdministeredAgentConfig {
        address[] admins;
        address[] actors;
        address[] grantors;
        address[] revokers;
    }

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted once a PAU stack and AdministeredAgents have been deployed and configured.
     * @param  proxy                 The deployed ALMProxy contract.
     * @param  controller            The deployed Controller contract.
     * @param  accessControls        The deployed AccessControls contract.
     * @param  rateLimits            The deployed RateLimits contract.
     * @param  allocatorAgents       The deployed allocators as AdministeredAgent contracts.
     * @param  integrationIds        The integration IDs synced on the Controller.
     * @param  adminConfig           The admin configuration applied across the stack.
     * @param  allocatorAgentConfigs The configurations applied to each AdministeredAgent allocator.
     */
    event Deployment(
        address                   indexed proxy,
        address                   indexed controller,
        address                           accessControls,
        address                           rateLimits,
        address[]                         allocatorAgents,
        bytes32[]                         integrationIds,
        AdminConfig                       adminConfig,
        AdministeredAgentConfig[]         allocatorAgentConfigs
    );

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @notice Semantic version of this assembler implementation.
     * @return The version string.
     */
    function VERSION() external view returns (string memory);

    /**
     * @notice The underlying PAU factory used to deploy each individual component.
     * @return The address of the PAU factory.
     */
    function pauFactory() external view returns (address);

    /**
     * @notice The factory used to deploy the AdministeredAgent.
     * @return The address of the AdministeredAgent factory.
     */
    function administeredAgentFactory() external view returns (address);

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Deploys and configures a full PAU stack (ALMProxy, Controller, AccessControls,
     *         RateLimits) with allocators as AdministeredAgent contracts, in a single transaction.
     *         Wires up roles, syncs integrations on the Controller, configures each
     *         AdministeredAgent with the respective supplied admins/actors/grantors/revokers.
     * @dev    Emits {Deployment} on completion. After this call, this assembler holds no privileged
     *         roles on any of the returned contracts. The Controller is granted CONTROLLER on the
     *         ALMProxy and on the RateLimits.
     *
     *         Notes:
     *         - When `integrationIds` is empty, the Controller `updateIntegrations` call is
     *           skipped entirely (the Controller reverts on an empty array), so a stack can be
     *           deployed with no integrations and configured later by an admin.
     * @param  integrationIds        Integration IDs to sync on the Controller via
     *                               `updateIntegrations` (may be empty).
     * @param  adminConfig           Admins to grant across the deployed stack.
     * @param  allocatorAgentConfigs Admin/actor/grantor/revoker configuration for the allocator
     *                               AdministeredAgent contracts.
     * @return proxy                 The deployed ALMProxy contract.
     * @return controller            The deployed Controller contract.
     * @return accessControls        The deployed AccessControls contract.
     * @return rateLimits            The deployed RateLimits contract.
     * @return allocatorAgents       The deployed allocator AdministeredAgent contracts.
     */
    function deploy(
        bytes32[]                 memory integrationIds,
        AdminConfig               memory adminConfig,
        AdministeredAgentConfig[] memory allocatorAgentConfigs
    )
        external
        returns (
            address          proxy,
            address          controller,
            address          accessControls,
            address          rateLimits,
            address[] memory allocatorAgents
        );

}
