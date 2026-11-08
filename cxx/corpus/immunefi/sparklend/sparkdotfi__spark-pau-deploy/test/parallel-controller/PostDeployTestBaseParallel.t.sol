// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { stdJson } from "../../lib/forge-std/src/StdJson.sol";
import { VmSafe }  from "../../lib/forge-std/src/Vm.sol";

import { IERC4626Facet } from "../../lib/diamond-pau/src/facets/erc4626/IERC4626Facet.sol";

import { PostDeployTestBase, IBeacon } from "../PostDeployTestBase.t.sol";

abstract contract PostDeployTestBaseParallel is PostDeployTestBase {

    using stdJson for string;

    IBeacon internal skyMainnetBeacon;

    address internal legacyController;

    function _setUpAddresses(string memory json) internal override {
        super._setUpAddresses(json);

        skyMainnetBeacon = IBeacon(json.readAddress(".skyMainnetBeacon"));
        legacyController = json.readAddress(".legacyController");
    }

    /**********************************************************************************************/
    /*** State Assertions                                                                       ***/
    /**********************************************************************************************/

    function _assertPauFactoryState() internal view {
        assertEq(pauFactory.beacon(), address(beacon));
    }

    function _assertBeaconState() internal view {
        assertEq(beacon.hasRole(DEFAULT_ADMIN_ROLE, admin),     true);
        assertEq(beacon.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1);

        assertEq(beacon.hasRole(DEFAULT_ADMIN_ROLE, deployer), false);
    }

    function _assertFacetConstructors() internal view virtual;

    function _assertAdministeredAgentState() internal view {
        assertEq(administeredAgent.adminCount(),   1);
        assertEq(administeredAgent.actorCount(),   1);
        assertEq(administeredAgent.grantorCount(), 1);
        assertEq(administeredAgent.revokerCount(), 1);

        assertEq(administeredAgent.getAdmin(0),   admin);
        assertEq(administeredAgent.getActor(0),   relayer);
        assertEq(administeredAgent.getGrantor(0), grantor);
        assertEq(administeredAgent.getRevoker(0), freezer);

        assertEq(administeredAgent.getIsAdmin(deployer),              false);
        assertEq(administeredAgent.getIsAdmin(address(agentFactory)), false);
    }

    function _assertAccessControlsState() internal view {
        assertEq(accessControls.hasRole(DEFAULT_ADMIN_ROLE, admin),     true);
        assertEq(accessControls.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1);

        assertEq(accessControls.hasRole(ALLOCATOR_ROLE, address(administeredAgent)), true);
        assertEq(accessControls.getRoleMemberCount(ALLOCATOR_ROLE),                  1);

        // Neither the deployer nor the deploy infrastructure retains any role.

        assertEq(accessControls.hasRole(ALLOCATOR_ROLE,     deployer), false);
        assertEq(accessControls.hasRole(DEFAULT_ADMIN_ROLE, deployer), false);

        assertEq(accessControls.hasRole(ALLOCATOR_ROLE,     address(pauFactory)), false);
        assertEq(accessControls.hasRole(DEFAULT_ADMIN_ROLE, address(pauFactory)), false);
    }

    function _assertALMProxyState_unchanged() internal view {
        assertEq(almProxy.hasRole(DEFAULT_ADMIN_ROLE, admin),            true);
        assertEq(almProxy.hasRole(CONTROLLER_ROLE,    legacyController), true);

        assertEq(almProxy.hasRole(CONTROLLER_ROLE,    address(controller)), false);
        assertEq(almProxy.hasRole(CONTROLLER_ROLE,    deployer),            false);
        assertEq(almProxy.hasRole(DEFAULT_ADMIN_ROLE, deployer),            false);
    }

    function _assertRateLimitsInitializationState() internal view {
        assertEq(rateLimits.hasRole(DEFAULT_ADMIN_ROLE, admin),               true);
        assertEq(rateLimits.hasRole(CONTROLLER_ROLE,    address(controller)), true);

        assertEq(rateLimits.hasRole(CONTROLLER_ROLE,    deployer), false);
        assertEq(rateLimits.hasRole(DEFAULT_ADMIN_ROLE, deployer), false);

        assertEq(rateLimits.hasRole(CONTROLLER_ROLE,    address(pauFactory)), false);
        assertEq(rateLimits.hasRole(DEFAULT_ADMIN_ROLE, address(pauFactory)), false);
    }

}
