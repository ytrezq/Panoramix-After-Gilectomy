// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

interface IAccessControlLike {

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

}

interface IAdministeredAgentLike {

    function addActor(address actor) external;

    function addAdmin(address admin) external;

    function addGrantor(address grantor) external;

    function addRevoker(address revoker) external;

    function removeAdmin(address admin) external;

}

interface IControllerLike {

    function accessControls() external view returns (address);

    function proxy() external view returns (address);

    function rateLimits() external view returns (address);

    function updateIntegrations(bytes32[] calldata ids) external;

}

interface IRateLimitsLike {

    function CONTROLLER() external view returns (bytes32);

}

library InitParallelPAU {

    /**********************************************************************************************/
    /*** Custom Errors                                                                          ***/
    /**********************************************************************************************/

    /// @notice Thrown when an admin array for an AdministeredAgent is empty.
    error NoAgentAdmins();

    /// @notice Thrown when an admin array for a component's default admins is empty.
    error NoDefaultAdmins();

    /// @notice Thrown when an AdministeredAgent address is the zero address.
    error ZeroAgent();

    /// @notice Thrown when a supplied default admin address is the zero address.
    error ZeroDefaultAdmin();

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when the PAU stack is initialized.
     * @param  controller     Address of the Controller contract.
     * @param  accessControls Address of the AccessControls contract.
     * @param  rateLimits     Address of the RateLimits contract.
     * @param  integrationIds IDs of the integrations to update.
     * @param  adminConfig    Configuration for the admins of the deployed PAU stack components.
     * @param  agentConfigs   Configuration for the AdministeredAgents of the deployed PAU stack.
     */
    event InitParallelPAU(
        address                   indexed controller,
        address                           accessControls,
        address                           rateLimits,
        bytes32[]                         integrationIds,
        AdminConfig                       adminConfig,
        AdministeredAgentConfig[]         agentConfigs
    );

    /**********************************************************************************************/
    /*** Structs                                                                                ***/
    /**********************************************************************************************/

    /**
     * @notice Admins to be granted admin rights on each component of the deployed stack.
     * @param  accessControlAdmins Admins for the AccessControls contract.
     * @param  rateLimitsAdmins    Admins for the RateLimits contract.
     */
    struct AdminConfig {
        address[] accessControlAdmins;
        address[] rateLimitsAdmins;
    }

    /**
     * @notice Configuration applied to an AdministeredAgent after deployment.
     * @param  agent    Address of the AdministeredAgent to configure.
     * @param  admins   Addresses to configure as admins on the agent.
     * @param  actors   Addresses to configure as actors on the agent.
     * @param  grantors Addresses to configure as grantors on the agent.
     * @param  revokers Addresses to configure as revokers on the agent.
     */
    struct AdministeredAgentConfig {
        address   agent;
        address[] admins;
        address[] actors;
        address[] grantors;
        address[] revokers;
    }

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 internal constant _ALLOCATOR_ROLE     = keccak256("ALLOCATOR_ROLE");
    bytes32 internal constant _DEFAULT_ADMIN_ROLE = 0x00;

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    /**
     * @notice Initializes the parallel PAU stack components.
     * @param  controller     Address of the Controller contract.
     * @param  integrationIds IDs of the integrations to update.
     * @param  adminConfig    Configuration for the admins of the deployed PAU stack components.
     * @param  agentConfigs   Configuration for the AdministeredAgents of the deployed PAU stack.
     */
    function initParallelPAU(
        address                          controller,
        bytes32[]                 memory integrationIds,
        AdminConfig               memory adminConfig,
        AdministeredAgentConfig[] memory agentConfigs
    ) internal {
        address accessControls = IControllerLike(controller).accessControls();
        address rateLimits     = IControllerLike(controller).rateLimits();

        // Step 1: Config AdministeredAgents

        for (uint256 i = 0; i < agentConfigs.length; ++i) {
            _configureAgent(agentConfigs[i]);
        }

        // Step 2: Configure all Roles

        _grantRoles(accessControls, controller, rateLimits, adminConfig, agentConfigs);

        // Step 3: Update integrations

        if (integrationIds.length > 0) {
            IControllerLike(controller).updateIntegrations(integrationIds);
        }

        // Step4: Remove deployer as admin of AccessControls, AdministeredAgent and RateLimits.

        emit InitParallelPAU(
            controller,
            accessControls,
            rateLimits,
            integrationIds,
            adminConfig,
            agentConfigs
        );
    }

    /**********************************************************************************************/
    /*** Internal Helper Functions                                                              ***/
    /**********************************************************************************************/

    function _configureAgent(AdministeredAgentConfig memory config) internal {
        require(config.agent        != address(0), ZeroAgent());
        require(config.admins.length > 0,          NoAgentAdmins());

        IAdministeredAgentLike agent = IAdministeredAgentLike(config.agent);

        for (uint256 i = 0; i < config.admins.length; ++i) {
            agent.addAdmin(config.admins[i]);
        }

        for (uint256 i = 0; i < config.actors.length; ++i) {
            agent.addActor(config.actors[i]);
        }

        for (uint256 i = 0; i < config.grantors.length; ++i) {
            agent.addGrantor(config.grantors[i]);
        }

        for (uint256 i = 0; i < config.revokers.length; ++i) {
            agent.addRevoker(config.revokers[i]);
        }
    }

    function _grantDefaultAdmins(address target, address[] memory admins) internal {
        require(admins.length > 0, NoDefaultAdmins());

        for (uint256 i = 0; i < admins.length; ++i) {
            require(admins[i] != address(0), ZeroDefaultAdmin());
            IAccessControlLike(target).grantRole(_DEFAULT_ADMIN_ROLE, admins[i]);
        }
    }

    function _grantRoles(
        address                          accessControls,
        address                          controller,
        address                          rateLimits,
        AdminConfig               memory adminConfig,
        AdministeredAgentConfig[] memory agentConfigs
    ) internal {
        // AccessControls Roles

        _grantDefaultAdmins(accessControls, adminConfig.accessControlAdmins);

        for (uint256 i = 0; i < agentConfigs.length; ++i) {
            IAccessControlLike(accessControls).grantRole(_ALLOCATOR_ROLE, agentConfigs[i].agent);
        }

        // RateLimits Roles

        _grantDefaultAdmins(rateLimits, adminConfig.rateLimitsAdmins);

        IAccessControlLike(rateLimits).grantRole(IRateLimitsLike(rateLimits).CONTROLLER(), controller);
    }

}
