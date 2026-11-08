// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Script, stdJson } from "../../lib/forge-std/src/Script.sol";

import { console2 } from "../../lib/forge-std/src/console2.sol";

import { ScriptTools } from "../../lib/dss-test/src/ScriptTools.sol";

import { InitParallelPAU } from "../../src/InitParallelPAU.sol";
import { BeaconConfig }    from "../../src/BeaconConfig.sol";

interface IAccessControlsLike {

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);

    function revokeRole(bytes32 role, address account) external;

}

interface IAdministeredAgentLike {

    function addAdmin(address admin) external;

    function removeAdmin(address admin) external;

}

interface IBeaconLike {

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

}

interface IControllerLike {

    function accessControls() external view returns (address);

    function rateLimits() external view returns (address);

}

interface IRateLimitsLike {

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);

    function revokeRole(bytes32 role, address account) external;

}

abstract contract ConfigureSparkPAUParallelBase is Script {

    using stdJson     for string;
    using ScriptTools for string;

    IBeaconLike internal beacon;

    IControllerLike        internal controller;
    IAccessControlsLike    internal accessControls;
    IRateLimitsLike        internal rateLimits;
    IAdministeredAgentLike internal administeredAgent;

    address internal admin;
    address internal deployer;
    address internal relayer;
    address internal grantor;
    address internal freezer;

    string internal config;

    function run() public virtual {
        string memory chain = vm.envOr("CHAIN", string("mainnet"));

        vm.createSelectFork(getChain(chain).rpcUrl);

        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(block.chainid));

        string memory env      = vm.envString("ENV");
        string memory fileSlug = string(abi.encodePacked("config-parallel-pau-", chain, "-", env));

        config = ScriptTools.loadConfig(fileSlug);

        require(block.chainid == config.readUint(".chainId"), "ConfigureSparkPAUParallelBase/invalid-chain-id");

        admin    = config.readAddress(".admin");
        deployer = config.readAddress(".deployer");
        relayer  = config.readAddress(".relayer");
        grantor  = config.readAddress(".grantor");
        freezer  = config.readAddress(".freezer");

        require(admin      != deployer, "ConfigureSparkPAUParallelBase/admin-is-deployer");
        require(msg.sender == deployer, "ConfigureSparkPAUParallelBase/sender-not-deployer");

        beacon = IBeaconLike(config.readAddress(".beacon"));

        controller        = IControllerLike(config.readAddress(".pauController"));
        rateLimits        = IRateLimitsLike(controller.rateLimits());
        accessControls    = IAccessControlsLike(controller.accessControls());
        administeredAgent = IAdministeredAgentLike(config.readAddress(".administeredAgent"));

        vm.startBroadcast();

        // Step 1: Wire facets on beacon

        _wireFacetsOnBeacon();

        // Step 2: Initialize the parallel PAU stack components

        InitParallelPAU.AdminConfig               memory adminConfig    = _getAdminConfig();
        InitParallelPAU.AdministeredAgentConfig[] memory agentConfigs   = _getAgentConfigs();
        bytes32[]                                 memory integrationIds = _getControllerIntegrationIds();

        InitParallelPAU.initParallelPAU(
            address(controller),
            integrationIds,
            adminConfig,
            agentConfigs
        );

        // Step 3: Remove deployer as admin of AccessControls, AdministeredAgent and RateLimits.

        _transferAdminRoles();

        console2.log("Deployer removed as admin of Beacon, AccessControls, AdministeredAgent and RateLimits");

        vm.stopBroadcast();
    }

    /**********************************************************************************************/
    /*** Helper Functions                                                                       ***/
    /**********************************************************************************************/

    function _wireFacetsOnBeacon() internal virtual;

    function _getControllerIntegrationIds() internal virtual returns (bytes32[] memory integrationIds);

    function _getAdminConfig() internal virtual returns (InitParallelPAU.AdminConfig memory adminConfig) {
        address[] memory accessControlAdmins = new address[](1);
        address[] memory rateLimitsAdmins    = new address[](1);

        accessControlAdmins[0] = admin;
        rateLimitsAdmins[0]    = admin;

        adminConfig = InitParallelPAU.AdminConfig({
            accessControlAdmins : accessControlAdmins,
            rateLimitsAdmins    : rateLimitsAdmins
        });
    }

    function _getAgentConfigs() internal virtual returns (InitParallelPAU.AdministeredAgentConfig[] memory agentConfigs) {
        address[] memory agentAdmins   = new address[](1);
        address[] memory agentActors   = new address[](1);
        address[] memory agentGrantors = new address[](1);
        address[] memory agentRevokers = new address[](1);

        agentAdmins[0]   = admin;
        agentActors[0]   = relayer;
        agentGrantors[0] = grantor;
        agentRevokers[0] = freezer;

        agentConfigs = new InitParallelPAU.AdministeredAgentConfig[](1);

        agentConfigs[0] = InitParallelPAU.AdministeredAgentConfig({
            agent    : address(administeredAgent),
            admins   : agentAdmins,
            actors   : agentActors,
            grantors : agentGrantors,
            revokers : agentRevokers
        });
    }

    function _transferAdminRoles() internal {
        // Grant admin roles to admin
        beacon.grantRole(beacon.DEFAULT_ADMIN_ROLE(), admin);

        // Revoke admin roles from deployer
        beacon.revokeRole(beacon.DEFAULT_ADMIN_ROLE(), deployer);

        accessControls.revokeRole(accessControls.DEFAULT_ADMIN_ROLE(), deployer);
        rateLimits.revokeRole(rateLimits.DEFAULT_ADMIN_ROLE(),         deployer);

        administeredAgent.removeAdmin(deployer);
    }

}

contract ConfigureSparkPAUParallelArbitrum is ConfigureSparkPAUParallelBase {

    using stdJson for string;

    function _wireFacetsOnBeacon() internal override {
        BeaconConfig.setCCTPIntegration(address(beacon), config.readAddress(".cctpFacet"));
    }

    function _getControllerIntegrationIds() internal override returns (bytes32[] memory integrationIds) {
        integrationIds = new bytes32[](1);

        integrationIds[0] = BeaconConfig.CCTP_INTEGRATION;
    }

}

contract ConfigureSparkPAUParallelBaseChain is ConfigureSparkPAUParallelBase {

    using stdJson for string;

    function _wireFacetsOnBeacon() internal override {
        BeaconConfig.setCCTPIntegration(address(beacon), config.readAddress(".cctpFacet"));
    }

    function _getControllerIntegrationIds() internal override returns (bytes32[] memory integrationIds) {
        integrationIds = new bytes32[](1);

        integrationIds[0] = BeaconConfig.CCTP_INTEGRATION;
    }

}
