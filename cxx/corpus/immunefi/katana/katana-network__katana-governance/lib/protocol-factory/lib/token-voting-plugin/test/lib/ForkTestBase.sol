// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {Vm} from "forge-std/Test.sol";
import {TestBase} from "./TestBase.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {PluginSetupRef} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";

contract ForkTestBase is TestBase {
    // Defaults for OSx v1.4 on Sepolia
    DAOFactory internal immutable daoFactory =
        DAOFactory(vm.envOr("DAO_FACTORY_ADDRESS", address(0xB815791c233807D39b7430127975244B36C19C8e)));
    PluginRepoFactory internal immutable pluginRepoFactory =
        PluginRepoFactory(vm.envOr("PLUGIN_REPO_FACTORY_ADDRESS", address(0x399Ce2a71ef78bE6890EB628384dD09D4382a7f0)));
    PluginSetupProcessor internal immutable pluginSetupProcessor = PluginSetupProcessor(
        vm.envOr("PLUGIN_SETUP_PROCESSOR_ADDRESS", address(0xC24188a73dc09aA7C721f96Ad8857B469C01dC9f))
    );

    constructor() {
        vm.roll(10);
        vm.warp(100_000);

        if (address(daoFactory) == address(0)) {
            revert("Please, set DAO_FACTORY_ADDRESS on your .env file");
        } else if (address(pluginRepoFactory) == address(0)) {
            revert("Please, set PLUGIN_REPO_FACTORY_ADDRESS on your .env file");
        } else if (address(pluginSetupProcessor) == address(0)) {
            revert("Please, set PLUGIN_SETUP_PROCESSOR_ADDRESS on your .env file");
        }

        vm.label(address(daoFactory), "DaoFactory");
        vm.label(address(pluginRepoFactory), "PluginRepoFactory");
        vm.label(address(pluginSetupProcessor), "PluginSetupProcessor");

        // Start the fork
        vm.createSelectFork(vm.envString("RPC_URL"));
    }

    /// @notice Fetches the latest tag from the PluginRepo
    /// @param repo The PluginRepo to fetch the latest tag from
    /// @return The latest tag from the PluginRepo
    function getLatestTag(PluginRepo repo) internal view returns (PluginRepo.Tag memory) {
        PluginRepo.Version memory v = repo.getLatestVersion(repo.latestRelease());
        return v.tag;
    }
}
