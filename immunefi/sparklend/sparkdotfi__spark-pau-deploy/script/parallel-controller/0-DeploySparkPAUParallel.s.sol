// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { console2 }        from "../../lib/forge-std/src/console2.sol";
import { Script, stdJson } from "../../lib/forge-std/src/Script.sol";

import { ScriptTools } from "../../lib/dss-test/src/ScriptTools.sol";

import { Beacon }     from "../../lib/diamond-pau/src/Beacon.sol";
import { PAUFactory } from "../../lib/diamond-pau/src/PAUFactory.sol";
import { CCTPFacet }  from "../../lib/diamond-pau/src/facets/cctp/CCTPFacet.sol";

import { AdministeredAgentFactory } from "../../lib/pau-administered-agent/src/AdministeredAgentFactory.sol";
import { AdministeredAgent }        from "../../lib/pau-administered-agent/src/AdministeredAgent.sol";

abstract contract DeploySparkPAUParallelBase is Script {

    using stdJson     for string;
    using ScriptTools for string;

    AdministeredAgentFactory administeredAgentFactory;
    Beacon                   beacon;
    PAUFactory               pauFactory;

    address internal admin;
    address internal deployer;
    address internal almProxy;

    string internal fileSlug;
    string internal config;

    function run() public virtual {
        string memory chain = vm.envOr("CHAIN", string("mainnet"));

        vm.createSelectFork(getChain(chain).rpcUrl);

        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(block.chainid));

        string memory env = vm.envString("ENV");

        fileSlug = string(abi.encodePacked("deploy-parallel-pau-", chain, "-", env));
        config   = ScriptTools.loadConfig(fileSlug);

        require(block.chainid == config.readUint(".chainId"), "DeploySparkPAUParallelBase/Invalid chain ID");

        deployer = config.readAddress(".deployer");
        almProxy = config.readAddress(".almProxy");

        vm.startBroadcast();

        // Step 1: Deploy Beacon, PAUFactory and AdministeredAgentFactory.

        beacon                   = new Beacon(deployer);
        pauFactory               = new PAUFactory(address(beacon));
        administeredAgentFactory = new AdministeredAgentFactory();

        // Step 2: Deploy facets.

        _deployFacets();

        // Step 3: Deploy AccessControls, RateLimits and Controller.
        //         deployer is the initial admin; configure script will transfer to admin.

        address accessControls = pauFactory.deployAccessControls(deployer);
        address rateLimits     = pauFactory.deployRateLimits(deployer);
        address controller     = pauFactory.deployController(accessControls, almProxy, rateLimits);

        // Step 4: Deploy AdministeredAgent contract.

        address administeredAgent = administeredAgentFactory.deploy(deployer);

        vm.stopBroadcast();

        ScriptTools.exportContract(fileSlug, "administeredAgentFactory", address(administeredAgentFactory));
        ScriptTools.exportContract(fileSlug, "beacon",                   address(beacon));
        ScriptTools.exportContract(fileSlug, "pauFactory",               address(pauFactory));
        ScriptTools.exportContract(fileSlug, "accessControls",           accessControls);
        ScriptTools.exportContract(fileSlug, "rateLimits",               rateLimits);
        ScriptTools.exportContract(fileSlug, "controller",               controller);
        ScriptTools.exportContract(fileSlug, "administeredAgent",        administeredAgent);
    }

    // Chain specific scripts should override this function to deploy the facets and export the addresses.
    function _deployFacets() internal virtual;

}

contract DeploySparkPAUParallelArbitrum is DeploySparkPAUParallelBase {

    using stdJson for string;

    function _deployFacets() internal override {
        // Deploy CCTP facet.

        address cctpFacet = address(new CCTPFacet({
            cctp_ : config.readAddress(".cctpTokenMessenger"),
            usdc_ : config.readAddress(".usdc")
        }));

        ScriptTools.exportContract(fileSlug, "cctpFacet", cctpFacet);
    }

}

contract DeploySparkPAUParallelBaseChain is DeploySparkPAUParallelBase {

    using stdJson for string;

    function _deployFacets() internal override {
        // Deploy CCTP facet.

        address cctpFacet = address(new CCTPFacet({
            cctp_ : config.readAddress(".cctpTokenMessenger"),
            usdc_ : config.readAddress(".usdc")
        }));

        ScriptTools.exportContract(fileSlug, "cctpFacet", cctpFacet);
    }

}
