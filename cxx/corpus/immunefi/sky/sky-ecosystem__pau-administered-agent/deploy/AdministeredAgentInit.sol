// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

interface IAdministeredAgentLike {

    function addActor(address account) external;

    function addAdmin(address account) external;

    function addGrantor(address account) external;

    function addRevoker(address account) external;

    function actorCount() external view returns (uint256);

    function adminCount() external view returns (uint256);

    function getIsAdmin(address account) external view returns (bool);

    function grantorCount() external view returns (uint256);

    function revokerCount() external view returns (uint256);

}

/**
 * @param admins   Additional admins — the governance contract already holds admin from
 *                 deployment (may be empty).
 * @param actors   Addresses to configure as actors on the agent (may be empty).
 * @param grantors Addresses to configure as grantors on the agent (may be empty).
 * @param revokers Addresses to configure as revokers on the agent (may be empty).
 */
struct AdministeredAgentInitParams {
    address[] admins;
    address[] actors;
    address[] grantors;
    address[] revokers;
}

/**
 * @title  AdministeredAgentInit
 * @notice Initialization library for a deployed (inert) AdministeredAgent. Intended to be
 *         called by a spell executing as the governance contract (PauseProxy or SubProxy) that
 *         is the agent's sole admin.
 *
 * @dev    Internal-functions-only so the compiler inlines the library into the spell action and
 *         every call executes as the governance proxy. Covers the bulk initialization only;
 *         subsequent single-role operations (addActor, removeActor, …) should be inlined
 *         directly in the relevant spell.
 */
library AdministeredAgentInit {

    /**
     * @notice Configures an AdministeredAgent's roles in bulk.
     * @dev    This function is NOT idempotent. It requires the agent to be inert (the executing
     *         context as sole admin, and no actors, grantors or revokers) so that init establishes
     *         the role sets rather than extending them. Re-running init after any role has been
     *         configured therefore reverts.
     * @param  agent The agent to configure.
     * @param  p     Role configuration.
     */
    function init(address agent, AdministeredAgentInitParams memory p) internal {
        require(agent != address(0), "AdministeredAgentInit/agent-zero-address");

        IAdministeredAgentLike agent_ = IAdministeredAgentLike(agent);

        // Sanity check: the executing context must be the agent's sole admin.
        require(agent_.getIsAdmin(address(this)), "AdministeredAgentInit/not-admin");
        require(agent_.adminCount() == 1,         "AdministeredAgentInit/not-sole-admin");

        // Sanity check: the agent must be inert, so init establishes the role sets rather than
        // extending sets configured outside of this spell.
        require(agent_.actorCount()   == 0, "AdministeredAgentInit/actors-not-empty");
        require(agent_.grantorCount() == 0, "AdministeredAgentInit/grantors-not-empty");
        require(agent_.revokerCount() == 0, "AdministeredAgentInit/revokers-not-empty");

        for (uint256 i = 0; i < p.admins.length; ++i) {
            agent_.addAdmin(p.admins[i]);
        }

        for (uint256 i = 0; i < p.actors.length; ++i) {
            agent_.addActor(p.actors[i]);
        }

        for (uint256 i = 0; i < p.grantors.length; ++i) {
            agent_.addGrantor(p.grantors[i]);
        }

        for (uint256 i = 0; i < p.revokers.length; ++i) {
            agent_.addRevoker(p.revokers[i]);
        }
    }

}
