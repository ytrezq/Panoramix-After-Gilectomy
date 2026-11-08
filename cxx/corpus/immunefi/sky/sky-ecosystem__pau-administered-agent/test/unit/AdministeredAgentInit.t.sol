// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { AdministeredAgent }   from "../../src/AdministeredAgent.sol";
import { IAdministeredAgent }  from "../../src/interfaces/IAdministeredAgent.sol";

import {
    AdministeredAgentInit,
    AdministeredAgentInitParams
} from "../../deploy/AdministeredAgentInit.sol";

/**
 * @notice Stand-in for the governance proxy (PauseProxy / SubProxy) executing a spell action. The
 *         init library is internal-functions-only, so it inlines here and every wrapped call
 *         executes with this contract as `msg.sender` — exactly as it would inside a delegatecalled
 *         spell action. Deployed as the agent's sole admin.
 */
contract GovernanceHarness {

    function init(address agent, AdministeredAgentInitParams memory p) external {
        AdministeredAgentInit.init(agent, p);
    }

}

contract AdministeredAgentInit_Unit_Tests is Test {

    GovernanceHarness internal governance;
    AdministeredAgent internal agent;

    address internal admin   = makeAddr("admin");
    address internal actor   = makeAddr("actor");
    address internal grantor = makeAddr("grantor");
    address internal revoker = makeAddr("revoker");

    function setUp() external {
        governance = new GovernanceHarness();
        agent      = new AdministeredAgent(address(governance));
    }

    /**********************************************************************************************/
    /*** Helpers                                                                                ***/
    /**********************************************************************************************/

    function _empty() internal pure returns (AdministeredAgentInitParams memory p) {
        p.admins   = new address[](0);
        p.actors   = new address[](0);
        p.grantors = new address[](0);
        p.revokers = new address[](0);
    }

    function _one(address a) internal pure returns (address[] memory arr) {
        arr    = new address[](1);
        arr[0] = a;
    }

    function _two(address a, address b) internal pure returns (address[] memory arr) {
        arr    = new address[](2);
        arr[0] = a;
        arr[1] = b;
    }

    /**********************************************************************************************/
    /*** Tests                                                                                  ***/
    /**********************************************************************************************/

    function test_init_configuresAllRoles() external {
        AdministeredAgentInitParams memory p = _empty();
        p.admins   = _one(admin);
        p.actors   = _one(actor);
        p.grantors = _one(grantor);
        p.revokers = _one(revoker);

        governance.init(address(agent), p);

        assertEq(agent.getIsAdmin(admin),     true);
        assertEq(agent.getIsActor(actor),     true);
        assertEq(agent.getIsGrantor(grantor), true);
        assertEq(agent.getIsRevoker(revoker), true);

        // The governance proxy (constructor admin) remains admin.
        assertEq(agent.getIsAdmin(address(governance)), true);
    }

    function test_init_emptyParams_leavesOnlyConstructorAdmin() external {
        governance.init(address(agent), _empty());

        assertEq(agent.getIsAdmin(address(governance)), true);
        assertEq(agent.getIsActor(actor),               false);
        assertEq(agent.getIsGrantor(grantor),           false);
        assertEq(agent.getIsRevoker(revoker),           false);
    }

    function test_init_zeroAgent_reverts() external {
        vm.expectRevert(bytes("AdministeredAgentInit/agent-zero-address"));
        governance.init(address(0), _empty());
    }

    function test_init_notAdmin_reverts() external {
        // Deployed with a different admin: the harness holds no admin on this agent.
        AdministeredAgent otherAgent = new AdministeredAgent(makeAddr("otherAdmin"));

        vm.expectRevert(bytes("AdministeredAgentInit/not-admin"));
        governance.init(address(otherAgent), _empty());
    }

    function test_init_notSoleAdmin_reverts() external {
        // Governance is admin, but a second admin exists: it is not the sole admin.
        vm.prank(address(governance));
        agent.addAdmin(makeAddr("secondAdmin"));

        vm.expectRevert(bytes("AdministeredAgentInit/not-sole-admin"));
        governance.init(address(agent), _empty());
    }

    function test_init_secondInitWithNewAdmin_reverts() external {
        // A successful init that adds an admin leaves the agent with two admins, so re-running init
        // trips the sole-admin guard. init is documented as NOT idempotent.
        AdministeredAgentInitParams memory p = _empty();
        p.admins   = _one(admin);
        p.actors   = _one(actor);
        p.grantors = _one(grantor);
        p.revokers = _one(revoker);

        governance.init(address(agent), p);

        vm.expectRevert(bytes("AdministeredAgentInit/not-sole-admin"));
        governance.init(address(agent), p);
    }

    function test_init_secondInitSameRoles_reverts() external {
        // With no new admin the sole-admin guard still passes on the second run, but the role sets
        // configured by the first run are no longer empty, so re-running init still reverts.
        AdministeredAgentInitParams memory p = _empty();
        p.actors = _one(actor);

        governance.init(address(agent), p);

        vm.expectRevert(bytes("AdministeredAgentInit/actors-not-empty"));
        governance.init(address(agent), p);
    }

    function test_init_actorsNotEmpty_reverts() external {
        // An actor configured before init means init would extend the set rather than establish it.
        vm.prank(address(governance));
        agent.addActor(makeAddr("preExistingActor"));

        vm.expectRevert(bytes("AdministeredAgentInit/actors-not-empty"));
        governance.init(address(agent), _empty());
    }

    function test_init_grantorsNotEmpty_reverts() external {
        vm.prank(address(governance));
        agent.addGrantor(makeAddr("preExistingGrantor"));

        vm.expectRevert(bytes("AdministeredAgentInit/grantors-not-empty"));
        governance.init(address(agent), _empty());
    }

    function test_init_revokersNotEmpty_reverts() external {
        vm.prank(address(governance));
        agent.addRevoker(makeAddr("preExistingRevoker"));

        vm.expectRevert(bytes("AdministeredAgentInit/revokers-not-empty"));
        governance.init(address(agent), _empty());
    }

    function test_init_duplicateAdminInParams_reverts() external {
        // Duplicates within a single params list are rejected by the agent's add* functions.
        AdministeredAgentInitParams memory p = _empty();
        p.admins = _two(admin, admin);

        vm.expectRevert(IAdministeredAgent.AccountAlreadyAdmin.selector);
        governance.init(address(agent), p);
    }

    function test_init_duplicateActorInParams_reverts() external {
        AdministeredAgentInitParams memory p = _empty();
        p.actors = _two(actor, actor);

        vm.expectRevert(IAdministeredAgent.AccountAlreadyActor.selector);
        governance.init(address(agent), p);
    }

    function test_init_duplicateGrantorInParams_reverts() external {
        AdministeredAgentInitParams memory p = _empty();
        p.grantors = _two(grantor, grantor);

        vm.expectRevert(IAdministeredAgent.AccountAlreadyGrantor.selector);
        governance.init(address(agent), p);
    }

    function test_init_duplicateRevokerInParams_reverts() external {
        AdministeredAgentInitParams memory p = _empty();
        p.revokers = _two(revoker, revoker);

        vm.expectRevert(IAdministeredAgent.AccountAlreadyRevoker.selector);
        governance.init(address(agent), p);
    }

    function test_init_zeroAdmin_reverts() external {
        AdministeredAgentInitParams memory p = _empty();
        p.admins = _one(address(0));

        vm.expectRevert(IAdministeredAgent.ZeroAccount.selector);
        governance.init(address(agent), p);
    }

    function test_init_zeroActor_reverts() external {
        AdministeredAgentInitParams memory p = _empty();
        p.actors = _one(address(0));

        vm.expectRevert(IAdministeredAgent.ZeroAccount.selector);
        governance.init(address(agent), p);
    }

    function test_init_zeroGrantor_reverts() external {
        AdministeredAgentInitParams memory p = _empty();
        p.grantors = _one(address(0));

        vm.expectRevert(IAdministeredAgent.ZeroAccount.selector);
        governance.init(address(agent), p);
    }

    function test_init_zeroRevoker_reverts() external {
        AdministeredAgentInitParams memory p = _empty();
        p.revokers = _one(address(0));

        vm.expectRevert(IAdministeredAgent.ZeroAccount.selector);
        governance.init(address(agent), p);
    }

}
