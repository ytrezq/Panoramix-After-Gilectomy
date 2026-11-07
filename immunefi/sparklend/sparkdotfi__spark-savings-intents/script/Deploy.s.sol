// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import { Script, stdJson, console } from "../lib/forge-std/src/Script.sol";

import { ScriptTools } from "dss-test/ScriptTools.sol";

import { SavingsVaultIntents }       from "../src/SavingsVaultIntents.sol";
import { SavingsVaultIntentsDeploy } from "../deploy/SavingsVaultIntentsDeploy.sol";
import { SavingsVaultIntentsInit }   from "../deploy/SavingsVaultIntentsInit.sol";

contract DeployIntents is Script {

    using stdJson     for string;
    using ScriptTools for string;

    function run() external {
        vm.setEnv("FOUNDRY_ROOT_CHAINID",             "1");
        vm.setEnv("FOUNDRY_EXPORTS_OVERWRITE_LATEST", "true");

        string memory chainName = vm.envString("CHAIN");
        string memory fileSlug  = string(abi.encodePacked(chainName, "-", vm.envString("ENV")));
        string memory config    = ScriptTools.loadConfig(fileSlug);

        console.log("Deploying", chainName, "SavingsVaultIntents..");

        vm.createSelectFork(getChain(chainName).rpcUrl);

        vm.startBroadcast();

        address deployer = msg.sender;

        // Step 1: Deploy with deployer as temporary admin

        SavingsVaultIntents savingsVaultIntents = SavingsVaultIntents(
            SavingsVaultIntentsDeploy.deployFull({
                admin               : deployer,
                relayer             : config.readAddress(".relayer"),
                maxDeadlineDuration : config.readUint(".maxDeadlineDuration")
            })
        );

        console.log("SavingsVaultIntents deployed at : ", address(savingsVaultIntents));

        ScriptTools.exportContract(fileSlug, "savingsVaultIntents", address(savingsVaultIntents));

        // Step 2: Prepare init params

        SavingsVaultIntentsInit.CheckDeployParams memory checkDeployParams =
            SavingsVaultIntentsInit.CheckDeployParams(
                deployer,
                config.readAddress(".relayer"),
                config.readUint(".maxDeadlineDuration")
            );

        uint256 numVaults = config.readUint(".numVaults");

        SavingsVaultIntentsInit.ConfigVaultParams[] memory configVaultParams =
            new SavingsVaultIntentsInit.ConfigVaultParams[](numVaults);

        for (uint256 i; i < numVaults; ++i) {
            string memory base = string(abi.encodePacked(".vaults[", vm.toString(i), "]"));

            configVaultParams[i] = SavingsVaultIntentsInit.ConfigVaultParams({
                vault           : config.readAddress(string(abi.encodePacked(base, ".vault"))),
                whitelist       : config.readBool(string(abi.encodePacked(base, ".whitelist"))),
                minIntentAssets : config.readUint(string(abi.encodePacked(base, ".minIntentAssets"))),
                maxIntentAssets : config.readUint(string(abi.encodePacked(base, ".maxIntentAssets")))
            });
        }

        // Step 3: Init SavingsVaultIntents

        SavingsVaultIntentsInit.initSavingsVaultIntents(
            address(savingsVaultIntents),
            configVaultParams,
            checkDeployParams
        );

        // Step 4: Transfer admin role to real admin and revoke from deployer

        address admin = config.readAddress(".admin");

        // Deployer == admin would leave the contract adminless after revoke
        require(deployer != admin, "DeployMainnetFull/deployer-must-differ-from-admin");

        savingsVaultIntents.grantRole(savingsVaultIntents.DEFAULT_ADMIN_ROLE(), admin);

        savingsVaultIntents.revokeRole(savingsVaultIntents.DEFAULT_ADMIN_ROLE(), deployer);

        console.log("Admin role transferred to : ", admin);

        ScriptTools.exportContract(fileSlug, "savingsVaultIntents", address(savingsVaultIntents));

        vm.stopBroadcast();
    }

}
