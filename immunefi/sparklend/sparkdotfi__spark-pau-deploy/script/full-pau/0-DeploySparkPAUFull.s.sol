// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { console2 }        from "../../lib/forge-std/src/console2.sol";
import { Script, stdJson } from "../../lib/forge-std/src/Script.sol";

import { ScriptTools } from "../../lib/dss-test/src/ScriptTools.sol";

interface IDefaultPAUAssembler {

    struct AdminConfig {
        address[] accessControlAdmins;
        address[] proxyAdmins;
        address[] rateLimitsAdmins;
    }

    struct AdministeredAgentConfig {
        address[] admins;
        address[] actors;
        address[] grantors;
        address[] revokers;
    }

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

abstract contract DeploySparkPAUFullBase is Script {

    using stdJson     for string;
    using ScriptTools for string;

    IDefaultPAUAssembler defaultPAUAssembler;

    address internal admin;
    address internal relayer;
    address internal freezer;
    address internal grantor;

    function run() public virtual {
        _setXLayerAndRHChainForks();

        string memory chain = vm.envOr("CHAIN", string("mainnet"));

        vm.createSelectFork(getChain(chain).rpcUrl);

        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(block.chainid));

        string memory env      = vm.envString("ENV");
        string memory fileSlug = string(abi.encodePacked("deploy-pau-with-assembler-", chain, "-", env));
        string memory config   = ScriptTools.loadConfig(fileSlug);

        require(block.chainid == config.readUint(".chainId"), "DeploySparkPAUFull/Invalid chain ID");

        admin   = config.readAddress(".admin");
        relayer = config.readAddress(".relayer");
        freezer = config.readAddress(".freezer");
        grantor = config.readAddress(".grantor");

        defaultPAUAssembler = IDefaultPAUAssembler(config.readAddress(".defaultPAUAssembler"));

        vm.startBroadcast();

        // Step 1: Prepare configs.

        bytes32[]                                      memory integrationIds = _getIntegrationIds();
        IDefaultPAUAssembler.AdminConfig               memory adminConfig    = _getAdminConfig();
        IDefaultPAUAssembler.AdministeredAgentConfig[] memory agentConfigs   = _getAgentConfigs();

        // Step 2: Deploy PAU with default PAUAssembler.

        (
            address          proxy,
            address          controller,
            address          accessControls,
            address          rateLimits,
            address[] memory allocatorAgents
        ) = defaultPAUAssembler.deploy(integrationIds, adminConfig, agentConfigs);

        vm.stopBroadcast();

        console2.log("Deployed PAU with default PAUAssembler");

        ScriptTools.exportContract(fileSlug, "proxy",          address(proxy));
        ScriptTools.exportContract(fileSlug, "controller",     address(controller));
        ScriptTools.exportContract(fileSlug, "accessControls", address(accessControls));
        ScriptTools.exportContract(fileSlug, "rateLimits",     address(rateLimits));
        ScriptTools.exportContract(fileSlug, "allocatorAgent", allocatorAgents[0]);
    }

    /**********************************************************************************************/
    /*** Helper Functions                                                                       ***/
    /**********************************************************************************************/

    function _getIntegrationIds() internal virtual returns (bytes32[] memory integrationIds) { }

    function _getAdminConfig() internal returns (IDefaultPAUAssembler.AdminConfig memory adminConfig) {
        address[] memory accessControlAdmins = new address[](1);
        address[] memory almProxyAdmins      = new address[](1);
        address[] memory rateLimitsAdmins    = new address[](1);

        accessControlAdmins[0] = admin;
        almProxyAdmins[0]      = admin;
        rateLimitsAdmins[0]    = admin;

        adminConfig = IDefaultPAUAssembler.AdminConfig({
            accessControlAdmins : accessControlAdmins,
            proxyAdmins         : almProxyAdmins,
            rateLimitsAdmins    : rateLimitsAdmins
        });
    }

    function _getAgentConfigs() internal returns (IDefaultPAUAssembler.AdministeredAgentConfig[] memory agentConfigs) {
        address[] memory agentAdmins   = new address[](1);
        address[] memory agentActors   = new address[](1);
        address[] memory agentGrantors = new address[](address(grantor) == address(0) ? 0 : 1);
        address[] memory agentRevokers = new address[](1);

        agentAdmins[0]   = admin;
        agentActors[0]   = relayer;
        agentRevokers[0] = freezer;

        if (agentGrantors.length > 0) {
            agentGrantors[0] = grantor;
        }

        agentConfigs = new IDefaultPAUAssembler.AdministeredAgentConfig[](1); // Only one allocator agent is deployed.

        agentConfigs[0] = IDefaultPAUAssembler.AdministeredAgentConfig({
            admins   : agentAdmins,
            actors   : agentActors,
            grantors : agentGrantors,
            revokers : agentRevokers
        });
    }

    function _setXLayerAndRHChainForks() internal {
        setChain("xlayer", ChainData({
            name    : "XLayer",
            rpcUrl  : vm.envString("XLAYER_RPC_URL"),
            chainId : 196
        }));

        setChain("robinhood_chain", ChainData({
            name    : "Robinhood Chain",
            rpcUrl  : vm.envString("RH_RPC_URL"),
            chainId : 4663
        }));
    }

}

contract DeploySparkPAUFullMainnet is DeploySparkPAUFullBase {

    function run() public override {
        super.run();
    }

    function _getIntegrationIds() internal override returns (bytes32[] memory integrationIds) {
        integrationIds = new bytes32[](2);

        integrationIds[0] = "CCTP_FACET";
        integrationIds[1] = "ERC4626_FACET";

        return integrationIds;
    }

}

contract DeploySparkPAUFullXLayer is DeploySparkPAUFullBase {

    function run() public override {
        super.run();
    }

    function _getIntegrationIds() internal override returns (bytes32[] memory integrationIds) {
        integrationIds = new bytes32[](3);

        integrationIds[0] = "CCTP_FACET";
        integrationIds[1] = "TRANSFER_ASSET_FACET";
        integrationIds[2] = "SPARK_VAULT_FACET";

        return integrationIds;
    }

}

